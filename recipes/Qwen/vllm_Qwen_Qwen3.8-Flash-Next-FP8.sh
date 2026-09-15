#!/usr/bin/env bash

PYTHON_ENV="env_qwen-flash-next-vllm"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env VLLM_PLE_CPU_OFFLOAD=1"
MODEL_REPO="Qwen/Qwen3.8-Flash-Next-FP8"
MODEL_NAME="qwen3"
SERVED_MODEL_NAME="qwen"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE=""
REASONING_PARSER="--reasoning-parser qwen3"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser qwen3_coder"
GPU_MEM_UTIL_VALUE=0.858381
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
SPECULATIVE='--speculative-config {"method":"mtp","num_speculative_tokens":3}'
QUANTIZATION=""
NO_PREFIX_CACHE=""
SCRIPT_DIR=""
REASONING_PARSER_PLUGIN="${SCRIPT_DIR:+$SCRIPT_DIR/plugins/super_v3_reasoning_parser.py}"
EXTRA_ARGS="--max-num-seqs 256 --enable-prefix-caching --no-enable-flashinfer-autotune --moe-backend triton --enable-expert-parallel"

RECIPE_DIR="/workspace/scripts/recipes"
# shellcheck source=/workspace/scripts/tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
