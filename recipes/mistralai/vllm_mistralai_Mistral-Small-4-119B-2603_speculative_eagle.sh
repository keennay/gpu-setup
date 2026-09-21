#!/usr/bin/env bash

PYTHON_ENV="env_mistralai-vllm"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV=""
MODEL_REPO="mistralai/Mistral-Small-4-119B-2603"
MODEL_NAME="mistral"
SERVED_MODEL_NAME="mistral"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser $MODEL_NAME"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser $MODEL_NAME"
GPU_MEM_UTIL_VALUE=0.864369
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
SPECULATIVE="--speculative-config {\"model\":\"mistralai/Mistral-Small-4-119B-2603-eagle\",\"num_speculative_tokens\":3,\"method\":\"eagle\",\"max_model_len\":65536}"
QUANTIZATION=""
NO_PREFIX_CACHE="--no-enable-prefix-caching"
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS=""

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$RECIPE_DIR/../../tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
