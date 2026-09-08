#!/usr/bin/env bash

PYTHON_ENV="env_poolside-vllm"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env VLLM_BLOCKSCALE_FP8_GEMM_FLASHINFER=0"
MODEL_REPO="poolside/Laguna-S-2.1-FP8"
MODEL_NAME="poolside_v1"
SERVED_MODEL_NAME="poolside"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser $MODEL_NAME"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser $MODEL_NAME"
GPU_MEM_UTIL_VALUE=0.843565
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
ENABLE_SPECULATIVE=1
ENABLE_REASONING_PARSER=0
SPECULATIVE='--speculative-config {"method":"dflash","model":"poolside/Laguna-S-2.1-DFlash-FP8","num_speculative_tokens":15}'
QUANTIZATION=""
NO_PREFIX_CACHE="--no-enable-prefix-caching"
SCRIPT_DIR=""
REASONING_PARSER_PLUGIN="${SCRIPT_DIR:+$SCRIPT_DIR/plugins/super_v3_reasoning_parser.py}"
EXTRA_ARGS="--default-chat-template-kwargs {\"enable_thinking\":true} --reasoning-parser poolside_v1 --max-num-batched-tokens 32768 --enforce-eager"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=helpers/inference_recipe.sh
source "$RECIPE_DIR/helpers/inference_recipe.sh"
run_inference_recipe "$@"
