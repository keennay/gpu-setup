#!/usr/bin/env bash

PYTHON_ENV="env_nemotron-ultra-vllm-9c2d21046"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV=""
MODEL_REPO="nvidia/Qwen3.5-397B-A17B-NVFP4"
MODEL_NAME="qwen3"
SERVED_MODEL_NAME="qwen"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=4
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser $MODEL_NAME"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser qwen3_coder"
GPU_MEM_UTIL_VALUE=0.863133
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
SPECULATIVE='--speculative-config {"method":"mtp","num_speculative_tokens":3,"moe_backend":"triton","kv_cache_dtype":"bfloat16","attention_backend":"TRITON_ATTN"}'
QUANTIZATION="--quantization modelopt_fp4"
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS='--dtype bfloat16 --kv-cache-dtype fp8_e4m3 --attention-backend FLASHINFER --attention-config {"disable_flashinfer_q_quantization":true} --mamba-cache-dtype auto --mamba-ssm-cache-dtype float32 --enable-prefix-caching --mamba-cache-mode align --moe-backend emulation'

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=helpers/inference_recipe.sh
source "$RECIPE_DIR/helpers/inference_recipe.sh"
run_inference_recipe "$@"
