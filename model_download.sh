#!/bin/bash
# Script: model_download.sh
# Purpose: Download Hugging Face models or datasets to a custom location with easy replication
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

WORKSPACE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Default values
DEFAULT_HF_PATH="$WORKSPACE_DIR/models/huggingface"
DEFAULT_MODEL="PrimeIntellect/INTELLECT-2"
DEFAULT_REPO_TYPE="auto"
DEFAULT_HF_DOWNLOAD_MAX_WORKERS=32
DEFAULT_HF_XET_NUM_CONCURRENT_RANGE_GETS=32
DEFAULT_HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS=600
DEFAULT_HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS=120
DEFAULT_HF_DOWNLOAD_RETRY_DELAY_SECONDS=10
DEFAULT_HF_DOWNLOAD_MAX_RETRIES=0

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check and create directory
setup_directory() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        print_info "Creating directory: $dir"
        mkdir -p "$dir"
        if [ $? -eq 0 ]; then
            print_info "Directory created successfully"
        else
            print_error "Failed to create directory"
            exit 1
        fi
    else
        print_info "Directory already exists: $dir"
    fi
}

check_hf_fast_download_tooling() {
    python3 - <<'PY'
from importlib.metadata import PackageNotFoundError, version
import shutil
import sys

missing = []

try:
    import huggingface_hub  # noqa: F401
except ImportError:
    missing.append("huggingface_hub")

try:
    import hf_xet  # noqa: F401
except ImportError:
    missing.append("hf-xet")

if shutil.which("hf") is None:
    missing.append("hf CLI")

if missing:
    print("Missing: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)

try:
    hub_version = version("huggingface_hub")
except PackageNotFoundError:
    hub_version = "unknown"

try:
    xet_version = version("hf-xet")
except PackageNotFoundError:
    xet_version = "unknown"

print(f"huggingface_hub {hub_version}, hf-xet {xet_version}, hf CLI ready")
PY
}

# Parse command line arguments
MODEL_NAME=""
REPO_TYPE="${REPO_TYPE:-$DEFAULT_REPO_TYPE}"
HF_PATH=""
HF_CACHE_PATH=""
QUANTIZATION=""
AUTO_MODE=false
AUTO_YES=false
UPDATE_AND_PRUNE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--model)
            MODEL_NAME="$2"
            shift 2
            ;;
        -r|--repo-type)
            REPO_TYPE="$2"
            shift 2
            ;;
        --dataset)
            REPO_TYPE="dataset"
            shift
            ;;
        -p|--path)
            HF_PATH="$2"
            shift 2
            ;;
        -q|--quantization)
            QUANTIZATION="$2"
            shift 2
            ;;
        --update-and-prune)
            UPDATE_AND_PRUNE=true
            AUTO_YES=true
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        --auto)
            AUTO_MODE=true
            AUTO_YES=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [REPO_ID] [OPTIONS]"
            echo "Options:"
            echo "  -m, --model REPO_ID        Hugging Face repo to download (e.g., 'openai/gpt-oss-120b')"
            echo "  -r, --repo-type TYPE       Optional override: auto, model, dataset, or space (default: $DEFAULT_REPO_TYPE)"
            echo "  --dataset                  Optional shortcut for --repo-type dataset"
            echo "  -p, --path PATH           Custom path for Hugging Face cache (default: $DEFAULT_HF_PATH or \$HF_HOME)"
            echo "  -q, --quantization TYPE   Download quantized version (e.g., 'GGUF', 'GPTQ')"
            echo "  -y, --yes                Automatically accept snapshot download prompts"
            echo "  --update-and-prune       Accept a new snapshot, verify it, then remove all older cached snapshots"
            echo "  --auto                    Use default settings and accept prompts"
            echo "  -h, --help               Show this help message"
            echo ""
            echo "Environment overrides:"
            echo "  HF_DOWNLOAD_MAX_WORKERS             Parallel hf download workers (default: $DEFAULT_HF_DOWNLOAD_MAX_WORKERS)"
            echo "  HF_XET_NUM_CONCURRENT_RANGE_GETS    Per-file Xet range concurrency (default: $DEFAULT_HF_XET_NUM_CONCURRENT_RANGE_GETS)"
            echo "  HF_XET_HIGH_PERFORMANCE             Enable Xet high-performance mode (default: 1)"
            echo "  HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS  Recreate download connections periodically (default: $DEFAULT_HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS; 0 disables)"
            echo "  HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS  Per-instance refresh jitter (default: $DEFAULT_HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS)"
            echo "  HF_DOWNLOAD_RETRY_DELAY_SECONDS     Delay after a transient hf failure (default: $DEFAULT_HF_DOWNLOAD_RETRY_DELAY_SECONDS)"
            echo "  HF_DOWNLOAD_MAX_RETRIES             Transient hf retries (default: $DEFAULT_HF_DOWNLOAD_MAX_RETRIES; 0 is unlimited)"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 'AlienKevin/SWE-ZERO-12M-trajectories'"
            echo "  $0 -m 'PrimeIntellect/INTELLECT-2'"
            echo "  $0 -m 'AlienKevin/SWE-ZERO-12M-trajectories'"
            echo "  $0 -m 'Qwen/Qwen3-30B-A3B-Instruct-2507' -q GGUF"
            echo "  $0 -m 'deepseek-ai/DeepSeek-V3' -p ../models/huggingface"
            echo "  $0 -y 'google/gemma-4-31B-it'"
            echo "  $0 'deepseek-ai/DeepSeek-V4-Flash-Vision-Exp' --update-and-prune"
            exit 0
            ;;
        *)
            if [[ "$1" == -* ]]; then
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
            fi

            if [ -n "$MODEL_NAME" ]; then
                print_error "Only one Hugging Face repo can be downloaded at a time"
                echo "Use -h or --help for usage information"
                exit 1
            fi

            MODEL_NAME="$1"
            shift
            ;;
    esac
done

REPO_TYPE=$(printf '%s' "$REPO_TYPE" | tr '[:upper:]' '[:lower:]')
case "$REPO_TYPE" in
    auto|model|dataset|space) ;;
    *)
        print_error "Invalid repo type: $REPO_TYPE"
        print_info "Use one of: auto, model, dataset, space"
        exit 1
        ;;
esac

