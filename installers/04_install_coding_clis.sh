#!/bin/bash
# Script: 04_install_coding_clis.sh
# Purpose: Install coding CLIs and their config files

set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_OWNER_USER="${SUDO_USER:-$USER}"
CONFIG_OWNER_GROUP="$(id -gn "$CONFIG_OWNER_USER" 2>/dev/null || echo "$CONFIG_OWNER_USER")"
CONFIG_HOME="$(eval echo "~$CONFIG_OWNER_USER")"
CONFIG_ROOT="$CONFIG_HOME/.config"

# Keep every upstream source and package specification in one place.  The
# preflight path uses these same values as the installation path.
NAC_INSTALL_URL="https://raw.githubusercontent.com/arcee-ai/nac/main/scripts/install.sh"
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
DEEPSEEK_REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"
GROK_INSTALL_URL="https://x.ai/cli/install.sh"
KIMI_INSTALL_URL="https://code.kimi.com/kimi-code/install.sh"
MUSE_INSTALL_URL="https://dev.meta.ai/install.sh"
MIMO_INSTALL_URL="https://mimo.xiaomi.com/install"
MCODE_INSTALL_URL="https://filecdn.minimax.chat/public/install.sh"
OMP_INSTALL_URL="https://omp.sh/install"
CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"
OPENCODE_INSTALL_URL="https://opencode.ai/install"
PRIME_INSTALL_URL="https://app.primeintellect.ai/prime-agent/install.sh"
QWEN_INSTALL_URL="https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh"
GEMINI_PACKAGE="@google/gemini-cli"
GEMINI_PACKAGE_METADATA_URL="https://registry.npmjs.org/@google%2fgemini-cli/latest"
PI_PACKAGE="@earendil-works/pi-coding-agent"
PI_PACKAGE_METADATA_URL="https://registry.npmjs.org/@earendil-works%2fpi-coding-agent/latest"
DEEPSEEK_HARNESS_DIR="$HOME/deepseek-harness"

ensure_config_ownership() {
    local config_root="$1"

    if [ -z "$config_root" ]; then
        print_warning "Config root not set; skipping config setup"
        return 1
    fi

    if [ ! -d "$config_root" ]; then
        if ! mkdir -p "$config_root"; then
            print_warning "Failed to create $config_root without sudo; skipping config setup"
            return 1
        fi
    fi

    local owner group
    owner=$(stat -c '%U' "$config_root" 2>/dev/null)
    group=$(stat -c '%G' "$config_root" 2>/dev/null)

    if [ "$owner" != "$CONFIG_OWNER_USER" ] || [ "$group" != "$CONFIG_OWNER_GROUP" ]; then
        print_warning "$config_root is owned by $owner:$group; skipping config setup to avoid sudo"
        return 1
    fi

    if [ ! -w "$config_root" ]; then
        print_warning "$config_root is not writable; skipping config setup"
        return 1
    fi

    return 0
}

warn_on_ownership_mismatch() {
    local target="$1"

    if [ -e "$target" ]; then
        local owner group
        owner=$(stat -c '%U' "$target" 2>/dev/null)
        group=$(stat -c '%G' "$target" 2>/dev/null)

        if [ "$owner" != "$CONFIG_OWNER_USER" ] || [ "$group" != "$CONFIG_OWNER_GROUP" ]; then
            print_warning "$target is owned by $owner:$group; leaving ownership unchanged to avoid sudo"
        fi
    fi
}

prompt_yes_no() {
    local result_var="$1"
    local prompt="$2"
    local answer

    if [ "$AUTO_YES" = true ]; then
        printf -v "$result_var" "y"
    else
        read -r -p "$prompt" answer
        printf -v "$result_var" "%s" "$answer"
    fi
}

load_nvm_node() {
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        return
    fi

    export NVM_DIR="${NVM_DIR:-$CONFIG_HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # Sourcing nvm only changes this shell's environment.  The normal
        # installer keeps the existing behavior of selecting Node 24 first.
        . "$NVM_DIR/nvm.sh"
        if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
            nvm use 24 >/dev/null 2>&1 || nvm use node >/dev/null 2>&1 || true
        fi
    fi
}

command_usable() {
    local command_name="$1"
    local version_arg="${2:---version}"

    command -v "$command_name" >/dev/null 2>&1 || return 1
    "$command_name" "$version_arg" >/dev/null 2>&1
}

# Parse arguments
AUTO_YES=false
PREFLIGHT=false
SELECT_ALL=false
SELECT_ARCEE=false
SELECT_CLAUDE=false
SELECT_DEEPSEEK=false
SELECT_GEMINI=false
SELECT_GROK=false
SELECT_KIMI=false
SELECT_MUSE=false
SELECT_MIMO=false
SELECT_MCODE=false
SELECT_OMP=false
SELECT_CODEX=false
SELECT_OPENCODE=false
SELECT_PI=false
SELECT_PRIME=false
SELECT_QWEN=false
SELECTION_MADE=false

print_usage() {
    echo "Usage: $0 [-y|--auto] [--preflight] (--all | CLI flags...)"
    echo "  -y, --auto  Automatically install selected CLIs"
    echo "  --preflight Check selected CLIs without installing or changing config"
    echo "  --all       Select every coding CLI"
    echo "  --arcee     Select Arcee nac"
    echo "  --claude    Select Claude Code"
    echo "  --deepseek  Select DeepSeek Harness"
    echo "  --gemini    Select Gemini CLI"
    echo "  --grok      Select Grok Build"
    echo "  --kimi      Select Kimi Code"
    echo "  --muse      Select Meta Muse Code"
    echo "  --mimo      Select MiMo Code"
    echo "  --mcode     Select MiniMax Code"
    echo "  --omp       Select OMP"
    echo "  --codex     Select OpenAI Codex"
    echo "  --opencode  Select OpenCode"
    echo "  --pi        Select Pi"
    echo "  --prime     Select Prime Intellect Agent"
    echo "  --qwen      Select Qwen Code"
    echo "  -h, --help  Show this help message"
}

