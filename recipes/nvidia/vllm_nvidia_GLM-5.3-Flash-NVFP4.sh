#!/usr/bin/env bash

PYTHON_ENV="env_nvidia-vllm-pr-55222"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env VLLM_USE_V2_MODEL_RUNNER=1 VLLM_ENGINE_READY_TIMEOUT_S=3600"
MODEL_REPO="nvidia/GLM-5.3-Flash-NVFP4"
MODEL_NAME="glm5next"
SERVED_MODEL_NAME="nvidia/GLM-5.3-Flash-NVFP4"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=4
TRUST_REMOTE_CODE=""
REASONING_PARSER="--reasoning-parser glm45"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser glm47"
GPU_MEM_UTIL_VALUE=0.88
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
ENABLE_SPECULATIVE=0
ENABLE_REASONING_PARSER=0
SPECULATIVE=""
QUANTIZATION=""
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS='--data-parallel-size 1 --enable-expert-parallel --enable-ep-weight-filter --model-loader-extra-config {"enable_multithread_load":true,"num_threads":128} --max-num-batched-tokens 8192 --enable-chunked-prefill --max-num-seqs 32'

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../../tools/recipes/inference_recipe.sh
source "$RECIPE_DIR/../../tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
