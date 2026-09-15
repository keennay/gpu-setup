#!/usr/bin/env bash

PYTHON_ENV="env_nvidia-sglang"
INFERENCE_PROVIDER="SGLang"
INFERENCE_ENV="env SGLANG_ALLOW_OVERWRITE_LONGER_CONTEXT_LEN=1"
MODEL_REPO="nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-BF16"
MODEL_NAME="nemotron"
SERVED_MODEL_NAME="nemotron"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser nemotron_3"
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER="--tool-call-parser qwen3_coder"
GPU_MEM_UTIL_VALUE=0.861854
METRICS_FLAG="--enable-metrics"
HOST="0.0.0.0"
DEFAULT_PORT=8000
API_KEY="--api-key YOUR_API_KEY"

BACKEND_MOE_RUNNER_SM90=""
BACKEND_MOE_RUNNER_SM100=""
BACKEND_MOE_RUNNER_SM103=""
BACKEND_MOE_RUNNER_SM120=""
BACKEND_MOE_RUNNER_SM121=""

ENABLE_CACHE_FLAG=0
ENABLE_SPECULATIVE=0
ENABLE_REASONING_PARSER=0
SPECULATIVE=""
QUANTIZATION=""
NO_PREFIX_CACHE="--disable-radix-cache"
SCRIPT_DIR=""
REASONING_PARSER_PLUGIN="${SCRIPT_DIR:+$SCRIPT_DIR/plugins/super_v3_reasoning_parser.py}"
EXTRA_ARGS="--kv-cache-dtype fp8_e4m3"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/workspace/scripts/tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
