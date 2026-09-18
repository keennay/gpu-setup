#!/usr/bin/env bash

PYTHON_ENV="env_glm53-vllm-v0290"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env FLASH_ATTENTION_CUTE_DSL_CACHE_ENABLED=1 VLLM_ENGINE_READY_TIMEOUT_S=3600"
MODEL_REPO="MiniMaxAI/MiniMax-M2.5"
MODEL_NAME="minimax_m2"
SERVED_MODEL_NAME="z-lab/MiniMax-M2.5-DFlash"
CONTEXT_LEN_VALUE=196608
DEFAULT_TENSOR_PARALLEL_SIZE=4
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser minimax_m2"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser minimax_m2"
GPU_MEM_UTIL_VALUE=0.81
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
ENABLE_SPECULATIVE=1
ENABLE_REASONING_PARSER=0
SPECULATIVE='--speculative-config {"method":"dflash","model":"z-lab/MiniMax-M2.5-DFlash","num_speculative_tokens":8}'
QUANTIZATION=""
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS="--kernel-config.enable_flashinfer_autotune=False"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
