#!/usr/bin/env bash

# Shared inference recipe runtime; source after defining recipe configuration.
: "${RECIPE_DIR:?RECIPE_DIR must be set by the calling recipe}"
PYTHON_ENV="${PYTHON_ENV:-}"
INFERENCE_PROVIDER_NORMALIZED="${INFERENCE_PROVIDER,,}"
HELPER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$(cd -- "$HELPER_DIR/../.." && pwd -P)"
SETUP_ENV_SCRIPT="$SCRIPTS_DIR/installers/05_setup_env.sh"
PACKAGE_INSTALLER_SCRIPT="$SCRIPTS_DIR/installers/06_install_packages.sh"
INFERENCE_COMMAND=""
INFERENCE_EXECUTABLE=""

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


# Runtime argument state
DEFAULT_ENABLE_SPECULATIVE="$ENABLE_SPECULATIVE"
INTERACTIVE_MODE=0
POSITIONAL_ARGS=()
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
    LOG_DIR="$SCRIPTS_DIR/recipes/$CALLING_REPO/logs"
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

trap 'handle_inference_signal INT 130' INT
trap 'handle_inference_signal TERM 143' TERM
trap 'handle_inference_signal HUP 129' HUP
trap 'handle_inference_signal QUIT 131' QUIT
trap 'handle_inference_exit "$?"' EXIT

get_cuda_sm_version() {
    local visible_devices="${CUDA_VISIBLE_DEVICES:-}"

    if [ "${GPU_SELECTION_MODE:-}" = "custom" ]; then
        visible_devices="$CUDA_VISIBLE_DEVICES_VALUE"
    fi

    if [ -n "$visible_devices" ]; then
        CUDA_VISIBLE_DEVICES="$visible_devices" python3 - <<'PY' 2>/dev/null
import torch

if torch.cuda.is_available():
    major, minor = torch.cuda.get_device_capability(0)
    print(f"sm_{major}{minor}")
PY
    else
        python3 - <<'PY' 2>/dev/null
import torch

if torch.cuda.is_available():
    major, minor = torch.cuda.get_device_capability(0)
    print(f"sm_{major}{minor}")
PY
    fi
}

configure_moe_runner_backend() {
    local sm_version=""

    if [ -n "$BACKEND_MOE_RUNNER_SM90" ] ||
        [ -n "$BACKEND_MOE_RUNNER_SM100" ] ||
        [ -n "$BACKEND_MOE_RUNNER_SM103" ] ||
        [ -n "$BACKEND_MOE_RUNNER_SM120" ] ||
        [ -n "$BACKEND_MOE_RUNNER_SM121" ]; then
        sm_version="$(get_cuda_sm_version || true)"
    fi

    case "$sm_version" in
        sm_90)
            BACKEND_MOE_RUNNER="$BACKEND_MOE_RUNNER_SM90"
            ;;
        sm_100)
            BACKEND_MOE_RUNNER="$BACKEND_MOE_RUNNER_SM100"
            ;;
        sm_103)
            BACKEND_MOE_RUNNER="$BACKEND_MOE_RUNNER_SM103"
            ;;
        sm_120)
            BACKEND_MOE_RUNNER="$BACKEND_MOE_RUNNER_SM120"
            ;;
        sm_121)
            BACKEND_MOE_RUNNER="$BACKEND_MOE_RUNNER_SM121"
            ;;
        *)
            BACKEND_MOE_RUNNER="${BACKEND_MOE_RUNNER:-}"
            ;;
    esac

    export BACKEND_MOE_RUNNER
}

is_valid_tensor_parallel_size() {
    [[ "$1" =~ ^(1|2|4|8)$ ]]
}

is_valid_gpu_list() {
    [[ "$1" =~ ^[0-9]+(,[0-9]+)*$ ]]
}

count_gpus() {
    local list="$1"
    local IFS=,
    local gpu_array=()
    read -ra gpu_array <<< "$list"
    echo "${#gpu_array[@]}"
}

