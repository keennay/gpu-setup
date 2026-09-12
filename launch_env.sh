#!/bin/bash

# Script: launch_env.sh
# Purpose: Activate ML environment with all optimizations
# Usage: source launch_env.sh [--auto] [ENV_NAME|1-114]

# Source bashrc to ensure environment is properly loaded
if [ -f "$HOME/.bashrc" ]; then
    # shellcheck source=/dev/null
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
        # shellcheck source=/dev/null
        source "$cuda_config"
    fi

    case "${CUDA_ENV_MODE:-bashrc}" in
        explicit)
            if ! cuda_home_is_valid "$CUDA_ENV_HOME"; then
                print_error "Selected CUDA toolkit is not available: $CUDA_ENV_HOME"
                print_error "Install CUDA first with ./02_install_cuda.sh or rerun 05_setup_env.sh to select another CUDA version."
                return 1
            fi
            export CUDA_HOME="${CUDA_ENV_HOME%/}"
            export CUDA_PATH="$CUDA_HOME"
            export ML_ENV_CUDA_SOURCE="environment selection"
            ;;
        bashrc|"")
            local default_cuda_home
            if ! default_cuda_home=$(detect_default_cuda_home); then
                print_error "No CUDA toolkit detected. Install CUDA first with ./02_install_cuda.sh."
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
        32|glm53flash_dflash2_sglang_pr_37818|glm53flash-dflash2-sglang-pr-37818)
            echo "glm53flash-dflash2-sglang-pr-37818"
            ;;
        33|glm53flash_dflash2_vllm_pr_55423|glm53flash-dflash2-vllm-pr-55423)
            echo "glm53flash-dflash2-vllm-pr-55423"
            ;;
        34|gptoss_sglang|gpt-oss_sglang|gptoss-sglang|gpt-oss-sglang)
            echo "gpt-oss-sglang"
            ;;
        35|gptoss_transformers|gpt-oss_transformers|gptoss-transformers|gpt-oss-transformers)
            echo "gpt-oss-transformers"
            ;;
        36|gptoss_vllm|gpt-oss_vllm|vllm_gptoss|gptoss-vllm|gpt-oss-vllm)
            echo "gpt-oss-vllm"
            ;;
        37|ibm_sglang|ibm-sglang)
            echo "ibm-sglang"
            ;;
        38|ibm_vllm|ibm-vllm)
            echo "ibm-vllm"
            ;;
        39|inclusionai_ling3_vllm|inclusionai-ling3-vllm)
            echo "inclusionai-ling3-vllm"
            ;;
        40|inclusionai_sglang|inclusionai-sglang)
            echo "inclusionai-sglang"
            ;;
        41|inclusionai_transformers|inclusionai-transformers)
            echo "inclusionai-transformers"
            ;;
        42|inclusionai_vllm|inclusionai-vllm)
            echo "inclusionai-vllm"
            ;;
        43|incoai_sglang|incoai-sglang)
            echo "incoai-sglang"
            ;;
        44|incoai_vllm|incoai-vllm)
            echo "incoai-vllm"
            ;;
        45|intel_sglang|intel-sglang)
            echo "intel-sglang"
            ;;
        46|intel_vllm|intel-vllm)
            echo "intel-vllm"
            ;;
        47|kimi_ktransformers|kimi-ktransformers)
            echo "kimi-ktransformers"
            ;;
        48|kimi_sglang|kimi-sglang)
            echo "kimi-sglang"
            ;;
        49|kimi_vllm|kimi-vllm)
            echo "kimi-vllm"
            ;;
        50|liquidai_sglang|liquidai-sglang)
            echo "liquidai-sglang"
            ;;
        51|liquidai_sglang_pr_31041|liquidai-sglang-pr-31041)
            echo "liquidai-sglang-pr-31041"
            ;;
        52|liquidai_transformers|liquidai-transformers)
            echo "liquidai-transformers"
            ;;
        53|liquidai_vllm|liquidai-vllm)
            echo "liquidai-vllm"
            ;;
        54|meta_sglang|meta-sglang)
            echo "meta-sglang"
            ;;
        55|meta_vllm|meta-vllm)
            echo "meta-vllm"
            ;;
        56|microsoft_sglang|microsoft-sglang)
            echo "microsoft-sglang"
            ;;
        57|microsoft_vllm|microsoft-vllm)
            echo "microsoft-vllm"
            ;;
        58|minimax_ktransformers|minimax-ktransformers)
            echo "minimax-ktransformers"
            ;;
        59|minimax_m2_sglang_v0510_post1|minimax-m2-sglang-v0510-post1)
            echo "minimax-m2-sglang-v0510-post1"
            ;;
        60|minimax_m2_vllm_0f3ce4c74|minimax-m2-vllm-0f3ce4c74)
            echo "minimax-m2-vllm-0f3ce4c74"
            ;;
        61|minimax_m25_vllm_v0280|minimax-m25-vllm-v0280)
            echo "minimax-m25-vllm-v0280"
            ;;
        62|minimax_sglang|minimax-sglang)
            echo "minimax-sglang"
            ;;
        63|minimax_transformers|minimax-transformers)
            echo "minimax-transformers"
            ;;
        64|minimax_vllm|minimax-vllm)
            echo "minimax-vllm"
            ;;
        65|mistralai_sglang|mistralai-sglang)
            echo "mistralai-sglang"
            ;;
        66|mistralai_transformers|mistralai-transformers)
            echo "mistralai-transformers"
            ;;
        67|mistralai_vllm|mistralai-vllm)
            echo "mistralai-vllm"
            ;;
        68|nanbeige_sglang|nanbeige-sglang)
            echo "nanbeige-sglang"
            ;;
        69|nanbeige_transformers|nanbeige-transformers)
            echo "nanbeige-transformers"
            ;;
        70|nanbeige_vllm|nanbeige-vllm)
            echo "nanbeige-vllm"
            ;;
        71|nemotron_trtllm|nemotron-trtllm|nemotron_trt_llm|nemotron-trt-llm)
            echo "nemotron-trtllm"
            ;;
        72|nemotron_ultra_vllm_9c2d21046|nemotron-ultra-vllm-9c2d21046)
            echo "nemotron-ultra-vllm-9c2d21046"
            ;;
        73|nex_n2_sglang_v0519|nex-n2-sglang-v0519)
            echo "nex-n2-sglang-v0519"
            ;;
        74|nex_n2_vllm_v0290|nex-n2-vllm-v0290)
            echo "nex-n2-vllm-v0290"
            ;;
        75|nvidia_deepseek_sglang|nvidia-deepseek-sglang)
            echo "nvidia-deepseek-sglang"
            ;;
        76|nvidia_nemotron|nvidia-nemotron)
            echo "nvidia-nemotron"
            ;;
        77|nvidia_sglang|nvidia-sglang)
            echo "nvidia-sglang"
            ;;
        78|nvidia_sglang_pr_33554|nvidia-sglang-pr-33554)
            echo "nvidia-sglang-pr-33554"
            ;;
        79|nvidia_sglang_pr_34966|nvidia-sglang-pr-34966)
            echo "nvidia-sglang-pr-34966"
            ;;
        80|nvidia_vllm|nvidia-vllm)
            echo "nvidia-vllm"
            ;;
        81|poolside_laguna_xs_vllm|poolside-laguna-xs-vllm)
            echo "poolside-laguna-xs-vllm"
            ;;
        82|poolside_sglang|poolside-sglang)
            echo "poolside-sglang"
            ;;
        83|poolside_sglang_pr_22513|poolside-sglang-pr-22513)
            echo "poolside-sglang-pr-22513"
            ;;
        84|poolside_transformers|poolside-transformers)
            echo "poolside-transformers"
            ;;
        85|poolside_vllm|poolside-vllm)
            echo "poolside-vllm"
            ;;
        86|primeintellect_sglang|primeintellect-sglang)
            echo "primeintellect-sglang"
            ;;
        87|primeintellect_vllm|primeintellect-vllm)
            echo "primeintellect-vllm"
            ;;
        88|qwen_flash_next_sglang|qwen-flash-next-sglang)
            echo "qwen-flash-next-sglang"
            ;;
        89|qwen_flash_next_vllm|qwen-flash-next-vllm)
            echo "qwen-flash-next-vllm"
            ;;
        90|qwen_ktransformers|qwen-ktransformers)
            echo "qwen-ktransformers"
            ;;
        91|qwen_sglang|qwen-sglang)
            echo "qwen-sglang"
            ;;
        92|qwen_sglang_pr_22121|qwen-sglang-pr-22121)
            echo "qwen-sglang-pr-22121"
            ;;
        93|qwen_transformers|qwen-transformers)
            echo "qwen-transformers"
            ;;
        94|qwen_vllm|qwen-vllm)
            echo "qwen-vllm"
            ;;
        95|radixark_qwen_sglang|radixark-qwen-sglang)
            echo "radixark-qwen-sglang"
            ;;
        96|radixark_sglang|radixark-sglang)
            echo "radixark-sglang"
            ;;
        97|redhat_sglang_pr_35809|redhat-sglang-pr-35809)
            echo "redhat-sglang-pr-35809"
            ;;
        98|redhatai_sglang|redhatai-sglang)
            echo "redhatai-sglang"
            ;;
        99|redhatai_vllm|redhatai-vllm)
            echo "redhatai-vllm"
            ;;
        100|stepfun_sglang|stepfun-sglang)
            echo "stepfun-sglang"
            ;;
        101|stepfun_transformers|stepfun-transformers)
            echo "stepfun-transformers"
            ;;
        102|stepfun_vllm|stepfun-vllm)
            echo "stepfun-vllm"
            ;;
        103|z_lab_sglang|z-lab-sglang)
            echo "z-lab-sglang"
            ;;
        104|z_lab_sglang_pr_35209|z-lab-sglang-pr-35209)
            echo "z-lab-sglang-pr-35209"
            ;;
        105|z_lab_vllm|z-lab-vllm)
            echo "z-lab-vllm"
            ;;
        106|zyphra_legacy_sglang|zyphra-legacy-sglang)
            echo "zyphra-legacy-sglang"
            ;;
        107|zyphra_legacy_transformers|zyphra-legacy-transformers)
            echo "zyphra-legacy-transformers"
            ;;
        108|zyphra_legacy_vllm|zyphra-legacy-vllm)
            echo "zyphra-legacy-vllm"
            ;;
        109|zyphra_sglang|zyphra-sglang)
            echo "zyphra-sglang"
            ;;
        110|zyphra_sglang_pr_32517|zyphra-sglang-pr-32517)
            echo "zyphra-sglang-pr-32517"
            ;;
        111|zyphra_transformers|zyphra-transformers)
            echo "zyphra-transformers"
            ;;
        112|zyphra_vllm|zyphra-vllm)
            echo "zyphra-vllm"
            ;;
        113|custom|custom_uv|custom-uv|env_custom_uv)
            echo "custom_uv"
            ;;
        114|custom_pip|custom-pip|env_custom_pip)
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
    print_error "Use: source $0 [--auto] [ENV_NAME|1-114]"
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
    echo "32) GLM 5.3 Flash DFlash2 (SGLang) PR 37818"
    echo "33) GLM 5.3 Flash DFlash2 (vLLM) PR 55423"
    echo "34) GPT-OSS (SGLang)"
    echo "35) gpt-oss (Transformers)"
    echo "36) gpt-oss (vLLM)"
    echo "37) IBM (SGLang)"
    echo "38) IBM (vLLM)"
    echo "39) InclusionAI Ling 3 (vLLM)"
    echo "40) InclusionAI (SGLang)"
    echo "41) InclusionAI (Transformers)"
    echo "42) InclusionAI (vLLM)"
    echo "43) IncoAI (SGLang)"
    echo "44) IncoAI (vLLM)"
    echo "45) Intel (SGLang)"
    echo "46) Intel (vLLM)"
    echo "47) Kimi (KTransformers)"
    echo "48) Kimi (SGLang)"
    echo "49) Kimi (vLLM)"
    echo "50) LiquidAI (SGLang)"
    echo "51) LiquidAI (SGLang) PR 31041"
    echo "52) LiquidAI (Transformers)"
    echo "53) LiquidAI (vLLM)"
    echo "54) Meta (SGLang)"
    echo "55) Meta (vLLM)"
    echo "56) Microsoft (SGLang)"
    echo "57) Microsoft (vLLM)"
    echo "58) MiniMax (KTransformers)"
    echo "59) MiniMax M2 family (SGLang) 0.5.10.post1"
    echo "60) MiniMax M2 family (vLLM) 0f3ce4c74"
    echo "61) MiniMax M2.5 (vLLM) 0.28.0"
    echo "62) MiniMax (SGLang)"
    echo "63) MiniMax (Transformers)"
    echo "64) MiniMax (vLLM)"
    echo "65) MistralAI (SGLang)"
    echo "66) MistralAI (Transformers)"
    echo "67) MistralAI (vLLM)"
    echo "68) Nanbeige (SGLang)"
    echo "69) Nanbeige (Transformers)"
    echo "70) Nanbeige (vLLM)"
    echo "71) Nemotron (TRT-LLM)"
    echo "72) NVIDIA Nemotron Ultra (vLLM) PR54788 merge"
    echo "73) Nex N2 (SGLang) 0.5.19"
    echo "74) Nex N2 (vLLM) 0.29.0"
    echo "75) NVIDIA DeepSeek (SGLang)"
    echo "76) NVIDIA Nemotron (vLLM)"
    echo "77) NVIDIA (SGLang)"
    echo "78) NVIDIA (SGLang) PR 33554"
    echo "79) NVIDIA (SGLang) PR 34966"
    echo "80) NVIDIA (vLLM)"
    echo "81) Poolside Laguna XS (vLLM)"
    echo "82) Poolside (SGLang)"
    echo "83) Poolside (SGLang) PR 22513"
    echo "84) Poolside (Transformers)"
    echo "85) Poolside (vLLM)"
    echo "86) PrimeIntellect (SGLang)"
    echo "87) PrimeIntellect (vLLM)"
    echo "88) Qwen Flash Next (SGLang)"
    echo "89) Qwen Flash Next (vLLM)"
    echo "90) Qwen (KTransformers)"
    echo "91) Qwen (SGLang)"
    echo "92) Qwen (SGLang) PR 22121"
    echo "93) Qwen (Transformers)"
    echo "94) Qwen (vLLM)"
    echo "95) RadixArk Qwen Flash Next (SGLang)"
    echo "96) RadixArk (SGLang)"
    echo "97) RedHat (SGLang) PR 35809"
    echo "98) RedHatAI (SGLang)"
    echo "99) RedHatAI (vLLM)"
    echo "100) StepFun (SGLang)"
    echo "101) StepFun (Transformers)"
    echo "102) StepFun (vLLM)"
    echo "103) z-lab (SGLang)"
    echo "104) z-lab (SGLang) PR 35209"
    echo "105) z-lab (vLLM)"
    echo "106) Zyphra Legacy (SGLang)"
    echo "107) Zyphra Legacy (Transformers)"
    echo "108) Zyphra Legacy (vLLM)"
    echo "109) Zyphra (SGLang)"
    echo "110) Zyphra (SGLang) PR 32517"
    echo "111) Zyphra (Transformers)"
    echo "112) Zyphra (vLLM)"
    echo "113) Custom (uv)"
    echo "114) Custom (pip)"
    echo ""
    while true; do
        read -r -p "Enter your choice (1-114): " choice
        if ENV_TYPE=$(resolve_env_type "$choice"); then
            break
        else
            print_error "Invalid choice. Please enter a number between 1 and 114."
        fi
    done
