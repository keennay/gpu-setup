#!/usr/bin/env bash

PYTHON_ENV="env_nex-n2-sglang-v0519"
INFERENCE_PROVIDER="SGLang"
INFERENCE_ENV=""
MODEL_REPO="nex-agi/Nex-N2-mini"
MODEL_NAME="nex_n2_mini"
SERVED_MODEL_NAME="nex-n2-mini"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=4
TRUST_REMOTE_CODE=""
REASONING_PARSER="--reasoning-parser qwen3"
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER="--tool-call-parser qwen3_coder"
GPU_MEM_UTIL_VALUE=0.841297
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
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS="--dtype bfloat16 --mamba-ssm-dtype float32 --mamba-radix-cache-strategy extra_buffer"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=helpers/inference_recipe.sh
source "$RECIPE_DIR/helpers/inference_recipe.sh"
run_inference_recipe "$@"