collect_selected_gpu_ids() {
    local requested_count="$TENSOR_PARALLEL_SIZE_VALUE"
    local visible_devices=""
    local candidate
    local index
    local -a candidates=()
    SELECTED_GPU_IDS=()

    if [ "$GPU_SELECTION_MODE" = "custom" ]; then
        visible_devices="$CUDA_VISIBLE_DEVICES_VALUE"
    elif [ "${CUDA_VISIBLE_DEVICES+x}" = "x" ]; then
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

parse_arguments() {
    ENABLE_SPECULATIVE="$DEFAULT_ENABLE_SPECULATIVE"
    ENABLE_CACHE_FLAG=0
    INTERACTIVE_MODE=0
    POSITIONAL_ARGS=()

    local arg
    for arg in "$@"; do
        case "$arg" in
            --interactive)
                INTERACTIVE_MODE=1
                ;;
            --speculative)
                ENABLE_SPECULATIVE=1
                ;;
            --cache)
                ENABLE_CACHE_FLAG=1
                ;;
            *)
                POSITIONAL_ARGS+=("$arg")
                ;;
        esac
    done
}

set_custom_gpus() {
    local gpu_list="$1"
    GPU_SELECTION_MODE="custom"
    CUDA_VISIBLE_DEVICES_VALUE="$gpu_list"
    TENSOR_PARALLEL_SIZE_VALUE="$(count_gpus "$gpu_list")"
}