elif [ -z "$ENV_TYPE" ]; then
    # Default to GLM (SGLang) in auto mode
    ENV_TYPE="glm_sglang"
fi

# Normalize and validate the selected managed environment.
if [ -n "$ENV_TYPE" ]; then
    if ! ENV_TYPE_MAPPED=$(resolve_env_type "$ENV_TYPE"); then
        print_error "Invalid environment selection: $ENV_TYPE. Choose a listed environment name or a number from 1 to 114."
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
    print_info "Run 05_setup_env.sh first to create it"
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
    # shellcheck source=/dev/null
    if ! source "$ENV_PATH/activate_ml"; then
        print_error "Failed to activate environment '$ENV_NAME' with $ENV_PATH/activate_ml"
        return 1
    fi
elif [ -f "$ENV_PATH/bin/activate" ]; then
    # Fallback to manual activation
    print_info "Activating $ENV_NAME environment..."
    # shellcheck source=/dev/null
    if ! source "$ENV_PATH/bin/activate"; then
        print_error "Failed to activate environment '$ENV_NAME' with $ENV_PATH/bin/activate"
        return 1
    fi
    
    # Determine HF_PATH - check if already set, otherwise use default
    if [ -n "$HF_HOME" ]; then
        HF_PATH="$HF_HOME"
    else
        HF_PATH="/workspace/models/huggingface"
    fi
    
    # Set ML environment variables
    export HF_HOME="$HF_PATH"
    export HF_HUB_CACHE="$HF_PATH/hub"

    # Detect GPU architecture
    print_info "Detecting GPU architecture..."
    TORCH_CUDA_ARCH_LIST=""
    
    if command -v nvidia-smi &> /dev/null; then
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | tr '[:lower:]' '[:upper:]')
        
        if [ -n "$GPU_NAME" ]; then
            print_info "Detected GPU: $GPU_NAME"
            
            # Determine architecture based on GPU model
            if [[ "$GPU_NAME" == *"V100"* ]]; then
                TORCH_CUDA_ARCH_LIST="7.0"
                print_info "  → $GPU_NAME (Volta) detected: sm_70"
                
            elif [[ "$GPU_NAME" == *"T4"* ]] || \
                 { [[ "$GPU_NAME" == *"RTX 5000"* ]] && [[ "$GPU_NAME" != *"ADA"* ]]; } || \
                 { [[ "$GPU_NAME" == *"RTX 4000"* ]] && [[ "$GPU_NAME" != *"ADA"* ]]; } || \
                 { [[ "$GPU_NAME" == *"RTX 6000"* ]] && [[ "$GPU_NAME" != *"ADA"* ]]; }; then
                TORCH_CUDA_ARCH_LIST="7.5"
                print_info "  → $GPU_NAME (Turing) detected: sm_75"
                
            elif [[ "$GPU_NAME" == *"A100"* ]] || [[ "$GPU_NAME" == *"A30"* ]]; then
                TORCH_CUDA_ARCH_LIST="8.0"
                print_info "  → $GPU_NAME (Ampere) detected: sm_80"
                
            elif [[ "$GPU_NAME" == *"RTX 3090"* ]] || [[ "$GPU_NAME" == *"3090"* ]] || \
                 [[ "$GPU_NAME" == *"RTX 3080"* ]] || [[ "$GPU_NAME" == *"3080"* ]] || \
                 [[ "$GPU_NAME" == *"RTX 3070"* ]] || [[ "$GPU_NAME" == *"3070"* ]] || \
                 [[ "$GPU_NAME" == *"RTX A6000"* ]] || [[ "$GPU_NAME" == *"A6000"* ]] || \
                 [[ "$GPU_NAME" == *"RTX A5000"* ]] || [[ "$GPU_NAME" == *"A5000"* ]] || \
                 [[ "$GPU_NAME" == *"RTX A4500"* ]] || [[ "$GPU_NAME" == *"A4500"* ]] || \
                 [[ "$GPU_NAME" == *"RTX A4000"* ]] || [[ "$GPU_NAME" == *"A4000"* ]] || \
                 [[ "$GPU_NAME" == *"RTX A2000"* ]] || [[ "$GPU_NAME" == *"A2000"* ]] || \
                 [[ "$GPU_NAME" == *"A10"* ]] || [[ "$GPU_NAME" == *"A40"* ]]; then
                TORCH_CUDA_ARCH_LIST="8.6"
                print_info "  → $GPU_NAME (Ampere) detected: sm_86"
                
            elif [[ "$GPU_NAME" == *"RTX 4090"* ]] || [[ "$GPU_NAME" == *"4090"* ]] || \
                 [[ "$GPU_NAME" == *"RTX 4070 TI"* ]] || [[ "$GPU_NAME" == *"4070 TI"* ]] || \
                 [[ "$GPU_NAME" == *"L40S"* ]] || [[ "$GPU_NAME" == *"L40"* ]] || [[ "$GPU_NAME" == *"L4"* ]] || \
                 { [[ "$GPU_NAME" == *"RTX 6000"* ]] && [[ "$GPU_NAME" == *"ADA"* ]]; } || \
                 { [[ "$GPU_NAME" == *"RTX 5000"* ]] && [[ "$GPU_NAME" == *"ADA"* ]]; } || \
                 { [[ "$GPU_NAME" == *"RTX 4000"* ]] && [[ "$GPU_NAME" == *"ADA"* ]]; }; then
                TORCH_CUDA_ARCH_LIST="8.9"
                print_info "  → $GPU_NAME (Ada Lovelace) detected: sm_89"
                
            elif [[ "$GPU_NAME" == *"H100"* ]] || [[ "$GPU_NAME" == *"H200"* ]] || [[ "$GPU_NAME" == *"GH200"* ]]; then
                TORCH_CUDA_ARCH_LIST="9.0"
                print_info "  → $GPU_NAME (Hopper) detected: sm_90"
                
            elif [[ "$GPU_NAME" == *"B200"* ]]; then
                TORCH_CUDA_ARCH_LIST="10.0"
                print_info "  → $GPU_NAME (Blackwell) detected: sm_100"
            
            elif [[ "$GPU_NAME" == *"RTX 5090"* ]] || [[ "$GPU_NAME" == *"5090"* ]] || \
                 { [[ "$GPU_NAME" == *"RTX PRO 6000"* ]] && [[ "$GPU_NAME" == *"BLACKWELL"* ]]; }; then
                TORCH_CUDA_ARCH_LIST="12.0"
                print_info "  → $GPU_NAME (Blackwell) detected: sm_120"
                
            else
                print_warning "  → Unknown GPU model, will use default PyTorch CUDA architectures"
            fi
            
            if [ -n "$TORCH_CUDA_ARCH_LIST" ]; then
                export TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST"
                print_info "  → Set TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST"
            fi
        else
            print_warning "Could not detect GPU name"
        fi
    else
        print_warning "nvidia-smi not found - no GPU detected"
    fi

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
    if [ -n "$TORCH_CUDA_ARCH_LIST" ]; then
        echo "  - TORCH_CUDA_ARCH_LIST: $TORCH_CUDA_ARCH_LIST"
    fi
    if [ -n "${ML_ENV_CUDA_HOME:-}" ]; then
        echo "  - CUDA toolkit: $ML_ENV_CUDA_HOME (${ML_ENV_CUDA_VERSION:-unknown}, ${ML_ENV_CUDA_SOURCE:-configured})"
    elif command -v nvcc &> /dev/null; then
        echo "  - CUDA: $(nvcc --version | grep release | awk '{print $6}')"
    fi
fi

echo ""
print_info "To deactivate: deactivate"
print_info "To install or configure environment packages: ./06_install_packages.sh"
