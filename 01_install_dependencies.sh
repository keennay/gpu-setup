#!/bin/bash
# Script: 01_install_dependencies.sh
# Purpose: Initialize environment with system tools, Node.js, and editor tooling

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

CONFIG_OWNER_USER="${SUDO_USER:-$USER}"
CONFIG_OWNER_GROUP="$(id -gn "$CONFIG_OWNER_USER" 2>/dev/null || echo "$CONFIG_OWNER_USER")"
CONFIG_HOME="$(eval echo "~$CONFIG_OWNER_USER")"

remove_legacy_docker_apt_source() {
    local legacy_source="/etc/apt/sources.list.d/docker.list"

    if [ ! -e "$legacy_source" ]; then
        return 0
    fi

    print_info "Removing legacy Docker APT repository definition..."
    if ! sudo rm -f "$legacy_source"; then
        print_error "Failed to remove legacy Docker APT repository definition: $legacy_source"
        return 1
    fi
}

ensure_sudo_installed() {
    if command -v sudo &> /dev/null; then
        print_info "sudo already installed"
        return
    fi

    if [ "$(id -u)" -ne 0 ]; then
        print_error "sudo is required but not installed. Run this script as root or install sudo manually."
        exit 1
    fi

    if [ "$AUTO_YES" = true ]; then
        INSTALL_SUDO="y"
        print_info "AUTO_YES enabled; installing sudo without prompt"
    else
        read -p "sudo is required. Install sudo now? (y/n): " INSTALL_SUDO
    fi

    if [[ "$INSTALL_SUDO" =~ ^[Yy]$ ]]; then
        print_info "Installing sudo..."
        if $PKG_UPDATE_CMD && $PKG_INSTALL_CMD sudo; then
            print_info "✓ sudo installed"
        else
            print_error "Failed to install sudo"
            exit 1
        fi
    else
        print_error "Cannot continue without sudo"
        exit 1
    fi
}

# Parse arguments
AUTO_YES=false
SELECT_ALL=false
SELECT_DOCKER=false
SELECT_TMUX=false
SELECT_NODE=false
SELECT_PNPM=false
SELECT_BUN=false
SELECT_GO=false
SELECT_RUST=false
SELECT_ZIG=false
SELECT_NEOVIM=false

print_usage() {
    echo "Usage: $0 [-y|--auto] [--all] [section flags...]"
    echo "  -y, --auto       Automatically accept prompts for enabled sections"
    echo "  --all            Enable every optional section"
    echo "  --docker         Enable Docker Engine installation"
    echo "  --node           Enable Node.js 24 installation/update"
    echo "  --pnpm           Enable pnpm installation/update"
    echo "  --bun            Enable Bun installation/update"
    echo "  --go             Enable Go installation/update and shell paths"
    echo "  --rust           Enable Rustup installation/update"
    echo "  --zig            Enable Zig installation/update and xz-utils dependency"
    echo "  --neovim         Enable Neovim installation/update and aliases"
    echo "  --tmux           Enable tmux installation and configuration"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Without section flags, optional sections are skipped. Use --all to enable them."
}

for arg in "$@"; do
    case "$arg" in
        -y|--auto) AUTO_YES=true ;;
        --all) SELECT_ALL=true ;;
        --docker) SELECT_DOCKER=true ;;
        --node) SELECT_NODE=true ;;
        --pnpm) SELECT_PNPM=true ;;
        --bun) SELECT_BUN=true ;;
        --go) SELECT_GO=true ;;
        --rust) SELECT_RUST=true ;;
        --zig) SELECT_ZIG=true ;;
        --neovim) SELECT_NEOVIM=true ;;
        --tmux) SELECT_TMUX=true ;;
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

section_selected() {
    local selected="$1"
    [ "$SELECT_ALL" = true ] || [ "$selected" = true ]
}

# OS/package manager detection
OS_TYPE=""
PKG_INSTALL_CMD=""
PKG_UPDATE_CMD=""
PKG_UPGRADE_CMD=""
PKG_CLEAN_CMD=""
OS_ID=""
OS_NAME=""
OS_VERSION_ID=""

detect_os_package_manager() {
    if [ ! -f /etc/os-release ]; then
        return 1
    fi

    source /etc/os-release
    OS_ID="$ID"
    OS_NAME="$NAME"
    OS_VERSION_ID="$VERSION_ID"
    local version_major
    version_major=$(echo "$VERSION_ID" | cut -d. -f1)

    local sudo_prefix="sudo "
    if [ "$(id -u)" -eq 0 ]; then
        sudo_prefix=""
    fi

    if [ "$ID" = "ubuntu" ]; then
        if [ "$version_major" -lt 22 ]; then
            return 1
        fi
        OS_TYPE="ubuntu"
        PKG_INSTALL_CMD="${sudo_prefix}apt install -y"
        PKG_UPDATE_CMD="${sudo_prefix}apt update"
        PKG_UPGRADE_CMD="${sudo_prefix}apt upgrade -y"
        PKG_CLEAN_CMD="${sudo_prefix}apt clean"
        return 0
    fi

    if [[ "$ID" =~ ^(rhel|rocky|almalinux)$ ]]; then
        if [ "$version_major" -lt 9 ]; then
            return 1
        fi
        OS_TYPE="rhel"
        if command -v dnf &> /dev/null; then
            PKG_INSTALL_CMD="${sudo_prefix}dnf install -y"
            PKG_UPDATE_CMD="${sudo_prefix}dnf makecache"
            PKG_UPGRADE_CMD="${sudo_prefix}dnf upgrade -y"
            PKG_CLEAN_CMD="${sudo_prefix}dnf clean all"
        else
            PKG_INSTALL_CMD="${sudo_prefix}yum install -y"
            PKG_UPDATE_CMD="${sudo_prefix}yum makecache"
            PKG_UPGRADE_CMD="${sudo_prefix}yum upgrade -y"
            PKG_CLEAN_CMD="${sudo_prefix}yum clean all"
        fi
        return 0
    fi

    return 1
}

print_info "Initialization Script for Development Environment"
echo ""

print_info "Checking OS version..."
if ! detect_os_package_manager; then
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot determine OS version. /etc/os-release not found."
    elif [ "$OS_ID" = "ubuntu" ]; then
        print_error "This script requires Ubuntu 22.04 or newer. Detected: $OS_ID $OS_VERSION_ID"
    elif [[ "$OS_ID" =~ ^(rhel|rocky|almalinux)$ ]]; then
        print_error "This script requires RHEL/Rocky/AlmaLinux 9 or newer. Detected: $OS_ID $OS_VERSION_ID"
    else
        print_error "Unsupported OS. This script supports Ubuntu 22.04+ and RHEL/Rocky/AlmaLinux 9+. Detected: $OS_ID $OS_VERSION_ID"
    fi
    exit 1
