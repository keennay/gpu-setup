#!/bin/bash

# Script: 03_install_python.sh
# Purpose: Check and install the latest Python via pyenv and uv

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_command() { echo -e "${BLUE}[RUN]${NC} $1"; }

is_valid_python_version_arg() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+)+$ ]]
}

# Parse arguments
AUTO_YES=false
INSTALL_UV_SELECTED=false
PYTHON_VERSION_ARG=""
for arg in "$@"; do
    case "$arg" in
        -y|--auto)
            AUTO_YES=true
            ;;
        --uv)
            INSTALL_UV_SELECTED=true
            ;;
        -h|--help)
            echo "Usage: $0 [-y|--auto] [--uv] [python-version]"
            echo "  -y, --auto        Automatically accept Python and pyenv prompts"
            echo "  --uv              Include uv in automatic installation"
            echo "  python-version    Automatically select custom Python version (e.g. 3.11.15)"
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
                print_error "Python version must be numeric, such as 3.11.15."
                exit 1
            fi
            ;;
    esac
done

NEEDS_PATH_UPDATE=false

# Function to reload shell environment
reload_shell_env() {
    # Source bashrc to get latest PATH
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
    
    # Reload pyenv if installed
    if [ -d "$HOME/.pyenv" ]; then
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        if command -v pyenv &> /dev/null; then
            eval "$(pyenv init -)"
        fi
    fi
    
    # Reload cargo/uv path if installed
    if [ -d "$HOME/.cargo/bin" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
}

# Initial environment load
reload_shell_env

print_info "Checking pyenv availability..."
if command -v pyenv &> /dev/null; then
    print_info "✓ pyenv detected ($(pyenv --version | head -1))"
else
    print_warning "pyenv not found; it will be required if you choose to install a new Python version."
fi

find_system_python3() {
    local candidates=(
        /usr/bin/python3
        /usr/local/bin/python3
        /bin/python3
    )

    for candidate in "${candidates[@]}"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    echo ""
    return 1
}

fetch_latest_python_version() {
    local latest=""

    if command -v pyenv &> /dev/null; then
        latest=$(pyenv install --list 2>/dev/null | sed 's/^ *//' | grep -E '^3\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
    fi

    if [ -z "$latest" ] && command -v curl &> /dev/null; then
        latest=$(curl -fsSL https://www.python.org/downloads/ 2>/dev/null | \
            grep -m1 -oP 'Latest Python 3 Release - Python \K[0-9]+\.[0-9]+\.[0-9]+')
    fi

    if [ -z "$latest" ]; then
        latest="3.12.0"
    fi

    echo "$latest"
}

ensure_pyenv() {
    if command -v pyenv &> /dev/null; then
        return 0
    fi

    print_warning "pyenv is not installed"

    local INSTALL_PYENV
    if [ "$AUTO_YES" = true ]; then
        INSTALL_PYENV="y"
        print_info "Automatic mode enabled (-y): installing pyenv"
    else
        read -r -p "Install pyenv? (y/n): " INSTALL_PYENV
    fi

    if [[ ! "$INSTALL_PYENV" =~ ^[Yy]$ ]]; then
        print_error "pyenv installation declined. Cannot proceed with Python installation."
        exit 1
    fi

    print_info "Installing pyenv..."
    curl https://pyenv.run | bash

    if ! grep -q "PYENV_ROOT" ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc <<'EOF'

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

    if command -v pyenv &> /dev/null; then
        print_info "✓ pyenv installed successfully"
        print_info "  Location: $(which pyenv)"
    else
        print_error "pyenv installation failed"
        print_error "Please run: source ~/.bashrc"
        print_error "Then rerun this script"
        exit 1
    fi
}

ensure_runpod_pyenv_guard() {
    local bashrc="$HOME/.bashrc"
    local marker="# runpod_pyenv_guard"

    if [ ! -f "$bashrc" ]; then
        return
    fi

    if ! grep -q "/etc/rp_environment" "$bashrc" 2>/dev/null; then
        return
    fi

    if grep -q "$marker" "$bashrc" 2>/dev/null; then
        return
    fi

    if ! command -v python3 &> /dev/null; then
        print_warning "python3 not available for RunPod guard modification; skipping"
        return
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

# Step 1 & 2: Evaluate current Python and decide on installation
PYENV_EXPECTED=false
TARGET_PYTHON_VERSION=""

print_info "Checking python3 availability..."
CURRENT_PYTHON_VERSION=""
PYTHON_PRESENT=false
PYTHON_PATH=""

if command -v python3 &> /dev/null; then
    PYTHON_PATH=$(command -v python3)
    CURRENT_PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    PYTHON_PRESENT=true
    print_info "✓ python3 found on PATH at $PYTHON_PATH (version $CURRENT_PYTHON_VERSION)"
else
    SYSTEM_PYTHON_BIN=$(find_system_python3)
    if [ -n "$SYSTEM_PYTHON_BIN" ]; then
        CURRENT_PYTHON_VERSION=$($SYSTEM_PYTHON_BIN --version 2>&1 | awk '{print $2}')
        PYTHON_PRESENT=true
        PYTHON_PATH="$SYSTEM_PYTHON_BIN"
        print_info "✓ System python3 located at $SYSTEM_PYTHON_BIN (version $CURRENT_PYTHON_VERSION)"
    else
        print_warning "python3 not found via PATH or standard locations"
    fi
fi

LATEST_PYTHON_VERSION=$(fetch_latest_python_version)
if [ -z "$LATEST_PYTHON_VERSION" ]; then
    LATEST_PYTHON_VERSION="3.12.0"
    print_warning "Unable to determine the latest Python release automatically; defaulting to $LATEST_PYTHON_VERSION"
else
    print_info "Latest Python release detected: $LATEST_PYTHON_VERSION"
fi

PYTHON_ACTION=""

if [ -n "$PYTHON_VERSION_ARG" ]; then
    PYTHON_ACTION="install_custom"
    TARGET_PYTHON_VERSION="$PYTHON_VERSION_ARG"
    print_info "Python version argument provided; selecting custom Python $TARGET_PYTHON_VERSION."
elif [ "$AUTO_YES" = true ]; then
    PYTHON_ACTION="install_latest"
    print_info "Automatic mode enabled (-y): installing the latest Python version via pyenv."
elif [ "$PYTHON_PRESENT" = false ]; then
    print_warning "No existing python3 installation detected; a new version will be installed."
    PYTHON_ACTION="install_latest"
else
    while true; do
        echo "Choose Python setup option:"
        echo "  1) Keep current version ($CURRENT_PYTHON_VERSION)"
        echo "  2) Install latest version via pyenv ($LATEST_PYTHON_VERSION)"
        echo "  3) Install custom version via pyenv"
        read -r -p "Enter choice (1/2/3): " PYTHON_CHOICE

        if [[ ! "$PYTHON_CHOICE" =~ ^[123]$ ]]; then
            print_error "Invalid choice. Please enter 1, 2, or 3."
            continue
        fi

        if [ "$PYTHON_CHOICE" = "1" ]; then
            PYTHON_ACTION="keep"
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

CUSTOM_VERSION=""
if [ "$PYTHON_ACTION" = "install_custom" ] && [ -z "$TARGET_PYTHON_VERSION" ]; then
    while true; do
        read -r -p "Enter desired Python version (e.g. 3.11.8): " CUSTOM_VERSION
        if is_valid_python_version_arg "$CUSTOM_VERSION"; then
            break
        else
            print_error "Invalid version format. Please use numeric values like 3.11.8"
        fi
    done
    TARGET_PYTHON_VERSION="$CUSTOM_VERSION"
fi

if [ "$PYTHON_ACTION" = "keep" ]; then
    TARGET_PYTHON_VERSION="$CURRENT_PYTHON_VERSION"
    print_info "Keeping existing python3 version $TARGET_PYTHON_VERSION"
else
    ensure_pyenv
    PYENV_EXPECTED=true

    if [ "$PYTHON_ACTION" = "install_latest" ]; then
        # Re-fetch latest version now that pyenv is available
        LATEST_PYTHON_VERSION=$(fetch_latest_python_version)
        TARGET_PYTHON_VERSION="$LATEST_PYTHON_VERSION"
    fi

    if [ -z "$TARGET_PYTHON_VERSION" ]; then
        print_error "No target Python version specified"
        exit 1
    fi

    if pyenv versions 2>/dev/null | tr -d ' *' | grep -qx "$TARGET_PYTHON_VERSION"; then
        print_info "Python $TARGET_PYTHON_VERSION already installed via pyenv"
    else
        print_info "Installing Python $TARGET_PYTHON_VERSION via pyenv..."
        print_info "This compiles Python from source and may take several minutes."
        if ! MAKE_OPTS="-j$(nproc)" pyenv install --force "$TARGET_PYTHON_VERSION"; then
            print_error "Failed to install Python $TARGET_PYTHON_VERSION"
            exit 1
        fi
    fi

    pyenv global "$TARGET_PYTHON_VERSION"
    pyenv rehash
    reload_shell_env
    ensure_runpod_pyenv_guard
    CURRENT_PYTHON_VERSION="$TARGET_PYTHON_VERSION"
    PYTHON_PRESENT=true
    print_info "Python $TARGET_PYTHON_VERSION is now set as the global pyenv version"

    if command -v pyenv &> /dev/null; then
        NEW_PYTHON_PATH=$(pyenv which python3 2>/dev/null)
        if [ -n "$NEW_PYTHON_PATH" ]; then
            PYTHON_PATH="$NEW_PYTHON_PATH"
        else
            PYTHON_PATH=$(command -v python3 2>/dev/null)
        fi
    else
        PYTHON_PATH=$(command -v python3 2>/dev/null)
    fi
fi

echo ""

# Step 3: Check and install uv
print_info "Checking uv..."
if command -v uv &> /dev/null; then
    print_info "✓ uv is installed ($(uv --version))"
else
    print_error "✗ uv is not installed"
    
    if [ "$AUTO_YES" = true ]; then
        if [ "$INSTALL_UV_SELECTED" = true ]; then
            INSTALL_UV="y"
        else
            INSTALL_UV="n"
        fi
    else
        read -r -p "Install uv? (y/n): " INSTALL_UV
    fi
    
    if [[ "$INSTALL_UV" =~ ^[Yy]$ ]]; then
        print_info "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        
        # Add to PATH if not present
        if ! grep -q ".cargo/bin" "$HOME/.bashrc"; then
            echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
            print_info "Added cargo/bin to PATH in ~/.bashrc"
            NEEDS_PATH_UPDATE=true
        fi
        
        print_info "Please run: source ~/.bashrc"
        print_info "Then verify with: which uv"
    else
        print_info "Skipping uv installation."
    fi
fi

echo ""
echo "=============================================="

# Final verification
ALL_GOOD=true

print_info "Final verification:"

if command -v pyenv &> /dev/null; then
    print_info "  ✓ pyenv: $(pyenv --version | head -1)"
    print_info "    Location: $(which pyenv)"
elif [ "$PYENV_EXPECTED" = true ]; then
    print_error "  ✗ pyenv not found despite installation attempt"
    ALL_GOOD=false
else
    print_info "  ℹ pyenv not installed (not requested)"
fi

if command -v python3 &> /dev/null; then
    ACTIVE_PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    print_info "  ✓ python3: $(python3 --version)"
    print_info "    Location: $(which python3)"
    if [ -n "$TARGET_PYTHON_VERSION" ] && [ "$PYTHON_ACTION" != "keep" ] && [ "$ACTIVE_PYTHON_VERSION" != "$TARGET_PYTHON_VERSION" ]; then
        print_warning "  ! Expected python3 version $TARGET_PYTHON_VERSION but found $ACTIVE_PYTHON_VERSION"
        print_info "    Run: pyenv global $TARGET_PYTHON_VERSION"
        ALL_GOOD=false
    fi
else
    print_error "  ✗ python3 not found"
    ALL_GOOD=false
fi

echo ""

# Summary
if [ "$ALL_GOOD" = true ]; then
    print_info "✅ All Python tools are properly installed!"
else
    print_error "Some tools are missing or not properly configured."
fi

if [ "$NEEDS_PATH_UPDATE" = true ]; then
    echo ""
    print_warning "Some tools may not be visible until you reload your shell."
    print_info "Please run:"
    print_command "source ~/.bashrc"
    print_info "Or start a new terminal session, then run this script again to verify."
fi

# Debug info if needed
if [ "$ALL_GOOD" = false ]; then
    echo ""
    print_info "Debug information:"
    print_info "  PATH: $PATH"
    print_info "  PYENV_ROOT: ${PYENV_ROOT:-not set}"
fi

PYTHON3_BIN_PATH="$PYTHON_PATH"
if [ -z "$PYTHON3_BIN_PATH" ]; then
    PYTHON3_BIN_PATH=$(command -v python3 2>/dev/null)
fi

if [ -n "$PYTHON3_BIN_PATH" ] && ! command -v python &> /dev/null; then
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
        fi
    else
        print_info "Skipped creating python symlink."
    fi
fi