if [ -n "$QUANTIZATION" ] && [ "$REPO_TYPE" != "model" ] && [ "$REPO_TYPE" != "auto" ]; then
    print_error "Quantization suffixes are only supported for model downloads"
    exit 1
fi

# Determine HuggingFace path
# Priority: 1) Command line arg, 2) HF_HOME env var, 3) HF_HUB_CACHE env var, 4) Interactive prompt/default
if [ -n "$HF_PATH" ]; then
    # Use command line argument
    print_info "Using HuggingFace path from command line: $HF_PATH"
elif [ -n "$HF_HOME" ]; then
    # Use existing HF_HOME environment variable
    HF_PATH="$HF_HOME"
    print_info "Using existing HF_HOME environment variable: $HF_PATH"
elif [ -n "$HF_HUB_CACHE" ]; then
    # Use existing HF_HUB_CACHE environment variable and infer HF_HOME from it
    HF_CACHE_PATH="$HF_HUB_CACHE"
    HF_PATH="$(dirname "$HF_HUB_CACHE")"
    print_info "Using existing HF_HUB_CACHE environment variable: $HF_CACHE_PATH"
    print_info "Inferred HF_HOME: $HF_PATH"
else
    # No environment variable set, ask user (same logic as installers/05_setup_env.sh)
    if [ "$AUTO_MODE" = false ]; then
        echo ""
        print_info "Where would you like to store HuggingFace models and datasets?"
        print_info "Default: $DEFAULT_HF_PATH"
        read -p "Enter path (press Enter for default): " HF_PATH_INPUT
        
        if [ -z "$HF_PATH_INPUT" ]; then
            HF_PATH="$DEFAULT_HF_PATH"
            print_info "Using default path: $HF_PATH"
        else
            # Expand tilde if present
            HF_PATH="${HF_PATH_INPUT/#\~/$HOME}"
            print_info "Using custom path: $HF_PATH"
        fi
    else
        HF_PATH="$DEFAULT_HF_PATH"
        print_info "Using default HuggingFace path: $HF_PATH"
    fi
fi

if [ -z "$HF_CACHE_PATH" ]; then
    HF_CACHE_PATH="$HF_PATH/hub"
fi

# Check if required tools are installed
print_info "Checking required tools..."

# Check Python
if ! command -v python3 &> /dev/null; then
    print_error "Python 3 is not installed"
    print_info "Please install Python 3.11 with pyenv first"
    exit 1
fi

# Check uv
if ! command -v uv &> /dev/null; then
    print_error "uv is not installed"
    print_info "Please install uv with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Check if virtual environment is activated
if [ -z "$VIRTUAL_ENV" ]; then
    print_warning "No virtual environment activated"
    print_info "Please activate your virtual environment first:"
    print_info "  source ./launch_env.sh"
    exit 1
fi

case ":$PATH:" in
    *":$VIRTUAL_ENV/bin:"*) ;;
    *) export PATH="$VIRTUAL_ENV/bin:$PATH" ;;
esac

# Check if required packages are installed
if ! check_hf_fast_download_tooling; then
    print_warning "Installing/upgrading Hugging Face fast-download tooling in the active environment..."
    if ! uv pip install -U "huggingface_hub[hf-xet]"; then
        print_error "Failed to install Hugging Face Hub fast-download tooling"
        print_info "Run source ./installers/05_setup_env.sh first, then retry this script."
        exit 1
    fi

    if ! check_hf_fast_download_tooling; then
        print_error "Required Hugging Face tooling is still unavailable after install"
        print_info "Make sure the active virtual environment exposes the modern 'hf' CLI and hf-xet package."
        exit 1
    fi
fi

# Interactive mode if no model specified
if [ -z "$MODEL_NAME" ] && [ "$REPO_TYPE" != "model" ] && [ "$REPO_TYPE" != "auto" ]; then
    if [ "$AUTO_MODE" = true ]; then
        print_error "No $REPO_TYPE repo specified"
        print_info "Use: $0 --repo-type $REPO_TYPE -m 'organization/repo-name'"
        exit 1
    fi

    echo "----------------------------------------"
    echo "Hugging Face $REPO_TYPE Downloader"
    echo "----------------------------------------"
    echo ""
    if [ "$REPO_TYPE" = "dataset" ]; then
        read -p "Enter dataset repo name (e.g., AlienKevin/SWE-ZERO-12M-trajectories): " MODEL_NAME
    else
        read -p "Enter $REPO_TYPE repo name (e.g., organization/repo-name): " MODEL_NAME
    fi

    if [ -z "$MODEL_NAME" ]; then
        print_error "No $REPO_TYPE repo specified"
        exit 1
    fi
fi