fi

if [ "$OS_TYPE" = "ubuntu" ]; then
    print_info "✓ Ubuntu $OS_VERSION_ID detected"
else
    print_info "✓ $OS_NAME $OS_VERSION_ID detected"
fi

ensure_sudo_installed

# Repair the conflicting state left by an interrupted migration from Docker's
# legacy docker.list definition before the first apt command reads the sources.
if [ "$OS_TYPE" = "ubuntu" ] && [ -e /etc/apt/sources.list.d/docker.sources ]; then
    if ! remove_legacy_docker_apt_source; then
        exit 1
    fi
fi

# Update system packages
if [ "$AUTO_YES" = true ]; then
    UPDATE_SYSTEM="y"
else
    read -p "Update system packages (package manager update)? (y/n): " UPDATE_SYSTEM
fi

if [[ "$UPDATE_SYSTEM" =~ ^[Yy]$ ]]; then
    print_info "Updating system packages..."
    $PKG_UPDATE_CMD
    if [ $? -ne 0 ]; then
        print_error "Failed to update packages"
        exit 1
    fi
    print_info "✓ System packages updated"
else
    print_info "Skipped system update"
fi

echo ""

# Upgrade system packages
if [ "$AUTO_YES" = true ]; then
    UPGRADE_SYSTEM="y"
else
    read -p "Upgrade system packages (package manager upgrade)? This may take a while. (y/n): " UPGRADE_SYSTEM
fi

if [[ "$UPGRADE_SYSTEM" =~ ^[Yy]$ ]]; then
    print_info "Upgrading system packages..."
    $PKG_UPGRADE_CMD
    if [ $? -ne 0 ]; then
        print_error "Failed to upgrade packages"
        exit 1
    fi
    print_info "✓ System packages upgraded"
else
    print_info "Skipped system upgrade"
fi

echo ""

# Basic Linux essentials installed after upgrades to keep tooling current
if [ "$OS_TYPE" = "ubuntu" ]; then
    BASIC_LINUX_ESSENTIALS=(curl wget zip unzip less vim nano git git-lfs htop nvtop ripgrep shellcheck bubblewrap ffmpeg)
else
    BASIC_LINUX_ESSENTIALS=(curl wget zip unzip less vim-enhanced nano git git-lfs htop nvtop ripgrep ShellCheck bubblewrap ffmpeg)
fi
if [ "$AUTO_YES" = true ]; then
    INSTALL_BASICS="y"
else
    read -p "Install basic Linux essentials (${BASIC_LINUX_ESSENTIALS[*]})? (y/n): " INSTALL_BASICS
fi

if [[ "$INSTALL_BASICS" =~ ^[Yy]$ ]]; then
    print_info "Installing basic Linux essentials..."
    if $PKG_INSTALL_CMD "${BASIC_LINUX_ESSENTIALS[@]}"; then
        print_info "✓ Basic Linux essentials installed"
    else
        print_warning "Failed to install some basic Linux essentials"
    fi
else
    print_info "Skipped installing basic Linux essentials"
fi

echo ""

# Core/build dependencies for ML and Python package compilation
if [ "$OS_TYPE" = "ubuntu" ]; then
    CORE_BUILD_DEPENDENCIES=(
        # Essential build tools
        "build-essential"
        "gcc"
        "g++"
        "make"
        "cmake"
        "pkg-config"
        "protobuf-compiler"
        "libclang-dev"

        # NUMA optimization
        "numactl"
        "libnuma-dev"
        "libhwloc-dev"

        # Essential Python dependencies
        "libssl-dev"
        "libffi-dev"
        "liblzma-dev"
        "libbz2-dev"
        "libreadline-dev"
        "libsqlite3-dev"
        "libncurses-dev"
        "zlib1g-dev"
    )
else
    CORE_BUILD_DEPENDENCIES=(
        # Essential build tools
        "gcc"
        "gcc-c++"
        "make"
        "cmake"
        "pkgconf-pkg-config"
        "protobuf-compiler"
        "clang-devel"

        # NUMA optimization
        "numactl"
        "numactl-devel"
        "hwloc-devel"

        # Essential Python dependencies
        "openssl-devel"
        "libffi-devel"
        "zlib-devel"
        "xz-devel"
        "bzip2-devel"
        "readline-devel"
        "ncurses-devel"
        "sqlite-devel"
    )
fi

print_info "Checking core/build dependencies..."
MISSING_CORE_BUILD_DEPENDENCIES=()
for pkg in "${CORE_BUILD_DEPENDENCIES[@]}"; do
    if [ "$OS_TYPE" = "ubuntu" ]; then
        if dpkg -l 2>/dev/null | grep -q "^ii  $pkg"; then
            print_info "  ✓ $pkg"
        else
            print_error "  ✗ $pkg"
            MISSING_CORE_BUILD_DEPENDENCIES+=("$pkg")
        fi
    else
        if rpm -q "$pkg" &> /dev/null; then
            print_info "  ✓ $pkg"
        else
            print_error "  ✗ $pkg"
            MISSING_CORE_BUILD_DEPENDENCIES+=("$pkg")
        fi
    fi
done

