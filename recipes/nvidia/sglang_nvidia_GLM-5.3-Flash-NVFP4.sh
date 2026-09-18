#!/usr/bin/env bash

PYTHON_ENV="env_glm53flash-dflash2-sglang-pr-37818"
INFERENCE_PROVIDER="SGLang"
INFERENCE_ENV=""
MODEL_REPO="nvidia/GLM-5.3-Flash-NVFP4"
MODEL_NAME="glm5next"
SERVED_MODEL_NAME="nvidia/GLM-5.3-Flash-NVFP4"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=4
TRUST_REMOTE_CODE=""
REASONING_PARSER="--reasoning-parser glm45"
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER="--tool-call-parser glm47"
GPU_MEM_UTIL_VALUE=0.85
METRICS_FLAG="--enable-metrics"
HOST="0.0.0.0"
DEFAULT_PORT=8000
API_KEY="--api-key YOUR_API_KEY"

BACKEND_MOE_RUNNER_SM90="marlin"
BACKEND_MOE_RUNNER_SM100="flashinfer_cutlass"
BACKEND_MOE_RUNNER_SM103="flashinfer_cutlass"
BACKEND_MOE_RUNNER_SM120="flashinfer_cutlass"
BACKEND_MOE_RUNNER_SM121="flashinfer_cutlass"

ENABLE_CACHE_FLAG=0
ENABLE_SPECULATIVE=0
ENABLE_REASONING_PARSER=0
SPECULATIVE=""
QUANTIZATION="--quantization modelopt_fp4"
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS="--dsa-prefill-backend tilelang --dsa-decode-backend tilelang --moe-runner-backend marlin"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$RECIPE_DIR/../../tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
