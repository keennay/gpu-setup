#!/usr/bin/env bash

PYTHON_ENV="env_nvidia-nemotron"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env VLLM_ALLOW_LONG_MAX_MODEL_LEN=1"
MODEL_REPO="nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4"
MODEL_NAME="nemotron_v3"
SERVED_MODEL_NAME="nemotron"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=1
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser super_v3"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser qwen3_coder"
GPU_MEM_UTIL_VALUE=0.886040
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
ENABLE_REASONING_PARSER=1
SPECULATIVE=""
QUANTIZATION=""
NO_PREFIX_CACHE="--no-enable-prefix-caching"
REASONING_PARSER_PLUGIN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/plugin/super_v3_reasoning_parser.py"
EXTRA_ARGS="--async-scheduling --dtype auto --kv-cache-dtype fp8 --attention-backend TRITON_ATTN --max-cudagraph-capture-size 128 --enable-chunked-prefill --mamba-ssm-cache-dtype float16 --reasoning-parser-plugin $REASONING_PARSER_PLUGIN"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$RECIPE_DIR/../../tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
