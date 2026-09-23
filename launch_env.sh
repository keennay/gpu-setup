#!/bin/bash

# Script: launch_env.sh
# Purpose: Activate ML environment with all optimizations
# Usage: source launch_env.sh [--auto] [ENV_NAME|1-126]

WORKSPACE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Source bashrc to ensure environment is properly loaded
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

prepend_env_path_once() {
    local var_name="$1"
    local dir="$2"
    local current="${!var_name:-}"

    [ -n "$dir" ] || return 0
    [ -d "$dir" ] || return 0
    case ":$current:" in
        *":$dir:"*) return 0 ;;
    esac

    if [ -n "$current" ]; then
        export "$var_name=$dir:$current"
    else
        export "$var_name=$dir"
    fi
}

cuda_home_is_valid() {
    local cuda_home="$1"

    [ -n "$cuda_home" ] || return 1
    cuda_home="${cuda_home%/}"
    [ -d "$cuda_home" ] || return 1
    [ -x "$cuda_home/bin/nvcc" ] || return 1
}

cuda_version_for_home() {
    local cuda_home="$1"

    cuda_home="${cuda_home%/}"
    if ! cuda_home_is_valid "$cuda_home"; then
        echo ""
        return 1
    fi

    "$cuda_home/bin/nvcc" --version 2>/dev/null | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1
}

detect_default_cuda_home() {
    local candidates=()
    local nvcc_path=""

    candidates+=("/usr/local/cuda")
    if [ -n "${CUDA_HOME:-}" ]; then
        candidates+=("$CUDA_HOME")
    fi
    if [ -n "${CUDA_PATH:-}" ]; then
        candidates+=("$CUDA_PATH")
    fi
    if nvcc_path=$(command -v nvcc 2>/dev/null); then
        candidates+=("$(cd -- "$(dirname -- "$nvcc_path")/.." && pwd)")
    fi

    local candidate
    local seen=":"
    for candidate in "${candidates[@]}"; do
        [ -n "$candidate" ] || continue
        candidate="${candidate%/}"
        case "$seen" in
            *":$candidate:"*) continue ;;
        esac
        seen+="$candidate:"

        if cuda_home_is_valid "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

apply_env_cuda_selection() {
    local cuda_config="$ENV_PATH/.cuda_env"
    CUDA_ENV_MODE="bashrc"
    CUDA_ENV_HOME=""

    if [ -f "$cuda_config" ]; then
        source "$cuda_config"
    fi

    case "${CUDA_ENV_MODE:-bashrc}" in
        explicit)
            if ! cuda_home_is_valid "$CUDA_ENV_HOME"; then
                print_error "Selected CUDA toolkit is not available: $CUDA_ENV_HOME"
                print_error "Install CUDA first with ./installers/02_install_cuda.sh or rerun ./installers/05_setup_env.sh to select another CUDA version."
                return 1
            fi
            export CUDA_HOME="${CUDA_ENV_HOME%/}"
            export CUDA_PATH="$CUDA_HOME"
            export ML_ENV_CUDA_SOURCE="environment selection"
            ;;
        bashrc|"")
            local default_cuda_home
            if ! default_cuda_home=$(detect_default_cuda_home); then
                print_error "No CUDA toolkit detected. Install CUDA first with ./installers/02_install_cuda.sh."
                return 1
            fi
            export CUDA_HOME="${default_cuda_home%/}"
            export CUDA_PATH="$CUDA_HOME"
            export CUDA_ENV_MODE="bashrc"
            export ML_ENV_CUDA_SOURCE="bashrc default"
            ;;
        *)
            print_error "Invalid CUDA_ENV_MODE in $cuda_config: $CUDA_ENV_MODE"
            return 1
            ;;
    esac

    prepend_env_path_once PATH "$CUDA_HOME/bin"
    prepend_env_path_once LD_LIBRARY_PATH "$CUDA_HOME/lib64"
    prepend_env_path_once LD_LIBRARY_PATH "$CUDA_HOME/lib"
    prepend_env_path_once LIBRARY_PATH "$CUDA_HOME/lib64"
    prepend_env_path_once LIBRARY_PATH "$CUDA_HOME/lib"
    if [ -d "$CUDA_HOME/include/cccl" ]; then
        prepend_env_path_once CPATH "$CUDA_HOME/include/cccl"
    fi

    export ML_ENV_CUDA_APPLIED=1
    export ML_ENV_CUDA_HOME="$CUDA_HOME"
    export ML_ENV_CUDA_VERSION
    ML_ENV_CUDA_VERSION=$(cuda_version_for_home "$CUDA_HOME")
    print_info "CUDA toolkit: $ML_ENV_CUDA_HOME (${ML_ENV_CUDA_VERSION:-unknown}, $ML_ENV_CUDA_SOURCE)"
}