CORE_BUILD_DEPENDENCIES_MISSING_COUNT=${#MISSING_CORE_BUILD_DEPENDENCIES[@]}
if [ $CORE_BUILD_DEPENDENCIES_MISSING_COUNT -gt 0 ]; then
    print_warning "Missing ${CORE_BUILD_DEPENDENCIES_MISSING_COUNT} core/build dependencies: ${MISSING_CORE_BUILD_DEPENDENCIES[*]}"
else
    print_info "All core/build dependencies already installed."
fi

INSTALL_CORE_BUILD_DEPENDENCIES="n"
if [ $CORE_BUILD_DEPENDENCIES_MISSING_COUNT -gt 0 ]; then
    if [ "$AUTO_YES" = true ]; then
        INSTALL_CORE_BUILD_DEPENDENCIES="y"
    else
        read -p "Install missing core/build dependencies? (y/n): " INSTALL_CORE_BUILD_DEPENDENCIES
    fi
fi

if [[ "$INSTALL_CORE_BUILD_DEPENDENCIES" =~ ^[Yy]$ ]]; then
    AVAILABLE_SPACE=$(df -BG /var | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 5 ]; then
        print_error "Low disk space: ${AVAILABLE_SPACE}GB available on /var"
        print_error "At least 5GB recommended for package installation"
        if [ -n "$PKG_CLEAN_CMD" ]; then
            print_info "Free up space with: $PKG_CLEAN_CMD"
        fi
        exit 1
    fi

    if [ "$AVAILABLE_SPACE" -lt 10 ]; then
        if [ "$AUTO_YES" = true ]; then
            CLEAN_CACHE="y"
        else
            print_warning "Low disk space (${AVAILABLE_SPACE}GB). Clean package cache to free space?"
            read -p "Clean package cache? (y/n): " CLEAN_CACHE
        fi

        if [[ "$CLEAN_CACHE" =~ ^[Yy]$ ]]; then
            print_info "Cleaning package cache to free space..."
            if [ -n "$PKG_CLEAN_CMD" ]; then
                $PKG_CLEAN_CMD
            else
                print_warning "No package cache clean command available for this OS"
            fi
        else
            print_warning "Proceeding without cleaning package cache - installation may fail if space runs out"
        fi
    fi

    print_info "Updating package index before installing core/build dependencies..."
    if ! $PKG_UPDATE_CMD; then
        print_error "Package update failed - check your internet connection and disk space"
        exit 1
    fi

    print_info "Installing missing core/build dependencies..."
    if $PKG_INSTALL_CMD "${MISSING_CORE_BUILD_DEPENDENCIES[@]}"; then
        print_info "✓ Core/build dependencies installed"
    else
        print_error "Failed to install some core/build dependencies"
        exit 1
    fi

    print_info "Checking gcc/g++ version compatibility..."
    if command -v gcc &> /dev/null; then
        GCC_VERSION=$(gcc --version | head -1 | grep -oE '[0-9]+' | head -1)
        print_info "Detected gcc-$GCC_VERSION"

        if command -v g++-$GCC_VERSION &> /dev/null; then
            print_info "✓ g++-$GCC_VERSION already available"
        else
            if [ "$AUTO_YES" = true ]; then
                INSTALL_GPP="y"
            else
                read -p "Install g++-$GCC_VERSION to match gcc-$GCC_VERSION? (y/n): " INSTALL_GPP
            fi

            if [[ "$INSTALL_GPP" =~ ^[Yy]$ ]]; then
                if [ "$OS_TYPE" = "ubuntu" ]; then
                    print_info "Installing g++-$GCC_VERSION to match gcc-$GCC_VERSION..."
                    if $PKG_INSTALL_CMD "g++-$GCC_VERSION"; then
                        print_info "✓ g++-$GCC_VERSION installed"

                        if [ "$AUTO_YES" = true ]; then
                            SET_DEFAULT="y"
                        else
                            read -p "Set g++-$GCC_VERSION as default g++ compiler? (y/n): " SET_DEFAULT
                        fi

                        if [[ "$SET_DEFAULT" =~ ^[Yy]$ ]]; then
                            if sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-$GCC_VERSION 100; then
                                print_info "✓ Set g++-$GCC_VERSION as default g++ compiler"
                            else
                                print_warning "Could not set g++-$GCC_VERSION as default"
                            fi
                        else
                            print_info "Skipped setting g++-$GCC_VERSION as default"
                        fi
                    else
                        print_warning "Could not install g++-$GCC_VERSION - CUDA compilation may fail"
                    fi
                else
                    print_info "✓ gcc-c++ package provides matching g++ version on RHEL-compatible systems"
                fi
            else
                print_warning "Skipped g++-$GCC_VERSION installation - CUDA compilation may fail"
            fi
        fi
    fi
else
    if [ $CORE_BUILD_DEPENDENCIES_MISSING_COUNT -gt 0 ]; then
        print_info "Skipped installing core/build dependencies"
    fi
fi

# Install Docker Engine; Ubuntu follows https://docs.docker.com/engine/install/ubuntu/
if section_selected "$SELECT_DOCKER"; then
    if [ "$AUTO_YES" = true ]; then
        INSTALL_DOCKER="y"
    else
        read -r -p "Install Docker Engine? (y/n): " INSTALL_DOCKER
    fi

    if [[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]]; then
        if [ "$OS_TYPE" = "ubuntu" ]; then
            if ! remove_legacy_docker_apt_source; then
                exit 1
            fi

            print_info "Removing conflicting Ubuntu container packages..."
            if ! sudo apt remove -y $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc | cut -f1); then
                print_error "Failed to remove conflicting Ubuntu container packages"
                exit 1
            fi

            print_info "Installing Docker repository prerequisites..."
            if ! sudo apt install -y ca-certificates curl; then
                print_error "Failed to install Docker repository prerequisites"
                exit 1
            fi

            if ! sudo install -m 0755 -d /etc/apt/keyrings; then
                print_error "Failed to create /etc/apt/keyrings"
                exit 1
            fi

            print_info "Installing Docker repository signing key..."
            if ! sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
                print_error "Failed to download Docker repository signing key"
                exit 1
            fi
            if ! sudo chmod a+r /etc/apt/keyrings/docker.asc; then
                print_error "Failed to set Docker signing key permissions"
                exit 1
            fi

            print_info "Configuring the Docker APT repository..."
            if ! sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
            then
                print_error "Failed to configure the Docker APT repository"
                exit 1
            fi

            if ! sudo apt update; then
                print_error "Failed to update package metadata for the Docker repository"
                exit 1
            fi

            print_info "Installing Docker Engine..."
            if ! sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
                print_error "Failed to install Docker Engine"
                exit 1
            fi

            print_info "Starting Docker service..."
            if ! sudo systemctl start docker; then
                print_error "Failed to start the Docker service"
                exit 1
            fi

            print_info "Enabling Docker service at boot..."
            if ! sudo systemctl enable docker; then
                print_error "Failed to enable the Docker service"
                exit 1
            fi
        else
            if ! command -v dnf &> /dev/null; then
                print_error "dnf is required to install Docker Engine on RHEL-compatible systems"
                exit 1
            fi

            print_info "Removing conflicting RHEL container packages..."
            if ! sudo dnf remove -y \
                docker \
                docker-client \
                docker-client-latest \
                docker-common \
                docker-latest \
                docker-latest-logrotate \
                docker-logrotate \
                docker-engine \
                podman \
                runc; then
                print_error "Failed to remove conflicting RHEL container packages"
                exit 1
            fi

            if ! sudo dnf -y install dnf-plugins-core; then
                print_error "Failed to install dnf-plugins-core"
                exit 1
            fi

            if ! sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo; then
                print_error "Failed to configure the Docker RHEL repository"
                exit 1
            fi

            print_info "Installing Docker Engine..."
            if ! sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
                print_error "Failed to install Docker Engine"
                exit 1
            fi

            if ! sudo systemctl enable --now docker; then
                print_error "Failed to enable and start the Docker service"
                exit 1
            fi
        fi

        print_info "✓ Docker Engine installed"
    else
        print_info "Skipped Docker Engine installation"
    fi
