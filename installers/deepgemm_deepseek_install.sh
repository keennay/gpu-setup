#!/bin/bash

# Script: deepgemm_deepseek_install.sh
# Purpose: Install DeepGEMM into the currently active ML virtual environment.
# Usage: source ./launch_env.sh, then ./installers/deepgemm_deepseek_install.sh

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

if [ -n "$ENV_PATH" ]; then
    ENV_NAME=$(basename "$ENV_PATH")
    ENV_NAME="${ENV_NAME#env_}"
fi

run_env_uv_pip_install() {
    local cmd=(uv pip install)
    cmd+=("$@")

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
        print_error "Activate one first, for example: source ./launch_env.sh"
        return 1
    fi

    if [ ! -x "$ENV_PATH/bin/python" ]; then
        print_error "Active virtual environment does not have a Python executable: $ENV_PATH"
        return 1
    fi
}

check_install_prerequisites() {
    if ! command -v uv >/dev/null 2>&1; then
        print_error "uv is not available on PATH."
        return 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        print_error "git is not available on PATH."
        return 1
    fi

    if ! env_python_has_module torch; then
        print_error "PyTorch is required to build DeepGEMM, but torch is not installed in $ENV_PATH."
        print_error "Install your sglang/vllm/torch stack first, then rerun this script."
        return 1
    fi
}

install_latest_deepgemm() {
    local deepgemm_dir="$ENV_PATH/DeepGEMM"
    local parent_dir
    parent_dir=$(dirname "$deepgemm_dir")

    check_install_prerequisites || return 1

    print_info "Installing setuptools into $ENV_NAME..."
    run_env_uv_pip_install -U setuptools || return 1

    print_info "Installing latest DeepGEMM into $ENV_NAME..."
    mkdir -p "$parent_dir" || return 1

    if [ -d "$deepgemm_dir/.git" ]; then
        print_info "Updating existing DeepGEMM checkout at $deepgemm_dir"
        print_command "git -C $deepgemm_dir fetch origin --recurse-submodules"
        git -C "$deepgemm_dir" fetch origin --recurse-submodules || return 1
        print_command "git -C $deepgemm_dir pull --ff-only --recurse-submodules"
        git -C "$deepgemm_dir" pull --ff-only --recurse-submodules || return 1
        print_command "git -C $deepgemm_dir submodule update --init --recursive"
        git -C "$deepgemm_dir" submodule update --init --recursive || return 1
    elif [ -e "$deepgemm_dir" ]; then
        print_error "$deepgemm_dir exists but is not a git checkout."
        print_error "Move or remove it, then rerun this script to install DeepGEMM."
        return 1
    else
        print_command "git clone --recursive https://github.com/deepseek-ai/DeepGEMM.git $deepgemm_dir"
        git clone --recursive https://github.com/deepseek-ai/DeepGEMM.git "$deepgemm_dir" || return 1
    fi

    print_info "Building DeepGEMM from source with DG_FORCE_BUILD=1..."
    print_command "cd $deepgemm_dir && DG_FORCE_BUILD=1 uv pip install --force-reinstall --no-build-isolation ."
    (
        cd "$deepgemm_dir" || exit 1
        VIRTUAL_ENV="$ENV_PATH" PATH="$ENV_PATH/bin:$PATH" DG_FORCE_BUILD=1 \
            uv pip install --force-reinstall --no-build-isolation .
    ) || return 1

    print_info "✓ DeepGEMM installed"
}

prompt_install_deepgemm() {
    echo ""
    while true; do
        read -p "Install latest DeepGEMM into this environment? (y/n): " INSTALL_DEEPGEMM_REPLY
        case ${INSTALL_DEEPGEMM_REPLY,,} in
            y|yes)
                install_latest_deepgemm || return 1
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