resolve_env_type() {
    local input="${1#env_}"

    case "$input" in
        1|allenai_sglang|allenai-sglang)
            echo "allenai-sglang"
            ;;
        2|allenai_transformers|allenai-transformers)
            echo "allenai-transformers"
            ;;
        3|allenai_vllm|allenai-vllm)
            echo "allenai-vllm"
            ;;
        4|arcee_nvfp4_vllm|arcee-nvfp4-vllm)
            echo "arcee-nvfp4-vllm"
            ;;
        5|arcee_sglang|arcee-sglang)
            echo "arcee-sglang"
            ;;
        6|arcee_transformers|arcee-transformers)
            echo "arcee-transformers"
            ;;
        7|arcee_vllm|arcee-vllm)
            echo "arcee-vllm"
            ;;
        8|arcee_vllm_pr_54479|arcee-vllm-pr-54479)
            echo "arcee-vllm-pr-54479"
            ;;
        9|arcee_vllm_pr_54479_fp8_block|arcee-vllm-pr-54479-fp8-block)
            echo "arcee-vllm-pr-54479-fp8-block"
            ;;
        10|arcee_vllm_pr_54479_thinking_fp8_block|arcee-vllm-pr-54479-thinking-fp8-block)
            echo "arcee-vllm-pr-54479-thinking-fp8-block"
            ;;
        11|cohere_sglang|cohere-sglang)
            echo "cohere-sglang"
            ;;
        12|cohere_transformers|cohere-transformers)
            echo "cohere-transformers"
            ;;
        13|cohere_vllm|cohere-vllm)
            echo "cohere-vllm"
            ;;
        14|cohere_vllm_pr_54479|cohere-vllm-pr-54479)
            echo "cohere-vllm-pr-54479"
            ;;
        15|datalab_sglang|datalab-sglang)
            echo "datalab-sglang"
            ;;
        16|datalab_vllm|datalab-vllm)
            echo "datalab-vllm"
            ;;
        17|deepseek_ktransformers|deepseek-ktransformers)
            echo "deepseek-ktransformers"
            ;;
        18|deepseek_lmdeploy|deepseek-lmdeploy)
            echo "deepseek-lmdeploy"
            ;;
        19|deepseek_sglang|deepseek-sglang)
            echo "deepseek-sglang"
            ;;
        20|deepseek_v41_vllm_e77daef89|deepseek-v41-vllm-e77daef89)
            echo "deepseek-v41-vllm-e77daef89"
            ;;
        21|deepseek_vision_sglang_pr_37253|deepseek-vision-sglang-pr-37253)
            echo "deepseek-vision-sglang-pr-37253"
            ;;
        22|deepseek_vision_vllm_pr_54566|deepseek-vision-vllm-pr-54566)
            echo "deepseek-vision-vllm-pr-54566"
            ;;
        23|deepseek_vllm|deepseek-vllm)
            echo "deepseek-vllm"
            ;;
        24|diffusiongemma_sglang|diffusiongemma-sglang)
            echo "diffusiongemma-sglang"
            ;;
        25|gemma_sglang|gemma-sglang)
            echo "gemma-sglang"
            ;;
        26|gemma_vllm|gemma-vllm|gemma4_vllm|gemma4-vllm|gemma_4_vllm|gemma-4-vllm)
            echo "gemma-vllm"
            ;;
        27|gemma3n_vllm|gemma3n-vllm)
            echo "gemma3n-vllm"
            ;;
        28|glm_ktransformers|glm-ktransformers)
            echo "glm-ktransformers"
            ;;
        29|glm_sglang|glm-sglang)
            echo "glm-sglang"
            ;;
        30|glm_transformers|glm-transformers)
            echo "glm-transformers"
            ;;
        31|glm_vllm|glm-vllm)
            echo "glm-vllm"
            ;;
        32|glm53_vllm_v0290|glm53-vllm-v0290)
            echo "glm53-vllm-v0290"
            ;;
        33|glm53flash_dflash2_sglang_pr_37818|glm53flash-dflash2-sglang-pr-37818)
            echo "glm53flash-dflash2-sglang-pr-37818"
            ;;
        34|glm53flash_dflash2_vllm_pr_55423|glm53flash-dflash2-vllm-pr-55423)
            echo "glm53flash-dflash2-vllm-pr-55423"
            ;;
        35|glm53flash_vllm_pr_53906|glm53flash-vllm-pr-53906)
            echo "glm53flash-vllm-pr-53906"
            ;;
        36|gptoss_sglang|gpt-oss_sglang|gptoss-sglang|gpt-oss-sglang)
            echo "gpt-oss-sglang"
            ;;
        37|gptoss_transformers|gpt-oss_transformers|gptoss-transformers|gpt-oss-transformers)
            echo "gpt-oss-transformers"
            ;;
        38|gptoss_vllm|gpt-oss_vllm|vllm_gptoss|gptoss-vllm|gpt-oss-vllm)
            echo "gpt-oss-vllm"
            ;;
        39|ibm_sglang|ibm-sglang)
            echo "ibm-sglang"
            ;;
        40|ibm_vllm|ibm-vllm)
            echo "ibm-vllm"
            ;;
        41|inclusionai_ling3_vllm|inclusionai-ling3-vllm)
            echo "inclusionai-ling3-vllm"
            ;;
        42|inclusionai_sglang|inclusionai-sglang)
            echo "inclusionai-sglang"
            ;;
        43|inclusionai_transformers|inclusionai-transformers)
            echo "inclusionai-transformers"
            ;;
        44|inclusionai_vllm|inclusionai-vllm)
            echo "inclusionai-vllm"
            ;;
        45|incoai_sglang|incoai-sglang)
            echo "incoai-sglang"
            ;;
        46|incoai_vllm|incoai-vllm)
            echo "incoai-vllm"
            ;;
        47|intel_sglang|intel-sglang)
            echo "intel-sglang"
            ;;
        48|intel_vllm|intel-vllm)
            echo "intel-vllm"
            ;;
        49|kimi_ktransformers|kimi-ktransformers)
            echo "kimi-ktransformers"
            ;;
        50|kimi_sglang|kimi-sglang)
            echo "kimi-sglang"
            ;;
        51|kimi_vllm|kimi-vllm)
            echo "kimi-vllm"
            ;;
        52|liquidai_sglang|liquidai-sglang)
            echo "liquidai-sglang"
            ;;
        53|liquidai_sglang_pr_31041|liquidai-sglang-pr-31041)
            echo "liquidai-sglang-pr-31041"
            ;;
        54|liquidai_transformers|liquidai-transformers)
            echo "liquidai-transformers"
            ;;
        55|liquidai_vllm|liquidai-vllm)
            echo "liquidai-vllm"
            ;;
        56|meta_sglang|meta-sglang)
            echo "meta-sglang"
            ;;
        57|meta_vllm|meta-vllm)
            echo "meta-vllm"
            ;;
        58|microsoft_sglang|microsoft-sglang)
            echo "microsoft-sglang"
            ;;
        59|microsoft_vllm|microsoft-vllm)
            echo "microsoft-vllm"
            ;;
        60|minimax_ktransformers|minimax-ktransformers)
            echo "minimax-ktransformers"
            ;;
        61|minimax_m2_sglang_v0510_post1|minimax-m2-sglang-v0510-post1)
            echo "minimax-m2-sglang-v0510-post1"
            ;;
        62|minimax_m2_vllm_0f3ce4c74|minimax-m2-vllm-0f3ce4c74)
            echo "minimax-m2-vllm-0f3ce4c74"
            ;;
        63|minimax_m25_vllm_v0280|minimax-m25-vllm-v0280)
            echo "minimax-m25-vllm-v0280"
            ;;
        64|minimax_sglang|minimax-sglang)
            echo "minimax-sglang"
            ;;
        65|minimax_transformers|minimax-transformers)
            echo "minimax-transformers"
            ;;
        66|minimax_vllm|minimax-vllm)
            echo "minimax-vllm"
            ;;
        67|mistralai_sglang|mistralai-sglang)
            echo "mistralai-sglang"
            ;;
        68|mistralai_transformers|mistralai-transformers)
            echo "mistralai-transformers"
            ;;
        69|mistralai_vllm|mistralai-vllm)
            echo "mistralai-vllm"
            ;;
        70|nanbeige_sglang|nanbeige-sglang)
            echo "nanbeige-sglang"
            ;;
        71|nanbeige_transformers|nanbeige-transformers)
            echo "nanbeige-transformers"
            ;;
        72|nanbeige_vllm|nanbeige-vllm)
            echo "nanbeige-vllm"
            ;;
        73|nemotron_trtllm|nemotron-trtllm|nemotron_trt_llm|nemotron-trt-llm)
            echo "nemotron-trtllm"
            ;;
        74|nemotron_ultra_vllm_9c2d21046|nemotron-ultra-vllm-9c2d21046)
            echo "nemotron-ultra-vllm-9c2d21046"
            ;;
        75|nex_n2_sglang_v0519|nex-n2-sglang-v0519)
            echo "nex-n2-sglang-v0519"
            ;;
        76|nex_n2_vllm_v0290|nex-n2-vllm-v0290)
            echo "nex-n2-vllm-v0290"
            ;;
        77|nvidia_deepseek_sglang|nvidia-deepseek-sglang)
            echo "nvidia-deepseek-sglang"
            ;;
        78|nvidia_muse_sglang_v0520|nvidia-muse-sglang-v0520)
            echo "nvidia-muse-sglang-v0520"
            ;;
        79|nvidia_muse_vllm_v0290|nvidia-muse-vllm-v0290)
            echo "nvidia-muse-vllm-v0290"
            ;;
        80|nvidia_nemotron|nvidia-nemotron)
            echo "nvidia-nemotron"
            ;;
        81|nvidia_sglang|nvidia-sglang)
            echo "nvidia-sglang"
            ;;
        82|nvidia_sglang_pr_33554|nvidia-sglang-pr-33554)
            echo "nvidia-sglang-pr-33554"
            ;;
        83|nvidia_sglang_pr_34966|nvidia-sglang-pr-34966)
            echo "nvidia-sglang-pr-34966"
            ;;
        84|nvidia_vllm|nvidia-vllm)
            echo "nvidia-vllm"
            ;;
        85|nvidia_vllm_pr_55222|nvidia-vllm-pr-55222)
            echo "nvidia-vllm-pr-55222"
            ;;
        86|openai_sglang_pr_38626|openai-sglang-pr-38626)
            echo "openai-sglang-pr-38626"
            ;;
        87|openai_vllm_pr_53207|openai-vllm-pr-53207)
            echo "openai-vllm-pr-53207"
            ;;
        88|paradigma_inc_vllm_v0260|paradigma-inc-vllm-v0260)
            echo "paradigma-inc-vllm-v0260"
            ;;
        89|poolside_laguna_xs_vllm|poolside-laguna-xs-vllm)
            echo "poolside-laguna-xs-vllm"
            ;;
        90|poolside_sglang|poolside-sglang)
            echo "poolside-sglang"
            ;;
        91|poolside_sglang_pr_22513|poolside-sglang-pr-22513)
            echo "poolside-sglang-pr-22513"
            ;;
        92|poolside_transformers|poolside-transformers)
            echo "poolside-transformers"
            ;;
        93|poolside_vllm|poolside-vllm)
            echo "poolside-vllm"
            ;;
        94|primeintellect_sglang|primeintellect-sglang)
            echo "primeintellect-sglang"
            ;;
        95|primeintellect_vllm|primeintellect-vllm)
            echo "primeintellect-vllm"
            ;;
        96|qwen_flash_next_sglang|qwen-flash-next-sglang)
            echo "qwen-flash-next-sglang"
            ;;
        97|qwen_flash_next_vllm|qwen-flash-next-vllm)
            echo "qwen-flash-next-vllm"
            ;;
        98|qwen_flash_next_vllm_pr_54129|qwen-flash-next-vllm-pr-54129)
            echo "qwen-flash-next-vllm-pr-54129"
            ;;
        99|qwen_ktransformers|qwen-ktransformers)
            echo "qwen-ktransformers"
            ;;
        100|qwen_sglang|qwen-sglang)
            echo "qwen-sglang"
            ;;
        101|qwen_sglang_pr_22121|qwen-sglang-pr-22121)
            echo "qwen-sglang-pr-22121"
            ;;
        102|qwen_transformers|qwen-transformers)
            echo "qwen-transformers"
            ;;
        103|qwen_vllm|qwen-vllm)
            echo "qwen-vllm"
            ;;
        104|radixark_qwen_sglang|radixark-qwen-sglang)
            echo "radixark-qwen-sglang"
            ;;
        105|radixark_sglang|radixark-sglang)
            echo "radixark-sglang"
            ;;
        106|redhat_sglang_pr_35809|redhat-sglang-pr-35809)
            echo "redhat-sglang-pr-35809"
            ;;
        107|redhatai_sglang|redhatai-sglang)
            echo "redhatai-sglang"
            ;;
        108|redhatai_vllm|redhatai-vllm)
            echo "redhatai-vllm"
            ;;
        109|stepfun_sglang|stepfun-sglang)
            echo "stepfun-sglang"
            ;;
        110|stepfun_transformers|stepfun-transformers)
            echo "stepfun-transformers"
            ;;
        111|stepfun_vllm|stepfun-vllm)
            echo "stepfun-vllm"
            ;;
        112|xiaomimimo_flash_vllm_1ea7c63|xiaomimimo-flash-vllm-1ea7c63)
            echo "xiaomimimo-flash-vllm-1ea7c63"
            ;;
        113|xiaomimimo_sglang_v0520|xiaomimimo-sglang-v0520)
            echo "xiaomimimo-sglang-v0520"
            ;;
        114|xiaomimimo_vllm_v0300|xiaomimimo-vllm-v0300)
            echo "xiaomimimo-vllm-v0300"
            ;;
        115|z_lab_sglang|z-lab-sglang)
            echo "z-lab-sglang"
            ;;
        116|z_lab_sglang_pr_35209|z-lab-sglang-pr-35209)
            echo "z-lab-sglang-pr-35209"
            ;;
        117|z_lab_vllm|z-lab-vllm)
            echo "z-lab-vllm"
            ;;
        118|zyphra_legacy_sglang|zyphra-legacy-sglang)
            echo "zyphra-legacy-sglang"
            ;;
        119|zyphra_legacy_transformers|zyphra-legacy-transformers)
            echo "zyphra-legacy-transformers"
            ;;
        120|zyphra_legacy_vllm|zyphra-legacy-vllm)
            echo "zyphra-legacy-vllm"
            ;;
        121|zyphra_sglang|zyphra-sglang)
            echo "zyphra-sglang"
            ;;
        122|zyphra_sglang_pr_32517|zyphra-sglang-pr-32517)
            echo "zyphra-sglang-pr-32517"
            ;;
        123|zyphra_transformers|zyphra-transformers)
            echo "zyphra-transformers"
            ;;
        124|zyphra_vllm|zyphra-vllm)
            echo "zyphra-vllm"
            ;;
        125|custom|custom_uv|custom-uv|env_custom_uv)
            echo "custom_uv"
            ;;
        126|custom_pip|custom-pip|env_custom_pip)
            echo "custom_pip"
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_env_name() {
    local env_type="$1"

    if [ -z "$env_type" ]; then
        echo "custom_uv"
        return 0
    fi

    echo "$env_type"
}

