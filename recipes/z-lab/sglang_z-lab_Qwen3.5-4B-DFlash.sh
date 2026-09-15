#!/usr/bin/env bash

PYTHON_ENV="env_z-lab-sglang"
INFERENCE_PROVIDER="SGLang"
INFERENCE_ENV=""
MODEL_REPO="Qwen/Qwen3.5-4B"
MODEL_NAME="qwen3"
SERVED_MODEL_NAME="qwen"
CONTEXT_LEN_VALUE=262144
DEFAULT_TENSOR_PARALLEL_SIZE=1
TRUST_REMOTE_CODE="--trust-remote-code"
REASONING_PARSER="--reasoning-parser qwen3"
ENABLE_AUTO_TOOL_CHOICE=""
TOOL_CALL_PARSER="--tool-call-parser qwen3_coder"
GPU_MEM_UTIL_VALUE=0.856315
METRICS_FLAG="--enable-metrics"
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
SPECULATIVE="--speculative-algorithm DFLASH --speculative-draft-model-path z-lab/Qwen3.5-4B-DFlash --speculative-dflash-block-size 8 --speculative-draft-attention-backend fa4"
QUANTIZATION=""
NO_PREFIX_CACHE="--disable-radix-cache"
SCRIPT_DIR=""
REASONING_PARSER_PLUGIN="${SCRIPT_DIR:+$SCRIPT_DIR/plugins/super_v3_reasoning_parser.py}"
EXTRA_ARGS="--attention-backend flashinfer --linear-attn-prefill-backend flashinfer --linear-attn-decode-backend flashinfer --mamba-scheduler-strategy extra_buffer --max-running-requests 32 --cuda-graph-max-bs-decode 32 --cuda-graph-backend-prefill tc_piecewise --enable-flashinfer-allreduce-fusion"

RECIPE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/workspace/scripts/tools/recipes/inference_recipe.sh
source "/workspace/scripts/tools/recipes/inference_recipe.sh"
run_inference_recipe "$@"