if [ -z "$MODEL_NAME" ]; then
    echo "----------------------------------------"
    echo "Hugging Face Model Downloader"
    echo "----------------------------------------"
    echo ""
    echo "Popular models:"
    echo ""
    echo "Prime Intellect Models:"
    echo "1) PrimeIntellect/INTELLECT-2 (INTELLECT-2 32B) - DEFAULT"
    echo ""
    echo "OpenAI Models:"
    echo "2) openai/gpt-oss-20b (OpenAI GPT OSS 20B)"
    echo "3) openai/gpt-oss-120b (OpenAI GPT OSS 120B)"
    echo ""
    echo "DeepSeek Models:"
    echo "4) deepseek-ai/DeepSeek-V3 (DeepSeek V3)"
    echo "5) deepseek-ai/DeepSeek-R1-0528 (DeepSeek R1)"
    echo ""
    echo "Moonshot AI Models:"
    echo "6) moonshotai/Kimi-K2-Base (Kimi K2 Base)"
    echo "7) moonshotai/Kimi-K2-Instruct (Kimi K2 Instruct)"
    echo ""
    echo "Qwen Models:"
    echo "8) Qwen/Qwen3-30B-A3B-Instruct-2507 (Qwen3 30B Instruct)"
    echo "9) Qwen/Qwen3-30B-A3B-Instruct-2507-FP8 (Qwen3 30B Instruct FP8)"
    echo "10) Qwen/Qwen3-30B-A3B-Thinking-2507 (Qwen3 30B Thinking)"
    echo "11) Qwen/Qwen3-30B-A3B-Thinking-2507-FP8 (Qwen3 30B Thinking FP8)"
    echo "12) Qwen/Qwen3-235B-A22B-Instruct-2507 (Qwen3 235B Instruct)"
    echo "13) Qwen/Qwen3-235B-A22B-Instruct-2507-FP8 (Qwen3 235B Instruct FP8)"
    echo "14) Qwen/Qwen3-235B-A22B-Thinking-2507 (Qwen3 235B Thinking)"
    echo "15) Qwen/Qwen3-235B-A22B-Thinking-2507-FP8 (Qwen3 235B Thinking FP8)"
    echo "16) Qwen/Qwen3-Coder-30B-A3B-Instruct (Qwen3 30B Coder)"
    echo "17) Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8 (Qwen3 30B Coder FP8)"
    echo "18) Qwen/Qwen3-Coder-480B-A35B-Instruct (Qwen3 480B Coder)"
    echo "19) Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8 (Qwen3 480B Coder FP8)"
    echo ""
    echo "GLM Models:"
    echo "20) zai-org/GLM-4.1V-9B-Thinking (GLM 4.1V 9B Thinking)"
    echo "21) zai-org/GLM-4.5 (GLM 4.5)"
    echo "22) zai-org/GLM-4.5-FP8 (GLM 4.5 FP8)"
    echo "23) zai-org/GLM-4.5-Air (GLM 4.5 Air)"
    echo "24) zai-org/GLM-4.5-Air-FP8 (GLM 4.5 Air FP8)"
    echo "25) zai-org/GLM-4.5-Base (GLM 4.5 Base)"
    echo ""
    echo "Hermes Models:"
    echo "26) NousResearch/Hermes-4-14B (Hermes 4 14B)"
    echo "27) NousResearch/Hermes-4-14B-FP8 (Hermes 4 14B FP8)"
    echo "28) NousResearch/Hermes-4-70B (Hermes 4 70B)"
    echo "29) NousResearch/Hermes-4-70B-FP8 (Hermes 4 70B FP8)"
    echo "30) NousResearch/Hermes-4-405B (Hermes 4 405B)"
    echo "31) NousResearch/Hermes-4-405B-FP8 (Hermes 4 405B FP8)"
    echo ""
    echo "32) Custom (enter your own)"
    echo ""
    read -p "Select model (1-32) or press Enter for default [PrimeIntellect/INTELLECT-2]: " choice
    
    case $choice in
        1|"") MODEL_NAME="PrimeIntellect/INTELLECT-2" ;;
        2) MODEL_NAME="openai/gpt-oss-20b" ;;
        3) MODEL_NAME="openai/gpt-oss-120b" ;;
        4) MODEL_NAME="deepseek-ai/DeepSeek-V3" ;;
        5) MODEL_NAME="deepseek-ai/DeepSeek-R1-0528" ;;
        6) MODEL_NAME="moonshotai/Kimi-K2-Base" ;;
        7) MODEL_NAME="moonshotai/Kimi-K2-Instruct" ;;
        8) MODEL_NAME="Qwen/Qwen3-30B-A3B-Instruct-2507" ;;
        9) MODEL_NAME="Qwen/Qwen3-30B-A3B-Instruct-2507-FP8" ;;
        10) MODEL_NAME="Qwen/Qwen3-30B-A3B-Thinking-2507" ;;
        11) MODEL_NAME="Qwen/Qwen3-30B-A3B-Thinking-2507-FP8" ;;
        12) MODEL_NAME="Qwen/Qwen3-235B-A22B-Instruct-2507" ;;
        13) MODEL_NAME="Qwen/Qwen3-235B-A22B-Instruct-2507-FP8" ;;
        14) MODEL_NAME="Qwen/Qwen3-235B-A22B-Thinking-2507" ;;
        15) MODEL_NAME="Qwen/Qwen3-235B-A22B-Thinking-2507-FP8" ;;
        16) MODEL_NAME="Qwen/Qwen3-Coder-30B-A3B-Instruct" ;;
        17) MODEL_NAME="Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8" ;;
        18) MODEL_NAME="Qwen/Qwen3-Coder-480B-A35B-Instruct" ;;
        19) MODEL_NAME="Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8" ;;
        20) MODEL_NAME="zai-org/GLM-4.1V-9B-Thinking" ;;
        21) MODEL_NAME="zai-org/GLM-4.5" ;;
        22) MODEL_NAME="zai-org/GLM-4.5-FP8" ;;
        23) MODEL_NAME="zai-org/GLM-4.5-Air" ;;
        24) MODEL_NAME="zai-org/GLM-4.5-Air-FP8" ;;
        25) MODEL_NAME="zai-org/GLM-4.5-Base" ;;
        26) MODEL_NAME="NousResearch/Hermes-4-14B" ;;
        27) MODEL_NAME="NousResearch/Hermes-4-14B-FP8" ;;
        28) MODEL_NAME="NousResearch/Hermes-4-70B" ;;
        29) MODEL_NAME="NousResearch/Hermes-4-70B-FP8" ;;
        30) MODEL_NAME="NousResearch/Hermes-4-405B" ;;
        31) MODEL_NAME="NousResearch/Hermes-4-405B-FP8" ;;
        32) 
            read -p "Enter model name (e.g., organization/model-name): " MODEL_NAME
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
fi

# Check for quantization suffix
if [ -n "$QUANTIZATION" ]; then
    case $QUANTIZATION in
        GGUF|gguf)
            # Append -GGUF to model name if not already there
            if [[ ! "$MODEL_NAME" == *"-GGUF" ]]; then
                MODEL_NAME="${MODEL_NAME}-GGUF"
            fi
            ;;
        GPTQ|gptq)
            # Append -GPTQ to model name if not already there
            if [[ ! "$MODEL_NAME" == *"-GPTQ"* ]]; then
                MODEL_NAME="${MODEL_NAME}-GPTQ"
            fi
            ;;
    esac
fi

# Setup directories
print_info "Setting up Hugging Face cache directory..."
setup_directory "$HF_PATH"
setup_directory "$HF_CACHE_PATH"

# Export environment variables using the standard Hugging Face cache layout.
export HF_HOME="$HF_PATH"
export HF_HUB_CACHE="$HF_CACHE_PATH"
export MODEL_NAME
export REPO_TYPE
export AUTO_YES
export UPDATE_AND_PRUNE

