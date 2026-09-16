#!/usr/bin/env bash

PYTHON_ENV="env_glm53-vllm-v0290"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env VLLM_USE_V2_MODEL_RUNNER=1 FLASH_ATTENTION_CUTE_DSL_CACHE_ENABLED=1 VLLM_ENGINE_READY_TIMEOUT_S=3600"
MODEL_REPO="tencent/Hy4-preview-FP8"
MODEL_NAME="hy_v4"
SERVED_MODEL_NAME="tencent/Hy4-preview-FP8"
CONTEXT_LEN_VALUE=65536
DEFAULT_TENSOR_PARALLEL_SIZE=8
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser hy_v4"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser hy_v4"
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
EXTRA_ARGS="--kernel-config.enable_flashinfer_autotune=False"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../../tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
