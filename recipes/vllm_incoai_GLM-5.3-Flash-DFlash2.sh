#!/usr/bin/env bash

PYTHON_ENV="env_glm53flash-dflash2-vllm-pr-55423"
INFERENCE_PROVIDER="vLLM"
INFERENCE_ENV="env VLLM_USE_V2_MODEL_RUNNER=1 VLLM_ENGINE_READY_TIMEOUT_S=3600"
MODEL_REPO="zai-org/GLM-5.3-Flash"
MODEL_NAME="glm5next"
SERVED_MODEL_NAME="glm-5.3-flash-dflash2"
CONTEXT_LEN_VALUE=1048576
DEFAULT_TENSOR_PARALLEL_SIZE=4
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser glm45"
ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"
TOOL_CALL_PARSER="--tool-call-parser glm47"
GPU_MEM_UTIL_VALUE=0.883543
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
SPECULATIVE="--speculative-config {\"method\":\"dflash\",\"model\":\"incoai/GLM-5.3-Flash-DFlash2\",\"num_speculative_tokens\":7,\"disable_eagle_block_drop\":true}"
QUANTIZATION=""
NO_PREFIX_CACHE=""
REASONING_PARSER_PLUGIN=""
EXTRA_ARGS="--dtype bfloat16 --kv-cache-dtype bfloat16 --no-enable-flashinfer-autotune"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=helpers/inference_recipe.sh
source "$RECIPE_DIR/helpers/inference_recipe.sh"
run_inference_recipe "$@"
