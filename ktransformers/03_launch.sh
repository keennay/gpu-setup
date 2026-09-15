#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/tools/launch_config.sh"
load_launch_config "$@"
setup_sglang_launch_log "$script_dir" "$(basename "$0" .sh)"
recorder_dir="$script_dir/experts/$EXPERTS_PATH/01"

if [[ ! -d "$recorder_dir" ]]; then
  echo "Recorder directory not found: $recorder_dir" >&2
  exit 1
fi

latest_expert_location="$(find "$recorder_dir" -maxdepth 1 -type f -name 'expert_distribution_recorder_*.pt' | sort -V | tail -n 1)"

if [[ -z "$latest_expert_location" ]]; then
  echo "No expert_distribution_recorder_*.pt files found in $recorder_dir" >&2
  exit 1
fi

cmd=(
  env CUDA_VISIBLE_DEVICES="$CUDA_VISIBLE_DEVICES"
  "${ADDITIONAL_SGLANG_ENV_ARGS[@]}"
  "${NUMACTL_CMD[@]}"
  python -m sglang.launch_server \
    --host 0.0.0.0 \
    --port "$HTTP_PORT" \
    --model-path "$model_path" \
    --kt-weight-path "$model_path" \
    --kt-cpuinfer "$KT_CPUINFER" \
    --kt-threadpool-count "$KT_THREADPOOL_COUNT" \
    --kt-num-gpu-experts "$KT_NUM_GPU_EXPERTS" \
    --kt-method "$KT_METHOD" \
    --kt-max-deferred-experts-per-token "$KT_MAX_DEFERRED_EXPERTS_PER_TOKEN" \
    --kt-expert-placement-strategy frequency \
    --init-expert-location "$latest_expert_location" \
    --trust-remote-code \
    --context-length "$CONTEXT_LENGTH" \
    --max-total-tokens "$MAX_TOTAL_TOKENS" \
    --mem-fraction-static "$MEM_FRACTION_STATIC" \
    --chunked-prefill-size "$CHUNKED_PREFILL_SIZE" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --enable-mixed-chunk \
    --tensor-parallel-size "$TENSOR_PARALLEL_SIZE" \
    "${SGLANG_NUMA_NODE_ARGS[@]}" \
    --enable-p2p-check \
    --disable-shared-experts-fusion \
    --disable-radix-cache \
    --disable-chunked-prefix-cache \
    --enable-metrics \
    --collect-tokens-histogram \
    "${ADDITIONAL_SGLANG_ARG_LIST[@]}"
)
print_launch_command "${cmd[@]}"
exec "${cmd[@]}"
