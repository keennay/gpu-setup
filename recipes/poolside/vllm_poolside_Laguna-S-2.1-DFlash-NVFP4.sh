#!/usr/bin/env bash

PYTHON_ENV="env_poolside-vllm"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV=""
MODEL_REPO="poolside/Laguna-S-2.1-NVFP4"
MODEL_NAME="poolside_v1"
SERVED_MODEL_NAME="poolside"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser $MODEL_NAME"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser $MODEL_NAME"
GPU_MEM_UTIL_VALUE=0.870840
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
SPECULATIVE="--speculative-config {\"method\":\"dflash\",\"model\":\"poolside/Laguna-S-2.1-DFlash-NVFP4\",\"num_speculative_tokens\":15}"
QUANTIZATION=""
NO_PREFIX_CACHE="--no-enable-prefix-caching"
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS="--default-chat-template-kwargs {\"enable_thinking\":true} --max-num-seqs 32 --override-generation-config {\"temperature\":0.7,\"top_p\":0.95} --reasoning-parser poolside_v1"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$RECIPE_DIR/../../tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
