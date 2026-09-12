#!/usr/bin/env bash

PYTHON_ENV="env_minimax-m2-vllm-0f3ce4c74"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV=""
MODEL_REPO="MiniMaxAI/MiniMax-M2"
MODEL_NAME="minimax_m2"
SERVED_MODEL_NAME="minimax-m2"
CONTEXT_LEN_VALUE=196608
DEFAULT_TENSOR_PARALLEL_SIZE=4
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser minimax_m2"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser minimax_m2"
GPU_MEM_UTIL_VALUE=0.858628
METRICS_FLAG=""
HOST="0.0.0.0"
DEFAULT_PORT=8000
API_KEY="--api-key YOUR_API_KEY"

BACKEND_MOE_RUNNER_SM90=""
BACKEND_MOE_RUNNER_SM100=""
BACKEND_MOE_RUNNER_SM103=""
BACKEND_MOE_RUNNER_SM120=""
BACKEND_MOE_RUNNER_SM121=""

ENABLE_CACHE_FLAG=1
ENABLE_SPECULATIVE=0
ENABLE_REASONING_PARSER=0
SPECULATIVE=""
QUANTIZATION=""
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS='--dtype bfloat16 --compilation-config {"mode":3,"pass_config":{"fuse_minimax_qk_norm":true}}'

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=helpers/inference_recipe.sh
source "$RECIPE_DIR/helpers/inference_recipe.sh"
run_inference_recipe "$@"
