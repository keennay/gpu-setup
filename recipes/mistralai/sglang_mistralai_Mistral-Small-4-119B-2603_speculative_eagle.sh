#!/usr/bin/env bash

PYTHON_ENV="env_mistralai-sglang"
INFERENCE_PROVIDER="SGLang"
INFERENCE_ENV="env SGLANG_ALLOW_OVERWRITE_LONGER_CONTEXT_LEN=1"
MODEL_REPO="mistralai/Mistral-Small-4-119B-2603"
MODEL_NAME="mistral"
SERVED_MODEL_NAME="mistral"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser mistral"
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER="--tool-call-parser mistral"
GPU_MEM_UTIL_VALUE=0.876739
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
ENABLE_SPECULATIVE=1
ENABLE_REASONING_PARSER=0
SPECULATIVE="--speculative-algorithm EAGLE --speculative-draft-model-path mistralai/Mistral-Small-4-119B-2603-eagle --speculative-num-steps 3 --speculative-eagle-topk 1 --speculative-num-draft-tokens 4"
QUANTIZATION=""
NO_PREFIX_CACHE="--disable-radix-cache"
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS="--dtype bfloat16"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$RECIPE_DIR/../../tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