fi

echo ""

# Install Node.js 24 through nvm, installing nvm first when needed
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh"

load_nvm() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
    fi
    command -v nvm &> /dev/null
}

if section_selected "$SELECT_NODE"; then
    NVM_AVAILABLE=false
    if load_nvm; then
        NVM_AVAILABLE=true
    fi

    if [ "$AUTO_YES" = true ]; then
        INSTALL_NODE="y"
    elif [ "$NVM_AVAILABLE" = true ]; then
        read -r -p "Install/update Node.js 24 with nvm? (y/n): " INSTALL_NODE
    else
        read -r -p "Install nvm and Node.js 24? (y/n): " INSTALL_NODE
    fi

    if [[ "$INSTALL_NODE" =~ ^[Yy]$ ]]; then
        if [ "$NVM_AVAILABLE" = false ]; then
            if ! command -v curl &> /dev/null; then
                print_error "curl not found - install basic Linux essentials before installing Node.js"
                exit 1
            fi

            print_info "Installing nvm..."
            if ! curl -o- "$NVM_INSTALL_URL" | bash; then
                print_error "Failed to install nvm"
                exit 1
            fi

            if ! load_nvm; then
                print_error "nvm installation completed, but nvm could not be loaded"
                exit 1
            fi

            NVM_VERSION="$(nvm --version 2>/dev/null)"
            print_info "✓ nvm ready: $NVM_VERSION"
        fi

        CURRENT_NVM_NODE="$(nvm current 2>/dev/null || true)"
        print_info "Installing/updating Node.js 24..."
        if ! nvm install 24; then
            print_error "Failed to install or update Node.js 24"
            exit 1
        fi

        UPDATED_NVM_NODE="$(nvm current 2>/dev/null || true)"
        if [ -n "$CURRENT_NVM_NODE" ] && [ "$CURRENT_NVM_NODE" != "none" ] && [ "$CURRENT_NVM_NODE" != "system" ] && [ "$CURRENT_NVM_NODE" != "$UPDATED_NVM_NODE" ]; then
            print_info "Reinstalling global npm packages from $CURRENT_NVM_NODE..."
            if ! nvm reinstall-packages "$CURRENT_NVM_NODE"; then
                print_warning "Could not reinstall global npm packages from $CURRENT_NVM_NODE"
            fi
        fi

        nvm alias default 24

        BASHRC_PATH="$CONFIG_HOME/.bashrc"
        if [ ! -f "$BASHRC_PATH" ]; then
            if ! touch "$BASHRC_PATH" 2>/dev/null; then
                sudo touch "$BASHRC_PATH"
                sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
            fi
        fi

        if ! sed -i '/# nvm default Node version (added by 01_install_dependencies.sh)/,/^# End nvm default Node version/d' "$BASHRC_PATH" 2>/dev/null; then
            sudo sed -i '/# nvm default Node version (added by 01_install_dependencies.sh)/,/^# End nvm default Node version/d' "$BASHRC_PATH"
            sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
        fi

        if [ -w "$BASHRC_PATH" ]; then
            cat <<'EOF' >> "$BASHRC_PATH"
# nvm default Node version (added by 01_install_dependencies.sh)
nvm use default >/dev/null 2>&1
hash -r 2>/dev/null || true
# End nvm default Node version
EOF
        else
            cat <<'EOF' | sudo tee -a "$BASHRC_PATH" > /dev/null
# nvm default Node version (added by 01_install_dependencies.sh)
nvm use default >/dev/null 2>&1
hash -r 2>/dev/null || true
# End nvm default Node version
EOF
            sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
        fi
        print_info "✓ nvm default Node version block updated in $BASHRC_PATH"

        nvm use default
        hash -r 2>/dev/null || true

        NODE_VERSION="$(node -v 2>/dev/null)"
        if [[ "$NODE_VERSION" != v24.* ]]; then
            print_error "Node.js installation verification failed: expected v24, got ${NODE_VERSION:-no version}"
            exit 1
        fi

        NPM_VERSION="$(npm -v 2>/dev/null)"
        print_info "✓ Node.js ready: $NODE_VERSION"
        print_info "npm version: $NPM_VERSION"
    else
        print_info "Skipped Node.js installation/update"
    fi
fi

