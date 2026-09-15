#!/usr/bin/env bash

PYTHON_ENV="env_arcee-vllm"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV=""
MODEL_REPO="arcee-ai/Trinity-Nano-Preview-W4A16"
MODEL_NAME="trinity"
SERVED_MODEL_NAME="trinity"
CONTEXT_LEN_VALUE=131072
DEFAULT_TENSOR_PARALLEL_SIZE=1
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER=""
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER=""
GPU_MEM_UTIL_VALUE=0.884365
METRICS_FLAG=""
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
SPECULATIVE=''
QUANTIZATION=""
NO_PREFIX_CACHE="--no-enable-prefix-caching"
SCRIPT_DIR=""
REASONING_PARSER_PLUGIN="${SCRIPT_DIR:+$SCRIPT_DIR/plugins/super_v3_reasoning_parser.py}"
EXTRA_ARGS="--dtype bfloat16"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/workspace/scripts/tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