for arg in "$@"; do
    case "$arg" in
        -y|--auto) AUTO_YES=true ;;
        --preflight) PREFLIGHT=true ;;
        --all) SELECT_ALL=true; SELECTION_MADE=true ;;
        --arcee) SELECT_ARCEE=true; SELECTION_MADE=true ;;
        --claude) SELECT_CLAUDE=true; SELECTION_MADE=true ;;
        --deepseek) SELECT_DEEPSEEK=true; SELECTION_MADE=true ;;
        --gemini) SELECT_GEMINI=true; SELECTION_MADE=true ;;
        --grok) SELECT_GROK=true; SELECTION_MADE=true ;;
        --kimi) SELECT_KIMI=true; SELECTION_MADE=true ;;
        --muse) SELECT_MUSE=true; SELECTION_MADE=true ;;
        --mimo) SELECT_MIMO=true; SELECTION_MADE=true ;;
        --mcode) SELECT_MCODE=true; SELECTION_MADE=true ;;
        --omp) SELECT_OMP=true; SELECTION_MADE=true ;;
        --codex) SELECT_CODEX=true; SELECTION_MADE=true ;;
        --opencode) SELECT_OPENCODE=true; SELECTION_MADE=true ;;
        --pi) SELECT_PI=true; SELECTION_MADE=true ;;
        --prime) SELECT_PRIME=true; SELECTION_MADE=true ;;
        --qwen) SELECT_QWEN=true; SELECTION_MADE=true ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $arg"
            print_usage
            exit 1
            ;;
    esac
done

if [ "$SELECTION_MADE" = false ]; then
    print_error "Select at least one coding CLI flag or use --all."
    print_usage
    exit 1
fi

section_selected() {
    local selected="$1"
    [ "$SELECT_ALL" = true ] || [ "$selected" = true ]
}

curl_cli_selected() {
    section_selected "$SELECT_ARCEE" ||
        section_selected "$SELECT_CLAUDE" ||
        section_selected "$SELECT_GROK" ||
        section_selected "$SELECT_KIMI" ||
        section_selected "$SELECT_MUSE" ||
        section_selected "$SELECT_MIMO" ||
        section_selected "$SELECT_MCODE" ||
        section_selected "$SELECT_OMP" ||
        section_selected "$SELECT_CODEX" ||
        section_selected "$SELECT_OPENCODE" ||
        section_selected "$SELECT_PRIME" ||
        section_selected "$SELECT_QWEN"
}

CLI_KEYS=(arcee claude deepseek gemini grok kimi muse mimo mcode omp codex opencode pi prime qwen)
CLI_LABELS=(
    "Arcee nac"
    "Claude Code"
    "DeepSeek Harness"
    "Gemini CLI"
    "Grok Build"
    "Kimi Code"
    "Meta Muse Code"
    "MiMo Code"
    "MiniMax Code"
    "OMP"
    "OpenAI Codex"
    "OpenCode"
    "Pi"
    "Prime Intellect Agent"
    "Qwen Code"
)
declare -A CLI_STATUS CLI_REASON
for cli_key in "${CLI_KEYS[@]}"; do
    CLI_STATUS["$cli_key"]="PENDING"
    CLI_REASON["$cli_key"]=""
done

set_cli_status() {
    local cli_key="$1"
    local status="$2"
    local reason="${3:-}"
    CLI_STATUS["$cli_key"]="$status"
    CLI_REASON["$cli_key"]="$reason"
}

cli_selected_by_key() {
    case "$1" in
        arcee) section_selected "$SELECT_ARCEE" ;;
        claude) section_selected "$SELECT_CLAUDE" ;;
        deepseek) section_selected "$SELECT_DEEPSEEK" ;;
        gemini) section_selected "$SELECT_GEMINI" ;;
        grok) section_selected "$SELECT_GROK" ;;
        kimi) section_selected "$SELECT_KIMI" ;;
        muse) section_selected "$SELECT_MUSE" ;;
        mimo) section_selected "$SELECT_MIMO" ;;
        mcode) section_selected "$SELECT_MCODE" ;;
        omp) section_selected "$SELECT_OMP" ;;
        codex) section_selected "$SELECT_CODEX" ;;
        opencode) section_selected "$SELECT_OPENCODE" ;;
        pi) section_selected "$SELECT_PI" ;;
        prime) section_selected "$SELECT_PRIME" ;;
        qwen) section_selected "$SELECT_QWEN" ;;
        *) return 1 ;;
    esac
}

normalise_planned_flag() {
    case "${1:-0}" in
        1|true|TRUE|yes|YES|y|Y) echo 1 ;;
        *) echo 0 ;;
    esac
}

