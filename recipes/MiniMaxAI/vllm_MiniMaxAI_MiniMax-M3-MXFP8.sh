#!/usr/bin/env bash

PYTHON_ENV="env_glm53-vllm-v0290"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env FLASH_ATTENTION_CUTE_DSL_CACHE_ENABLED=1 VLLM_ENGINE_READY_TIMEOUT_S=3600"
MODEL_REPO="MiniMaxAI/MiniMax-M3-MXFP8"
MODEL_NAME="minimax_m3_vl"
SERVED_MODEL_NAME="MiniMaxAI/MiniMax-M3-MXFP8"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=8
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser minimax_m3"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser minimax_m3"
GPU_MEM_UTIL_VALUE=0.845639
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
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS='--enforce-eager --block-size 128 --kv-cache-dtype fp8 --limit-mm-per-prompt {"image":1,"video":0}'

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../../tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
