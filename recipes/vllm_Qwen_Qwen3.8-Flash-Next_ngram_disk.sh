#!/usr/bin/env bash

PYTHON_ENV="env_qwen-flash-next-vllm-pr-54129"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env VLLM_PLE_MMAP=1"
MODEL_REPO="Qwen/Qwen3.8-Flash-Next"
MODEL_NAME="qwen3"
SERVED_MODEL_NAME="qwen"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=4
TRUST_REMOTE_CODE_VALUE=true
GPU_MEM_UTIL_VALUE=0.84
KV_CACHE_DTYPE_VALUE="bfloat16"
EXTRA_ARGS_VALUE="--reasoning-parser qwen3 --enable-auto-tool-choice --tool-call-parser qwen3_coder --enable-expert-parallel"

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/workspace/scripts/recipes/helpers/inference_recipe.sh
source "$RECIPE_DIR/helpers/inference_recipe.sh"
run_inference_recipe "$@"
