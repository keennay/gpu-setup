#!/usr/bin/env bash

# Shared inference recipe runtime; configure the recipe and SM profile before calling run_inference_recipe.

detect_gpu_configuration() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "Error: nvidia-smi is required for GPU detection." >&2
        return 1
    fi

    local gpu_inventory
    if ! gpu_inventory="$(nvidia-smi --query-gpu=index --format=csv,noheader,nounits)"; then
        echo "Error: unable to enumerate NVIDIA GPUs." >&2
        return 1
    fi
    if [ -z "$gpu_inventory" ]; then
        echo "Error: no NVIDIA GPUs detected." >&2
        return 1
    fi

    local -a gpu_ids=()
    mapfile -t gpu_ids <<< "$gpu_inventory"
    TOTAL_GPU_COUNT="${#gpu_ids[@]}"
    FIRST_VISIBLE_GPU="${gpu_ids[0]}"
    if [ "${CUDA_VISIBLE_DEVICES+x}" = "x" ]; then
        FIRST_VISIBLE_GPU="${CUDA_VISIBLE_DEVICES%%,*}"
    fi
    FIRST_VISIBLE_GPU="${FIRST_VISIBLE_GPU//[[:space:]]/}"
    if [ -z "$FIRST_VISIBLE_GPU" ] || [ "$FIRST_VISIBLE_GPU" = "-1" ]; then
        echo "Error: CUDA_VISIBLE_DEVICES exposes no GPUs." >&2
        return 1
    fi

    if ! CUDA_SM_VERSION="$(get_cuda_sm_version "$FIRST_VISIBLE_GPU")"; then
        return 1
    fi

    local attention_backend
    local gemm_backend
    local moe_backend
    case "$CUDA_SM_VERSION" in
        sm_90)
            TENSOR_PARALLEL_SIZE_VALUE="${TENSOR_PARALLEL_SIZE_SM90:-}"
            GPU_MEM_UTIL_VALUE="${GPU_MEM_UTIL_VALUE_SM90:-}"
            CONTEXT_LEN_VALUE="${CONTEXT_LEN_VALUE_SM90:-}"
            attention_backend="${BACKEND_ATTENTION_SM90:-}"
            gemm_backend="${BACKEND_FP8_GEMM_SM90:-${BACKEND_FP4_GEMM_SM90:-}}"
            moe_backend="${BACKEND_MOE_RUNNER_SM90:-}"
            ;;
        sm_100)
            TENSOR_PARALLEL_SIZE_VALUE="${TENSOR_PARALLEL_SIZE_SM100:-}"
            GPU_MEM_UTIL_VALUE="${GPU_MEM_UTIL_VALUE_SM100:-}"
            CONTEXT_LEN_VALUE="${CONTEXT_LEN_VALUE_SM100:-}"
            attention_backend="${BACKEND_ATTENTION_SM100:-}"
            gemm_backend="${BACKEND_FP8_GEMM_SM100:-${BACKEND_FP4_GEMM_SM100:-}}"
            moe_backend="${BACKEND_MOE_RUNNER_SM100:-}"
            ;;
        sm_103)
            TENSOR_PARALLEL_SIZE_VALUE="${TENSOR_PARALLEL_SIZE_SM103:-}"
            GPU_MEM_UTIL_VALUE="${GPU_MEM_UTIL_VALUE_SM103:-}"
            CONTEXT_LEN_VALUE="${CONTEXT_LEN_VALUE_SM103:-}"
            attention_backend="${BACKEND_ATTENTION_SM103:-}"
            gemm_backend="${BACKEND_FP8_GEMM_SM103:-${BACKEND_FP4_GEMM_SM103:-}}"
            moe_backend="${BACKEND_MOE_RUNNER_SM103:-}"
            ;;
        sm_120)
            TENSOR_PARALLEL_SIZE_VALUE="${TENSOR_PARALLEL_SIZE_SM120:-}"
            GPU_MEM_UTIL_VALUE="${GPU_MEM_UTIL_VALUE_SM120:-}"
            CONTEXT_LEN_VALUE="${CONTEXT_LEN_VALUE_SM120:-}"
            attention_backend="${BACKEND_ATTENTION_SM120:-}"
            gemm_backend="${BACKEND_FP8_GEMM_SM120:-${BACKEND_FP4_GEMM_SM120:-}}"
            moe_backend="${BACKEND_MOE_RUNNER_SM120:-}"
            ;;
        sm_121)
            TENSOR_PARALLEL_SIZE_VALUE="${TENSOR_PARALLEL_SIZE_SM121:-}"
            GPU_MEM_UTIL_VALUE="${GPU_MEM_UTIL_VALUE_SM121:-}"
            CONTEXT_LEN_VALUE="${CONTEXT_LEN_VALUE_SM121:-}"
            attention_backend="${BACKEND_ATTENTION_SM121:-}"
            gemm_backend="${BACKEND_FP8_GEMM_SM121:-${BACKEND_FP4_GEMM_SM121:-}}"
            moe_backend="${BACKEND_MOE_RUNNER_SM121:-}"
            ;;
        *)
            echo "Error: no recipe configuration is defined for $CUDA_SM_VERSION." >&2
            return 1
            ;;
    esac

    if [[ "$GPU_MEM_UTIL_VALUE" =~ ^0+([.]0+)?$ ]]; then
        printf '%s\n' \
            "An inference cookbook recipe for this model on your specific GPU architecture does not yet exist." \
            "" \
            "To create one, add the skills provided by this repo to your coding CLI of choice & follow the guide:" \
            "" \
            "$SCRIPTS_DIR/skills/llm-vlm-cookbook-recipe-creation-and-update" \
            "$SCRIPTS_DIR/skills/llm-vlm-cookbook-recipe-source" >&2
        return 1
    fi

    if [ -z "$TENSOR_PARALLEL_SIZE_VALUE" ] || [ -z "$GPU_MEM_UTIL_VALUE" ] || [ -z "$CONTEXT_LEN_VALUE" ]; then
        echo "Error: tensor-parallel size, GPU memory utilization, and context length must be configured for $CUDA_SM_VERSION." >&2
        return 1
    fi

    local backend_args
    for backend_args in "$attention_backend" "$gemm_backend" "$moe_backend"; do
        if [ -n "$backend_args" ]; then
            EXTRA_ARGS+="${EXTRA_ARGS:+ }$backend_args"
        fi
    done
    printf 'GPU configuration: total=%s first=%s SM=%s TP=%s memory=%s\n' \
        "$TOTAL_GPU_COUNT" "$FIRST_VISIBLE_GPU" "$CUDA_SM_VERSION" \
        "$TENSOR_PARALLEL_SIZE_VALUE" "$GPU_MEM_UTIL_VALUE"
}

