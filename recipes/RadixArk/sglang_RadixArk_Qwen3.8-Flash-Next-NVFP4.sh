#!/usr/bin/env bash

PYTHON_ENV="env_radixark-qwen-sglang"
INFERENCE_PROVIDER="SGLang"
INFERENCE_ENV=""
MODEL_REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
MODEL_NAME="qwen3"
SERVED_MODEL_NAME="qwen"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE=""
REASONING_PARSER="--reasoning-parser auto"
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER="--tool-call-parser auto"
GPU_MEM_UTIL_VALUE=0.886040
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
QUANTIZATION="--quantization modelopt_fp4"
NO_PREFIX_CACHE=""
SCRIPT_DIR=""
REASONING_PARSER_PLUGIN="${SCRIPT_DIR:+$SCRIPT_DIR/plugins/super_v3_reasoning_parser.py}"
EXTRA_ARGS="--fp4-gemm-backend flashinfer_cutlass --page-size 64 --mamba-radix-cache-strategy extra_buffer --mamba-track-interval 64 --chunked-prefill-size 4096 --max-running-requests 36 --allow-auto-truncate"

RECIPE_DIR="/workspace/scripts/recipes"
# shellcheck source=/workspace/scripts/tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
