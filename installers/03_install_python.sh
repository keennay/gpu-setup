#!/bin/bash

# Script: 03_install_python.sh
# Purpose: Check and install Python via pyenv and/or standalone uv

set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_command() { echo -e "${BLUE}[RUN]${NC} $1"; }

is_valid_python_version_arg() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

PREFLIGHT=false
AUTO_YES=false
INSTALL_UV_SELECTED=false
UV_ONLY=false
PYTHON_VERSION_ARG=""
for arg in "$@"; do
    case "$arg" in
        -y|--auto)
            AUTO_YES=true
            ;;
        --uv)
            INSTALL_UV_SELECTED=true
            ;;
        --uv-only)
            INSTALL_UV_SELECTED=true
            UV_ONLY=true
            ;;
        --preflight)
            PREFLIGHT=true
            ;;
        -h|--help)
            echo "Usage: $0 [-y|--auto] [--preflight] [--uv] [python-version]"
            echo "       $0 [-y|--auto] [--preflight] --uv-only"
            echo "  -y, --auto        Automatically accept installation prompts"
            echo "  --preflight       Check prerequisites without installing or changing Python"
            echo "  --uv              Include uv in automatic installation/checks"
            echo "  --uv-only         Install/check uv without installing or configuring Python/pyenv"
            echo "  python-version    Automatically select custom Python version (e.g. 3.11.16)"
            exit 0
            ;;
        *)
            if is_valid_python_version_arg "$arg"; then
                if [ -n "$PYTHON_VERSION_ARG" ]; then
                    print_error "Only one Python version argument is allowed."
                    exit 1
                fi
                PYTHON_VERSION_ARG="$arg"
            else
                print_error "Invalid argument: $arg"
                print_error "Python version must be numeric, such as 3.11.16."
                exit 1
            fi
            ;;
    esac
done

if [ "$UV_ONLY" = true ] && [ -n "$PYTHON_VERSION_ARG" ]; then
    print_error "--uv-only cannot be combined with a Python version."
    exit 1
fi

NEEDS_PATH_UPDATE=false
PYENV_EXPECTED=false
TARGET_PYTHON_VERSION=""
PYTHON_ACTION=""
PYTHON_PATH=""
CURRENT_PYTHON_VERSION=""
CURRENT_PYTHON_HEALTHY=false
UV_EXPECTED=false
ALL_GOOD=true

# These are deliberately set only for --preflight runs.  The setup orchestrator
# uses them to describe tools that an earlier selected component will install.
SETUP_PLANNED_CORE="${SETUP_PLANNED_CORE:-0}"

if [ "$PREFLIGHT" = true ]; then
    if [ ! -r "$SCRIPT_DIR/preflight.sh" ]; then
        print_error "Shared preflight helper is missing: $SCRIPT_DIR/preflight.sh"
        exit 1
    fi
    source "$SCRIPT_DIR/preflight.sh"
fi

