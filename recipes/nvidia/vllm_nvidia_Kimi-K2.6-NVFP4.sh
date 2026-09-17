#!/usr/bin/env bash

PYTHON_ENV="env_glm53-vllm-v0290"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env FLASH_ATTENTION_CUTE_DSL_CACHE_ENABLED=1 VLLM_ENGINE_READY_TIMEOUT_S=3600"
MODEL_REPO="nvidia/Kimi-K2.6-NVFP4"
MODEL_NAME="kimi_k25"
SERVED_MODEL_NAME="nvidia/Kimi-K2.6-NVFP4"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=8
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser kimi_k2"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser kimi_k2"
GPU_MEM_UTIL_VALUE=0.86
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
EXTRA_ARGS="--enforce-eager --max-num-batched-tokens 16384 --kernel-config.enable_flashinfer_autotune=False"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../../tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