run_preflight() {
    local planned_core planned_node planned_pnpm curl_checked=false curl_unusable=false
    planned_core="$(normalise_planned_flag "${SETUP_PLANNED_CORE:-0}")"
    planned_node="$(normalise_planned_flag "${SETUP_PLANNED_NODE:-0}")"
    planned_pnpm="$(normalise_planned_flag "${SETUP_PLANNED_PNPM:-0}")"

    if [ ! -r "$SCRIPT_DIR/preflight.sh" ]; then
        print_error "Shared preflight helper not found: $SCRIPT_DIR/preflight.sh"
        return 1
    fi
    if ! . "$(dirname -- "${BASH_SOURCE[0]}")/preflight.sh"; then
        print_error "Failed to load shared preflight helper: $SCRIPT_DIR/preflight.sh"
        return 1
    fi
    preflight_init "Coding CLIs"
    preflight_info "Checking selected coding CLI prerequisites and upstream sources"

    # Resolve an already-installed nvm Node without installing anything or
    # touching shell startup files.  This makes a usable nvm Node visible to
    # the checks below when the caller's shell has not loaded nvm yet.
    if section_selected "$SELECT_DEEPSEEK" ||
       section_selected "$SELECT_GEMINI" ||
       section_selected "$SELECT_PI" ||
       section_selected "$SELECT_PRIME"; then
        if { ! command_usable node || [ "$planned_node" = 1 ]; } &&
           [ -s "${NVM_DIR:-$CONFIG_HOME/.nvm}/nvm.sh" ]; then
            export NVM_DIR="${NVM_DIR:-$CONFIG_HOME/.nvm}"
            . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
            if command -v nvm >/dev/null 2>&1; then
                nvm use 24 >/dev/null 2>&1 || nvm use node >/dev/null 2>&1 || true
            fi
        fi
    fi

    local node_present=false npm_present=false pnpm_present=false
    if command -v node >/dev/null 2>&1; then node_present=true; fi
    if command -v npm >/dev/null 2>&1; then npm_present=true; fi
    if command -v pnpm >/dev/null 2>&1; then pnpm_present=true; fi
    if section_selected "$SELECT_DEEPSEEK" ||
       section_selected "$SELECT_GEMINI" ||
       section_selected "$SELECT_PI" ||
       section_selected "$SELECT_PRIME"; then
        preflight_command node "$planned_node"
        if [ "$node_present" = true ]; then
            if ! node --version >/dev/null 2>&1; then
                if [ "$planned_node" = 1 ]; then
                    preflight_defer "Existing Node.js is not usable; planned Node.js 24 will replace it"
                else
                    preflight_error "Node.js is present but cannot execute"
                fi
            else
                preflight_info "Node.js is usable"
            fi
        elif [ "$planned_node" = 1 ]; then
            preflight_defer "Node.js will be provided by the planned dependency stage"
        fi
    fi

    if section_selected "$SELECT_GEMINI" ||
       section_selected "$SELECT_PI" ||
       section_selected "$SELECT_PRIME"; then
        preflight_command npm "$planned_node"
        if [ "$npm_present" = true ]; then
            if ! npm --version >/dev/null 2>&1; then
                if [ "$planned_node" = 1 ]; then
                    preflight_defer "Existing npm is not usable; planned Node.js 24 will replace it"
                else
                    preflight_error "npm is present but cannot execute"
                fi
            else
                preflight_info "npm is usable"
            fi
        elif [ "$planned_node" = 1 ]; then
            preflight_defer "npm will be provided by the planned Node.js stage"
        fi
    fi
    if section_selected "$SELECT_DEEPSEEK"; then
        preflight_info "Checking DeepSeek Harness"
        preflight_command pnpm "$planned_pnpm"
        if [ "$pnpm_present" = true ]; then
            if ! pnpm --version >/dev/null 2>&1; then
                if [ "$planned_pnpm" = 1 ]; then
                    preflight_defer "Existing pnpm is not usable; planned pnpm will replace it"
                else
                    preflight_error "pnpm is present but cannot execute"
                fi
            fi
        elif [ "$planned_pnpm" = 1 ]; then
            preflight_defer "pnpm will be provided by the planned dependency stage"
        fi
        preflight_command git "$planned_core"
        if command -v git >/dev/null 2>&1 && ! git --version >/dev/null 2>&1; then
            if [ "$planned_core" = 1 ]; then
                preflight_defer "Existing git is not usable; planned core dependencies will replace it"
            else
                preflight_error "git is present but cannot execute"
            fi
        fi
        preflight_url "DeepSeek Harness repository" "$DEEPSEEK_REPO_URL"

        if [ -e "$DEEPSEEK_HARNESS_DIR" ]; then
            if [ ! -d "$DEEPSEEK_HARNESS_DIR/.git" ]; then
                preflight_error "DeepSeek Harness path exists but is not a Git checkout: $DEEPSEEK_HARNESS_DIR"
            elif command -v git >/dev/null 2>&1; then
                if ! git -C "$DEEPSEEK_HARNESS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    if [ "$planned_core" = 1 ]; then
                        preflight_defer "DeepSeek Harness checkout validation deferred until planned git is available"
                    else
                        preflight_error "DeepSeek Harness checkout is invalid: $DEEPSEEK_HARNESS_DIR"
                    fi
                fi
            elif [ "$planned_core" = 1 ]; then
                preflight_defer "DeepSeek Harness checkout validation requires planned git"
            fi
            if [ ! -w "$DEEPSEEK_HARNESS_DIR" ]; then
                preflight_error "DeepSeek Harness checkout is not writable: $DEEPSEEK_HARNESS_DIR"
            fi
        else
            preflight_writable "$DEEPSEEK_HARNESS_DIR"
        fi
    fi
    if curl_cli_selected; then
        if [ -z "$HOME" ]; then
            preflight_error "Selected curl installers require a HOME directory"
        else
            preflight_writable "$HOME"
            preflight_writable "$HOME/.local/bin"
        fi
    fi

    preflight_check_curl_source() {
        local label="$1" url="$2"
        if [ "$curl_checked" = false ]; then
            preflight_command curl "$planned_core"
            if command -v curl >/dev/null 2>&1 && ! curl --version >/dev/null 2>&1; then
                curl_unusable=true
                if [ "$planned_core" = 1 ]; then
                    preflight_defer "Existing curl is not usable; planned core dependencies will replace it"
                else
                    preflight_error "curl is present but cannot execute"
                fi
            fi
            curl_checked=true
        fi
        if [ "$curl_unusable" = true ]; then
            preflight_defer "$label endpoint check deferred until usable curl is available"
        else
            preflight_url "$label" "$url"
        fi
    }

    if section_selected "$SELECT_ARCEE"; then
        preflight_info "Checking Arcee nac"
        preflight_check_curl_source "Arcee nac installer" "$NAC_INSTALL_URL"
    fi
    if section_selected "$SELECT_CLAUDE"; then
        if [ -e "$HOME/.bashrc" ] && [ ! -w "$HOME/.bashrc" ]; then
            preflight_error "Claude Code PATH configuration file is not writable: $HOME/.bashrc"
        elif [ ! -e "$HOME/.bashrc" ]; then
            preflight_writable "$HOME/.bashrc"
        fi
        preflight_info "Checking Claude Code"
        preflight_check_curl_source "Claude Code installer" "$CLAUDE_INSTALL_URL"
    fi
    if section_selected "$SELECT_GROK"; then
        preflight_info "Checking Grok Build"
        preflight_check_curl_source "Grok Build installer" "$GROK_INSTALL_URL"
    fi
    if section_selected "$SELECT_KIMI"; then
        preflight_info "Checking Kimi Code"
        preflight_check_curl_source "Kimi Code installer" "$KIMI_INSTALL_URL"
    fi
    if section_selected "$SELECT_MUSE"; then
        preflight_info "Checking Meta Muse Code"
        preflight_check_curl_source "Meta Muse Code installer" "$MUSE_INSTALL_URL"
    fi
    if section_selected "$SELECT_MIMO"; then
        preflight_info "Checking MiMo Code"
        preflight_check_curl_source "MiMo Code installer" "$MIMO_INSTALL_URL"
    fi
    if section_selected "$SELECT_MCODE"; then
        preflight_info "Checking MiniMax Code"
        preflight_check_curl_source "MiniMax Code installer" "$MCODE_INSTALL_URL"
    fi
    if section_selected "$SELECT_OMP"; then
        preflight_info "Checking OMP"
        preflight_check_curl_source "OMP installer" "$OMP_INSTALL_URL"
    fi
    if section_selected "$SELECT_CODEX"; then
        preflight_info "Checking OpenAI Codex"
        preflight_check_curl_source "OpenAI Codex installer" "$CODEX_INSTALL_URL"
    fi
    if section_selected "$SELECT_OPENCODE"; then
        preflight_info "Checking OpenCode"
        preflight_check_curl_source "OpenCode installer" "$OPENCODE_INSTALL_URL"
    fi
    if section_selected "$SELECT_PRIME"; then
        preflight_info "Checking Prime Intellect Agent"
        preflight_check_curl_source "Prime Intellect Agent installer" "$PRIME_INSTALL_URL"
        preflight_command setsid "$planned_core"
        if command -v setsid >/dev/null 2>&1 && ! setsid --version >/dev/null 2>&1; then
            if [ "$planned_core" = 1 ]; then
                preflight_defer "Existing setsid is not usable; planned core dependencies will replace it"
            else
                preflight_error "setsid is present but cannot execute"
            fi
        fi
    fi
    if section_selected "$SELECT_QWEN"; then
        preflight_info "Checking Qwen Code"
        preflight_check_curl_source "Qwen Code installer" "$QWEN_INSTALL_URL"
    fi

    preflight_npm_package() {
        local label="$1" package_name="$2" metadata_url="$3"
        local metadata_tmp compatibility effective_node_version

        if ! preflight_can_fetch; then
            if [ "$planned_core" = 1 ]; then
                preflight_defer "$label npm metadata check deferred until planned fetch tooling is available"
            else
                preflight_error "$label npm metadata cannot be checked because curl/wget is unavailable"
            fi
            return 0
        fi

        metadata_tmp="$(mktemp "${TMPDIR:-/tmp}/coding-cli-npm.XXXXXX" 2>/dev/null)" || {
            preflight_error "$label npm metadata check could not create a temporary file"
            return 0
        }
        if ! preflight_fetch "$metadata_url" >"$metadata_tmp"; then
            rm -f "$metadata_tmp"
            preflight_error "$label npm package metadata could not be fetched: $package_name"
            return 0
        fi
        if [ ! -s "$metadata_tmp" ]; then
            rm -f "$metadata_tmp"
            preflight_error "$label npm package metadata was empty: $package_name"
            return 0
        fi

        if ! command_usable node || ! command_usable npm; then
            rm -f "$metadata_tmp"
            if [ "$planned_node" = 1 ]; then
                preflight_defer "$label Node.js compatibility check deferred until planned Node.js 24 is available"
            else
                preflight_error "$label Node.js compatibility cannot be checked because Node.js is unusable"
            fi
            return 0
        fi

        effective_node_version="$(node --version 2>/dev/null || true)"
        if [ "$planned_node" = 1 ]; then
            effective_node_version="24.x"
        fi
        # Use npm's own semver implementation, not a partial range parser.
        compatibility="$(node - "$metadata_tmp" "$effective_node_version" "$package_name" \
            "$(command -v npm)" "$planned_node" 2>/dev/null <<'NODE'
const fs = require("fs");
try {
    const [metadataPath, target, expected, npmBinary, planned] = process.argv.slice(2);
    const metadata = JSON.parse(fs.readFileSync(metadataPath, "utf8"));
    if (metadata.name !== expected || !metadata.version) {
        process.stdout.write("mismatch");
    } else {
        const engine = metadata.engines && metadata.engines.node;
        if (!engine) {
            process.stdout.write("none");
        } else {
            const npmRequire = require("module").createRequire(fs.realpathSync(npmBinary));
            const semver = npmRequire("semver");
            if (!semver.validRange(engine)) {
                process.stdout.write("unknown");
            } else if (planned === "1") {
                process.stdout.write(semver.intersects(target, engine) ? "planned" : "incompatible");
            } else {
                process.stdout.write(semver.satisfies(target, engine) ? "ok" : "incompatible");
            }
        }
    }
} catch (error) {
    process.stdout.write("unknown");
}
NODE
        )" || compatibility="unknown"
        rm -f "$metadata_tmp"

        case "$compatibility" in
            ok)
                preflight_info "$label npm package metadata is available and compatible with Node.js $effective_node_version"
                ;;
            planned)
                preflight_defer "$label supports the planned Node.js 24 series; its exact version will be checked after Node installation"
                ;;
            none)
                preflight_info "$label npm package metadata is available; no Node.js engine requirement is published"
                ;;
            mismatch)
                preflight_error "$label metadata endpoint returned a different package than $package_name"
                ;;
            incompatible)
                preflight_error "$label requires a Node.js version incompatible with $effective_node_version"
                ;;
            *)
                if [ "$planned_node" = 1 ]; then
                    preflight_defer "$label engine check requires the planned working Node.js/npm installation"
                else
                    preflight_error "$label Node.js engine requirement could not be evaluated from package metadata"
                fi
                ;;
        esac
    }

    if section_selected "$SELECT_GEMINI"; then
        preflight_info "Checking Gemini CLI"
        preflight_npm_package "Gemini CLI" "$GEMINI_PACKAGE" "$GEMINI_PACKAGE_METADATA_URL"
    fi
    if section_selected "$SELECT_PI"; then
        preflight_info "Checking Pi"
        preflight_npm_package "Pi" "$PI_PACKAGE" "$PI_PACKAGE_METADATA_URL"
    fi

    if section_selected "$SELECT_OPENCODE"; then
        local opencode_config_source="$SCRIPT_DIR/../configs/opencode.json"
        local opencode_config_dir="$CONFIG_ROOT/opencode"
        if [ ! -r "$opencode_config_source" ]; then
            preflight_error "OpenCode config source is missing or unreadable: $opencode_config_source"
        fi
        if [ -e "$CONFIG_ROOT" ]; then
            if [ ! -d "$CONFIG_ROOT" ]; then
                preflight_error "OpenCode config root is not a directory: $CONFIG_ROOT"
            else
                local config_owner config_group
                config_owner=$(stat -c '%U' "$CONFIG_ROOT" 2>/dev/null)
                config_group=$(stat -c '%G' "$CONFIG_ROOT" 2>/dev/null)
                if [ "$config_owner" != "$CONFIG_OWNER_USER" ] || [ "$config_group" != "$CONFIG_OWNER_GROUP" ]; then
                    preflight_error "OpenCode config root is owned by $config_owner:$config_group, expected $CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP"
                fi
                if [ ! -w "$CONFIG_ROOT" ]; then
                    preflight_error "OpenCode config root is not writable: $CONFIG_ROOT"
                fi
            fi
        else
            preflight_writable "$CONFIG_ROOT"
        fi
        if [ -e "$opencode_config_dir" ] && [ ! -d "$opencode_config_dir" ]; then
            preflight_error "OpenCode config path is not a directory: $opencode_config_dir"
        elif [ -d "$opencode_config_dir" ] && [ ! -w "$opencode_config_dir" ]; then
            preflight_error "OpenCode config directory is not writable: $opencode_config_dir"
        fi
    fi

    return 0
}

