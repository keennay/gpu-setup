#!/usr/bin/env bash

PYTHON_ENV="env_gemma-vllm"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV=""
MODEL_REPO="google/diffusiongemma-26B-A4B-it"
MODEL_NAME="gemma4"
SERVED_MODEL_NAME="gemma"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=1
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser $MODEL_NAME"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser $MODEL_NAME"
GPU_MEM_UTIL_VALUE=0.857500
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
EXTRA_ARGS="--max-num-seqs 4"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/workspace/scripts/tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
