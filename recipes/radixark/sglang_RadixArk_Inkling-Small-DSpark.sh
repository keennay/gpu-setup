#!/usr/bin/env bash

PYTHON_ENV="env_radixark-sglang"
INFERENCE_PROVIDER="SGLang"
INFERENCE_ENV=""
MODEL_REPO="thinkingmachines/Inkling-Small-NVFP4"
MODEL_NAME="inkling"
SERVED_MODEL_NAME="inkling"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser inkling"
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER="--tool-call-parser inkling"
GPU_MEM_UTIL_VALUE=0.787167
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
SPECULATIVE="--speculative-algorithm DSPARK --speculative-draft-model-path RadixArk/Inkling-Small-DSpark --speculative-draft-model-quantization unquant --speculative-dspark-block-size 7"
QUANTIZATION="--quantization modelopt_fp4"
NO_PREFIX_CACHE="--disable-radix-cache"
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS="--page-size 128 --mamba-radix-cache-strategy extra_buffer --swa-full-tokens-ratio 0.1 --mamba-full-memory-ratio 0.1 --disable-flashinfer-autotune"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$RECIPE_DIR/../../tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