print_info "Coding CLI Installer"
echo ""

if [ "$PREFLIGHT" = true ]; then
    run_preflight
    preflight_run_status=$?
    if [ "$preflight_run_status" -ne 0 ]; then
        exit "$preflight_run_status"
    fi
    preflight_finish
    exit $?
fi

# Resolve a previously installed nvm Node before checking normal-install
# prerequisites.  This does not install Node or edit shell startup files.
if section_selected "$SELECT_DEEPSEEK" ||
   section_selected "$SELECT_GEMINI" ||
   section_selected "$SELECT_PI" ||
   section_selected "$SELECT_PRIME"; then
    load_nvm_node
fi

NODE_AVAILABLE=false
NPM_AVAILABLE=false
PNPM_AVAILABLE=false
CURL_AVAILABLE=false
if command_usable node; then NODE_AVAILABLE=true; fi
if command_usable npm; then NPM_AVAILABLE=true; fi
if command_usable pnpm; then PNPM_AVAILABLE=true; fi
if command_usable curl; then CURL_AVAILABLE=true; fi

require_curl_cli() {
    local cli_key="$1" label="$2"
    if [ "$CURL_AVAILABLE" != true ]; then
        set_cli_status "$cli_key" "BLOCKED" "curl is not available"
        print_error "$label blocked: curl was not found or is not usable"
        return 1
    fi
    return 0
}

