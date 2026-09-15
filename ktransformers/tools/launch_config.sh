#!/usr/bin/env bash

launch_tools_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$launch_tools_dir/sglang_launch_logging.sh"

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <config.env>
       $(basename "$0") [--log|--logs] <config.env>

Example:
  $(basename "$0") envs/qwen35_122b_a10b_fp8/h200.env
  $(basename "$0") --log envs/qwen35_122b_a10b_fp8/h200.env
EOF
}

load_launch_config() {
  local config_file=""
  LAUNCH_ENABLE_LOG=0

  local arg
  for arg in "$@"; do
    case "$arg" in
      --log|--logs)
        LAUNCH_ENABLE_LOG=1
        ;;
      -*)
        echo "Error: unknown launch option: $arg" >&2
        usage
        exit 2
        ;;
      *)
        if [[ -n "$config_file" ]]; then
          echo "Error: expected exactly one config file; got '$config_file' and '$arg'." >&2
          usage
          exit 2
        fi
        config_file="$arg"
        ;;
    esac
  done

  if [[ -z "$config_file" ]]; then
    echo "Error: needs a config file." >&2
    usage
    exit 2
  fi

  if [[ ! -f "$config_file" ]]; then
    echo "Error: config file not found: $config_file" >&2
    usage
    exit 2
  fi
  LAUNCH_CONFIG_FILE="$config_file"

  : "${HF_HOME:?HF_HOME must be set to the Hugging Face model cache path}"
  HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"

  set -a
  source "$config_file"
  set +a

  : "${MODEL:?MODEL must be set in $config_file}"
  : "${CUDA_VISIBLE_DEVICES:?CUDA_VISIBLE_DEVICES must be set in $config_file}"
  if [[ -z ${NUMACTL_CPUNODEBIND+x} ]]; then
    echo "Error: NUMACTL_CPUNODEBIND must be set in $config_file" >&2
    exit 2
  fi
  if [[ -z ${NUMACTL_MEMBIND+x} ]]; then
    echo "Error: NUMACTL_MEMBIND must be set in $config_file" >&2
    exit 2
  fi
  : "${KT_CPUINFER:?KT_CPUINFER must be set in $config_file}"
  : "${KT_THREADPOOL_COUNT:?KT_THREADPOOL_COUNT must be set in $config_file}"
  : "${KT_NUM_GPU_EXPERTS:?KT_NUM_GPU_EXPERTS must be set in $config_file}"
  : "${KT_METHOD:?KT_METHOD must be set in $config_file}"
  : "${KT_MAX_DEFERRED_EXPERTS_PER_TOKEN:?KT_MAX_DEFERRED_EXPERTS_PER_TOKEN must be set in $config_file}"
  : "${MEM_FRACTION_STATIC:?MEM_FRACTION_STATIC must be set in $config_file}"
  : "${CONTEXT_LENGTH:?CONTEXT_LENGTH must be set in $config_file}"
  : "${MAX_TOTAL_TOKENS:?MAX_TOTAL_TOKENS must be set in $config_file}"
  : "${CHUNKED_PREFILL_SIZE:?CHUNKED_PREFILL_SIZE must be set in $config_file}"
  : "${SERVED_MODEL_NAME:?SERVED_MODEL_NAME must be set in $config_file}"
  : "${TENSOR_PARALLEL_SIZE:?TENSOR_PARALLEL_SIZE must be set in $config_file}"
  if [[ -z ${NUMA_NODE+x} ]]; then
    echo "Error: NUMA_NODE must be set in $config_file" >&2
    exit 2
  fi
  : "${EXPERTS_PATH:?EXPERTS_PATH must be set in $config_file}"

  EXPERTS_PATH="${EXPERTS_PATH#/}"
  EXPERTS_PATH="${EXPERTS_PATH%/}"
  if [[ -z "$EXPERTS_PATH" ]]; then
    echo "Error: EXPERTS_PATH must not be empty in $config_file" >&2
    exit 2
  fi

  ADDITIONAL_SGLANG_ENVS="${ADDITIONAL_SGLANG_ENVS:-}"
  ADDITIONAL_SGLANG_ARGS="${ADDITIONAL_SGLANG_ARGS:-}"
  HTTP_PORT="${HTTP_PORT:-8000}"

  model_path="$HF_HUB_CACHE/$MODEL"
  if [[ ! -e "$model_path" ]]; then
    echo "Error: model path not found: $model_path" >&2
    exit 2
  fi

  NUMACTL_CMD=()
  NUMACTL_ARGS=()
  if [[ -n "$NUMACTL_CPUNODEBIND" ]]; then
    NUMACTL_ARGS+=(--cpunodebind="$NUMACTL_CPUNODEBIND")
  fi
  if [[ -n "$NUMACTL_MEMBIND" ]]; then
    NUMACTL_ARGS+=(--membind="$NUMACTL_MEMBIND")
  fi
  if (( ${#NUMACTL_ARGS[@]} )); then
    NUMACTL_CMD=(numactl "${NUMACTL_ARGS[@]}")
  fi

  NUMA_NODE_ARGS=()
  SGLANG_NUMA_NODE_ARGS=()
  if [[ -n "$NUMA_NODE" ]]; then
    read -r -a NUMA_NODE_ARGS <<< "$NUMA_NODE"
    SGLANG_NUMA_NODE_ARGS=(--numa-node "${NUMA_NODE_ARGS[@]}")
  fi
  ADDITIONAL_SGLANG_ENV_ARGS=()
  if [[ -n "$ADDITIONAL_SGLANG_ENVS" ]]; then
    read -r -a ADDITIONAL_SGLANG_ENV_ARGS <<< "$ADDITIONAL_SGLANG_ENVS"
  fi
  ADDITIONAL_SGLANG_ARG_LIST=()
  if [[ -n "$ADDITIONAL_SGLANG_ARGS" ]]; then
    read -r -a ADDITIONAL_SGLANG_ARG_LIST <<< "$ADDITIONAL_SGLANG_ARGS"
  fi
}

quote_launch_arg() {
  local arg="$1"
  if [[ "$arg" =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then
    printf '%s' "$arg"
  else
    printf "'%s'" "${arg//\'/\'\\\'\'}"
  fi
}

print_wrapped_launch_line() {
  local indent="$1"
  local needs_backslash="$2"
  shift 2

  printf '%s' "$indent"
  local arg
  local first=1
  for arg in "$@"; do
    if (( first )); then
      first=0
    else
      printf ' '
    fi
    quote_launch_arg "$arg"
  done
  if [[ "$needs_backslash" == "yes" ]]; then
    printf ' \\'
  fi
  printf '\n'
}

print_launch_command() {
  echo
  echo "===================="
  echo "Now Launching:"
  echo "===================="
  echo

  local args=("$@")
  local count="${#args[@]}"
  local idx=0
  local line=()

  if (( count == 0 )); then
    return
  fi

  if [[ "${args[$idx]}" == "env" ]]; then
    line=("env")
    idx=$((idx + 1))
    while (( idx < count )) && [[ "${args[$idx]}" == *=* ]]; do
      line+=("${args[$idx]}")
      idx=$((idx + 1))
    done
    print_wrapped_launch_line "  " "yes" "${line[@]}"
  fi

  if (( idx < count )) && [[ "${args[$idx]}" == "numactl" ]]; then
    line=("numactl")
    idx=$((idx + 1))
    while (( idx < count )) && [[ "${args[$idx]}" != "python" ]]; do
      line+=("${args[$idx]}")
      idx=$((idx + 1))
    done
    print_wrapped_launch_line "    " "yes" "${line[@]}"
  fi

  if (( idx + 2 < count )) && [[ "${args[$idx]}" == "python" && "${args[$((idx + 1))]}" == "-m" ]]; then
    print_wrapped_launch_line "    " "yes" "${args[$idx]}" "${args[$((idx + 1))]}" "${args[$((idx + 2))]}"
    idx=$((idx + 3))
  fi

  while (( idx < count )); do
    line=("${args[$idx]}")
    idx=$((idx + 1))
    while (( idx < count )) && [[ "${args[$idx]}" != --* ]]; do
      line+=("${args[$idx]}")
      idx=$((idx + 1))
    done

    if (( idx < count )); then
      print_wrapped_launch_line "      " "yes" "${line[@]}"
    else
      print_wrapped_launch_line "      " "no" "${line[@]}"
    fi
  done
  echo
}