# This launcher mutates the caller's shell and therefore must be sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_error "This script must be sourced, not executed!"
    print_error "Use: source $0 [--auto] [ENV_NAME|1-120]"
    exit 1
fi

# Parse arguments
AUTO_MODE=false
ENV_TYPE=""

for arg in "$@"; do
    case $arg in
        --auto)
            AUTO_MODE=true
            ;;
        *)
            if [[ ! "$arg" =~ ^-- ]]; then
                ENV_TYPE="$arg"
            fi
            ;;
    esac
done

# Prompt for environment type if not provided and not in auto mode
if [ -z "$ENV_TYPE" ] && [ "$AUTO_MODE" = false ]; then
    echo ""
    print_info "Select ML environment type:"
    echo "1) AllenAI (SGLang)"
    echo "2) AllenAI (Transformers)"
    echo "3) AllenAI (vLLM)"
    echo "4) Arcee NVFP4 (vLLM)"
    echo "5) Arcee (SGLang)"
    echo "6) Arcee (Transformers)"
    echo "7) Arcee (vLLM)"
    echo "8) Arcee (vLLM) PR 54479"
    echo "9) Arcee FP8 Block (vLLM) PR 54479"
    echo "10) Arcee Thinking FP8 Block (vLLM) PR 54479"
    echo "11) Cohere (SGLang)"
    echo "12) Cohere (Transformers)"
    echo "13) Cohere (vLLM)"
    echo "14) Cohere (vLLM) PR 54479"
    echo "15) DataLab (SGLang)"
    echo "16) DataLab (vLLM)"
    echo "17) DeepSeek (KTransformers)"
    echo "18) DeepSeek (LMDeploy)"
    echo "19) DeepSeek (SGLang)"
    echo "20) DeepSeek V4.1 Flash (vLLM) e77daef89"
    echo "21) DeepSeek V4 Flash Vision Exp (SGLang) PR 37253"
    echo "22) DeepSeek V4 Flash Vision Exp (vLLM) PR 54566"
    echo "23) DeepSeek (vLLM)"
    echo "24) DiffusionGemma (SGLang)"
    echo "25) Gemma (SGLang)"
    echo "26) Gemma (vLLM)"
    echo "27) Gemma 3n (vLLM 0.10)"
    echo "28) GLM (KTransformers)"
    echo "29) GLM (SGLang)"
    echo "30) GLM (Transformers)"
    echo "31) GLM (vLLM)"
    echo "32) GLM 5.3 (vLLM 0.29.0)"
    echo "33) GLM 5.3 Flash DFlash2 (SGLang) PR 37818"
    echo "34) GLM 5.3 Flash DFlash2 (vLLM) PR 55423"
    echo "35) GLM 5.3 Flash (vLLM) PR 53906 merge"
    echo "36) GPT-OSS (SGLang)"
    echo "37) gpt-oss (Transformers)"
    echo "38) gpt-oss (vLLM)"
    echo "39) IBM (SGLang)"
    echo "40) IBM (vLLM)"
    echo "41) InclusionAI Ling 3 (vLLM)"
    echo "42) InclusionAI (SGLang)"
    echo "43) InclusionAI (Transformers)"
    echo "44) InclusionAI (vLLM)"
    echo "45) IncoAI (SGLang)"
    echo "46) IncoAI (vLLM)"
    echo "47) Intel (SGLang)"
    echo "48) Intel (vLLM)"
    echo "49) Kimi (KTransformers)"
    echo "50) Kimi (SGLang)"
    echo "51) Kimi (vLLM)"
    echo "52) LiquidAI (SGLang)"
    echo "53) LiquidAI (SGLang) PR 31041"
    echo "54) LiquidAI (Transformers)"
    echo "55) LiquidAI (vLLM)"
    echo "56) Meta (SGLang)"
    echo "57) Meta (vLLM)"
    echo "58) Microsoft (SGLang)"
    echo "59) Microsoft (vLLM)"
    echo "60) MiniMax (KTransformers)"
    echo "61) MiniMax M2 family (SGLang) 0.5.10.post1"
    echo "62) MiniMax M2 family (vLLM) 0f3ce4c74"
    echo "63) MiniMax M2.5 (vLLM) 0.28.0"
    echo "64) MiniMax (SGLang)"
    echo "65) MiniMax (Transformers)"
    echo "66) MiniMax (vLLM)"
    echo "67) MistralAI (SGLang)"
    echo "68) MistralAI (Transformers)"
    echo "69) MistralAI (vLLM)"
    echo "70) Nanbeige (SGLang)"
    echo "71) Nanbeige (Transformers)"
    echo "72) Nanbeige (vLLM)"
    echo "73) Nemotron (TRT-LLM)"
    echo "74) NVIDIA Nemotron Ultra (vLLM) PR54788 merge"
    echo "75) Nex N2 (SGLang) 0.5.19"
    echo "76) Nex N2 (vLLM) 0.29.0"
    echo "77) NVIDIA DeepSeek (SGLang)"
    echo "78) NVIDIA Muse Glimmer (SGLang) 0.5.20"
    echo "79) NVIDIA Muse Glimmer (vLLM) 0.29.0"
    echo "80) NVIDIA Nemotron (vLLM)"
    echo "81) NVIDIA (SGLang)"
    echo "82) NVIDIA (SGLang) PR 33554"
    echo "83) NVIDIA (SGLang) PR 34966"
    echo "84) NVIDIA (vLLM)"
    echo "85) NVIDIA GLM 5.3 Flash (vLLM) PR 55222"
    echo "86) OpenAI Whisper (SGLang) PR 38626"
    echo "87) OpenAI Whisper (vLLM) PR 53207"
    echo "88) Paradigma Limite (vLLM 0.26.0, official plugin)"
    echo "89) Poolside Laguna XS (vLLM)"
    echo "90) Poolside (SGLang)"
    echo "91) Poolside (SGLang) PR 22513"
    echo "92) Poolside (Transformers)"
    echo "93) Poolside (vLLM)"
    echo "94) PrimeIntellect (SGLang)"
    echo "95) PrimeIntellect (vLLM)"
    echo "96) Qwen Flash Next (SGLang)"
    echo "97) Qwen Flash Next (vLLM)"
    echo "98) Qwen Flash Next disk PLE (vLLM PR 54129)"
    echo "99) Qwen (KTransformers)"
    echo "100) Qwen (SGLang)"
    echo "101) Qwen (SGLang) PR 22121"
    echo "102) Qwen (Transformers)"
    echo "103) Qwen (vLLM)"
    echo "104) RadixArk Qwen Flash Next (SGLang)"
    echo "105) RadixArk (SGLang)"
    echo "106) RedHat (SGLang) PR 35809"
    echo "107) RedHatAI (SGLang)"
    echo "108) RedHatAI (vLLM)"
    echo "109) StepFun (SGLang)"
    echo "110) StepFun (Transformers)"
    echo "111) StepFun (vLLM)"
    echo "112) XiaomiMiMo Flash (vLLM 1ea7c63, audio)"
    echo "113) XiaomiMiMo Distill (SGLang 0.5.20)"
    echo "114) XiaomiMiMo Distill (vLLM 0.30.0)"
    echo "115) z-lab (SGLang)"
    echo "116) z-lab (SGLang) PR 35209"
    echo "117) z-lab (vLLM)"
    echo "118) Zyphra Legacy (SGLang)"
    echo "119) Zyphra Legacy (Transformers)"
    echo "120) Zyphra Legacy (vLLM)"
    echo "121) Zyphra (SGLang)"
    echo "122) Zyphra (SGLang) PR 32517"
    echo "123) Zyphra (Transformers)"
    echo "124) Zyphra (vLLM)"
    echo "125) Custom (uv)"
    echo "126) Custom (pip)"
    echo ""
    while true; do
        read -r -p "Enter your choice (1-126): " choice
        if ENV_TYPE=$(resolve_env_type "$choice"); then
            break
        else
            print_error "Invalid choice. Please enter a number between 1 and 126."
        fi
    done