# Enable Hugging Face's current high-performance download path. These are read
# by huggingface_hub at import time, so they must be exported before Python runs.
export HF_DOWNLOAD_MAX_WORKERS="${HF_DOWNLOAD_MAX_WORKERS:-$DEFAULT_HF_DOWNLOAD_MAX_WORKERS}"
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"
export HF_XET_NUM_CONCURRENT_RANGE_GETS="${HF_XET_NUM_CONCURRENT_RANGE_GETS:-$DEFAULT_HF_XET_NUM_CONCURRENT_RANGE_GETS}"
export HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS="${HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS:-$DEFAULT_HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS}"
export HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS="${HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS:-$DEFAULT_HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS}"
export HF_DOWNLOAD_RETRY_DELAY_SECONDS="${HF_DOWNLOAD_RETRY_DELAY_SECONDS:-$DEFAULT_HF_DOWNLOAD_RETRY_DELAY_SECONDS}"
export HF_DOWNLOAD_MAX_RETRIES="${HF_DOWNLOAD_MAX_RETRIES:-$DEFAULT_HF_DOWNLOAD_MAX_RETRIES}"

if ! [[ "$HF_DOWNLOAD_MAX_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
    print_error "HF_DOWNLOAD_MAX_WORKERS must be a positive integer"
    exit 1
fi

if ! [[ "$HF_XET_NUM_CONCURRENT_RANGE_GETS" =~ ^[1-9][0-9]*$ ]]; then
    print_error "HF_XET_NUM_CONCURRENT_RANGE_GETS must be a positive integer"
    exit 1
fi

for integer_setting in \
    HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS \
    HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS \
    HF_DOWNLOAD_RETRY_DELAY_SECONDS \
    HF_DOWNLOAD_MAX_RETRIES; do
    if ! [[ "${!integer_setting}" =~ ^[0-9]+$ ]]; then
        print_error "$integer_setting must be a non-negative integer"
        exit 1
    fi
done

case "${HF_HUB_DISABLE_XET:-}" in
    1|ON|On|on|YES|Yes|yes|TRUE|True|true)
        print_warning "HF_HUB_DISABLE_XET is set; Hugging Face fast Xet downloads are disabled."
        ;;
esac

print_info "Environment variables set:"
print_info "  HF_HOME=$HF_HOME"
print_info "  HF_HUB_CACHE=$HF_HUB_CACHE"
print_info "  REPO_TYPE=$REPO_TYPE"
print_info "  HF_XET_HIGH_PERFORMANCE=$HF_XET_HIGH_PERFORMANCE"
print_info "  HF_XET_NUM_CONCURRENT_RANGE_GETS=$HF_XET_NUM_CONCURRENT_RANGE_GETS"
print_info "  HF_DOWNLOAD_MAX_WORKERS=$HF_DOWNLOAD_MAX_WORKERS"
print_info "  HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS=$HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS"
print_info "  HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS=$HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS"
print_info "  HF_DOWNLOAD_RETRY_DELAY_SECONDS=$HF_DOWNLOAD_RETRY_DELAY_SECONDS"
print_info "  HF_DOWNLOAD_MAX_RETRIES=$HF_DOWNLOAD_MAX_RETRIES"

# Create Python download script
PYTHON_SCRIPT=$(mktemp /tmp/download_hf_repo_XXXXXX.py)
cat > "$PYTHON_SCRIPT" << 'PY'
#!/usr/bin/env python3
import os
import sys
import json
import random
import shlex
import signal
import subprocess
import time
from pathlib import Path
from datetime import datetime

try:
    from huggingface_hub import snapshot_download, HfApi
    from huggingface_hub.utils import LocalEntryNotFoundError
except ImportError as e:
    print(f"Error: Missing required package: {e}")
    print("Run source ./installers/05_setup_env.sh first; it installs Hugging Face Hub tooling into the selected environment.")
    sys.exit(1)

repo_id = os.environ["MODEL_NAME"]
requested_repo_type = os.environ.get("REPO_TYPE", "auto")
download_max_workers = int(os.environ.get("HF_DOWNLOAD_MAX_WORKERS", "32"))
connection_refresh_seconds = int(os.environ.get("HF_DOWNLOAD_CONNECTION_REFRESH_SECONDS", "600"))
connection_refresh_jitter_seconds = int(os.environ.get("HF_DOWNLOAD_CONNECTION_REFRESH_JITTER_SECONDS", "120"))
retry_delay_seconds = int(os.environ.get("HF_DOWNLOAD_RETRY_DELAY_SECONDS", "10"))
max_download_retries = int(os.environ.get("HF_DOWNLOAD_MAX_RETRIES", "0"))
cache_dir = Path(os.environ["HF_HUB_CACHE"])
auto_yes = os.environ.get("AUTO_YES", "false").lower() == "true"
update_and_prune = os.environ.get("UPDATE_AND_PRUNE", "false").lower() == "true"

def get_remote_info(api, repo_id, repo_type):
    kwargs = {"repo_id": repo_id, "files_metadata": True}
    try:
        if repo_type == "model":
            return api.model_info(**kwargs)
        if repo_type == "dataset":
            return api.dataset_info(**kwargs)
        return api.repo_info(**kwargs, repo_type=repo_type)
    except TypeError:
        kwargs.pop("files_metadata", None)
        if repo_type == "model":
            return api.model_info(**kwargs)
        if repo_type == "dataset":
            return api.dataset_info(**kwargs)
        return api.repo_info(**kwargs, repo_type=repo_type)

def resolve_repo_type(api, repo_id, requested_repo_type):
    if requested_repo_type != "auto":
        return requested_repo_type, get_remote_info(api, repo_id, requested_repo_type)

    errors = []
    for candidate in ("model", "dataset", "space"):
        try:
            return candidate, get_remote_info(api, repo_id, candidate)
        except Exception as exc:
            errors.append(f"{candidate}: {exc}")

    raise RuntimeError(
        f"Could not find Hugging Face repo '{repo_id}' as a model, dataset, or space.\n"
        + "\n".join(f"  - {error}" for error in errors)
    )

api = HfApi()
repo_type, initial_remote_info = resolve_repo_type(api, repo_id, requested_repo_type)
cache_repo_dir = cache_dir / f"{repo_type}s--{repo_id.replace('/', '--')}"
repo_label = repo_type.capitalize()
download_revision = initial_remote_info.sha
if not download_revision:
    raise RuntimeError("The Hub response did not include a snapshot commit")

print(f"\n{'='*60}")
print(f"{repo_label}: {repo_id}")
print(f"Repo type: {repo_type}")
if requested_repo_type == "auto":
    print("Repo type detection: auto")
print(f"Download location: {cache_dir}")
print(f"Repository cache directory: {cache_repo_dir}")
print(f"Latest Hub snapshot: {download_revision}")
print(f"hf download workers: {download_max_workers}")
print(f"HF_XET_HIGH_PERFORMANCE: {os.environ.get('HF_XET_HIGH_PERFORMANCE', '')}")
print(f"HF_XET_NUM_CONCURRENT_RANGE_GETS: {os.environ.get('HF_XET_NUM_CONCURRENT_RANGE_GETS', '')}")
if connection_refresh_seconds:
    print(
        "Connection refresh watchdog: "
        f"{connection_refresh_seconds}s + up to {connection_refresh_jitter_seconds}s jitter"
    )
else:
    print("Connection refresh watchdog: disabled")
print(f"{'='*60}\n")

class DownloadTermination(Exception):
    def __init__(self, signum):
        self.signum = signum
        super().__init__(f"received signal {signum}")

def stop_download_process(process, fast=False):
    """Stop the whole hf process group while allowing it to flush resumable state."""
    if process.poll() is not None:
        return

    stop_sequence = (
        ((signal.SIGINT, 2), (signal.SIGTERM, 2))
        if fast
        else ((signal.SIGINT, 20), (signal.SIGTERM, 10))
    )

    try:
        for stop_signal, wait_seconds in stop_sequence:
            try:
                os.killpg(process.pid, stop_signal)
            except ProcessLookupError:
                return

            try:
                process.wait(timeout=wait_seconds)
                return
            except subprocess.TimeoutExpired:
                pass

        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            return
        process.wait()
    except BaseException:
        # A second Ctrl+C must not leave the detached hf process running.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        raise

def run_resumable_download(command):
    """Run hf with periodic connection recreation and transient-failure retries."""
    launch_number = 0
    failed_attempts = 0

    while True:
        launch_number += 1
        refresh_after = 0
        if connection_refresh_seconds:
            refresh_after = connection_refresh_seconds + random.randint(
                0, connection_refresh_jitter_seconds
            )

        if launch_number > 1:
            print(f"\nResuming download (connection attempt {launch_number})...")

        process = subprocess.Popen(command, start_new_session=True)
        try:
            if refresh_after:
                return_code = process.wait(timeout=refresh_after)
            else:
                return_code = process.wait()
        except subprocess.TimeoutExpired:
            print(
                "\nRefreshing download connections so recovered bandwidth is used "
                f"(next resume is automatic; cached data is preserved)..."
            )
            stop_download_process(process)
            continue
        except BaseException:
            stop_download_process(process, fast=True)
            raise

        if return_code == 0:
            return

        if return_code in (-signal.SIGINT, 128 + signal.SIGINT):
            raise KeyboardInterrupt

        for termination_signal in (signal.SIGTERM, signal.SIGHUP):
            if return_code in (-termination_signal, 128 + termination_signal):
                raise DownloadTermination(termination_signal)

        failed_attempts += 1
        if max_download_retries and failed_attempts > max_download_retries:
            raise subprocess.CalledProcessError(return_code, command)

        retry_number = failed_attempts
        retry_limit = str(max_download_retries) if max_download_retries else "unlimited"
        retry_jitter = random.randint(0, min(connection_refresh_jitter_seconds, 30))
        retry_wait = retry_delay_seconds + retry_jitter
        print(
            f"\nhf download exited with status {return_code}; transient retry "
            f"{retry_number}/{retry_limit} in {retry_wait}s..."
        )
        time.sleep(retry_wait)

def handle_termination_signal(signum, _frame):
    raise DownloadTermination(signum)

signal.signal(signal.SIGINT, signal.default_int_handler)
for termination_signal in (signal.SIGTERM, signal.SIGHUP):
    signal.signal(termination_signal, handle_termination_signal)

def local_snapshot(repo_id, repo_type, cache_dir, revision):
    return snapshot_download(
        repo_id=repo_id,
        repo_type=repo_type,
        revision=revision,
        cache_dir=str(cache_dir),
        local_files_only=True,
    )

def save_repo_info(local_path, local_size, timestamp_key):
    info_file = Path(os.environ["HF_HOME"]).parent / "downloaded_models.json"
    repo_info_data = {
        "repo_id": repo_id,
        "repo_type": repo_type,
        "model_name": repo_id,
        "local_path": str(local_path) if local_path else "cached",
        "cache_dir": str(cache_dir),
        "cache_repo_dir": str(cache_repo_dir),
        "size_gb": local_size / 1e9,
        timestamp_key: datetime.now().isoformat(),
    }

    existing_data = []
    if info_file.exists():
        with open(info_file, "r") as f:
            try:
                existing_data = json.load(f)
            except Exception:
                existing_data = []

    repo_found = False
    for i, item in enumerate(existing_data):
        item_repo_id = item.get("repo_id", item.get("model_name"))
        item_repo_type = item.get("repo_type", "model")
        if item_repo_id == repo_id and item_repo_type == repo_type:
            existing_data[i] = repo_info_data
            repo_found = True
            break

    if not repo_found:
        existing_data.append(repo_info_data)

    with open(info_file, "w") as f:
        json.dump(existing_data, f, indent=2)

    return info_file

def write_download_result(local_path, status="downloaded"):
    result_file = os.environ.get("DOWNLOAD_RESULT_FILE")
    if not result_file:
        return

    with open(result_file, "w") as f:
        f.write(f"DOWNLOAD_REPO_ID={shlex.quote(repo_id)}\n")
        f.write(f"DOWNLOAD_REPO_TYPE={shlex.quote(repo_type)}\n")
        f.write(f"DOWNLOAD_CACHE_REPO_DIR={shlex.quote(str(cache_repo_dir))}\n")
        f.write(f"DOWNLOAD_LOCAL_PATH={shlex.quote(str(local_path) if local_path else '')}\n")
        f.write(f"DOWNLOAD_RESULT_STATUS={shlex.quote(status)}\n")

def update_main_ref(snapshot_sha):
    refs_dir = cache_repo_dir / "refs"
    refs_dir.mkdir(parents=True, exist_ok=True)
    (refs_dir / "main").write_text(snapshot_sha)

def check_repo_completeness(repo_id, repo_type, cache_dir, remote_info=None):
    """
    Check whether the exact latest Hub snapshot is cached and verify every file size.
    """
    try:
        print("Checking remote repository...")
        if remote_info is None:
            remote_info = get_remote_info(HfApi(), repo_id, repo_type)

        remote_sha = remote_info.sha
        if not remote_sha:
            raise RuntimeError("The Hub response did not include a snapshot commit")

        expected_files = {}
        total_size = 0

        for sibling in remote_info.siblings:
            if hasattr(sibling, "rfilename") and hasattr(sibling, "size"):
                expected_files[sibling.rfilename] = {
                    "size": sibling.size,
                    "lfs": getattr(sibling, "lfs", None),
                }
                if sibling.size:
                    total_size += sibling.size

        print(f"Latest snapshot: {remote_sha}")
        print(f"Expected {repo_type} size: {total_size / 1e9:.1f} GB")
        print(f"Number of files expected: {len(expected_files)}")

        print("\nChecking local cache...")
        if not cache_repo_dir.exists():
            print(f"{repo_label} not found in local cache")
            print(f"Expected cache directory: {cache_repo_dir}")
            return False, expected_files, 0

        try:
            local_path = Path(local_snapshot(repo_id, repo_type, cache_dir, remote_sha))
        except LocalEntryNotFoundError:
            print(f"{repo_label} snapshot {remote_sha} is not fully available in local cache")
            return False, expected_files, 0

        missing_files = []
        corrupted_files = []
        local_size = 0

        for filename, file_info in expected_files.items():
            file_path = local_path / filename
            if not file_path.exists():
                missing_files.append(filename)
                print(f"  ❌ Missing: {filename}")
                continue

            file_size = file_path.stat().st_size
            local_size += file_size
            if file_info["size"] is not None and file_size != file_info["size"]:
                corrupted_files.append(filename)
                print(f"  ❌ Size mismatch: {filename}")
                print(f"     Expected: {file_info['size']}, Got: {file_size}")

        print("\nLocal cache summary:")
        print(f"  Repository cache directory: {cache_repo_dir}")
        print(f"  Total size on disk: {local_size / 1e9:.1f} GB")
        print(f"  Files found: {len(expected_files) - len(missing_files)}/{len(expected_files)}")

        if missing_files:
            print(f"  Missing files: {len(missing_files)}")
            for f in missing_files[:5]:
                print(f"    - {f}")
            if len(missing_files) > 5:
                print(f"    ... and {len(missing_files) - 5} more")

        if corrupted_files:
            print(f"  Corrupted files: {len(corrupted_files)}")
            for f in corrupted_files[:5]:
                print(f"    - {f}")

        is_complete = len(missing_files) == 0 and len(corrupted_files) == 0

        if is_complete:
            print(f"\n✓ {repo_label} is fully downloaded and verified!")
            return True, expected_files, local_size, str(local_path)
        else:
            print(f"\n⚠️  {repo_label} is incomplete or has corrupted files")
            return False, expected_files, local_size

    except Exception as e:
        print(f"Error checking {repo_type} completeness: {e}")
        return False, {}, 0

def cached_snapshot_shas():
    snapshots_dir = cache_repo_dir / "snapshots"
    if not snapshots_dir.is_dir():
        return []
    return sorted(path.name for path in snapshots_dir.iterdir() if path.is_dir())

def preferred_previous_snapshot(snapshot_shas):
    refs_main = cache_repo_dir / "refs" / "main"
    if refs_main.is_file():
        referenced_sha = refs_main.read_text().strip()
        if referenced_sha in snapshot_shas:
            return referenced_sha

    return max(
        snapshot_shas,
        key=lambda sha: (cache_repo_dir / "snapshots" / sha).stat().st_mtime,
    )

def old_snapshot_shas(current_snapshot_sha):
    return [
        sha for sha in cached_snapshot_shas() if sha != current_snapshot_sha
    ]

def print_old_snapshot_reminder(current_snapshot_sha):
    snapshot_shas_to_remove = old_snapshot_shas(current_snapshot_sha)
    if not snapshot_shas_to_remove:
        return

    print("\n" + "="*60)
    print("OLD SNAPSHOT CLEANUP REMINDER")
    print("="*60)
    print(f"Current snapshot: {current_snapshot_sha}")
    print("Older or alternate snapshots are still cached:")
    for old_sha in snapshot_shas_to_remove:
        old_path = (cache_repo_dir / "snapshots" / old_sha).resolve()
        print(f"  - {old_path}")

    print("\nDelete only revisions you no longer need for rollback.")
    print("To reclaim unreferenced blobs safely, use:")
    for old_sha in snapshot_shas_to_remove:
        cleanup_command = [
            "hf",
            "cache",
            "rm",
            old_sha,
            "--cache-dir",
            str(cache_dir.resolve()),
        ]
        print("  " + " ".join(shlex.quote(part) for part in cleanup_command))
    print(
        "Removing only the snapshots/<sha> directory may not reclaim the "
        "underlying blob files."
    )

def prune_old_snapshots(current_snapshot_sha):
    snapshot_shas_to_remove = old_snapshot_shas(current_snapshot_sha)
    if not snapshot_shas_to_remove:
        return

    current_snapshot_dir = cache_repo_dir / "snapshots" / current_snapshot_sha
    if not current_snapshot_dir.is_dir():
        raise RuntimeError(
            "Refusing to prune old snapshots because the verified snapshot is "
            f"missing: {current_snapshot_dir}"
        )

    print("\n" + "="*60)
    print("PRUNING OLD SNAPSHOTS")
    print("="*60)
    print(f"Verified current snapshot: {current_snapshot_sha}")
    for old_sha in snapshot_shas_to_remove:
        print(f"  Removing: {old_sha}")

    cleanup_command = [
        "hf",
        "cache",
        "rm",
        *snapshot_shas_to_remove,
        "--cache-dir",
        str(cache_dir.resolve()),
        "--yes",
    ]
    print("$ " + " ".join(shlex.quote(part) for part in cleanup_command))
    try:
        subprocess.run(cleanup_command, check=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "The latest snapshot is verified and active, but pruning old "
            "snapshots failed"
        ) from exc
    for old_sha in snapshot_shas_to_remove:
        (cache_repo_dir / "trees" / f"{old_sha}.json").unlink(missing_ok=True)

    remaining_snapshot_shas = set(cached_snapshot_shas())
    failed_removals = [
        sha for sha in snapshot_shas_to_remove if sha in remaining_snapshot_shas
    ]
    if failed_removals:
        raise RuntimeError(
            "Old snapshot cleanup completed without removing: "
            + ", ".join(failed_removals)
        )

    print(
        f"Removed {len(snapshot_shas_to_remove)} old snapshot(s), their refs, "
        "and revision metadata."
    )

def handle_old_snapshots(current_snapshot_sha, prune_after_update):
    if update_and_prune:
        if prune_after_update:
            prune_old_snapshots(current_snapshot_sha)
        return

    print_old_snapshot_reminder(current_snapshot_sha)

def confirm_download(prompt):
    if auto_yes:
        print(f"{prompt}y (automatic)")
        return True

    while True:
        try:
            answer = input(prompt).strip().lower()
        except EOFError as exc:
            raise RuntimeError(
                "Cannot read a y/n response. Rerun with -y or --auto to accept automatically."
            ) from exc

        if answer in ("y", "yes"):
            return True
        if answer in ("n", "no"):
            return False
        print("Please answer y or n.")

def offer_new_snapshot(previous_snapshot):
    print("\n" + "="*60)
    print("NEW SNAPSHOT AVAILABLE")
    print("="*60)
    print(f"Cached snapshot: {previous_snapshot}")
    print(f"New snapshot:    {download_revision}")
    print(
        "Hugging Face will reuse unchanged cached blobs, so the transfer can be "
        "much smaller than the snapshot's total size."
    )
    if confirm_download("A new snapshot exists. Do you want to download it? (y/n): "):
        return

    print("Snapshot update declined; keeping the existing cached snapshot.")
    write_download_result("", "skipped")
    sys.exit(0)

cached_shas = cached_snapshot_shas()
previous_snapshot_shas = [sha for sha in cached_shas if sha != download_revision]
previous_snapshot = (
    preferred_previous_snapshot(previous_snapshot_shas)
    if previous_snapshot_shas
    else None
)
main_ref_path = cache_repo_dir / "refs" / "main"
main_ref_before = (
    main_ref_path.read_text().strip() if main_ref_path.is_file() else None
)
prune_after_success = bool(
    update_and_prune
    and previous_snapshot
    and main_ref_before != download_revision
)
update_accepted = False

# If the exact remote commit has no snapshot directory, it is unambiguously a
# new snapshot. Ask before doing the detailed local verification.
if previous_snapshot and download_revision not in cached_shas:
    offer_new_snapshot(previous_snapshot)
    update_accepted = True
    prune_after_success = update_and_prune

# Check whether the exact Hub commit is already fully downloaded.
result = check_repo_completeness(repo_id, repo_type, cache_dir, initial_remote_info)

if len(result) == 4 and result[0]:  # Repo is complete
    is_complete, expected_files, local_size, local_path = result
    print("\n" + "="*60)
    print(f"{repo_label.upper()} ALREADY FULLY DOWNLOADED")
    print("="*60)
    print(f"{repo_label}: {repo_id}")
    print(f"Repository cache directory: {cache_repo_dir}")
    if local_path:
        print(f"Location: {local_path}")
    print(f"Size: {local_size / 1e9:.1f} GB")
    print(f"\nNo download needed - {repo_type} is ready to use!")

    update_main_ref(download_revision)
    handle_old_snapshots(download_revision, prune_after_success)
    save_repo_info(local_path, local_size, "verified_at")
    write_download_result(local_path, "current")
    sys.exit(0)

if previous_snapshot and not update_accepted:
    # The new commit directory exists but failed completeness verification.
    # Keep treating it as an available update and offer to finish it.
    offer_new_snapshot(previous_snapshot)
    update_accepted = True
    prune_after_success = update_and_prune

# Repo is not complete, proceed with download
print("\n" + "="*60)
print("STARTING DOWNLOAD")
print("="*60)

# Create a progress file to track download
safe_repo_name = repo_id.replace("/", "_")
progress_file = Path(os.environ["HF_HOME"]).parent / f".download_progress_{repo_type}_{safe_repo_name}.json"
progress_data = {}

try:
    # Save download start info
    progress_data = {
        "repo_id": repo_id,
        "repo_type": repo_type,
        "model_name": repo_id,
        "started_at": datetime.now().isoformat(),
        "status": "downloading",
        "cache_repo_dir": str(cache_repo_dir),
        "snapshot_sha": download_revision,
    }
    with open(progress_file, "w") as f:
        json.dump(progress_data, f, indent=2)

    print(f"\nDownloading {repo_type} {repo_id}...")
    print(f"Snapshot: {download_revision}")
    print("Note: Download will resume automatically if interrupted")
    print("Note: Unchanged files are reused from the local Hugging Face blob cache")

    # Periodically recreate the CLI process. This resets Xet's connections and
    # retry/concurrency state while the Hub cache preserves completed data.
    hf_command = [
        "hf",
        "download",
        repo_id,
        "--revision",
        download_revision,
        "--cache-dir",
        str(cache_dir),
        "--max-workers",
        str(download_max_workers),
    ]
    if repo_type != "model":
        hf_command.extend(["--repo-type", repo_type])

    print("$ " + " ".join(shlex.quote(part) for part in hf_command))
    run_resumable_download(hf_command)

    local_path = snapshot_download(
        repo_id=repo_id,
        repo_type=repo_type,
        revision=download_revision,
        cache_dir=str(cache_dir),
        local_files_only=True,
    )

    if not cache_repo_dir.exists():
        raise RuntimeError(f"Expected cache repo directory was not created: {cache_repo_dir}")

    print(f"\n✓ {repo_label} downloaded to: {local_path}")
    print(f"✓ Repository cache directory: {cache_repo_dir}")

    # Verify completeness after download
    print("\nVerifying download...")
    final_remote_info = get_remote_info(HfApi(), repo_id, repo_type)
    final_check = check_repo_completeness(
        repo_id,
        repo_type,
        cache_dir,
        final_remote_info,
    )

    if final_check[0]:
        print("\n✓ Download completed and verified successfully!")

        verified_revision = final_remote_info.sha
        if not verified_revision:
            raise RuntimeError("The Hub response did not include a snapshot commit")
        update_main_ref(verified_revision)
        local_path = final_check[3]
        handle_old_snapshots(verified_revision, prune_after_success)

        # Update progress file
        progress_data["status"] = "completed"
        progress_data["completed_at"] = datetime.now().isoformat()
        progress_data["local_path"] = local_path
        with open(progress_file, "w") as f:
            json.dump(progress_data, f, indent=2)

        local_size = final_check[2] if len(final_check) >= 3 else 0
        info_file = save_repo_info(local_path, local_size, "downloaded_at")
        print(f"\n✓ Repository info saved to: {info_file}")
        write_download_result(local_path, "downloaded")

        # Clean up progress file
        if progress_file.exists():
            progress_file.unlink()
    else:
        print("\n⚠️  Download may be incomplete. Run this script again to resume.")
        progress_data["status"] = "incomplete"
        with open(progress_file, "w") as f:
            json.dump(progress_data, f, indent=2)
        sys.exit(1)

except KeyboardInterrupt:
    print("\n⚠️  Download interrupted by user")
    print("Run this script again to resume the download")
    if progress_file.exists():
        progress_data["status"] = "interrupted"
        progress_data["interrupted_at"] = datetime.now().isoformat()
        with open(progress_file, "w") as f:
            json.dump(progress_data, f, indent=2)
    sys.exit(130)

except DownloadTermination as e:
    print(f"\n⚠️  Download interrupted by signal {e.signum}")
    print("Run this script again to resume the download")
    if progress_file.exists():
        progress_data["status"] = "interrupted"
        progress_data["interrupted_at"] = datetime.now().isoformat()
        with open(progress_file, "w") as f:
            json.dump(progress_data, f, indent=2)
    sys.exit(128 + e.signum)

except Exception as e:
    print(f"\n❌ Error downloading {repo_type}: {e}")
    import traceback
    traceback.print_exc()

    if progress_file.exists() and progress_data:
        progress_data["status"] = "error"
        progress_data["error"] = str(e)
        progress_data["error_at"] = datetime.now().isoformat()
        with open(progress_file, "w") as f:
            json.dump(progress_data, f, indent=2)

    sys.exit(1)
PY

# Run the download script
PYTHON_RESULT_FILE=$(mktemp /tmp/download_hf_repo_result_XXXXXX.env)
export DOWNLOAD_RESULT_FILE="$PYTHON_RESULT_FILE"

print_info "Starting Hugging Face repository download..."
python3 "$PYTHON_SCRIPT"
RESULT=$?

if [ -f "$PYTHON_RESULT_FILE" ]; then
    . "$PYTHON_RESULT_FILE"
fi

# Cleanup
rm -f "$PYTHON_SCRIPT" "$PYTHON_RESULT_FILE"

if [ $RESULT -eq 0 ]; then
    DOWNLOAD_REPO_TYPE="${DOWNLOAD_REPO_TYPE:-$REPO_TYPE}"
    DOWNLOAD_REPO_ID="${DOWNLOAD_REPO_ID:-$MODEL_NAME}"
    DOWNLOAD_CACHE_REPO_DIR="${DOWNLOAD_CACHE_REPO_DIR:-$HF_CACHE_PATH/${DOWNLOAD_REPO_TYPE}s--${MODEL_NAME//\//--}}"
    DOWNLOAD_RESULT_STATUS="${DOWNLOAD_RESULT_STATUS:-downloaded}"

    if [ "$DOWNLOAD_RESULT_STATUS" = "skipped" ]; then
        print_warning "Snapshot update skipped for $DOWNLOAD_REPO_ID"
        exit 0
    fi

    if [ "$DOWNLOAD_RESULT_STATUS" = "current" ]; then
        print_info "Hugging Face $DOWNLOAD_REPO_TYPE already has the latest complete snapshot."
    else
        print_info "Hugging Face $DOWNLOAD_REPO_TYPE downloaded successfully!"
    fi
    
    if [ "$DOWNLOAD_REPO_TYPE" = "model" ]; then
        # Create a reference script for this model
        MODEL_SAFE_NAME=$(echo "$MODEL_NAME" | sed 's/[^a-zA-Z0-9-]/_/g')
        # Store the load script in the parent directory of HF_PATH
        LOAD_SCRIPT="$(dirname "$HF_PATH")/load_${MODEL_SAFE_NAME}.sh"
    
        cat > "$LOAD_SCRIPT" << EOF
#!/bin/bash
# Auto-generated script to load $MODEL_NAME
export HF_HOME="$HF_PATH"
export HF_HUB_CACHE="$HF_CACHE_PATH"
echo "Environment set for $MODEL_NAME"
echo "Model cache location: \$HF_HUB_CACHE"
echo ""
echo "To use in Python:"
echo "from transformers import AutoModelForCausalLM, AutoTokenizer"
echo "model = AutoModelForCausalLM.from_pretrained('$MODEL_NAME', trust_remote_code=True)"
echo "tokenizer = AutoTokenizer.from_pretrained('$MODEL_NAME', trust_remote_code=True)"
echo ""
echo "To serve with vLLM:"
echo "vllm serve $MODEL_NAME --trust-remote-code"
echo ""
echo "To serve with SGLang:"
echo "python -m sglang.launch_server --model-path $MODEL_NAME --trust-remote-code"
EOF
    
        chmod +x "$LOAD_SCRIPT"
        print_info "Created load script: $LOAD_SCRIPT"
    fi
    
    echo ""
    echo "=========================================="
    echo "✓ Setup Complete!"
    echo "=========================================="
    echo "Repository: $DOWNLOAD_REPO_ID"
    echo "Type: $DOWNLOAD_REPO_TYPE"
    echo "HF_HOME: $HF_PATH"
    echo "HF_HUB_CACHE: $HF_CACHE_PATH"
    echo "Repository cache: $DOWNLOAD_CACHE_REPO_DIR"
    echo ""
    echo "To use this cache in the future:"
    echo "1. Set environment variable:"
    echo "   export HF_HOME='$HF_PATH'"
    echo "   export HF_HUB_CACHE='$HF_CACHE_PATH'"
    if [ "$DOWNLOAD_REPO_TYPE" = "model" ]; then
        echo ""
        echo "2. Or source the load script:"
        echo "   source $LOAD_SCRIPT"
        echo ""
        echo "Note: If using custom architecture models, use --trust-remote-code flag"
    fi
    echo "=========================================="
else
    print_error "Hugging Face repository download failed!"
    exit 1
fi