echo ""
# Install pnpm
if section_selected "$SELECT_PNPM"; then
    PNPM_ALREADY_AVAILABLE=false
    if command -v pnpm &> /dev/null; then
        PNPM_ALREADY_AVAILABLE=true
    fi

    if [ "$AUTO_YES" = true ]; then
        INSTALL_PNPM="y"
    elif [ "$PNPM_ALREADY_AVAILABLE" = true ]; then
        read -r -p "Update pnpm to the latest stable version? (y/n): " INSTALL_PNPM
    else
        read -r -p "Install pnpm? (y/n): " INSTALL_PNPM
    fi

    if [[ "$INSTALL_PNPM" =~ ^[Yy]$ ]]; then
        if ! command -v curl &> /dev/null; then
            print_error "curl not found - install basic Linux essentials before installing pnpm"
            exit 1
        fi

        print_info "Installing/updating pnpm..."
        if (set -o pipefail; curl -fsSL https://get.pnpm.io/install.sh | sh -); then
            if [ -d "$HOME/.local/share/pnpm" ]; then
                export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
                export PATH="$PNPM_HOME:$PATH"
            fi
            hash -r 2>/dev/null || true

            PNPM_VERSION="$(pnpm --version 2>/dev/null || true)"
            if [ -n "$PNPM_VERSION" ]; then
                print_info "✓ pnpm ready: $PNPM_VERSION"
            else
                print_info "✓ pnpm installed; restart your shell to load it"
            fi
        else
            print_error "Failed to install or update pnpm"
            exit 1
        fi
    else
        print_info "Skipped pnpm installation/update"
    fi
fi

echo ""

# Install Bun
if [ -d "$HOME/.bun/bin" ]; then
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
fi

if ! section_selected "$SELECT_BUN"; then
    :
elif command -v bun &> /dev/null; then
    if [ "$AUTO_YES" = true ]; then
        UPDATE_BUN="y"
    else
        read -p "Update Bun to the latest stable version? (y/n): " UPDATE_BUN
    fi

    if [[ "$UPDATE_BUN" =~ ^[Yy]$ ]]; then
        print_info "Updating Bun..."
        if bun upgrade; then
            BUN_VERSION=$(bun --version 2>/dev/null)
            if [ -n "$BUN_VERSION" ]; then
                print_info "✓ Bun ready: $BUN_VERSION"
            else
                print_info "✓ Bun updated"
            fi
        else
            print_error "Failed to update Bun"
            exit 1
        fi
    else
        print_info "Skipped Bun update"
    fi
else
    if [ "$AUTO_YES" = true ]; then
        INSTALL_BUN="y"
    else
        read -p "Install Bun JavaScript runtime? (y/n): " INSTALL_BUN
    fi

    if [[ "$INSTALL_BUN" =~ ^[Yy]$ ]]; then
        if ! command -v curl &> /dev/null; then
            print_error "curl not found - install basic Linux essentials before installing Bun"
            exit 1
        fi

        print_info "Installing Bun..."
        if curl -fsSL https://bun.com/install | bash; then
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:$PATH"
            print_info "✓ Bun installed"

            BUN_VERSION=$(bun --version 2>/dev/null)
            if [ -n "$BUN_VERSION" ]; then
                print_info "Bun version: $BUN_VERSION"
            else
                print_info "Restart your shell or run: source ~/.bashrc"
            fi
        else
            print_error "Failed to install Bun"
            exit 1
        fi
    else
        print_info "Skipped Bun installation"
    fi
fi

echo ""

# Install Go
if ! command -v go &> /dev/null && [ -x /usr/local/go/bin/go ]; then
    export PATH="/usr/local/go/bin:$PATH"
fi

GO_ALREADY_AVAILABLE=false
if command -v go &> /dev/null; then
    GO_ALREADY_AVAILABLE=true
fi

if ! section_selected "$SELECT_GO"; then
    INSTALL_GO="n"
elif [ "$AUTO_YES" = true ]; then
    INSTALL_GO="y"
elif [ "$GO_ALREADY_AVAILABLE" = true ]; then
    read -r -p "Update Go to the latest stable version? (y/n): " INSTALL_GO
else
    read -r -p "Install Go latest stable version? (y/n): " INSTALL_GO
fi

GO_PATHS_READY=false
if [[ "$INSTALL_GO" =~ ^[Yy]$ ]]; then
    if ! command -v curl &> /dev/null; then
        print_error "curl not found - install basic Linux essentials before installing Go"
        exit 1
    fi

    if ! command -v tar &> /dev/null; then
        print_error "tar not found - install basic Linux essentials before installing Go"
        exit 1
    fi

    if ! command -v sha256sum &> /dev/null; then
        print_error "sha256sum not found - install coreutils before installing Go"
        exit 1
    fi

    GO_UNAME_ARCH="$(uname -m)"
    case "$GO_UNAME_ARCH" in
        x86_64|amd64) GO_ARCH="amd64" ;;
        aarch64|arm64) GO_ARCH="arm64" ;;
        *) print_error "Unsupported Go architecture: $GO_UNAME_ARCH"; exit 1 ;;
    esac

    print_info "Resolving latest stable Go release..."
    GO_RELEASE_JSON="$(curl -fsSL 'https://go.dev/dl/?mode=json')"
    GO_VERSION="$(printf '%s\n' "$GO_RELEASE_JSON" | sed -n 's/^[[:space:]]*"version": "\(go[^"]*\)",/\1/p' | head -n1)"

    if [ -z "$GO_VERSION" ]; then
        print_error "Failed to resolve latest Go version"
        exit 1
    fi

    CURRENT_GO_VERSION="$(go version 2>/dev/null | awk '{print $3}')"
    if [ "$CURRENT_GO_VERSION" = "$GO_VERSION" ]; then
        print_info "Go is already at latest stable version: $GO_VERSION"
        GO_PATHS_READY=true
    else
        GO_TARBALL="${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
        GO_SHA256="$(printf '%s\n' "$GO_RELEASE_JSON" | awk -v filename="$GO_TARBALL" '
            index($0, "\"filename\": \"" filename "\"") { found=1; next }
            found && /"sha256":/ {
                sub(/^.*"sha256": "/, "")
                sub(/".*$/, "")
                print
                exit
            }
        ')"

        if [ -z "$GO_SHA256" ]; then
            print_error "Failed to find SHA256 for $GO_TARBALL"
            exit 1
        fi

        TMP_DIR="$(mktemp -d /tmp/go-install.XXXXXX)"
        print_info "Downloading $GO_TARBALL..."
        if curl -fL "https://go.dev/dl/$GO_TARBALL" -o "$TMP_DIR/$GO_TARBALL"; then
            print_info "Verifying $GO_TARBALL..."
            if (cd "$TMP_DIR" && printf '%s  %s\n' "$GO_SHA256" "$GO_TARBALL" | sha256sum -c -); then
                print_info "Installing Go to /usr/local/go..."
                sudo rm -rf /usr/local/go
                if sudo tar -C /usr/local -xzf "$TMP_DIR/$GO_TARBALL"; then
                    export PATH="/usr/local/go/bin:$PATH"
                    export GOPATH="${GOPATH:-$CONFIG_HOME/go}"
                    export PATH="$PATH:$GOPATH/bin"
                    print_info "✓ Go installed"
                    GO_VERSION_OUTPUT="$(go version 2>/dev/null)"
                    [ -n "$GO_VERSION_OUTPUT" ] && print_info "$GO_VERSION_OUTPUT"
                    GO_PATHS_READY=true
                else
                    print_error "Failed to extract Go archive"
                    rm -rf "$TMP_DIR"
                    exit 1
                fi
            else
                print_error "Go archive checksum verification failed"
                rm -rf "$TMP_DIR"
                exit 1
            fi
        else
            print_error "Failed to download Go"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        rm -rf "$TMP_DIR"
    fi
else
    print_info "Skipped Go installation/update"
fi

if [ "$GO_PATHS_READY" = true ]; then
    BASHRC_PATH="$CONFIG_HOME/.bashrc"
    if [ ! -f "$BASHRC_PATH" ]; then
        if ! touch "$BASHRC_PATH" 2>/dev/null; then
            sudo touch "$BASHRC_PATH"
            sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
        fi
    fi

    if ! sed -i '/# Go paths (added by 01_install_dependencies.sh)/,/^# End Go paths/d' "$BASHRC_PATH" 2>/dev/null; then
        sudo sed -i '/# Go paths (added by 01_install_dependencies.sh)/,/^# End Go paths/d' "$BASHRC_PATH"
        sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
    fi

    if [ -w "$BASHRC_PATH" ]; then
        cat <<'EOF' >> "$BASHRC_PATH"
# Go paths (added by 01_install_dependencies.sh)
case ":$PATH:" in
    *":/usr/local/go/bin:"*) ;;
    *) export PATH="/usr/local/go/bin:$PATH" ;;
esac
export GOPATH="${GOPATH:-$HOME/go}"
case ":$PATH:" in
    *":$GOPATH/bin:"*) ;;
    *) export PATH="$PATH:$GOPATH/bin" ;;