get_cuda_sm_version() {
    local gpu_id="$1"
    local compute_capability
    if ! compute_capability="$(nvidia-smi --id="$gpu_id" --query-gpu=compute_cap --format=csv,noheader,nounits)"; then
        echo "Error: unable to determine CUDA SM version for GPU $gpu_id." >&2
        return 1
    fi
    compute_capability="${compute_capability//[[:space:]]/}"
    if [[ ! "$compute_capability" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        echo "Error: invalid CUDA compute capability '$compute_capability' for GPU $gpu_id." >&2
        return 1
    fi
    printf 'sm_%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

configured_environment_is_usable() {
    local env_path="$1"

    [ -d "$env_path" ] &&
        [ -x "$env_path/bin/python" ] &&
        { [ -f "$env_path/activate_ml" ] || [ -f "$env_path/bin/activate" ]; }
}

is_valid_python_environment_name() {
    local env_name="$1"

    [ "${#env_name}" -le 128 ] &&
        [[ "$env_name" =~ ^env_[a-z0-9]+([._-][a-z0-9]+)*$ ]]
}

install_inference_provider() {
    if [ ! -x "$PACKAGE_INSTALLER_SCRIPT" ]; then
        echo "Error: package installer not found or not executable: $PACKAGE_INSTALLER_SCRIPT" >&2
        return 1
    fi

    "$PACKAGE_INSTALLER_SCRIPT" "$PYTHON_ENV"
}

prepare_inference_runtime() {
    if [ -z "$PYTHON_ENV" ]; then
        echo "Error: PYTHON_ENV must be set in the recipe." >&2
        return 1
    fi
    if ! is_valid_python_environment_name "$PYTHON_ENV"; then
        echo "Error: invalid PYTHON_ENV '$PYTHON_ENV'." >&2
        echo "Use a lowercase environment name such as 'env_qwen-vllm'." >&2
        return 1
    fi

    local env_path="$HOME/$PYTHON_ENV"
    if ! configured_environment_is_usable "$env_path"; then
        if [ ! -x "$SETUP_ENV_SCRIPT" ]; then
            echo "Error: environment setup script not found or not executable: $SETUP_ENV_SCRIPT" >&2
            return 1
        fi
        echo "Python environment '$PYTHON_ENV' is missing or unusable; creating it..."
        if ! "$SETUP_ENV_SCRIPT" --auto "$PYTHON_ENV"; then
            echo "Error: failed to create Python environment '$PYTHON_ENV'." >&2
            return 1
        fi
    fi

    if ! configured_environment_is_usable "$env_path"; then
        echo "Error: Python environment '$PYTHON_ENV' is unusable after setup: $env_path" >&2
        return 1
    fi

    local provider_path="$env_path/bin/$INFERENCE_COMMAND"
    if [ ! -x "$provider_path" ]; then
        echo "$INFERENCE_PROVIDER is not installed in '$PYTHON_ENV'; installing it..."
        if ! install_inference_provider; then
            echo "Error: failed to install $INFERENCE_PROVIDER in '$PYTHON_ENV'." >&2
            return 1
        fi
    fi

    if [ ! -x "$provider_path" ]; then
        echo "Error: $INFERENCE_PROVIDER executable not found after installation: $provider_path" >&2
        return 1
    fi

    if [ "${VIRTUAL_ENV:-}" != "$env_path" ]; then
        local activation_script="$env_path/activate_ml"
        if [ ! -f "$activation_script" ]; then
            activation_script="$env_path/bin/activate"
        fi
        echo "Using Python environment: $env_path"
        if ! source "$activation_script"; then
            echo "Error: failed to activate Python environment '$PYTHON_ENV'." >&2
            return 1
        fi
    fi

    if [ "${VIRTUAL_ENV:-}" != "$env_path" ]; then
        echo "Error: activation did not select Python environment '$PYTHON_ENV'." >&2
        return 1
    fi
    INFERENCE_EXECUTABLE="$provider_path"
}

server_process_group_is_alive() {
    [ -n "$SERVER_PID" ] && kill -0 -- "-$SERVER_PID" 2>/dev/null
}

wait_for_server_process_group() {
    local timeout_seconds="$1"
    local deadline=$((SECONDS + timeout_seconds))

    while server_process_group_is_alive; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            return 1
        fi
        sleep 0.2
    done
}

signal_server_process_group() {
    local signal_name="$1"

    if server_process_group_is_alive; then
        kill "-$signal_name" -- "-$SERVER_PID" 2>/dev/null || true
    fi
}

shutdown_inference_server() {
    local reason="${1:-script exit}"

    if [ "$SERVER_SHUTDOWN_STARTED" -eq 1 ]; then
        return
    fi
    SERVER_SHUTDOWN_STARTED=1

    if server_process_group_is_alive; then
        echo "Stopping inference server process group $SERVER_PID ($reason)..."
        signal_server_process_group INT
        if ! wait_for_server_process_group "$SERVER_INTERRUPT_GRACE_SECONDS"; then
            echo "Server did not stop after SIGINT; sending SIGTERM..."
            signal_server_process_group TERM
            if ! wait_for_server_process_group "$SERVER_TERMINATE_GRACE_SECONDS"; then
                echo "Server did not stop after SIGTERM; sending SIGKILL..."
                signal_server_process_group KILL
                wait_for_server_process_group 1 || true
            fi
        fi
    fi

    if [ -n "$SERVER_MONITOR_PID" ]; then
        wait "$SERVER_MONITOR_PID" 2>/dev/null || true
    fi
    if [ -n "$SERVER_PID_FILE" ]; then
        rm -f "$SERVER_PID_FILE"
    fi

    SERVER_PID=""
    SERVER_MONITOR_PID=""
    SERVER_PID_FILE=""
    SERVER_SHUTDOWN_STARTED=0
}

handle_inference_signal() {
    local signal_name="$1"
    local exit_status="$2"

    trap '' INT TERM HUP QUIT
    trap - EXIT
    echo ""
    if server_process_group_is_alive; then
        shutdown_inference_server "received SIG$signal_name"
        echo "Inference server stopped."
    else
        shutdown_inference_server "received SIG$signal_name"
        echo "Inference launch interrupted."
    fi
    exit "$exit_status"
}

handle_inference_exit() {
    local exit_status="$1"

    trap - EXIT
    if server_process_group_is_alive; then
        shutdown_inference_server "launcher exited"
    elif [ -n "$SERVER_PID_FILE" ]; then
        rm -f "$SERVER_PID_FILE"
    fi
    exit "$exit_status"
}

launch_inference_server() {
    if ! command -v setsid >/dev/null 2>&1; then
        echo "Error: setsid is required to supervise the inference server process group." >&2
        return 1
    fi

    SERVER_PID_FILE="$(mktemp "${TMPDIR:-/tmp}/inference-recipe.XXXXXX")" || {
        echo "Error: unable to create inference server PID file." >&2
        return 1
    }
    SERVER_SHUTDOWN_STARTED=0

    setsid --fork --wait bash -c "
        pid_file=\$1
        shift
        printf '%s\n' \"\$\$\" > \"\$pid_file\" || exit 125
        exec \"\$@\"
    " inference-server "$SERVER_PID_FILE" "$@" &
    SERVER_MONITOR_PID=$!

    local attempt
    for ((attempt = 0; attempt < 200; attempt++)); do
        if [ -s "$SERVER_PID_FILE" ]; then
            break
        fi
        if ! kill -0 "$SERVER_MONITOR_PID" 2>/dev/null; then
            break
        fi
        sleep 0.01
    done

    if [ ! -s "$SERVER_PID_FILE" ]; then
        local monitor_status=1
        wait "$SERVER_MONITOR_PID" 2>/dev/null || monitor_status=$?
        rm -f "$SERVER_PID_FILE"
        SERVER_MONITOR_PID=""
        SERVER_PID_FILE=""
        echo "Error: inference server failed before process supervision was established." >&2
        return "$monitor_status"
    fi

    IFS= read -r SERVER_PID < "$SERVER_PID_FILE"
    rm -f "$SERVER_PID_FILE"
    SERVER_PID_FILE=""
    if ! [[ "$SERVER_PID" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: inference server returned an invalid process ID: $SERVER_PID" >&2
        shutdown_inference_server "invalid process ID"
        return 1
    fi

    local server_status=0
    wait "$SERVER_MONITOR_PID" || server_status=$?
    SERVER_MONITOR_PID=""

    if server_process_group_is_alive; then
        echo "Inference launcher exited while worker processes remained."
        shutdown_inference_server "launcher exited with active workers"
    else
        SERVER_PID=""
        SERVER_SHUTDOWN_STARTED=0
    fi

    return "$server_status"
}

is_valid_tensor_parallel_size() {
    [[ "$1" =~ ^(1|2|4|8)$ ]]
}

collect_selected_gpu_ids() {
    local requested_count="$TENSOR_PARALLEL_SIZE_VALUE"
    local visible_devices=""
    local candidate
    local index
    local -a candidates=()
    SELECTED_GPU_IDS=()

    if [ "${CUDA_VISIBLE_DEVICES+x}" = "x" ]; then
        visible_devices="$CUDA_VISIBLE_DEVICES"
    else
        for ((index = 0; index < requested_count; index++)); do
            SELECTED_GPU_IDS+=("$index")
        done
        return
    fi

    IFS=',' read -r -a candidates <<< "$visible_devices"
    for candidate in "${candidates[@]}"; do
        candidate="${candidate//[[:space:]]/}"
        if [ -n "$candidate" ]; then
            SELECTED_GPU_IDS+=("$candidate")
        fi
        if [ "${#SELECTED_GPU_IDS[@]}" -eq "$requested_count" ]; then
            break
        fi
    done

    if [ "${#SELECTED_GPU_IDS[@]}" -ne "$requested_count" ]; then
        echo "Error: tensor parallel size $requested_count requires $requested_count visible GPUs, but CUDA_VISIBLE_DEVICES provides ${#SELECTED_GPU_IDS[@]}." >&2
        return 1
    fi
}

check_selected_gpu_processes() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "Error: nvidia-smi is required for the GPU occupancy check." >&2
        return 1
    fi
    if ! collect_selected_gpu_ids; then
        return 1
    fi

    local gpu_id
    local processes
    local pid
    local process_name
    local command_line
    local busy=0
    local selected_gpu_list
    selected_gpu_list="$(IFS=,; printf '%s' "${SELECTED_GPU_IDS[*]}")"

    for gpu_id in "${SELECTED_GPU_IDS[@]}"; do
        if ! processes="$(nvidia-smi --id="$gpu_id" --query-compute-apps=pid,process_name --format=csv,noheader,nounits 2>/dev/null)"; then
            echo "Error: unable to query active compute processes for GPU $gpu_id." >&2
            return 1
        fi
        if [ -z "$processes" ]; then
            continue
        fi

        if [ "$busy" -eq 0 ]; then
            echo "Error: selected GPUs already have active compute processes:" >&2
        fi
        busy=1
        while IFS=',' read -r pid process_name; do
            pid="${pid//[[:space:]]/}"
            process_name="${process_name#"${process_name%%[![:space:]]*}"}"
            process_name="${process_name%"${process_name##*[![:space:]]}"}"
            command_line=""
            if [ -r "/proc/$pid/cmdline" ]; then
                command_line="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
            fi
            if [ -n "$command_line" ]; then
                printf '  GPU %s: PID %s (%s): %s\n' "$gpu_id" "$pid" "$process_name" "$command_line" >&2
            else
                printf '  GPU %s: PID %s (%s)\n' "$gpu_id" "$pid" "$process_name" >&2
            fi
        done <<< "$processes"
    done

    if [ "$busy" -eq 1 ]; then
        echo "Refusing to launch on GPU(s) $selected_gpu_list. Stop the existing processes or select different GPUs." >&2
        return 1
    fi

    echo "GPU preflight passed: no active compute processes on GPU(s) $selected_gpu_list."
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

build_extra_args() {
    local configured_extra_args="$EXTRA_ARGS"
    EXTRA_ARGS=""
    if [ -n "$configured_extra_args" ]; then
        EXTRA_ARGS+="$configured_extra_args "
    fi

    if [ "$ENABLE_SPECULATIVE" -eq 1 ]; then
        EXTRA_ARGS+="$SPECULATIVE "
    fi
    EXTRA_ARGS+="$QUANTIZATION "
    if [ "$ENABLE_CACHE_FLAG" -eq 1 ]; then
        EXTRA_ARGS+="$NO_PREFIX_CACHE "
    fi
}

get_speculative_value() {
    local target="$1"
    local previous=""
    local token

    for token in $SPECULATIVE; do
        if [ "$previous" = "$target" ]; then
            printf '%s' "$token"
            return
        fi
        previous="$token"
    done
}

print_speculative_config() {
    if [ "$ENABLE_SPECULATIVE" -ne 1 ] || [ -z "$SPECULATIVE" ]; then
        return
    fi

    if [ "$INFERENCE_PROVIDER" = "SGLang" ]; then
        echo "Speculative Algo: $(get_speculative_value --speculative-algo)"
        echo "Speculative Number of Steps: $(get_speculative_value --speculative-num-steps)"
        echo "Speculative Eagle TopK: $(get_speculative_value --speculative-eagle-topk)"
        echo "Speculative Number of Draft Tokens: $(get_speculative_value --speculative-num-draft-tokens)"
    else
        echo "Speculative Config: $SPECULATIVE"
    fi
}

run_inference_recipe() {
    : "${RECIPE_DIR:?RECIPE_DIR must be set by the calling recipe}"
    PYTHON_ENV="${PYTHON_ENV:-}"
    INFERENCE_PROVIDER_NORMALIZED="${INFERENCE_PROVIDER,,}"
    HELPER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    SCRIPTS_DIR="$(cd -- "$HELPER_DIR/../.." && pwd -P)"
    SETUP_ENV_SCRIPT="$SCRIPTS_DIR/installers/05_setup_env.sh"
    PACKAGE_INSTALLER_SCRIPT="$SCRIPTS_DIR/installers/06_install_packages.sh"
    INFERENCE_COMMAND=""
    INFERENCE_EXECUTABLE=""

    if ! detect_gpu_configuration; then
        exit 1
    fi

    case "$INFERENCE_PROVIDER_NORMALIZED" in
        sglang)
            INFERENCE_COMMAND="sglang"
            MODEL_PATH="--model-path $MODEL_REPO"
            TENSOR_PARALLEL_SIZE_FLAG="--tp"
            CONTEXT_LEN_FLAG="--context-length $CONTEXT_LEN_VALUE"
            GPU_MEM_UTIL_FLAG="--mem-fraction-static $GPU_MEM_UTIL_VALUE"
            ;;
        vllm)
            INFERENCE_COMMAND="vllm"
            MODEL_PATH="$MODEL_REPO"
            TENSOR_PARALLEL_SIZE_FLAG="--tensor-parallel-size"
            CONTEXT_LEN_FLAG="--max-model-len $CONTEXT_LEN_VALUE"
            GPU_MEM_UTIL_FLAG="--gpu-memory-utilization $GPU_MEM_UTIL_VALUE"
            ;;
        *)
            echo "INFERENCE_LAUNCH needs a value" >&2
            exit 1
            ;;
    esac
    if ! prepare_inference_runtime; then
        exit 1
    fi
    INFERENCE_LAUNCH="$INFERENCE_EXECUTABLE serve"


    LOG_SUFFIX="${INFERENCE_PROVIDER,,}"
    case "$LOG_SUFFIX" in
        vllm|sglang)
            ;;
        *)
            echo "Error: unsupported inference provider for logging: $INFERENCE_PROVIDER" >&2
            exit 1
            ;;
    esac
    CALLING_SCRIPT="${BASH_SOURCE[1]:-$0}"
    CALLING_BASENAME="$(basename -- "$CALLING_SCRIPT")"
    CALLING_REPO=""
    if [[ "$CALLING_BASENAME" =~ ^(vllm|sglang)_([^_]+)_ ]]; then
        CALLING_REPO="${BASH_REMATCH[2]}"
    elif [ -n "$RECIPE_DIR" ] && [ "$(basename "$(dirname "$RECIPE_DIR")")" = "recipes" ]; then
        CALLING_REPO="$(basename "$RECIPE_DIR")"
    fi

    if [ -n "$CALLING_REPO" ] && [ "$CALLING_REPO" != "recipes" ]; then
        LOG_DIR="$SCRIPTS_DIR/recipes/logs/${CALLING_REPO,,}"
    elif [ -n "$RECIPE_DIR" ] && [ -d "$RECIPE_DIR" ]; then
        LOG_DIR="$RECIPE_DIR/logs"
    else
        LOG_DIR="$SCRIPTS_DIR/recipes/logs"
    fi
    LOG_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
    LAUNCH_LOG="$LOG_DIR/${LOG_TIMESTAMP}_${LOG_SUFFIX}.log"
    LAUNCH_LOG_REL="./logs/${LOG_TIMESTAMP}_${LOG_SUFFIX}.log"
    if ! mkdir -p "$LOG_DIR"; then
        echo "Error: unable to create log directory: $LOG_DIR" >&2
        exit 1
    fi
    if ! : > "$LAUNCH_LOG"; then
        echo "Error: unable to write log file: $LAUNCH_LOG" >&2
        exit 1
    fi
    if [ "$LOG_SUFFIX" = "sglang" ]; then
        SGLANG_LAUNCH_LOG="$LAUNCH_LOG"
        export SGLANG_LAUNCH_LOG
    else
        VLLM_LAUNCH_LOG="$LAUNCH_LOG"
        export VLLM_LAUNCH_LOG
    fi
    exec > >(trap '' INT TERM HUP QUIT; exec tee -a "$LAUNCH_LOG") 2>&1
    echo "$INFERENCE_PROVIDER log: $LAUNCH_LOG_REL"
    echo "Full log path: $LAUNCH_LOG"

    echo ""
    echo "$MODEL_REPO $INFERENCE_PROVIDER Launcher"

    SERVER_PID=""
    SERVER_MONITOR_PID=""
    SERVER_PID_FILE=""
    SERVER_SHUTDOWN_STARTED=0
    SERVER_INTERRUPT_GRACE_SECONDS="${SERVER_INTERRUPT_GRACE_SECONDS:-10}"
    SERVER_TERMINATE_GRACE_SECONDS="${SERVER_TERMINATE_GRACE_SECONDS:-5}"

    trap 'handle_inference_signal INT 130' INT
    trap 'handle_inference_signal TERM 143' TERM
    trap 'handle_inference_signal HUP 129' HUP
    trap 'handle_inference_signal QUIT 131' QUIT
    trap 'handle_inference_exit "$?"' EXIT

    if ! is_valid_tensor_parallel_size "$TENSOR_PARALLEL_SIZE_VALUE"; then
        echo "Invalid tensor parallel size '$TENSOR_PARALLEL_SIZE_VALUE'. Use 1/2/4/8." >&2
        return 1
    fi
    if ! check_selected_gpu_processes; then
        return 1
    fi
    INFERENCE_PORT="$DEFAULT_PORT"
    if ! is_valid_port "$INFERENCE_PORT"; then
        echo "Invalid port '$INFERENCE_PORT'. Please provide a value between 1 and 65535." >&2
        return 1
    fi
    build_extra_args

    echo ""
    echo "============================================================"
    echo "Starting $INFERENCE_PROVIDER Server"
    echo "============================================================"
    echo "Model: $MODEL_REPO"
    echo "Model name: $MODEL_NAME"
    echo "Served as: $SERVED_MODEL_NAME"
    echo "Tensor parallel size: $TENSOR_PARALLEL_SIZE_VALUE"
    echo "Port: $INFERENCE_PORT"
    print_speculative_config
    echo ""

    if [ "$ENABLE_REASONING_PARSER" -eq 1 ] && [ ! -f "$REASONING_PARSER_PLUGIN" ]; then
        echo "Missing reasoning parser plugin: $REASONING_PARSER_PLUGIN"
        exit 1
    fi

    local base_command="$INFERENCE_ENV"
    base_command+=" $INFERENCE_LAUNCH"
    base_command+=" $MODEL_PATH"
    base_command+=" --served-model-name $SERVED_MODEL_NAME"
    base_command+=" $TRUST_REMOTE_CODE"
    base_command+=" $TENSOR_PARALLEL_SIZE_FLAG $TENSOR_PARALLEL_SIZE_VALUE"
    base_command+=" $REASONING_PARSER"
    if [ -n "$REASONING_PARSER_PLUGIN" ]; then
        base_command+=" --reasoning-parser-plugin $REASONING_PARSER_PLUGIN"
    fi
    base_command+=" $ENABLE_AUTO_TOOL_CHOICE"
    base_command+=" $TOOL_CALL_PARSER"
    base_command+=" $CONTEXT_LEN_FLAG"
    base_command+=" $GPU_MEM_UTIL_FLAG"
    base_command+=" $METRICS_FLAG"
    base_command+=" --host $HOST"
    base_command+=" --port $INFERENCE_PORT"
    base_command+=" $API_KEY"
    base_command+=" ${EXTRA_ARGS}"

    local -a base_command_args=()
    read -r -a base_command_args <<< "$base_command"

    printf 'Command: '
    if [ "${CUDA_VISIBLE_DEVICES+x}" = "x" ]; then
        printf 'CUDA_VISIBLE_DEVICES=%s ' "$CUDA_VISIBLE_DEVICES"
    fi
    printf '%s\n' "$base_command"
    echo ""
    echo "Press Ctrl+C to stop the server"
    echo "============================================================"
    echo ""

    launch_inference_server "${base_command_args[@]}"
}
