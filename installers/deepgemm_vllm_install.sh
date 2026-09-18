#!/bin/bash

# Script: deepgemm_vllm_install.sh
# Purpose: Install vLLM's pinned DeepGEMM build into the currently active ML virtual environment.
# Usage: source ./launch_env.sh deepseek-vllm, then ./installers/deepgemm_vllm_install.sh [-y|--yes|--auto]

if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_command() { echo -e "${BLUE}[RUN]${NC} $1"; }

ENV_PATH="${VIRTUAL_ENV:-}"
ENV_NAME=""
AUTO_YES=false
SHOW_HELP=false

if [ -n "$ENV_PATH" ]; then
    ENV_NAME=$(basename "$ENV_PATH")
    ENV_NAME="${ENV_NAME#env_}"
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--auto)
            AUTO_YES=true
            shift
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            print_warning "Ignoring unknown argument: $1"
            shift
            ;;
    esac
done

if [ "$SHOW_HELP" = true ]; then
    echo "Usage: ./installers/deepgemm_vllm_install.sh [-y|--yes|--auto]"
    echo "  -y, --yes, --auto    Install without prompting"
    exit 0
fi

run_env_command() {
    local cmd=("$@")

    print_command "VIRTUAL_ENV=$ENV_PATH PATH=$ENV_PATH/bin:\$PATH $(printf '%q ' "${cmd[@]}")"
    VIRTUAL_ENV="$ENV_PATH" PATH="$ENV_PATH/bin:$PATH" "${cmd[@]}"
}

env_python_has_module() {
    local module="$1"

    VIRTUAL_ENV="$ENV_PATH" PATH="$ENV_PATH/bin:$PATH" python - "$module" <<'PY'
import importlib.util
import sys

raise SystemExit(0 if importlib.util.find_spec(sys.argv[1]) else 1)
PY
}

check_environment() {
    if [ -z "$ENV_PATH" ]; then
        print_error "No active virtual environment detected."
        print_error "Activate one first, for example: source ./launch_env.sh deepseek-vllm"
        return 1
    fi

    if [ ! -x "$ENV_PATH/bin/python" ]; then
        print_error "Active virtual environment does not have a Python executable: $ENV_PATH"
        return 1
    fi
}

check_install_prerequisites() {
    if ! command -v curl >/dev/null 2>&1; then
        print_error "curl is not available on PATH."
        return 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        print_error "git is not available on PATH."
        return 1
    fi

    if ! command -v uv >/dev/null 2>&1; then
        print_error "uv is not available on PATH."
        return 1
    fi

    if ! command -v nvcc >/dev/null 2>&1; then
        print_error "nvcc is not available on PATH."
        print_error "vLLM's DeepGEMM installer auto-detects CUDA with nvcc."
        return 1
    fi

    if ! env_python_has_module torch; then
        print_error "PyTorch is required to build DeepGEMM, but torch is not installed in $ENV_PATH."
        print_error "Install your vLLM/torch stack first, then rerun this script."
        return 1
    fi
}

install_vllm_deepgemm() {
    local deepgemm_installer="$ENV_PATH/install_deepgemm.sh"
    local deepgemm_installer_url="https://raw.githubusercontent.com/vllm-project/vllm/main/tools/install_deepgemm.sh"

    check_install_prerequisites || return 1

    print_info "Downloading vLLM DeepGEMM installer into $ENV_NAME..."
    run_env_command curl -fsSL "$deepgemm_installer_url" -o "$deepgemm_installer" || return 1
    run_env_command chmod +x "$deepgemm_installer" || return 1

    print_info "Installing vLLM's pinned DeepGEMM build into $ENV_NAME..."
    run_env_command bash -c 'cd "$1" && bash "$2"' _ "$ENV_PATH" "$deepgemm_installer" || return 1

    print_info "✓ DeepGEMM installed"
}

prompt_install_deepgemm() {
    echo ""

    if [ "$AUTO_YES" = true ]; then
        print_info "Automatic mode enabled (-y): installing vLLM's pinned DeepGEMM build"
        install_vllm_deepgemm || return 1
        return 0
    fi

    while true; do
        read -p "Install vLLM's pinned DeepGEMM build into this environment? (y/n): " INSTALL_DEEPGEMM_REPLY
        case ${INSTALL_DEEPGEMM_REPLY,,} in
            y|yes)
                install_vllm_deepgemm || return 1
                return 0
                ;;
            n|no)
                print_info "Skipping DeepGEMM install"
                return 0
                ;;
            *)
                print_error "Please answer 'y' for yes or 'n' for no"
                ;;
        esac
    done
}

if ! check_environment; then
    exit 1
fi

prompt_install_deepgemm || {
    print_error "Failed to install DeepGEMM"
    exit 1
}
