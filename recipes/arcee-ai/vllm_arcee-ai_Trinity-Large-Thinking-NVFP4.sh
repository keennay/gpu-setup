#!/usr/bin/env bash

PYTHON_ENV="env_arcee-nvfp4-vllm"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env VLLM_ALLOW_LONG_MAX_MODEL_LEN=1"
MODEL_REPO="arcee-ai/Trinity-Large-Thinking-NVFP4"
MODEL_NAME="trinity"
SERVED_MODEL_NAME="trinity"
CONTEXT_LEN_VALUE=524288
DEFAULT_TENSOR_PARALLEL_SIZE=2
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser deepseek_r1"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser qwen3_coder"
GPU_MEM_UTIL_VALUE=0.850295
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
SPECULATIVE=''
QUANTIZATION=""
NO_PREFIX_CACHE="--no-enable-prefix-caching"
SCRIPT_DIR=""
REASONING_PARSER_PLUGIN="${SCRIPT_DIR:+$SCRIPT_DIR/plugins/super_v3_reasoning_parser.py}"
EXTRA_ARGS=""

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/workspace/scripts/tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