require_node_npm_cli() {
    local cli_key="$1" label="$2"
    if [ "$NODE_AVAILABLE" != true ] || [ "$NPM_AVAILABLE" != true ]; then
        set_cli_status "$cli_key" "BLOCKED" "usable Node.js and npm are required"
        print_error "$label blocked: usable Node.js and npm were not found"
        return 1
    fi
    return 0
}

require_deepseek_cli() {
    if [ "$NODE_AVAILABLE" != true ]; then
        set_cli_status deepseek "BLOCKED" "usable Node.js is required"
        print_error "DeepSeek Harness blocked: usable Node.js was not found"
        return 1
    fi
    if [ "$PNPM_AVAILABLE" != true ]; then
        set_cli_status deepseek "BLOCKED" "usable pnpm is required"
        print_error "DeepSeek Harness blocked: usable pnpm was not found"
        return 1
    fi
    if ! command_usable git; then
        set_cli_status deepseek "BLOCKED" "usable git is required"
        print_error "DeepSeek Harness blocked: usable git was not found"
        return 1
    fi
    return 0
}

require_prime_cli() {
    if ! require_node_npm_cli prime "Prime Intellect Agent"; then
        return 1
    fi
    if ! require_curl_cli prime "Prime Intellect Agent"; then
        return 1
    fi
    if ! command_usable setsid; then
        set_cli_status prime "BLOCKED" "usable setsid is required"
        print_error "Prime Intellect Agent blocked: usable setsid was not found"
        return 1
    fi
    return 0
}