build_extra_args() {
    local configured_extra_args="$EXTRA_ARGS"
    EXTRA_ARGS=""
    if [ -n "$configured_extra_args" ]; then
        EXTRA_ARGS+="$configured_extra_args "
    fi
    configure_moe_runner_backend

    if [ "$ENABLE_SPECULATIVE" -eq 1 ]; then
        EXTRA_ARGS+="$SPECULATIVE "
    fi
    EXTRA_ARGS+="$QUANTIZATION "
    if [ "$ENABLE_CACHE_FLAG" -eq 1 ]; then
        EXTRA_ARGS+="$NO_PREFIX_CACHE "
    fi
    if [ -n "$BACKEND_MOE_RUNNER" ]; then
        EXTRA_ARGS+="--moe-runner-backend ${BACKEND_MOE_RUNNER} "
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

get_tensor_parallel_size() {
    local arg_value="$1"
    GPU_SELECTION_MODE="tensor"

    if [ -n "$arg_value" ]; then
        if is_valid_tensor_parallel_size "$arg_value"; then
            TENSOR_PARALLEL_SIZE_VALUE="$arg_value"
            return
        elif [[ "$arg_value" =~ ^gpus?=(.*)$ ]]; then
            local gpu_list="${BASH_REMATCH[1]}"
            if is_valid_gpu_list "$gpu_list"; then
                set_custom_gpus "$gpu_list"
                return
            else
                echo "Invalid GPU list in argument '$arg_value'. Expected format gpus=0,1,2."
                exit 1
            fi
        elif [[ "$arg_value" == *","* ]] && is_valid_gpu_list "$arg_value"; then
            set_custom_gpus "$arg_value"
            return
        else
            echo "Invalid tensor parallel argument '$arg_value'. Use 1/2/4/8 or gpus=0,1."
            exit 1
        fi
    fi

    GPU_SELECTION_MODE="tensor"
    while true; do
        echo ""
        echo "============================================================"
        echo "Tensor Parallel Configuration"
        echo "============================================================"
        echo ""
        echo "Tensor parallel size determines how many GPUs to use:"
        echo "  1 = Single GPU"
        echo "  2 = 2 GPUs"
        echo "  4 = 4 GPUs"
        echo "  8 = 8 GPUs (default)"
        echo ""
        echo "Or type 'custom' (or provide a comma-separated list like 0,2,3) to set specific GPU IDs (overrides tensor parallel size)."
        echo ""

        read -r -p "Enter tensor parallel size (1/2/4/8) or 'custom' [default: ${DEFAULT_TENSOR_PARALLEL_SIZE}]: " size
        size="${size,,}"

        if [ -z "$size" ]; then
            TENSOR_PARALLEL_SIZE_VALUE="$DEFAULT_TENSOR_PARALLEL_SIZE"
            break
        elif is_valid_tensor_parallel_size "$size"; then
            TENSOR_PARALLEL_SIZE_VALUE="$size"
            break
        elif [[ "$size" == "custom" || "$size" == "c" ]]; then
            read -r -p "Enter GPU IDs to use (comma-separated, e.g., 0,2,3): " custom_list
            if is_valid_gpu_list "$custom_list"; then
                set_custom_gpus "$custom_list"
                break
            else
                echo "Invalid GPU list. Expected comma-separated integers (e.g., 0,1,3)."
            fi
        elif [[ "$size" == *","* ]] && is_valid_gpu_list "$size"; then
            set_custom_gpus "$size"
            break
        else
            echo "Invalid choice. Please enter 1, 2, 4, 8, or a comma-separated GPU list."
        fi
    done
}

get_port() {
    local arg_value="$1"

    if [ -n "$arg_value" ]; then
        if is_valid_port "$arg_value"; then
            INFERENCE_PORT="$arg_value"
            return
        else
            echo "Invalid port '$arg_value'. Please provide a value between 1 and 65535."
            exit 1
        fi
    fi

    while true; do
        echo ""
        echo "============================================================"
        echo "$INFERENCE_PROVIDER Server Port"
        echo "============================================================"
        echo ""

        read -r -p "Enter Inference Provider server port [default: ${DEFAULT_PORT}]: " port

        if [ -z "$port" ]; then
            INFERENCE_PORT="$DEFAULT_PORT"
            break
        elif is_valid_port "$port"; then
            INFERENCE_PORT="$port"
            break
        else
            echo "Invalid port. Please enter a number between 1 and 65535."
        fi
    done
}

run_inference_recipe() {
    parse_arguments "$@"
    local tensor_parallel_arg="${POSITIONAL_ARGS[0]:-}"
    local port_arg="${POSITIONAL_ARGS[1]:-}"

    if [ "$INTERACTIVE_MODE" -eq 0 ]; then
        tensor_parallel_arg="${tensor_parallel_arg:-$DEFAULT_TENSOR_PARALLEL_SIZE}"
        port_arg="${port_arg:-$DEFAULT_PORT}"
    fi
    get_tensor_parallel_size "$tensor_parallel_arg"
    if ! check_selected_gpu_processes; then
        return 1
    fi
    get_port "$port_arg"
    build_extra_args

    echo ""
    echo "============================================================"
    echo "Starting $INFERENCE_PROVIDER Server"
    echo "============================================================"
    echo "Model: $MODEL_REPO"
    echo "Model name: $MODEL_NAME"
    echo "Served as: $SERVED_MODEL_NAME"
    echo "Tensor parallel size: $TENSOR_PARALLEL_SIZE_VALUE"
    if [ "$GPU_SELECTION_MODE" = "custom" ]; then
        echo "GPU selection: CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES_VALUE"
    fi
    echo "Port: $INFERENCE_PORT"
    print_speculative_config
    if [ -n "$BACKEND_MOE_RUNNER" ]; then
        echo "MoE runner backend: $BACKEND_MOE_RUNNER"
    fi
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

    if [ "$GPU_SELECTION_MODE" = "custom" ]; then
        echo "Command: CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES_VALUE $base_command"
    else
        echo "Command: $base_command"
    fi
    echo ""
    echo "Press Ctrl+C to stop the server"
    echo "============================================================"
    echo ""

    if [ "$GPU_SELECTION_MODE" = "custom" ]; then
        launch_inference_server env "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES_VALUE" "${base_command_args[@]}"
    else
        launch_inference_server "${base_command_args[@]}"
    fi
}

