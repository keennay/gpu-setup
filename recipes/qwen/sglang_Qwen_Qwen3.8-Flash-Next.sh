#!/usr/bin/env bash

PYTHON_ENV="env_qwen-flash-next-sglang"
INFERENCE_PROVIDER="SGLang"
INFERENCE_ENV=""
MODEL_REPO="Qwen/Qwen3.8-Flash-Next"
MODEL_NAME="qwen3"
SERVED_MODEL_NAME="qwen"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE=""
REASONING_PARSER="--reasoning-parser auto"
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER="--tool-call-parser auto"
GPU_MEM_UTIL_VALUE=0.878817
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
SPECULATIVE="--speculative-algorithm NEXTN --speculative-num-steps 3 --speculative-eagle-topk 1 --speculative-num-draft-tokens 4"
QUANTIZATION=""
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS="--chunked-prefill-size 8192 --linear-attn-prefill-backend flashinfer --linear-attn-decode-backend flashinfer --mamba-ssm-dtype bfloat16 --max-running-requests 96"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$RECIPE_DIR/../../tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