elif [ -z "$ENV_TYPE" ]; then
    # Default to GLM (SGLang) in auto mode
    ENV_TYPE="glm_sglang"
fi

# Normalize and validate the selected managed environment.
if [ -n "$ENV_TYPE" ]; then
    if ! ENV_TYPE_MAPPED=$(resolve_env_type "$ENV_TYPE"); then
        print_error "Invalid environment selection: $ENV_TYPE. Choose a listed environment name or a number from 1 to 126."
        return 1
    fi
    ENV_TYPE="$ENV_TYPE_MAPPED"
fi

# Set environment name based on type
ENV_NAME=$(resolve_env_name "$ENV_TYPE")

ENV_PATH="$HOME/env_${ENV_NAME}"

# Check if environment exists
if [ ! -d "$ENV_PATH" ]; then
    print_error "Environment '$ENV_NAME' not found at $ENV_PATH"
    print_info "Run ./installers/05_setup_env.sh first to create it"
    return 1
fi

# Check if already in a virtual environment
if [ -n "$VIRTUAL_ENV" ]; then
    print_warning "Already in virtual environment: $VIRTUAL_ENV"
    if [ "$AUTO_MODE" = false ]; then
        read -r -p "Deactivate and switch to $ENV_NAME? (y/n): " SWITCH
    else
        SWITCH="y"
        print_info "Auto mode: switching environment"
    fi
    if [[ "$SWITCH" =~ ^[Yy]$ ]]; then
        deactivate
    else
        return 0
    fi