esac
# End Go paths
EOF
    else
        cat <<'EOF' | sudo tee -a "$BASHRC_PATH" > /dev/null
# Go paths (added by 01_install_dependencies.sh)
case ":$PATH:" in
    *":/usr/local/go/bin:"*) ;;
    *) export PATH="/usr/local/go/bin:$PATH" ;;
esac
export GOPATH="${GOPATH:-$HOME/go}"
case ":$PATH:" in
    *":$GOPATH/bin:"*) ;;
    *) export PATH="$PATH:$GOPATH/bin" ;;
esac
# End Go paths
EOF
        sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
    fi

    print_info "✓ Go paths updated in $BASHRC_PATH"
fi

echo ""

# Install Rustup
if ! command -v rustup &> /dev/null && [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

if ! section_selected "$SELECT_RUST"; then
    :
elif command -v rustup &> /dev/null; then
    if [ "$AUTO_YES" = true ]; then
        UPDATE_RUSTUP="y"
    else
        read -p "Update Rust toolchains with rustup? (y/n): " UPDATE_RUSTUP
    fi

    if [[ "$UPDATE_RUSTUP" =~ ^[Yy]$ ]]; then
        print_info "Updating Rust toolchains..."
        if rustup update; then
            RUSTC_VERSION=$(rustc --version 2>/dev/null)
            CARGO_VERSION=$(cargo --version 2>/dev/null)
            RUSTUP_VERSION=$(rustup --version 2>/dev/null | head -1)

            [ -n "$RUSTC_VERSION" ] && print_info "$RUSTC_VERSION"
            [ -n "$CARGO_VERSION" ] && print_info "$CARGO_VERSION"
            [ -n "$RUSTUP_VERSION" ] && print_info "$RUSTUP_VERSION"
        else
            print_error "Failed to update Rust toolchains"
            exit 1
        fi
    else
        print_info "Skipped Rustup update"
    fi
else
    if [ "$AUTO_YES" = true ]; then
        INSTALL_RUSTUP="y"
    else
        read -p "Install Rustup (Rust toolchain manager)? (y/n): " INSTALL_RUSTUP
    fi

    if [[ "$INSTALL_RUSTUP" =~ ^[Yy]$ ]]; then
        if ! command -v curl &> /dev/null; then
            print_error "curl not found - install basic Linux essentials before installing Rustup"
            exit 1
        fi

        print_info "Installing Rustup..."
        if [ "$AUTO_YES" = true ]; then
            RUSTUP_INSTALL_CMD=(sh -s -- -y)
        else
            RUSTUP_INSTALL_CMD=(sh)
        fi

        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | "${RUSTUP_INSTALL_CMD[@]}"; then
            if [ -f "$HOME/.cargo/env" ]; then
                . "$HOME/.cargo/env"
            fi

            print_info "✓ Rustup installed"

            RUSTC_VERSION=$(rustc --version 2>/dev/null)
            CARGO_VERSION=$(cargo --version 2>/dev/null)
            RUSTUP_VERSION=$(rustup --version 2>/dev/null | head -1)

            [ -n "$RUSTC_VERSION" ] && print_info "$RUSTC_VERSION"
            [ -n "$CARGO_VERSION" ] && print_info "$CARGO_VERSION"
            [ -n "$RUSTUP_VERSION" ] && print_info "$RUSTUP_VERSION"

            if [ -z "$RUSTC_VERSION" ] || [ -z "$CARGO_VERSION" ]; then
                print_info "Restart your shell or run: source ~/.cargo/env"
            fi
        else
            print_error "Failed to install Rustup"
            exit 1
        fi
    else
        print_info "Skipped Rustup installation"
    fi
fi


# Install the latest stable Zig release
ZIG_ALREADY_AVAILABLE=false
ZIG_CURRENT_VERSION=""
if command -v zig &> /dev/null; then
    ZIG_ALREADY_AVAILABLE=true
    ZIG_CURRENT_VERSION="$(zig version 2>/dev/null || true)"
fi

if ! section_selected "$SELECT_ZIG"; then
    INSTALL_ZIG="n"
elif [ "$AUTO_YES" = true ]; then
    INSTALL_ZIG="y"
elif [ "$ZIG_ALREADY_AVAILABLE" = true ]; then
    read -r -p "Update Zig to the latest stable release (currently ${ZIG_CURRENT_VERSION:-unknown})? (y/n): " INSTALL_ZIG
else
    read -r -p "Install the latest stable Zig release? (y/n): " INSTALL_ZIG
fi

if [[ "$INSTALL_ZIG" =~ ^[Yy]$ ]]; then
    if ! command -v curl &> /dev/null; then
        print_error "curl not found - install basic Linux essentials before installing Zig"
        exit 1
    fi

    ZIG_INDEX_URL="https://ziglang.org/download/index.json"
    print_info "Resolving latest stable Zig release..."
    if ! ZIG_RELEASE_JSON="$(curl --proto '=https' --tlsv1.2 -fsSL "$ZIG_INDEX_URL")"; then
        print_error "Failed to retrieve the Zig release index"
        exit 1
    fi

    ZIG_VERSION="$(
        printf '%s\n' "$ZIG_RELEASE_JSON" \
            | sed -nE '/^  "[0-9]+(\.[0-9]+)+": \{$/ { s/^  "([^"]+)".*/\1/; p; }' \
            | sort -V \
            | sed -n '$p'
    )"
    if [ -z "$ZIG_VERSION" ]; then
        print_error "Failed to resolve the latest stable Zig version"
        exit 1
    fi
    print_info "Latest stable Zig release: $ZIG_VERSION"

    if [ "$ZIG_CURRENT_VERSION" = "$ZIG_VERSION" ]; then
        print_info "Zig is already at the latest stable version: $ZIG_VERSION"
    else
        if ! command -v tar &> /dev/null; then
            print_error "tar not found - install basic Linux essentials before installing Zig"
            exit 1
        fi

        if ! command -v sha256sum &> /dev/null; then
            print_error "sha256sum not found - install coreutils before installing Zig"
            exit 1
        fi

        if ! command -v xz &> /dev/null; then
            if [ "$OS_TYPE" = "ubuntu" ]; then
                ZIG_XZ_PACKAGE="xz-utils"
            else
                ZIG_XZ_PACKAGE="xz"
            fi
            print_info "Installing $ZIG_XZ_PACKAGE for Zig archive extraction..."
            if ! $PKG_INSTALL_CMD "$ZIG_XZ_PACKAGE"; then
                print_error "Failed to install $ZIG_XZ_PACKAGE"
                exit 1
            fi
        fi

        ZIG_UNAME_ARCH="$(uname -m)"
        case "$ZIG_UNAME_ARCH" in
            x86_64|amd64) ZIG_ARCH="x86_64" ;;
            aarch64|arm64) ZIG_ARCH="aarch64" ;;
            *)
                print_error "Unsupported Zig architecture: $ZIG_UNAME_ARCH"
                exit 1
                ;;
        esac

        ZIG_ASSET_METADATA="$(
            printf '%s\n' "$ZIG_RELEASE_JSON" | awk \
                -v version="$ZIG_VERSION" \
                -v platform="${ZIG_ARCH}-linux" '
                $0 == "  \"" version "\": {" {
                    in_version = 1
                    next
                }
                in_version && $0 == "    \"" platform "\": {" {
                    in_platform = 1
                    next
                }
                in_platform && /"tarball":/ {
                    tarball = $0
                    sub(/^.*"tarball": "/, "", tarball)
                    sub(/".*$/, "", tarball)
                    next
                }
                in_platform && /"shasum":/ {
                    shasum = $0
                    sub(/^.*"shasum": "/, "", shasum)
                    sub(/".*$/, "", shasum)
                    print tarball, shasum
                    exit
                }
            '
        )"
        read -r ZIG_DOWNLOAD_URL ZIG_SHA256 <<< "$ZIG_ASSET_METADATA"
        if [ -z "$ZIG_DOWNLOAD_URL" ] || [ -z "$ZIG_SHA256" ]; then
            print_error "Failed to resolve the ${ZIG_ARCH}-linux Zig archive metadata"
            exit 1
        fi

        ZIG_TARBALL="${ZIG_DOWNLOAD_URL##*/}"
        ZIG_ARCHIVE_ROOT="${ZIG_TARBALL%.tar.xz}"
        ZIG_INSTALL_ROOT="/opt/zig"
        ZIG_INSTALL_DIR="$ZIG_INSTALL_ROOT/$ZIG_VERSION"
        TMP_DIR="$(mktemp -d /tmp/zig-install.XXXXXX)"

        print_info "Downloading $ZIG_TARBALL to $TMP_DIR..."
        if ! curl --proto '=https' --tlsv1.2 -fL "$ZIG_DOWNLOAD_URL" -o "$TMP_DIR/$ZIG_TARBALL"; then
            print_error "Failed to download Zig $ZIG_VERSION"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        print_info "Verifying $ZIG_TARBALL..."
        if ! (cd "$TMP_DIR" && printf '%s  %s\n' "$ZIG_SHA256" "$ZIG_TARBALL" | sha256sum -c -); then
            print_error "Zig archive checksum verification failed"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        if ! tar -C "$TMP_DIR" -xJf "$TMP_DIR/$ZIG_TARBALL"; then
            print_error "Failed to extract Zig archive"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        ZIG_EXTRACTED_DIR="$TMP_DIR/$ZIG_ARCHIVE_ROOT"
        if [ ! -x "$ZIG_EXTRACTED_DIR/zig" ]; then
            print_error "Zig executable not found in extracted archive"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        print_info "Installing Zig to $ZIG_INSTALL_DIR..."
        sudo mkdir -p "$ZIG_INSTALL_ROOT" /usr/local/bin
        sudo rm -rf "$ZIG_INSTALL_DIR"
        if ! sudo mv "$ZIG_EXTRACTED_DIR" "$ZIG_INSTALL_DIR"; then
            print_error "Failed to install Zig to $ZIG_INSTALL_DIR"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        if ! sudo ln -sfn "$ZIG_INSTALL_DIR/zig" /usr/local/bin/zig; then
            print_error "Failed to link Zig into /usr/local/bin"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        rm -rf "$TMP_DIR"
        export PATH="/usr/local/bin:$PATH"
        hash -r 2>/dev/null || true
        ZIG_INSTALLED_VERSION="$(zig version 2>/dev/null || true)"
        if [ "$ZIG_INSTALLED_VERSION" != "$ZIG_VERSION" ]; then
            print_error "Zig installation verification failed: expected $ZIG_VERSION, got ${ZIG_INSTALLED_VERSION:-no version}"
            exit 1
        fi
        print_info "✓ Zig ready: $ZIG_INSTALLED_VERSION"
    fi
else
    print_info "Skipped Zig installation"
fi

NVIM_AVAILABLE=false
NVIM_ALREADY_AVAILABLE=false
if command -v nvim &> /dev/null; then
    NVIM_AVAILABLE=true
    NVIM_ALREADY_AVAILABLE=true
fi

# Install latest Neovim (downloaded from GitHub releases)
if ! section_selected "$SELECT_NEOVIM"; then
    INSTALL_NVIM_LATEST="n"
elif [ "$AUTO_YES" = true ]; then
    INSTALL_NVIM_LATEST="y"
elif [ "$NVIM_ALREADY_AVAILABLE" = true ]; then
    read -p "Update latest Neovim (download from GitHub releases)? (y/n): " INSTALL_NVIM_LATEST
else
    read -p "Install latest Neovim (download from GitHub releases)? (y/n): " INSTALL_NVIM_LATEST
fi

if [[ "$INSTALL_NVIM_LATEST" =~ ^[Yy]$ ]]; then
    if ! command -v tar &> /dev/null; then
        print_warning "tar not found - skipping Neovim install"
    elif ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        print_warning "curl or wget not found - skipping Neovim install"
    else
        if [ "$NVIM_ALREADY_AVAILABLE" = true ]; then
            print_info "Updating latest Neovim..."
        else
            print_info "Installing latest Neovim..."
        fi
        NVIM_ARCH="$(uname -m)"
        case "$NVIM_ARCH" in
            x86_64|amd64) NVIM_ASSETS=("nvim-linux-x86_64.tar.gz" "nvim-linux64.tar.gz") ;;
            aarch64|arm64) NVIM_ASSETS=("nvim-linux-arm64.tar.gz") ;;
            *) NVIM_ASSETS=() ;;
        esac

        if [ ${#NVIM_ASSETS[@]} -eq 0 ]; then
            print_warning "Unsupported architecture for Neovim installer: $NVIM_ARCH"
        else
            TMP_DIR="$(mktemp -d /tmp/nvim-install.XXXXXX)"
            NVIM_TARBALL=""
            for asset in "${NVIM_ASSETS[@]}"; do
                URL="https://github.com/neovim/neovim/releases/latest/download/$asset"
                if command -v curl &> /dev/null; then
                    if curl -fL "$URL" -o "$TMP_DIR/$asset"; then
                        NVIM_TARBALL="$TMP_DIR/$asset"
                        break
                    fi
                else
                    if wget -O "$TMP_DIR/$asset" "$URL"; then
                        NVIM_TARBALL="$TMP_DIR/$asset"
                        break
                    fi
                fi
            done

            if [ -z "$NVIM_TARBALL" ]; then
                print_warning "Failed to download Neovim release from GitHub"
            else
                NVIM_TOP_DIR="$(tar -tf "$NVIM_TARBALL" | head -n1 | cut -d/ -f1)"
                if [ -z "$NVIM_TOP_DIR" ]; then
                    print_warning "Failed to read Neovim archive contents"
                else
                    sudo mkdir -p /opt
                    if sudo tar -C /opt -xzf "$NVIM_TARBALL"; then
                        if sudo ln -sfn "/opt/$NVIM_TOP_DIR/bin/nvim" /usr/local/bin/nvim; then
                            print_info "✓ Latest Neovim installed (symlinked to /usr/local/bin/nvim)"
                            NVIM_AVAILABLE=true
                        else
                            print_warning "Failed to link Neovim binary"
                        fi
                    else
                        print_warning "Failed to extract Neovim archive"
                    fi
                fi
            fi
            rm -rf "$TMP_DIR"
        fi
    fi
fi

# Check if Neovim is available (installed previously or just now)
if command -v nvim &> /dev/null; then
    NVIM_AVAILABLE=true
fi

# Optionally alias vi/vim to Neovim in bashrc (only if installed here)
if section_selected "$SELECT_NEOVIM" && [ "$NVIM_AVAILABLE" = true ]; then
    if [ "$AUTO_YES" = true ]; then
        ALIAS_NVIM="y"
    else
        read -p "Alias vi and vim to Neovim in $CONFIG_HOME/.bashrc? (y/n): " ALIAS_NVIM
    fi

    if [[ "$ALIAS_NVIM" =~ ^[Yy]$ ]]; then
        BASHRC_PATH="$CONFIG_HOME/.bashrc"

        if [ ! -f "$BASHRC_PATH" ]; then
            if ! touch "$BASHRC_PATH" 2>/dev/null; then
                sudo touch "$BASHRC_PATH"
                sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
            fi
        fi

        # Remove previous block and any existing vi/vim alias lines
        if ! sed -i '/# Neovim aliases (added by 01_install_dependencies.sh)/,/^# End Neovim aliases/d' "$BASHRC_PATH" 2>/dev/null; then
            sudo sed -i '/# Neovim aliases (added by 01_install_dependencies.sh)/,/^# End Neovim aliases/d' "$BASHRC_PATH"
            sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
        fi
        if ! sed -i '/^alias vi=/d; /^alias vim=/d' "$BASHRC_PATH" 2>/dev/null; then
            sudo sed -i '/^alias vi=/d; /^alias vim=/d' "$BASHRC_PATH"
            sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
        fi

        if [ -w "$BASHRC_PATH" ]; then
            cat <<'EOF' >> "$BASHRC_PATH"
# Neovim aliases (added by 01_install_dependencies.sh)
alias vi='nvim'
alias vim='nvim'
# End Neovim aliases
EOF
        else
            cat <<'EOF' | sudo tee -a "$BASHRC_PATH" > /dev/null
# Neovim aliases (added by 01_install_dependencies.sh)
alias vi='nvim'
alias vim='nvim'
# End Neovim aliases
EOF
            sudo chown "$CONFIG_OWNER_USER:$CONFIG_OWNER_GROUP" "$BASHRC_PATH"
        fi

        print_info "✓ Aliases for vi and vim added to $BASHRC_PATH"
    else
        print_info "Skipped aliasing vi/vim to Neovim"
    fi
fi

# Install tmux and copy its configuration
if section_selected "$SELECT_TMUX"; then
    TMUX_ALREADY_AVAILABLE=false
    if command -v tmux &> /dev/null; then
        TMUX_ALREADY_AVAILABLE=true
    fi

    if [ "$AUTO_YES" = true ]; then
        SETUP_TMUX="y"
    elif [ "$TMUX_ALREADY_AVAILABLE" = true ]; then
        read -r -p "Copy the provided tmux config? (y/n): " SETUP_TMUX
    else
        read -r -p "Install tmux and copy the provided config? (y/n): " SETUP_TMUX
    fi

    if [[ "$SETUP_TMUX" =~ ^[Yy]$ ]]; then
        if [ "$TMUX_ALREADY_AVAILABLE" = false ]; then
            print_info "Installing tmux..."
            if ! $PKG_INSTALL_CMD tmux; then
                print_error "Failed to install tmux"
                exit 1
            fi
            print_info "✓ tmux installed"
        fi

        TMUX_CONFIG_SOURCE="$(dirname "$0")/configs/.tmux.conf"
        TMUX_CONFIG_TARGET="$HOME/.tmux.conf"
        if [ -f "$TMUX_CONFIG_SOURCE" ]; then
            if cp "$TMUX_CONFIG_SOURCE" "$TMUX_CONFIG_TARGET"; then
                print_info "✓ tmux config copied to $TMUX_CONFIG_TARGET"
            else
                print_warning "Failed to copy tmux config"
            fi
        else
            print_warning "tmux config not found at $TMUX_CONFIG_SOURCE"
        fi
    else
        print_info "Skipped tmux installation/configuration"
    fi
fi

echo ""
print_info "✅ Initialization complete!"
print_info "If you installed nvm or Neovim, restart your shell or run: source ~/.bashrc"