reload_shell_env() {
    if [ "$UV_ONLY" = true ]; then
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        return 0
    fi
    # Never source a user's shell startup files during preflight.  Normal
    # installation retains the historical behavior so a newly installed pyenv
    # can be used by the remainder of this script.
    if [ "$PREFLIGHT" = false ] && [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi

    if [ -d "${PYENV_ROOT:-$HOME/.pyenv}" ]; then
        export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
        export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
        if [ "$PREFLIGHT" = false ] && command -v pyenv >/dev/null 2>&1; then
            eval "$(pyenv init -)"
        fi
    fi

    if [ -d "$HOME/.cargo/bin" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
    if [ -d "$HOME/.local/bin" ]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

find_system_python3() {
    local candidates=(
        "${PYTHON3_BIN:-}"
        /usr/bin/python3
        /usr/local/bin/python3
        /bin/python3
    )
    local candidate

    for candidate in "${candidates[@]}"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    echo ""
    return 1
}

python_version_for_binary() {
    local binary="$1"
    "$binary" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null
}

PYTHON_HEALTH_REASON=""
check_python_health() {
    local binary="$1"
    local expected_version="$2"
    local actual_version

    PYTHON_HEALTH_REASON=""
    if [ ! -x "$binary" ]; then
        PYTHON_HEALTH_REASON="interpreter is not executable: $binary"
        return 1
    fi

    actual_version=$(python_version_for_binary "$binary")
    if [ "$actual_version" != "$expected_version" ]; then
        PYTHON_HEALTH_REASON="reports Python ${actual_version:-unknown}, expected $expected_version"
        return 1
    fi

    if ! "$binary" - "$expected_version" <<'PY' >/dev/null 2>&1
import sys
expected = sys.argv[1]
actual = ".".join(str(part) for part in sys.version_info[:3])
if actual != expected:
    raise SystemExit("wrong Python version")
for module in ("ssl", "sqlite3", "lzma", "bz2", "ctypes", "zlib", "ensurepip", "venv"):
    __import__(module)
PY
    then
        PYTHON_HEALTH_REASON="one or more required stdlib modules are unavailable (ssl, sqlite3, lzma, bz2, ctypes, zlib, ensurepip, or venv)"
        return 1
    fi

    if ! "$binary" -m ensurepip --version >/dev/null 2>&1; then
        PYTHON_HEALTH_REASON="ensurepip is unavailable"
        return 1
    fi
    if ! "$binary" -m venv --help >/dev/null 2>&1; then
        PYTHON_HEALTH_REASON="venv is unavailable"
        return 1
    fi
    if ! "$binary" -m pip --version >/dev/null 2>&1; then
        PYTHON_HEALTH_REASON="pip is unavailable"
        return 1
    fi

    return 0
}

pyenv_root_path() {
    local root

    if [ -n "${PYENV_ROOT:-}" ]; then
        printf '%s\n' "$PYENV_ROOT"
        return 0
    fi
    if command -v pyenv >/dev/null 2>&1 && root=$(pyenv root 2>/dev/null); then
        printf '%s\n' "$root"
        return 0
    fi
    if [ -d "$HOME/.pyenv" ]; then
        printf '%s\n' "$HOME/.pyenv"
        return 0
    fi
    return 1
}

pyenv_definition_file() {
    local version="$1"
    local root
    local candidate
    local python_build_bin
    local python_build_dir

    root=$(pyenv_root_path) || return 1
    if [ -n "${PYTHON_BUILD_DEFINITIONS:-}" ]; then
        candidate="$PYTHON_BUILD_DEFINITIONS/$version"
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    if python_build_bin=$(pyenv which python-build 2>/dev/null); then
        python_build_dir=$(dirname "$python_build_bin")
        candidate="$python_build_dir/../share/python-build/$version"
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    for candidate in \
        "$root/plugins/python-build/share/python-build/$version" \
        "$root/share/python-build/$version" \
        "$root/../share/pyenv/plugins/python-build/share/python-build/$version"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

pyenv_definition_available() {
    local version="$1"

    command -v pyenv >/dev/null 2>&1 || return 1
    pyenv install --list 2>/dev/null | sed 's/^[[:space:]]*//' | grep -Fx -- "$version" >/dev/null 2>&1
}

find_pyenv_python() {
    local version="$1"
    local prefix
    local candidate

    command -v pyenv >/dev/null 2>&1 || return 1
    prefix=$(pyenv prefix "$version" 2>/dev/null) || return 1
    for candidate in "$prefix/bin/python3" "$prefix/bin/python"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# Set DEFINITION_SOURCE_URL and DEFINITION_SOURCE_CHECKSUM from one real
# python-build definition.  The source and checksum are never synthesized.
extract_definition_source() {
    local definition="$1"
    local version="$2"
    local line
    local reference

    DEFINITION_SOURCE_URL=""
    DEFINITION_SOURCE_CHECKSUM=""
    while IFS= read -r line; do
        case "$line" in
            *"Python-$version"*|*"Python_${version}"*)
                if [[ "$line" =~ (https?://[^\"[:space:]]+) ]]; then
                    reference="${BASH_REMATCH[1]}"
                    DEFINITION_SOURCE_URL="${reference%%#*}"
                    if [[ "$reference" == *'#'* ]]; then
                        DEFINITION_SOURCE_CHECKSUM="${reference##*#}"
                    fi
                    return 0
                fi
                ;;
        esac
    done < "$definition"
    return 1
}

# A failed refresh is retained as a useful reason by both normal and
# preflight execution; callers decide whether to print it through the shared
# collector or the normal error printer.
BUILDER_REFRESH_ATTEMPTED=false
BUILDER_REFRESH_REASON=""
BUILDER_REPOSITORIES=()

builder_failure() {
    BUILDER_REFRESH_REASON="$1"
    return 1
}

is_official_pyenv_remote() {
    local remote="$1"

    case "$remote" in
        https://github.com/pyenv/pyenv|https://github.com/pyenv/pyenv.git|\
        ssh://git@github.com/pyenv/pyenv|ssh://git@github.com/pyenv/pyenv.git|\
        git@github.com:pyenv/pyenv|git@github.com:pyenv/pyenv.git)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

prepare_builder_repository() {
    local repository="$1"
    local top
    local branch
    local upstream
    local tracking_remote
    local remote
    local status_output
    local existing

    top=$(git -C "$repository" rev-parse --show-toplevel 2>/dev/null) || {
        builder_failure "$repository is not a Git checkout"
        return 1
    }

    for existing in "${BUILDER_REPOSITORIES[@]}"; do
        [ "$existing" != "$top" ] || return 0
    done

    if ! status_output=$(git -C "$top" status --porcelain --untracked-files=all 2>/dev/null); then
        builder_failure "unable to inspect pyenv checkout $top; refusing to update it"
        return 1
    fi
    if [ -n "$status_output" ]; then
        builder_failure "preserving local changes: pyenv checkout $top is not clean"
        return 1
    fi
    branch=$(git -C "$top" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
        builder_failure "preserving pinned pyenv checkout $top: HEAD is detached"
        return 1
    }
    [ -n "$branch" ] || return 1
    upstream=$(git -C "$top" rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null) || {
        builder_failure "preserving pinned pyenv checkout $top: branch $branch has no upstream"
        return 1
    }
    [ -n "$upstream" ] || return 1
    tracking_remote="${upstream%%/*}"
    [ -n "$tracking_remote" ] || {
        builder_failure "pyenv checkout $top has an invalid tracking branch: $upstream"
        return 1
    }
    remote=$(git -C "$top" remote get-url "$tracking_remote" 2>/dev/null) || {
        builder_failure "pyenv checkout $top has no usable tracking remote: $tracking_remote"
        return 1
    }
    [ -n "$remote" ] || return 1
    if ! is_official_pyenv_remote "$remote"; then
        builder_failure "refusing to update non-official pyenv tracking remote $remote"
        return 1
    fi

    BUILDER_REPOSITORIES+=("$top")
    return 0
}

refresh_pyenv_builder_once() {
    local root
    local plugin
    local repository

    if [ "$BUILDER_REFRESH_ATTEMPTED" = true ]; then
        [ -n "$BUILDER_REFRESH_REASON" ] || BUILDER_REFRESH_REASON="pyenv builder refresh was already attempted"
        return 1
    fi
    BUILDER_REFRESH_ATTEMPTED=true
    BUILDER_REFRESH_REASON=""
    BUILDER_REPOSITORIES=()

    if ! command -v pyenv >/dev/null 2>&1; then
        builder_failure "pyenv is not available to refresh its python-build definitions"
        return 1
    fi
    root=$(pyenv_root_path) || {
        builder_failure "unable to determine the active pyenv root"
        return 1
    }
    [ -d "$root" ] || {
        builder_failure "active pyenv root does not exist: $root"
        return 1
    }

    # Validate every checkout before changing any one of them.  A separate
    # python-build checkout is common with package-managed pyenv installs.
    prepare_builder_repository "$root" || return 1
    plugin="$root/plugins/python-build"
    if [ -d "$plugin" ]; then
        prepare_builder_repository "$plugin" || return 1
    fi

    if [ "${#BUILDER_REPOSITORIES[@]}" -eq 0 ]; then
        builder_failure "active pyenv has no clean official Git checkout to update"
        return 1
    fi

    for repository in "${BUILDER_REPOSITORIES[@]}"; do
        print_info "Refreshing pyenv/python-build definitions in $repository (fast-forward only)..."
        if ! git -C "$repository" pull --ff-only --quiet; then
            builder_failure "safe fast-forward update failed for $repository; local changes and pinned checkouts were preserved"
            return 1
        fi
    done
    return 0
}

ensure_builder_definition() {
    local version="$1"

    if pyenv_definition_available "$version"; then
        return 0
    fi

    if ! refresh_pyenv_builder_once; then
        print_error "Python $version definition is unavailable, and pyenv/python-build could not be safely refreshed: $BUILDER_REFRESH_REASON"
        return 1
    fi

    if ! pyenv_definition_available "$version"; then
        print_error "Python $version is unsupported by the refreshed pyenv/python-build definition; no source fallback was selected."
        return 1
    fi
    return 0
}

fetch_latest_python_version() {
    local latest=""

    if command -v pyenv >/dev/null 2>&1; then
        latest=$(pyenv install --list 2>/dev/null | \
            sed 's/^[[:space:]]*//' | \
            grep -E '^3\.[0-9]+\.[0-9]+$' | \
            sort -V | tail -n 1)
    fi

    if [ -z "$latest" ] && command -v curl >/dev/null 2>&1; then
        latest=$(curl -fsSL --connect-timeout 10 --max-time 30 https://www.python.org/downloads/ 2>/dev/null | \
            grep -m1 -oP 'Latest Python 3 Release - Python \K[0-9]+\.[0-9]+\.[0-9]+')
    fi

    if is_valid_python_version_arg "$latest"; then
        printf '%s\n' "$latest"
        return 0
    fi
    return 1
}

ensure_pyenv() {
    local install_status=0
    local bashrc="$HOME/.bashrc"

    if command -v pyenv >/dev/null 2>&1; then
        return 0
    fi

    print_warning "pyenv is not installed"
    local install_pyenv
    if [ "$AUTO_YES" = true ]; then
        install_pyenv="y"
        print_info "Automatic mode enabled (-y): installing pyenv"
    else
        read -r -p "Install pyenv? (y/n): " install_pyenv
    fi

    if [[ ! "$install_pyenv" =~ ^[Yy]$ ]]; then
        print_error "pyenv installation declined. Cannot proceed with Python installation."
        return 1
    fi

    if command -v curl >/dev/null 2>&1; then
        print_info "Installing pyenv..."
        if ! (set -o pipefail; curl -fsSL --connect-timeout 10 --max-time 120 https://pyenv.run | bash); then
            print_error "pyenv installer failed."
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        print_info "Installing pyenv..."
        if ! (set -o pipefail; wget -qO- --timeout=30 https://pyenv.run | bash); then
            print_error "pyenv installer failed."
            return 1
        fi
    else
        print_error "Cannot install pyenv: curl or wget is required."
        return 1
    fi

    if ! grep -q "PYENV_ROOT" "$bashrc" 2>/dev/null; then
        cat >> "$bashrc" <<'EOF'

# Pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
        print_info "Added pyenv initialization to ~/.bashrc"
        NEEDS_PATH_UPDATE=true
    fi

    print_info "Reloading shell environment..."
    reload_shell_env
    if command -v pyenv >/dev/null 2>&1; then
        print_info "✓ pyenv installed successfully"
        print_info "  Location: $(command -v pyenv)"
        return 0
    fi

    print_error "pyenv installation failed: command is still unavailable after installation."
    print_error "Please run: source ~/.bashrc, then rerun this script."
    return 1
}

ensure_runpod_pyenv_guard() {
    local bashrc="$HOME/.bashrc"
    local marker="# runpod_pyenv_guard"

    [ "$PREFLIGHT" = false ] || return 0
    [ -f "$bashrc" ] || return 0
    grep -q "/etc/rp_environment" "$bashrc" 2>/dev/null || return 0
    grep -q "$marker" "$bashrc" 2>/dev/null && return 0

    if ! command -v python3 >/dev/null 2>&1; then
        print_warning "python3 not available for RunPod guard modification; skipping"
        return 0
    fi

    python3 - <<'PY'
from pathlib import Path

bashrc_path = Path.home() / ".bashrc"
text = bashrc_path.read_text()
needle = "source /etc/rp_environment"
if needle not in text:
    raise SystemExit(0)

guard = """

# runpod_pyenv_guard: ensure pyenv remains active after RunPod environment sourcing
if [ -d "$HOME/.pyenv" ]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    if command -v pyenv >/dev/null 2>&1; then
        eval "$(pyenv init -)"
    fi
fi
"""

if guard.strip() in text:
    raise SystemExit(0)

text = text.replace(needle, needle + guard, 1)
bashrc_path.write_text(text)
PY

    print_info "Added RunPod pyenv guard to ~/.bashrc"
    NEEDS_PATH_UPDATE=true
}

install_uv() {
    local install_uv_choice

    if [ "$AUTO_YES" = true ] && [ "$INSTALL_UV_SELECTED" = false ]; then
        print_info "Skipping uv installation."
        return 0
    fi

    print_info "Checking uv..."
    if command -v uv >/dev/null 2>&1; then
        if uv --version >/dev/null 2>&1; then
            print_info "✓ uv is installed ($(uv --version))"
            return 0
        fi
        print_error "uv is present but --version failed."
        return 1
    fi
    print_error "✗ uv is not installed"

    if [ "$AUTO_YES" = true ]; then
        install_uv_choice="y"
    else
        read -r -p "Install uv? (y/n): " install_uv_choice
    fi

    if [[ ! "$install_uv_choice" =~ ^[Yy]$ ]]; then
        print_info "Skipping uv installation."
        return 0
    fi

    print_info "Installing uv..."
    if command -v curl >/dev/null 2>&1; then
        if ! (set -o pipefail; curl -fsSL --connect-timeout 10 --max-time 120 https://astral.sh/uv/install.sh | sh); then
            print_error "Failed to install uv."
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! (set -o pipefail; wget -qO- --timeout=30 https://astral.sh/uv/install.sh | sh); then
            print_error "Failed to install uv."
            return 1
        fi
    else
        print_error "Failed to install uv: curl or wget is required."
        return 1
    fi

    reload_shell_env
    if ! command -v uv >/dev/null 2>&1 || ! uv --version >/dev/null 2>&1; then
        print_error "uv installer completed but uv is not usable on PATH."
        return 1
    fi
    print_info "✓ uv installed ($(uv --version))"
    return 0
}

preflight_definition_source() {
    local version="$1"
    local definition="$2"

    if ! extract_definition_source "$definition" "$version"; then
        preflight_error "Python $version definition has no upstream source entry for Python-$version"
        return 1
    fi
    if [ -z "$DEFINITION_SOURCE_CHECKSUM" ]; then
        preflight_error "Python $version definition does not pin a source checksum: $definition"
    elif [[ ! "$DEFINITION_SOURCE_CHECKSUM" =~ ^[[:xdigit:]]{64}$ ]]; then
        preflight_error "Python $version definition has an invalid source checksum: $DEFINITION_SOURCE_CHECKSUM"
    else
        preflight_info "Python $version source checksum is pinned by $definition"
    fi
    if [ -n "$DEFINITION_SOURCE_URL" ]; then
        preflight_url "Python $version source release" "$DEFINITION_SOURCE_URL"
    else
        preflight_error "Python $version definition did not provide a source URL"
        return 1
    fi
}

preflight_remote_definition_source() {
    local version="$1"
    local url="https://raw.githubusercontent.com/pyenv/pyenv/master/plugins/python-build/share/python-build/$version"
    local temporary

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        if [ "$SETUP_PLANNED_CORE" = 1 ]; then
            preflight_defer "Python $version definition metadata will be checked after planned core fetch tools are installed"
            return 0
        fi
        preflight_error "Cannot inspect official Python $version definition: curl or wget is unavailable"
        return 1
    fi
    if ! preflight_url "official Python $version definition" "$url"; then
        return 1
    fi

    temporary=$(mktemp "${TMPDIR:-/tmp}/python-definition.XXXXXX") || {
        preflight_error "Cannot create a temporary file for the official Python $version definition"
        return 1
    }
    if ! preflight_fetch "$url" >"$temporary"; then
        rm -f "$temporary"
        preflight_error "Cannot fetch the official Python $version definition metadata"
        return 1
    fi
    if ! preflight_definition_source "$version" "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    rm -f "$temporary"
    return 0
}

preflight_uv() {
    local uv_installer="https://astral.sh/uv/install.sh"

    if command -v uv >/dev/null 2>&1; then
        if uv --version >/dev/null 2>&1; then
            preflight_info "uv is installed and responds to --version"
        else
            preflight_error "uv is present but --version failed"
        fi
        return 0
    fi

    preflight_writable "$HOME/.local/bin" || true
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        preflight_url "Astral uv installer" "$uv_installer"
    elif [ "$SETUP_PLANNED_CORE" = 1 ]; then
        preflight_defer "uv installer reachability will be checked after planned core fetch tools are installed"
    else
        preflight_error "uv is missing and neither curl nor wget is available to install it"
    fi
}

preflight_python() {
    local target="$1"
    local current_binary=""
    local pyenv_binary=""
    local needs_install=true
    local install_tool
    local active_pyenv_root=""

    if [ -z "$target" ]; then
        preflight_error "Python preflight requires an exact version argument when no current python3 is available"
        return 1
    fi

    current_binary=$(command -v python3 2>/dev/null || true)
    if [ -n "$current_binary" ]; then
        if check_python_health "$current_binary" "$target"; then
            preflight_info "Healthy exact Python $target already exists at $current_binary; no network or builder update is required"
            needs_install=false
        else
            preflight_info "python3 at $current_binary cannot be reused for Python $target: $PYTHON_HEALTH_REASON"
        fi
    fi

    if [ "$needs_install" = true ] && command -v pyenv >/dev/null 2>&1; then
        if pyenv_binary=$(find_pyenv_python "$target"); then
            if check_python_health "$pyenv_binary" "$target"; then
                preflight_info "Healthy exact pyenv Python $target already exists at $pyenv_binary; no network or builder update is required"
                needs_install=false
            else
                preflight_info "Installed pyenv Python $target is not reusable: $PYTHON_HEALTH_REASON"
            fi
        fi
    fi


    [ "$needs_install" = true ] || return 0
    if command -v pyenv >/dev/null 2>&1; then
        active_pyenv_root=$(pyenv_root_path 2>/dev/null || true)
    else
        active_pyenv_root="${PYENV_ROOT:-$HOME/.pyenv}"
    fi
    [ -n "$active_pyenv_root" ] || active_pyenv_root="${PYENV_ROOT:-$HOME/.pyenv}"
    preflight_writable "$active_pyenv_root" || true
    preflight_writable "$active_pyenv_root/versions" || true
    preflight_writable "$HOME/.bashrc" || true
    preflight_writable "$HOME/.local/bin" || true

    # These are only needed when a source build may actually be required.
    for install_tool in make gcc tar xz; do
        preflight_command "$install_tool" "$SETUP_PLANNED_CORE" || true
    done

    if command -v pyenv >/dev/null 2>&1; then
        if ! pyenv_definition_available "$target"; then
            preflight_command git "$SETUP_PLANNED_CORE" || true
            if command -v git >/dev/null 2>&1; then
                if ! refresh_pyenv_builder_once; then
                    preflight_error "Python $target definition is unavailable and pyenv/python-build refresh failed: $BUILDER_REFRESH_REASON"
                fi
            elif [ "$SETUP_PLANNED_CORE" = 1 ]; then
                preflight_defer "Python $target definition refresh will run after planned git installation"
            else
                preflight_error "Python $target definition is unavailable and git is not installed for a safe builder refresh"
            fi
        fi

        if pyenv_definition_available "$target"; then
            if definition=$(pyenv_definition_file "$target"); then
                preflight_definition_source "$target" "$definition"
            else
                preflight_info "The active pyenv/python-build reports exact Python $target; reading official upstream metadata because its definition directory is custom."
                preflight_remote_definition_source "$target"
            fi
        elif [ "$SETUP_PLANNED_CORE" = 1 ] && ! command -v git >/dev/null 2>&1; then
            preflight_defer "Python $target definition/source checksum will be checked after planned pyenv tooling is installed"
        else
            preflight_error "Python $target has no exact definition in the active pyenv/python-build"
            preflight_remote_definition_source "$target"
        fi
    else
        preflight_command git "$SETUP_PLANNED_CORE" || true
        preflight_remote_definition_source "$target"
    fi
}

run_preflight() {
    local target="$1"
    local current_binary=""
    local status=0

    preflight_init "Python"
    if [ "$UV_ONLY" = true ]; then
        preflight_uv
    else
        if [ -z "$target" ]; then
            current_binary=$(command -v python3 2>/dev/null || true)
            if [ -n "$current_binary" ]; then
                target=$(python_version_for_binary "$current_binary")
            fi
        fi
        preflight_python "$target" || status=1
        if [ "$INSTALL_UV_SELECTED" = true ]; then
            preflight_uv || status=1
        fi
    fi

    preflight_finish
    local finish_status=$?
    if [ "$finish_status" -ne 0 ]; then
        status=1
    fi
    return "$status"
}

# Preflight is intentionally isolated before any normal-mode environment load,
# prompt, pyenv installation, global activation, or shell-file write.
if [ "$PREFLIGHT" = true ]; then
    # Resolve pyenv/cargo/uv paths without sourcing user startup files.
    reload_shell_env
    run_preflight "$PYTHON_VERSION_ARG"
    exit $?
fi

if [ "$UV_ONLY" = true ]; then
    install_uv
    exit $?
fi

reload_shell_env

print_info "Checking pyenv availability..."
if command -v pyenv >/dev/null 2>&1; then
    print_info "✓ pyenv detected ($(pyenv --version 2>/dev/null | head -1))"
else
    print_warning "pyenv not found; it will be required if you choose to install a new Python version."
fi

print_info "Checking python3 availability..."
if command -v python3 >/dev/null 2>&1; then
    PYTHON_PATH=$(command -v python3)
    CURRENT_PYTHON_VERSION=$(python_version_for_binary "$PYTHON_PATH")
    if [ -n "$CURRENT_PYTHON_VERSION" ]; then
        print_info "✓ python3 found on PATH at $PYTHON_PATH (version $CURRENT_PYTHON_VERSION)"
        if check_python_health "$PYTHON_PATH" "$CURRENT_PYTHON_VERSION"; then
            CURRENT_PYTHON_HEALTHY=true
            print_info "  Interpreter health checks passed"
        else
            print_warning "  Existing Python is incomplete: $PYTHON_HEALTH_REASON"
        fi
    fi
else
    PYTHON_PATH=$(find_system_python3 || true)
    if [ -n "$PYTHON_PATH" ]; then
        CURRENT_PYTHON_VERSION=$(python_version_for_binary "$PYTHON_PATH")
        print_info "✓ System python3 located at $PYTHON_PATH (version $CURRENT_PYTHON_VERSION)"
        if check_python_health "$PYTHON_PATH" "$CURRENT_PYTHON_VERSION"; then
            CURRENT_PYTHON_HEALTHY=true
        else
            print_warning "  Existing Python is incomplete: $PYTHON_HEALTH_REASON"
        fi
    else
        print_warning "python3 not found via PATH or standard locations"
    fi
fi

# A supplied version is already exact.  Check local interpreters before any
# latest-release lookup, pyenv metadata lookup, or network access.
if [ -n "$PYTHON_VERSION_ARG" ]; then
    TARGET_PYTHON_VERSION="$PYTHON_VERSION_ARG"
    if [ "$CURRENT_PYTHON_HEALTHY" = true ] && [ "$CURRENT_PYTHON_VERSION" = "$TARGET_PYTHON_VERSION" ]; then
        PYTHON_ACTION="keep"
        print_info "Healthy exact Python $TARGET_PYTHON_VERSION is already available; reusing it offline."
    else
        PYTHON_ACTION="install_custom"
        print_info "Python version argument provided; selecting custom Python $TARGET_PYTHON_VERSION."
    fi
elif [ "$AUTO_YES" = true ]; then
    PYTHON_ACTION="install_latest"
    print_info "Automatic mode enabled (-y): installing the latest Python version via pyenv."
elif [ -z "$PYTHON_PATH" ]; then
    PYTHON_ACTION="install_latest"
    print_warning "No existing python3 installation detected; a new version will be installed."
else
    while true; do
        echo "Choose Python setup option:"
        echo "  1) Keep current version ($CURRENT_PYTHON_VERSION)"
        echo "  2) Install latest version via pyenv"
        echo "  3) Install custom version via pyenv"
        read -r -p "Enter choice (1/2/3): " PYTHON_CHOICE

        if [[ ! "$PYTHON_CHOICE" =~ ^[123]$ ]]; then
            print_error "Invalid choice. Please enter 1, 2, or 3."
            continue
        fi
        if [ "$PYTHON_CHOICE" = "1" ]; then
            if [ "$CURRENT_PYTHON_HEALTHY" != true ]; then
                print_error "The current Python cannot be kept: $PYTHON_HEALTH_REASON"
                continue
            fi
            PYTHON_ACTION="keep"
            TARGET_PYTHON_VERSION="$CURRENT_PYTHON_VERSION"
            break
        elif [ "$PYTHON_CHOICE" = "2" ]; then
            PYTHON_ACTION="install_latest"
            break
        else
            PYTHON_ACTION="install_custom"
            break
        fi
    done
fi

if [ "$PYTHON_ACTION" = "install_custom" ] && [ -z "$TARGET_PYTHON_VERSION" ]; then
    while true; do
        read -r -p "Enter desired Python version (e.g. 3.11.16): " TARGET_PYTHON_VERSION
        if is_valid_python_version_arg "$TARGET_PYTHON_VERSION"; then
            break
        fi
        print_error "Invalid version format. Please use numeric values like 3.11.16"
    done
fi

if [ "$PYTHON_ACTION" = "keep" ]; then
    [ -n "$TARGET_PYTHON_VERSION" ] || TARGET_PYTHON_VERSION="$CURRENT_PYTHON_VERSION"
    print_info "Keeping existing python3 version $TARGET_PYTHON_VERSION"
else
    if ! ensure_pyenv; then
        exit 1
    fi
    PYENV_EXPECTED=true

    if [ "$PYTHON_ACTION" = "install_latest" ]; then
        if ! TARGET_PYTHON_VERSION=$(fetch_latest_python_version); then
            print_error "Unable to determine the latest Python release from pyenv or python.org; refusing an arbitrary fallback."
            exit 1
        fi
        print_info "Latest Python release detected: $TARGET_PYTHON_VERSION"
    fi

    if [ -z "$TARGET_PYTHON_VERSION" ] || ! is_valid_python_version_arg "$TARGET_PYTHON_VERSION"; then
        print_error "No valid target Python version specified"
        exit 1
    fi

    EXISTING_PYENV_PYTHON=""
    if EXISTING_PYENV_PYTHON=$(find_pyenv_python "$TARGET_PYTHON_VERSION"); then
        if check_python_health "$EXISTING_PYENV_PYTHON" "$TARGET_PYTHON_VERSION"; then
            print_info "Healthy exact Python $TARGET_PYTHON_VERSION already installed via pyenv"
        else
            print_warning "Installed pyenv Python $TARGET_PYTHON_VERSION is incomplete: $PYTHON_HEALTH_REASON"
            EXISTING_PYENV_PYTHON=""
        fi
    fi

    if [ -z "$EXISTING_PYENV_PYTHON" ]; then
        if ! ensure_builder_definition "$TARGET_PYTHON_VERSION"; then
            exit 1
        fi
        print_info "Installing Python $TARGET_PYTHON_VERSION via pyenv..."
        print_info "This compiles Python from source and may take several minutes."
        if [ -z "${MAKE_OPTS:-}" ]; then
            MAKE_OPTS="-j$(nproc)"
        fi
        if ! MAKE_OPTS="$MAKE_OPTS" pyenv install --force "$TARGET_PYTHON_VERSION"; then
            print_error "Failed to install Python $TARGET_PYTHON_VERSION"
            exit 1
        fi
        if ! EXISTING_PYENV_PYTHON=$(find_pyenv_python "$TARGET_PYTHON_VERSION"); then
            print_error "pyenv install completed but Python $TARGET_PYTHON_VERSION is not present"
            exit 1
        fi
        if ! check_python_health "$EXISTING_PYENV_PYTHON" "$TARGET_PYTHON_VERSION"; then
            print_error "New Python $TARGET_PYTHON_VERSION failed health verification: $PYTHON_HEALTH_REASON"
            print_error "The active pyenv global selection was left unchanged."
            exit 1
        fi
    fi

    PREVIOUS_PYENV_GLOBAL=$(pyenv global 2>/dev/null || true)
    if ! pyenv global "$TARGET_PYTHON_VERSION"; then
        print_error "Failed to set pyenv global version to $TARGET_PYTHON_VERSION"
        exit 1
    fi
    if ! pyenv rehash; then
        print_error "pyenv rehash failed; restoring previous global selection"
        if [ -n "$PREVIOUS_PYENV_GLOBAL" ]; then
            pyenv global "$PREVIOUS_PYENV_GLOBAL" >/dev/null 2>&1 || true
        fi
        exit 1
    fi
    reload_shell_env
    ensure_runpod_pyenv_guard

    PYTHON_PATH=$(pyenv which python3 2>/dev/null || true)
    if [ -z "$PYTHON_PATH" ]; then
        PYTHON_PATH="$EXISTING_PYENV_PYTHON"
    fi
    if ! check_python_health "$PYTHON_PATH" "$TARGET_PYTHON_VERSION"; then
        print_error "Activated Python $TARGET_PYTHON_VERSION failed final health verification: $PYTHON_HEALTH_REASON"
        print_error "Restoring previous pyenv global selection."
        if [ -n "$PREVIOUS_PYENV_GLOBAL" ]; then
            pyenv global "$PREVIOUS_PYENV_GLOBAL" >/dev/null 2>&1 || true
            pyenv rehash >/dev/null 2>&1 || true
        fi
        exit 1
    fi
    CURRENT_PYTHON_VERSION="$TARGET_PYTHON_VERSION"
    CURRENT_PYTHON_HEALTHY=true
    print_info "Python $TARGET_PYTHON_VERSION is now set as the global pyenv version"
fi
restore_previous_pyenv_global() {
    [ "$PYENV_EXPECTED" = true ] || return 0
    [ -n "${PREVIOUS_PYENV_GLOBAL:-}" ] || return 0
    pyenv global "$PREVIOUS_PYENV_GLOBAL" >/dev/null 2>&1 || true
    pyenv rehash >/dev/null 2>&1 || true
}

echo ""
# Step 3: Check and install uv
if [ "$INSTALL_UV_SELECTED" = true ] || [ "$AUTO_YES" = false ]; then
    if [ "$INSTALL_UV_SELECTED" = true ]; then
        UV_EXPECTED=true
    fi
    if ! install_uv; then
        ALL_GOOD=false
    fi
fi

echo ""
echo "=============================================="

print_info "Final verification:"
if [ "$PYENV_EXPECTED" = true ]; then
    PYENV_FINAL_FAILED=false
    if command -v pyenv >/dev/null 2>&1 && pyenv global >/dev/null 2>&1; then
        ACTIVE_PYENV_GLOBAL=$(pyenv global 2>/dev/null)
        if [ "$ACTIVE_PYENV_GLOBAL" = "$TARGET_PYTHON_VERSION" ]; then
            print_info "  ✓ pyenv global: $ACTIVE_PYENV_GLOBAL"
        else
            print_error "  ✗ pyenv global is '$ACTIVE_PYENV_GLOBAL', expected '$TARGET_PYTHON_VERSION'"
            PYENV_FINAL_FAILED=true
        fi
    else
        print_error "  ✗ pyenv global query failed"
        PYENV_FINAL_FAILED=true
    fi
    if command -v pyenv >/dev/null 2>&1 && ! pyenv rehash >/dev/null 2>&1; then
        print_error "  ✗ pyenv rehash failed during final verification"
        PYENV_FINAL_FAILED=true
    fi
    if [ "$PYENV_FINAL_FAILED" = true ]; then
        restore_previous_pyenv_global
        ALL_GOOD=false
    fi
elif command -v pyenv >/dev/null 2>&1; then
    print_info "  ℹ pyenv available (not needed for the retained system Python)"
else
    print_info "  ℹ pyenv not installed (not requested)"
fi

ACTIVE_COMMAND_PYTHON=$(command -v python3 2>/dev/null || true)
if [ -n "$ACTIVE_COMMAND_PYTHON" ] && check_python_health "$ACTIVE_COMMAND_PYTHON" "$TARGET_PYTHON_VERSION"; then
    ACTIVE_PYTHON_VERSION=$(python_version_for_binary "$ACTIVE_COMMAND_PYTHON")
    print_info "  ✓ python3: Python $ACTIVE_PYTHON_VERSION"
    print_info "    Location: $ACTIVE_COMMAND_PYTHON"
else
    print_error "  ✗ command -v python3 failed final health verification: ${PYTHON_HEALTH_REASON:-not found}"
    ALL_GOOD=false
fi

if [ "$UV_EXPECTED" = true ]; then
    if command -v uv >/dev/null 2>&1 && uv --version >/dev/null 2>&1; then
        print_info "  ✓ uv: $(uv --version)"
    else
        print_error "  ✗ uv is not usable after installation"
        ALL_GOOD=false
    fi
fi


echo ""
if [ "$ALL_GOOD" = true ]; then
    print_info "All Python tools are properly installed!"
else
    print_error "Some tools are missing or not properly configured."
fi

if [ "$NEEDS_PATH_UPDATE" = true ]; then
    echo ""
    print_warning "Some tools may not be visible until you reload your shell."
    print_info "Please run:"
    print_command "source ~/.bashrc"
fi

if [ "$ALL_GOOD" != true ]; then
    echo ""
    print_info "Debug information:"
    print_info "  PATH: $PATH"
    print_info "  PYENV_ROOT: ${PYENV_ROOT:-not set}"
    exit 1
fi

# Keep the existing convenience prompt, but only after all target health and
# activation checks pass.  Preflight returns above before reaching this block.
PYTHON3_BIN_PATH="$PYTHON_PATH"
if [ -z "$PYTHON3_BIN_PATH" ]; then
    PYTHON3_BIN_PATH=$(command -v python3 2>/dev/null || true)
fi
if [ -n "$PYTHON3_BIN_PATH" ] && ! command -v python >/dev/null 2>&1; then
    echo ""
    print_warning "python command not found, but python3 is available."
    print_info "python3 resolves to: $PYTHON3_BIN_PATH"

    SYMLINK_DIR=$(dirname "$PYTHON3_BIN_PATH")
    SYMLINK_PATH="$SYMLINK_DIR/python"
    if [ ! -w "$SYMLINK_DIR" ]; then
        SYMLINK_DIR="$HOME/.local/bin"
        SYMLINK_PATH="$SYMLINK_DIR/python"
        mkdir -p "$SYMLINK_DIR"
    fi

    if [ "$AUTO_YES" = true ]; then
        CREATE_PYTHON_SYMLINK="y"
    else
        while true; do
            read -r -p "Create python symlink pointing to python3 at $SYMLINK_PATH? (y/n): " CREATE_PYTHON_SYMLINK
            if [[ "$CREATE_PYTHON_SYMLINK" =~ ^[YyNn]$ ]]; then
                break
            fi
            print_error "Please answer y or n."
        done
    fi

    if [[ "$CREATE_PYTHON_SYMLINK" =~ ^[Yy]$ ]]; then
        if ln -sf "$PYTHON3_BIN_PATH" "$SYMLINK_PATH"; then
            print_info "Created python symlink at $SYMLINK_PATH"
            if [ "$SYMLINK_DIR" = "$HOME/.local/bin" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
                print_warning "$HOME/.local/bin is not currently on PATH; add it to your shell profile to use the python alias."
            fi
        else
            print_error "Failed to create python symlink at $SYMLINK_PATH"
            exit 1
        fi
    else
        print_info "Skipped creating python symlink."
    fi
fi

exit 0