fi

# Check if activate_ml script exists, use it if available
if [ -f "$ENV_PATH/activate_ml" ]; then
    print_info "Using activate_ml script..."
    if ! source "$ENV_PATH/activate_ml"; then
        print_error "Failed to activate environment '$ENV_NAME' with $ENV_PATH/activate_ml"
        return 1
    fi
elif [ -f "$ENV_PATH/bin/activate" ]; then
    # Fallback to manual activation
    print_info "Activating $ENV_NAME environment..."
    if ! source "$ENV_PATH/bin/activate"; then
        print_error "Failed to activate environment '$ENV_NAME' with $ENV_PATH/bin/activate"
        return 1
    fi
    
    # Determine HF_PATH - check if already set, otherwise use default
    if [ -n "$HF_HOME" ]; then
        HF_PATH="$HF_HOME"
    else
        HF_PATH="$WORKSPACE_DIR/models/huggingface"
    fi
    
    # Set ML environment variables
    export HF_HOME="$HF_PATH"
    export HF_HUB_CACHE="$HF_PATH/hub"

else
    print_error "No activation script found for environment '$ENV_NAME'"
    print_info "Expected $ENV_PATH/activate_ml or $ENV_PATH/bin/activate"
    return 1
fi

if [ "${ML_ENV_CUDA_APPLIED:-}" != "1" ]; then
    if ! apply_env_cuda_selection; then
        return 1
    fi