print_info "Available coding CLIs to install:"
print_info "  1. Arcee nac (nac)"
print_info "  2. Claude Code (@anthropic-ai/claude-code)"
print_info "  3. DeepSeek Harness (dsh)"
print_info "  4. Gemini CLI (@google/gemini-cli)"
print_info "  5. Grok Build (grok)"
print_info "  6. Kimi Code"
print_info "  7. Meta Muse Code"
print_info "  8. MiMo Code"
print_info "  9. MiniMax Code (mcode)"
print_info "  10. OMP (omp)"
print_info "  11. OpenAI Codex (@openai/codex)"
print_info "  12. OpenCode (opencode-ai)"
print_info "  13. Pi"
print_info "  14. Prime Intellect Agent"
print_info "  15. Qwen Code"
echo ""

if section_selected "$SELECT_ARCEE"; then
    if require_curl_cli arcee "Arcee nac"; then
        prompt_yes_no INSTALL_NAC "  Install Arcee nac? (y/n): "
        if [[ "$INSTALL_NAC" =~ ^[Yy]$ ]]; then
            print_info "Installing Arcee nac..."
            if curl -fsSL "$NAC_INSTALL_URL" | sh; then
                print_info "Arcee nac installed"
                set_cli_status arcee "INSTALLED"
            else
                print_error "Failed to install Arcee nac"
                set_cli_status arcee "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped Arcee nac installation"
            set_cli_status arcee "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_CLAUDE"; then
    if require_curl_cli claude "Claude Code"; then
        prompt_yes_no INSTALL_CLAUDE "  Install Claude Code? (y/n): "
        if [[ "$INSTALL_CLAUDE" =~ ^[Yy]$ ]]; then
            print_info "Installing Claude Code..."
            if curl -fsSL "$CLAUDE_INSTALL_URL" | bash; then
                print_info "Claude Code installed"
                CLAUDE_BIN_DIR="$HOME/.local/bin"
                CLAUDE_PATH_EXPORT='export PATH="$HOME/.local/bin:$PATH"'
                BASHRC_PATH="$HOME/.bashrc"
                if ! grep -Fqx "$CLAUDE_PATH_EXPORT" "$BASHRC_PATH" 2>/dev/null; then
                    if printf '\n%s\n' "$CLAUDE_PATH_EXPORT" >> "$BASHRC_PATH"; then
                        print_info "Added $CLAUDE_BIN_DIR to PATH in $BASHRC_PATH"
                    else
                        print_error "Claude Code installed, but failed to add $CLAUDE_BIN_DIR to PATH in $BASHRC_PATH"
                        set_cli_status claude "FAILED" "PATH setup failed"
                    fi
                fi
                case ":$PATH:" in
                    *":$CLAUDE_BIN_DIR:"*) ;;
                    *) export PATH="$CLAUDE_BIN_DIR:$PATH" ;;
                esac
                if [ "${CLI_STATUS[claude]}" = "PENDING" ]; then
                    set_cli_status claude "INSTALLED"
                fi
            else
                print_error "Failed to install Claude Code"
                set_cli_status claude "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped Claude Code installation"
            set_cli_status claude "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_DEEPSEEK"; then
    if require_deepseek_cli; then
        prompt_yes_no INSTALL_DEEPSEEK "  Install DeepSeek Harness? (y/n): "
        if [[ "$INSTALL_DEEPSEEK" =~ ^[Yy]$ ]]; then
            DEEPSEEK_READY=true

            if [ -e "$DEEPSEEK_HARNESS_DIR" ] && [ ! -d "$DEEPSEEK_HARNESS_DIR/.git" ]; then
                print_error "Cannot clone DeepSeek Harness because $DEEPSEEK_HARNESS_DIR already exists and is not a Git checkout"
                set_cli_status deepseek "BLOCKED" "existing path is not a Git checkout"
                DEEPSEEK_READY=false
            elif [ -d "$DEEPSEEK_HARNESS_DIR/.git" ]; then
                if git -C "$DEEPSEEK_HARNESS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    print_info "Using existing DeepSeek Harness checkout at $DEEPSEEK_HARNESS_DIR"
                else
                    print_error "DeepSeek Harness checkout is invalid: $DEEPSEEK_HARNESS_DIR"
                    set_cli_status deepseek "BLOCKED" "existing checkout is invalid"
                    DEEPSEEK_READY=false
                fi
            else
                print_info "Cloning DeepSeek Harness into $DEEPSEEK_HARNESS_DIR..."
                if ! git clone "$DEEPSEEK_REPO_URL" "$DEEPSEEK_HARNESS_DIR"; then
                    print_error "Failed to clone DeepSeek Harness"
                    set_cli_status deepseek "FAILED" "git clone failed"
                    DEEPSEEK_READY=false
                fi
            fi

            if [ "$DEEPSEEK_READY" = true ]; then
                print_info "Installing and building DeepSeek Harness..."
                if (
                    cd "$DEEPSEEK_HARNESS_DIR" &&
                    pnpm install &&
                    pnpm run build
                ); then
                    print_info "DeepSeek Harness installed"
                    print_info "Run it with: cd \"$DEEPSEEK_HARNESS_DIR\" && pnpm dsh web"
                    set_cli_status deepseek "INSTALLED"
                else
                    print_error "Failed to install or build DeepSeek Harness"
                    set_cli_status deepseek "FAILED" "pnpm install/build failed"
                fi
            fi
        else
            print_info "Skipped DeepSeek Harness installation"
            set_cli_status deepseek "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_GEMINI"; then
    if require_node_npm_cli gemini "Gemini CLI"; then
        prompt_yes_no INSTALL_GEMINI "  Install Gemini CLI? (y/n): "
        if [[ "$INSTALL_GEMINI" =~ ^[Yy]$ ]]; then
            if ! GEMINI_PREFIX=$(npm prefix --global) || [ -z "$GEMINI_PREFIX" ]; then
                print_error "Cannot determine the npm global installation path for Gemini CLI"
                set_cli_status gemini "BLOCKED" "npm global prefix is unavailable"
            elif npm install --global "${GEMINI_PACKAGE}@latest"; then
                GEMINI_BINARY="$GEMINI_PREFIX/bin/gemini"
                if [ -x "$GEMINI_BINARY" ] && "$GEMINI_BINARY" --version; then
                    print_info "Gemini CLI installed at $GEMINI_BINARY"
                    set_cli_status gemini "INSTALLED"
                    case ":$PATH:" in
                        *":$GEMINI_PREFIX/bin:"*) ;;
                        *) print_warning "Add $GEMINI_PREFIX/bin to PATH to run gemini." ;;
                    esac
                else
                    print_error "Gemini CLI was not usable at $GEMINI_BINARY"
                    set_cli_status gemini "FAILED" "installed gemini executable failed verification"
                fi
            else
                print_error "Failed to install ${GEMINI_PACKAGE}@latest"
                set_cli_status gemini "FAILED" "npm install failed"
            fi
        else
            print_info "Skipped Gemini CLI installation"
            set_cli_status gemini "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_GROK"; then
    if require_curl_cli grok "Grok Build"; then
        prompt_yes_no INSTALL_GROK "  Install Grok Build? (y/n): "
        if [[ "$INSTALL_GROK" =~ ^[Yy]$ ]]; then
            print_info "Installing Grok Build..."
            if curl -fsSL "$GROK_INSTALL_URL" | bash; then
                print_info "Grok Build installed"
                set_cli_status grok "INSTALLED"
            else
                print_error "Failed to install Grok Build"
                set_cli_status grok "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped Grok Build installation"
            set_cli_status grok "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_KIMI"; then
    if require_curl_cli kimi "Kimi Code"; then
        prompt_yes_no INSTALL_KIMI "  Install Kimi Code? (y/n): "
        if [[ "$INSTALL_KIMI" =~ ^[Yy]$ ]]; then
            print_info "Installing Kimi Code..."
            if curl -fsSL "$KIMI_INSTALL_URL" | bash; then
                print_info "Kimi Code installed"
                set_cli_status kimi "INSTALLED"
            else
                print_error "Failed to install Kimi Code"
                set_cli_status kimi "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped Kimi Code installation"
            set_cli_status kimi "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_MUSE"; then
    if require_curl_cli muse "Meta Muse Code"; then
        prompt_yes_no INSTALL_MUSE "  Install Meta Muse Code? (y/n): "
        if [[ "$INSTALL_MUSE" =~ ^[Yy]$ ]]; then
            print_info "Installing Meta Muse Code..."
            if curl -fsSL "$MUSE_INSTALL_URL" | bash; then
                print_info "Meta Muse Code installed"
                set_cli_status muse "INSTALLED"
            else
                print_error "Failed to install Meta Muse Code"
                set_cli_status muse "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped Meta Muse Code installation"
            set_cli_status muse "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_MIMO"; then
    if require_curl_cli mimo "MiMo Code"; then
        prompt_yes_no INSTALL_MIMO "  Install MiMo Code? (y/n): "
        if [[ "$INSTALL_MIMO" =~ ^[Yy]$ ]]; then
            print_info "Installing MiMo Code..."
            if curl -fsSL "$MIMO_INSTALL_URL" | bash; then
                print_info "MiMo Code installed"
                set_cli_status mimo "INSTALLED"
            else
                print_error "Failed to install MiMo Code"
                set_cli_status mimo "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped MiMo Code installation"
            set_cli_status mimo "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_MCODE"; then
    if require_curl_cli mcode "MiniMax Code"; then
        prompt_yes_no INSTALL_MCODE "  Install MiniMax Code? (y/n): "
        if [[ "$INSTALL_MCODE" =~ ^[Yy]$ ]]; then
            print_info "Installing MiniMax Code..."
            if curl -fsSL "$MCODE_INSTALL_URL" | bash; then
                print_info "MiniMax Code installed"
                set_cli_status mcode "INSTALLED"
            else
                print_error "Failed to install MiniMax Code"
                set_cli_status mcode "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped MiniMax Code installation"
            set_cli_status mcode "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_OMP"; then
    if require_curl_cli omp "OMP"; then
        prompt_yes_no INSTALL_OMP "  Install OMP? (y/n): "
        if [[ "$INSTALL_OMP" =~ ^[Yy]$ ]]; then
            print_info "Installing OMP..."
            if curl -fsSL "$OMP_INSTALL_URL" | sh; then
                print_info "OMP installed"
                set_cli_status omp "INSTALLED"
            else
                print_error "Failed to install OMP"
                set_cli_status omp "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped OMP installation"
            set_cli_status omp "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_CODEX"; then
    if require_curl_cli codex "OpenAI Codex"; then
        prompt_yes_no INSTALL_CODEX "  Install OpenAI Codex? (y/n): "
        if [[ "$INSTALL_CODEX" =~ ^[Yy]$ ]]; then
            print_info "Installing OpenAI Codex..."
            if curl -fsSL "$CODEX_INSTALL_URL" | CODEX_NON_INTERACTIVE=1 sh; then
                print_info "OpenAI Codex installed"
                set_cli_status codex "INSTALLED"
            else
                print_error "Failed to install OpenAI Codex"
                set_cli_status codex "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped OpenAI Codex installation"
            set_cli_status codex "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_OPENCODE"; then
    if require_curl_cli opencode "OpenCode"; then
        prompt_yes_no INSTALL_OPENCODE "  Install OpenCode? (y/n): "
        if [[ "$INSTALL_OPENCODE" =~ ^[Yy]$ ]]; then
            OPENCODE_SETUP_OK=true
            print_info "Installing OpenCode..."
            if curl -fsSL "$OPENCODE_INSTALL_URL" | bash; then
                print_info "OpenCode installed"

                OPENCODE_CONFIG_SOURCE="$SCRIPT_DIR/../configs/opencode.json"
                if [ -f "$OPENCODE_CONFIG_SOURCE" ]; then
                    print_info "Setting up OpenCode config..."
                    if ensure_config_ownership "$CONFIG_ROOT"; then
                        OPENCODE_CONFIG_DIR="$CONFIG_ROOT/opencode"
                        OPENCODE_CONFIG_TARGET="$OPENCODE_CONFIG_DIR/opencode.json"
                        if ! mkdir -p "$OPENCODE_CONFIG_DIR"; then
                            print_error "Failed to create OpenCode config directory"
                            OPENCODE_SETUP_OK=false
                        elif cp "$OPENCODE_CONFIG_SOURCE" "$OPENCODE_CONFIG_TARGET"; then
                            warn_on_ownership_mismatch "$OPENCODE_CONFIG_DIR"
                            print_info "OpenCode config copied to $OPENCODE_CONFIG_TARGET"
                        else
                            print_error "Failed to copy OpenCode config"
                            OPENCODE_SETUP_OK=false
                        fi
                    else
                        print_error "Skipping OpenCode config setup due to ownership issues"
                        OPENCODE_SETUP_OK=false
                    fi
                else
                    print_error "OpenCode config not found at $OPENCODE_CONFIG_SOURCE"
                    OPENCODE_SETUP_OK=false
                fi
            else
                print_error "Failed to install OpenCode"
                OPENCODE_SETUP_OK=false
            fi
            if [ "$OPENCODE_SETUP_OK" = true ]; then
                set_cli_status opencode "INSTALLED"
            else
                set_cli_status opencode "FAILED" "installation or config setup failed"
            fi
        else
            print_info "Skipped OpenCode installation"
            set_cli_status opencode "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_PI"; then
    if require_node_npm_cli pi "Pi"; then
        prompt_yes_no INSTALL_PI "  Install Pi? (y/n): "
        if [[ "$INSTALL_PI" =~ ^[Yy]$ ]]; then
            print_info "Installing Pi..."
            if npm install --global --ignore-scripts --no-fund --no-audit --progress=false "$PI_PACKAGE"; then
                print_info "Pi installed"
                set_cli_status pi "INSTALLED"
            else
                print_error "Failed to install Pi"
                set_cli_status pi "FAILED" "npm install failed"
            fi
        else
            print_info "Skipped Pi installation"
            set_cli_status pi "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_PRIME"; then
    if require_prime_cli; then
        prompt_yes_no INSTALL_PRIME "  Install Prime Intellect Agent? (y/n): "
        if [[ "$INSTALL_PRIME" =~ ^[Yy]$ ]]; then
            print_info "Installing Prime Intellect Agent..."
            if curl -fsSL "$PRIME_INSTALL_URL" | PRIME_AGENT_INSTALLER_PLAIN=1 PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 setsid --wait sh; then
                print_info "Prime Intellect Agent installed"
                set_cli_status prime "INSTALLED"
            else
                print_error "Failed to install Prime Intellect Agent"
                set_cli_status prime "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped Prime Intellect Agent installation"
            set_cli_status prime "SKIPPED" "declined"
        fi
    fi