fi

export DG_JIT_CACHE_DIR="${VIRTUAL_ENV:-$ENV_PATH}/.cache/deep_gemm"
export FLASHINFER_WORKSPACE_BASE="${VIRTUAL_ENV:-$ENV_PATH}"
export SGLANG_DG_CACHE_DIR="${VIRTUAL_ENV:-$ENV_PATH}/.cache/deep_gemm"
export TORCH_EXTENSIONS_DIR="${VIRTUAL_ENV:-$ENV_PATH}/.cache/torch_extensions"
export TORCH_HOME="${VIRTUAL_ENV:-$ENV_PATH}/.cache/torch"
export TORCHINDUCTOR_CACHE_DIR="${VIRTUAL_ENV:-$ENV_PATH}/.cache/torchinductor"
export TRITON_CACHE_DIR="${VIRTUAL_ENV:-$ENV_PATH}/.cache/triton"
export TRITON_HOME="${VIRTUAL_ENV:-$ENV_PATH}"
export TVM_FFI_CACHE_DIR="${VIRTUAL_ENV:-$ENV_PATH}/.cache/tvm-ffi"
export VLLM_CACHE_ROOT="${VIRTUAL_ENV:-$ENV_PATH}/.cache/vllm"
export XDG_CACHE_HOME="${VIRTUAL_ENV:-$ENV_PATH}/.cache"

# Display activation info if not using activate_ml script
if [ ! -f "$ENV_PATH/activate_ml" ]; then
    echo ""
    print_info "✓ ML environment activated!"
    echo "  - Virtual env: $ENV_PATH"
    echo "  - Python: $(which python) ($(python --version 2>&1))"
    echo "  - HF_HOME: $HF_HOME"
    echo "  - HF_HUB_CACHE: $HF_HUB_CACHE"
    echo "  - CPU threads: $OMP_NUM_THREADS"
    echo "  - TORCH_CUDA_ARCH_LIST: ${TORCH_CUDA_ARCH_LIST:-unset}"
    if [ -n "${ML_ENV_CUDA_HOME:-}" ]; then
        echo "  - CUDA toolkit: $ML_ENV_CUDA_HOME (${ML_ENV_CUDA_VERSION:-unknown}, ${ML_ENV_CUDA_SOURCE:-configured})"
    elif command -v nvcc &> /dev/null; then
        echo "  - CUDA: $(nvcc --version | grep release | awk '{print $6}')"
    fi
fi

echo ""
print_info "To deactivate: deactivate"
print_info "To install or configure environment packages: ./installers/06_install_packages.sh"