fi

if section_selected "$SELECT_QWEN"; then
    if require_curl_cli qwen "Qwen Code"; then
        prompt_yes_no INSTALL_QWEN "  Install Qwen Code? (y/n): "
        if [[ "$INSTALL_QWEN" =~ ^[Yy]$ ]]; then
            print_info "Installing Qwen Code..."
            if curl -fsSL "$QWEN_INSTALL_URL" | bash; then
                print_info "Qwen Code installed"
                set_cli_status qwen "INSTALLED"
            else
                print_error "Failed to install Qwen Code"
                set_cli_status qwen "FAILED" "upstream installer failed"
            fi
        else
            print_info "Skipped Qwen Code installation"
            set_cli_status qwen "SKIPPED" "declined"
        fi
    fi
fi

echo ""
print_info "Coding CLI installation summary:"
summary_failures=0
for index in "${!CLI_KEYS[@]}"; do
    cli_key="${CLI_KEYS[$index]}"
    if cli_selected_by_key "$cli_key"; then
        status="${CLI_STATUS[$cli_key]}"
        reason="${CLI_REASON[$cli_key]}"
        if [ -n "$reason" ]; then
            print_info "  ${CLI_LABELS[$index]}: $status ($reason)"
        else
            print_info "  ${CLI_LABELS[$index]}: $status"
        fi
        if [ "$status" = FAILED ] || [ "$status" = BLOCKED ]; then
            summary_failures=$((summary_failures + 1))
        fi
    fi
done

if [ "$summary_failures" -gt 0 ]; then
    print_error "Coding CLI installation finished with $summary_failures failed or blocked selection(s)."
    exit 1
fi

print_info "Coding CLI installation complete"
exit 0
