#!/bin/bash

# Script: 06_install_packages.sh
# Purpose: Provide environment placeholders without installing packages.
# Usage: ./06_install_packages.sh [ENV_NAME]

if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_command() { echo -e "${BLUE}[RUN]${NC} $1"; }



ENV_TYPES=(
  "allenai-sglang"
  "allenai-transformers"
  "allenai-vllm"
  "arcee-nvfp4-vllm"
  "arcee-sglang"
  "arcee-transformers"
  "arcee-vllm"
  "cohere-sglang"
  "cohere-transformers"
  "cohere-vllm"
  "datalab-sglang"
  "datalab-vllm"
  "deepseek-ktransformers"
  "deepseek-lmdeploy"
  "deepseek-sglang"
  "deepseek-vllm"
  "diffusiongemma-sglang"
  "gemma-sglang"
  "gemma-vllm"
  "glm-ktransformers"
  "glm-sglang"
  "glm-transformers"
  "glm-vllm"
  "gpt-oss-sglang"
  "gpt-oss-transformers"
  "gpt-oss-vllm"
  "ibm-sglang"
  "ibm-vllm"
  "inclusionai-sglang"
  "inclusionai-transformers"
  "inclusionai-vllm"
  "incoai-sglang"
  "incoai-vllm"
  "intel-sglang"
  "intel-vllm"
  "kimi-ktransformers"
  "kimi-sglang"
  "kimi-vllm"
  "liquidai-sglang"
  "liquidai-sglang-pr-31041"
  "liquidai-transformers"
  "liquidai-vllm"
  "meta-sglang"
  "meta-vllm"
  "microsoft-sglang"
  "microsoft-vllm"
  "minimax-ktransformers"
  "minimax-sglang"
  "minimax-transformers"
  "minimax-vllm"
  "mistralai-sglang"
  "mistralai-transformers"
  "mistralai-vllm"
  "nanbeige-sglang"
  "nanbeige-transformers"
  "nanbeige-vllm"
  "nemotron-trtllm"
  "nvidia-deepseek-sglang"
  "nvidia-nemotron"
  "nvidia-sglang"
  "nvidia-sglang-pr-33554"
  "nvidia-sglang-pr-34966"
  "nvidia-vllm"
  "poolside-laguna-xs-vllm"
  "poolside-sglang"
  "poolside-sglang-pr-22513"
  "poolside-transformers"
  "poolside-vllm"
  "primeintellect-sglang"
  "primeintellect-vllm"
  "qwen-flash-next-sglang"
  "qwen-flash-next-vllm"
  "qwen-ktransformers"
  "qwen-sglang"
  "qwen-sglang-pr-22121"
  "qwen-transformers"
  "qwen-vllm"
  "radixark-qwen-sglang"
  "radixark-sglang"
  "redhatai-sglang"
  "redhat-sglang-pr-35809"
  "redhatai-vllm"
  "stepfun-sglang"
  "stepfun-transformers"
  "stepfun-vllm"
  "z-lab-sglang"
  "z-lab-sglang-pr-35209"
  "z-lab-vllm"
  "zyphra-legacy-sglang"
  "zyphra-legacy-transformers"
  "zyphra-legacy-vllm"
  "zyphra-sglang"
  "zyphra-sglang-pr-32517"
  "zyphra-transformers"
  "zyphra-vllm"
  "custom_uv"
  "custom_pip"
  "inclusionai-ling3-vllm"
  "gemma3n-vllm"
)

declare -A ENV_DESCRIPTIONS=(
  ["allenai-sglang"]="AllenAI (SGLang)"
  ["allenai-transformers"]="AllenAI (Transformers)"
  ["allenai-vllm"]="AllenAI (vLLM)"
  ["arcee-nvfp4-vllm"]="Arcee NVFP4 (vLLM)"
  ["arcee-sglang"]="Arcee (SGLang)"
  ["arcee-transformers"]="Arcee (Transformers)"
  ["arcee-vllm"]="Arcee (vLLM)"
  ["cohere-sglang"]="Cohere (SGLang)"
  ["cohere-transformers"]="Cohere (Transformers)"
  ["cohere-vllm"]="Cohere (vLLM)"
  ["datalab-sglang"]="DataLab (SGLang)"
  ["datalab-vllm"]="DataLab (vLLM)"
  ["deepseek-ktransformers"]="DeepSeek (KTransformers)"
  ["deepseek-lmdeploy"]="DeepSeek (LMDeploy)"
  ["deepseek-sglang"]="DeepSeek (SGLang)"
  ["deepseek-vllm"]="DeepSeek (vLLM)"
  ["diffusiongemma-sglang"]="DiffusionGemma (SGLang)"
  ["gemma-sglang"]="Gemma (SGLang)"
  ["gemma-vllm"]="Gemma (vLLM)"
  ["glm-ktransformers"]="GLM (KTransformers)"
  ["glm-sglang"]="GLM (SGLang)"
  ["glm-transformers"]="GLM (Transformers)"
  ["glm-vllm"]="GLM (vLLM)"
  ["gpt-oss-sglang"]="GPT-OSS (SGLang)"
  ["gpt-oss-transformers"]="gpt-oss (Transformers)"
  ["gpt-oss-vllm"]="gpt-oss (vLLM)"
  ["ibm-sglang"]="IBM (SGLang)"
  ["ibm-vllm"]="IBM (vLLM)"
  ["inclusionai-sglang"]="InclusionAI (SGLang)"
  ["inclusionai-transformers"]="InclusionAI (Transformers)"
  ["inclusionai-vllm"]="InclusionAI (vLLM)"
  ["inclusionai-ling3-vllm"]="InclusionAI Ling 3 (vLLM)"
  ["incoai-sglang"]="IncoAI (SGLang)"
  ["incoai-vllm"]="IncoAI (vLLM)"
  ["intel-sglang"]="Intel (SGLang)"
  ["intel-vllm"]="Intel (vLLM)"
  ["kimi-ktransformers"]="Kimi (KTransformers)"
  ["kimi-sglang"]="Kimi (SGLang)"
  ["kimi-vllm"]="Kimi (vLLM)"
  ["liquidai-sglang"]="LiquidAI (SGLang)"
  ["liquidai-sglang-pr-31041"]="LiquidAI (SGLang) PR 31041"
  ["liquidai-transformers"]="LiquidAI (Transformers)"
  ["liquidai-vllm"]="LiquidAI (vLLM)"
  ["meta-sglang"]="Meta (SGLang)"
  ["meta-vllm"]="Meta (vLLM)"
  ["microsoft-sglang"]="Microsoft (SGLang)"
  ["microsoft-vllm"]="Microsoft (vLLM)"
  ["minimax-ktransformers"]="MiniMax (KTransformers)"
  ["minimax-sglang"]="MiniMax (SGLang)"
  ["minimax-transformers"]="MiniMax (Transformers)"
  ["minimax-vllm"]="MiniMax (vLLM)"
  ["mistralai-sglang"]="MistralAI (SGLang)"
  ["mistralai-transformers"]="MistralAI (Transformers)"
  ["mistralai-vllm"]="MistralAI (vLLM)"
  ["nanbeige-sglang"]="Nanbeige (SGLang)"
  ["nanbeige-transformers"]="Nanbeige (Transformers)"
  ["nanbeige-vllm"]="Nanbeige (vLLM)"
  ["nemotron-trtllm"]="Nemotron (TRT-LLM)"
  ["nvidia-deepseek-sglang"]="NVIDIA DeepSeek (SGLang)"
  ["nvidia-nemotron"]="NVIDIA Nemotron (vLLM)"
  ["nvidia-sglang"]="NVIDIA (SGLang)"
  ["nvidia-sglang-pr-33554"]="NVIDIA (SGLang) PR 33554"
  ["nvidia-sglang-pr-34966"]="NVIDIA (SGLang) PR 34966"
  ["nvidia-vllm"]="NVIDIA (vLLM)"
  ["poolside-laguna-xs-vllm"]="Poolside Laguna XS (vLLM)"
  ["poolside-sglang"]="Poolside (SGLang)"
  ["poolside-sglang-pr-22513"]="Poolside (SGLang) PR 22513"
  ["poolside-transformers"]="Poolside (Transformers)"
  ["poolside-vllm"]="Poolside (vLLM)"
  ["primeintellect-sglang"]="PrimeIntellect (SGLang)"
  ["primeintellect-vllm"]="PrimeIntellect (vLLM)"
  ["qwen-flash-next-sglang"]="Qwen Flash Next (SGLang)"
  ["qwen-flash-next-vllm"]="Qwen Flash Next (vLLM)"
  ["qwen-ktransformers"]="Qwen (KTransformers)"
  ["qwen-sglang"]="Qwen (SGLang)"
  ["qwen-sglang-pr-22121"]="Qwen (SGLang) PR 22121"
  ["qwen-transformers"]="Qwen (Transformers)"
  ["qwen-vllm"]="Qwen (vLLM)"
  ["radixark-qwen-sglang"]="RadixArk Qwen Flash Next (SGLang)"
  ["radixark-sglang"]="RadixArk (SGLang)"
  ["redhatai-sglang"]="RedHatAI (SGLang)"
  ["redhat-sglang-pr-35809"]="RedHat (SGLang) PR 35809"
  ["redhatai-vllm"]="RedHatAI (vLLM)"
  ["stepfun-sglang"]="StepFun (SGLang)"
  ["stepfun-transformers"]="StepFun (Transformers)"
  ["stepfun-vllm"]="StepFun (vLLM)"
  ["z-lab-sglang"]="z-lab (SGLang)"
  ["z-lab-sglang-pr-35209"]="z-lab (SGLang) PR 35209"
  ["z-lab-vllm"]="z-lab (vLLM)"
  ["zyphra-legacy-sglang"]="Zyphra Legacy (SGLang)"
  ["zyphra-legacy-transformers"]="Zyphra Legacy (Transformers)"
  ["zyphra-legacy-vllm"]="Zyphra Legacy (vLLM)"
  ["zyphra-sglang"]="Zyphra (SGLang)"
  ["zyphra-sglang-pr-32517"]="Zyphra (SGLang) PR 32517"
  ["zyphra-transformers"]="Zyphra (Transformers)"
  ["zyphra-vllm"]="Zyphra (vLLM)"
  ["custom_uv"]="Custom (uv)"
  ["custom_pip"]="Custom (pip)"
  ["inclusionai-ling3-vllm"]="InclusionAI Ling 3 (vLLM)"
  ["gemma3n-vllm"]="Gemma 3n (vLLM 0.10)"
)

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
        8|cohere_sglang|cohere-sglang)
            echo "cohere-sglang"
            ;;
        9|cohere_transformers|cohere-transformers)
            echo "cohere-transformers"
            ;;
        10|cohere_vllm|cohere-vllm)
            echo "cohere-vllm"
            ;;
        11|datalab_sglang|datalab-sglang)
            echo "datalab-sglang"
            ;;
        12|datalab_vllm|datalab-vllm)
            echo "datalab-vllm"
            ;;
        13|deepseek_ktransformers|deepseek-ktransformers)
            echo "deepseek-ktransformers"
            ;;
        14|deepseek_lmdeploy|deepseek-lmdeploy)
            echo "deepseek-lmdeploy"
            ;;
        15|deepseek_sglang|deepseek-sglang)
            echo "deepseek-sglang"
            ;;
        16|deepseek_vllm|deepseek-vllm)
            echo "deepseek-vllm"
            ;;
        17|diffusiongemma_sglang|diffusiongemma-sglang)
            echo "diffusiongemma-sglang"
            ;;
        18|gemma_sglang|gemma-sglang)
            echo "gemma-sglang"
            ;;
        19|gemma_vllm|gemma-vllm|gemma4_vllm|gemma4-vllm|gemma_4_vllm|gemma-4-vllm)
            echo "gemma-vllm"
            ;;
        20|glm_ktransformers|glm-ktransformers)
            echo "glm-ktransformers"
            ;;
        21|glm_sglang|glm-sglang)
            echo "glm-sglang"
            ;;
        22|glm_transformers|glm-transformers)
            echo "glm-transformers"
            ;;
        23|glm_vllm|glm-vllm)
            echo "glm-vllm"
            ;;
        24|gptoss_sglang|gpt-oss_sglang|gptoss-sglang|gpt-oss-sglang)
            echo "gpt-oss-sglang"
            ;;
        25|gptoss_transformers|gpt-oss_transformers|gptoss-transformers|gpt-oss-transformers)
            echo "gpt-oss-transformers"
            ;;
        26|gptoss_vllm|gpt-oss_vllm|vllm_gptoss|gptoss-vllm|gpt-oss-vllm)
            echo "gpt-oss-vllm"
            ;;
        27|ibm_sglang|ibm-sglang)
            echo "ibm-sglang"
            ;;
        28|ibm_vllm|ibm-vllm)
            echo "ibm-vllm"
            ;;
        29|inclusionai_sglang|inclusionai-sglang)
            echo "inclusionai-sglang"
            ;;
        30|inclusionai_transformers|inclusionai-transformers)
            echo "inclusionai-transformers"
            ;;
        31|inclusionai_vllm|inclusionai-vllm)
            echo "inclusionai-vllm"
            ;;
        32|incoai_sglang|incoai-sglang)
            echo "incoai-sglang"
            ;;
        33|incoai_vllm|incoai-vllm)
            echo "incoai-vllm"
            ;;
        34|intel_sglang|intel-sglang)
            echo "intel-sglang"
            ;;
        35|intel_vllm|intel-vllm)
            echo "intel-vllm"
            ;;
        36|kimi_ktransformers|kimi-ktransformers)
            echo "kimi-ktransformers"
            ;;
        37|kimi_sglang|kimi-sglang)
            echo "kimi-sglang"
            ;;
        38|kimi_vllm|kimi-vllm)
            echo "kimi-vllm"
            ;;
        39|liquidai_sglang|liquidai-sglang)
            echo "liquidai-sglang"
            ;;
        40|liquidai_sglang_pr_31041|liquidai-sglang-pr-31041)
            echo "liquidai-sglang-pr-31041"
            ;;
        41|liquidai_transformers|liquidai-transformers)
            echo "liquidai-transformers"
            ;;
        42|liquidai_vllm|liquidai-vllm)
            echo "liquidai-vllm"
            ;;
        43|meta_sglang|meta-sglang)
            echo "meta-sglang"
            ;;
        44|meta_vllm|meta-vllm)
            echo "meta-vllm"
            ;;
        45|microsoft_sglang|microsoft-sglang)
            echo "microsoft-sglang"
            ;;
        46|microsoft_vllm|microsoft-vllm)
            echo "microsoft-vllm"
            ;;
        47|minimax_ktransformers|minimax-ktransformers)
            echo "minimax-ktransformers"
            ;;
        48|minimax_sglang|minimax-sglang)
            echo "minimax-sglang"
            ;;
        49|minimax_transformers|minimax-transformers)
            echo "minimax-transformers"
            ;;
        50|minimax_vllm|minimax-vllm)
            echo "minimax-vllm"
            ;;
        51|mistralai_sglang|mistralai-sglang)
            echo "mistralai-sglang"
            ;;
        52|mistralai_transformers|mistralai-transformers)
            echo "mistralai-transformers"
            ;;
        53|mistralai_vllm|mistralai-vllm)
            echo "mistralai-vllm"
            ;;
        54|nanbeige_sglang|nanbeige-sglang)
            echo "nanbeige-sglang"
            ;;
        55|nanbeige_transformers|nanbeige-transformers)
            echo "nanbeige-transformers"
            ;;
        56|nanbeige_vllm|nanbeige-vllm)
            echo "nanbeige-vllm"
            ;;
        57|nemotron_trtllm|nemotron-trtllm|nemotron_trt_llm|nemotron-trt-llm)
            echo "nemotron-trtllm"
            ;;
        58|nvidia_deepseek_sglang|nvidia-deepseek-sglang)
            echo "nvidia-deepseek-sglang"
            ;;
        59|nvidia_nemotron|nvidia-nemotron)
            echo "nvidia-nemotron"
            ;;
        60|nvidia_sglang|nvidia-sglang)
            echo "nvidia-sglang"
            ;;
        61|nvidia_sglang_pr_33554|nvidia-sglang-pr-33554)
            echo "nvidia-sglang-pr-33554"
            ;;
        62|nvidia_sglang_pr_34966|nvidia-sglang-pr-34966)
            echo "nvidia-sglang-pr-34966"
            ;;
        63|nvidia_vllm|nvidia-vllm)
            echo "nvidia-vllm"
            ;;
        64|poolside_laguna_xs_vllm|poolside-laguna-xs-vllm)
            echo "poolside-laguna-xs-vllm"
            ;;
        65|poolside_sglang|poolside-sglang)
            echo "poolside-sglang"
            ;;
        66|poolside_sglang_pr_22513|poolside-sglang-pr-22513)
            echo "poolside-sglang-pr-22513"
            ;;
        67|poolside_transformers|poolside-transformers)
            echo "poolside-transformers"
            ;;
        68|poolside_vllm|poolside-vllm)
            echo "poolside-vllm"
            ;;
        69|primeintellect_sglang|primeintellect-sglang)
            echo "primeintellect-sglang"
            ;;
        70|primeintellect_vllm|primeintellect-vllm)
            echo "primeintellect-vllm"
            ;;
        71|qwen_flash_next_sglang|qwen-flash-next-sglang)
            echo "qwen-flash-next-sglang"
            ;;
        72|qwen_flash_next_vllm|qwen-flash-next-vllm)
            echo "qwen-flash-next-vllm"
            ;;
        73|qwen_ktransformers|qwen-ktransformers)
            echo "qwen-ktransformers"
            ;;
        74|qwen_sglang|qwen-sglang)
            echo "qwen-sglang"
            ;;
        75|qwen_sglang_pr_22121|qwen-sglang-pr-22121)
            echo "qwen-sglang-pr-22121"
            ;;
        76|qwen_transformers|qwen-transformers)
            echo "qwen-transformers"
            ;;
        77|qwen_vllm|qwen-vllm)
            echo "qwen-vllm"
            ;;
        78|radixark_qwen_sglang|radixark-qwen-sglang)
            echo "radixark-qwen-sglang"
            ;;
        79|radixark_sglang|radixark-sglang)
            echo "radixark-sglang"
            ;;
        80|redhatai_sglang|redhatai-sglang)
            echo "redhatai-sglang"
            ;;
        81|redhat_sglang_pr_35809|redhat-sglang-pr-35809)
            echo "redhat-sglang-pr-35809"
            ;;
        82|redhatai_vllm|redhatai-vllm)
            echo "redhatai-vllm"
            ;;
        83|stepfun_sglang|stepfun-sglang)
            echo "stepfun-sglang"
            ;;
        84|stepfun_transformers|stepfun-transformers)
            echo "stepfun-transformers"
            ;;
        85|stepfun_vllm|stepfun-vllm)
            echo "stepfun-vllm"
            ;;
        86|z_lab_sglang|z-lab-sglang)
            echo "z-lab-sglang"
            ;;
        87|z_lab_sglang_pr_35209|z-lab-sglang-pr-35209)
            echo "z-lab-sglang-pr-35209"
            ;;
        88|z_lab_vllm|z-lab-vllm)
            echo "z-lab-vllm"
            ;;
        89|zyphra_legacy_sglang|zyphra-legacy-sglang)
            echo "zyphra-legacy-sglang"
            ;;
        90|zyphra_legacy_transformers|zyphra-legacy-transformers)
            echo "zyphra-legacy-transformers"
            ;;
        91|zyphra_legacy_vllm|zyphra-legacy-vllm)
            echo "zyphra-legacy-vllm"
            ;;
        92|zyphra_sglang|zyphra-sglang)
            echo "zyphra-sglang"
            ;;
        93|zyphra_sglang_pr_32517|zyphra-sglang-pr-32517)
            echo "zyphra-sglang-pr-32517"
            ;;
        94|zyphra_transformers|zyphra-transformers)
            echo "zyphra-transformers"
            ;;
        95|zyphra_vllm|zyphra-vllm)
            echo "zyphra-vllm"
            ;;
        96|custom|custom_uv|custom-uv|env_custom_uv)
            echo "custom_uv"
            ;;
        97|custom_pip|custom-pip|env_custom_pip)
            echo "custom_pip"
            ;;
        98|inclusionai_ling3_vllm|inclusionai-ling3-vllm)
            echo "inclusionai-ling3-vllm"
            ;;
        99|gemma3n_vllm|gemma3n-vllm)
            echo "gemma3n-vllm"
            ;;
        *)
            return 1
            ;;
    esac
}

print_env_options() {
    print_info "Available environments from 05_setup_env.sh:"
    local index=1
    for key in "${ENV_TYPES[@]}"; do
        printf "  %2d) %s (%s)\n" "$index" "${ENV_DESCRIPTIONS[$key]}" "$key"
        index=$((index + 1))
    done
}

normalize_env_name() {
    local raw="$1"
    raw="${raw%/}"
    raw=$(basename "$raw")
    raw="${raw#env_}"
    echo "$raw"
}

activate_environment_override() {
    local env_type="$1"
    local env_path="$HOME/env_${env_type}"
    local activate_script=""

    if [ ! -d "$env_path" ]; then
        print_error "Requested environment not found: $env_path"
        print_info "Create it first: ./05_setup_env.sh env_${env_type} --auto"
        return 1
    fi

    if [ ! -x "$env_path/bin/python" ]; then
        print_error "Requested environment has no working Python interpreter: $env_path/bin/python"
        print_info "Rebuild it with: ./05_setup_env.sh env_${env_type} --auto"
        return 1
    fi

    if [ -f "$env_path/activate_ml" ]; then
        activate_script="$env_path/activate_ml"
    elif [ -f "$env_path/bin/activate" ]; then
        activate_script="$env_path/bin/activate"
    else
        print_error "Requested environment has no activation script: $env_path"
        print_info "Rebuild it with: ./05_setup_env.sh env_${env_type} --auto"
        return 1
    fi

    print_info "Activating requested environment: $env_path"
    if ! source "$activate_script"; then
        print_error "Failed to activate requested environment: $env_path"
        return 1
    fi

    if [ "${VIRTUAL_ENV:-}" != "$env_path" ]; then
        print_error "Activation did not select the requested environment: $env_path"
        return 1
    fi
}

detect_environment() {
    local virtual_env="${VIRTUAL_ENV:-}"
    if [ -z "$virtual_env" ]; then
        return 1
    fi

    local base
    base=$(normalize_env_name "$virtual_env")

    if resolved=$(resolve_env_type "$base"); then
        echo "$resolved"
        return 0
    fi

    for key in "${ENV_TYPES[@]}"; do
        if [[ "$virtual_env" == *"/env_${key}"* ]] || [[ "$virtual_env" == *"/$key"* ]]; then
            echo "$key"
            return 0
        fi
    done

    return 1
}

ensure_active_environment_matches() {
    local expected="$1"

    if [ -z "${VIRTUAL_ENV:-}" ]; then
        print_error "No active virtual environment detected."
        print_info "Activate the environment first: source ./launch_env.sh $expected"
        return 1
    fi

    local active=""
    if active=$(detect_environment); then
        if [ "$active" != "$expected" ]; then
            print_error "Active virtual environment is '$active', but requested '$expected'."
            print_info "Activate the requested environment first: source ./launch_env.sh $expected"
            return 1
        fi
        return 0
    fi

    print_error "Active virtual environment '$VIRTUAL_ENV' is not managed by this script."
    print_info "Activate the requested environment first: source ./launch_env.sh $expected"
    return 1
}

handle_environment() {
    local env="$1"
    local desc="${ENV_DESCRIPTIONS[$env]}"

    if [ -z "$desc" ]; then
        desc="$env"
    fi

    print_info "Environment: $desc"
}

run_command() {
    local cmd=("$@")
    print_command "$(printf '%q ' "${cmd[@]}")"
    if "${cmd[@]}"; then
        return 0
    fi
    return 1
}

run_uv_install() {
    if ! command -v uv >/dev/null 2>&1; then
        print_error "uv is not available on PATH."
        return 1
    fi

    local cmd=(uv pip install)
    cmd+=("$@")

    if run_command "${cmd[@]}"; then
        print_info "Packages installed successfully."
        return 0
    fi

    print_error "Package installation failed."
    return 1
}

run_pip_install() {
    if [ -z "${VIRTUAL_ENV:-}" ]; then
        print_error "No active virtual environment detected for pip install."
        return 1
    fi

    local python_path
    python_path=$(command -v python 2>/dev/null || true)
    if [[ "$python_path" != "$VIRTUAL_ENV/bin/python" ]]; then
        print_error "Active python is not from VIRTUAL_ENV: ${python_path:-not found}"
        print_info "Activate the expected environment first with ./launch_env.sh."
        return 1
    fi

    local cmd=(python -m pip install)
    cmd+=("$@")

    if run_command "${cmd[@]}"; then
        print_info "Packages installed successfully."
        return 0
    fi

    print_error "Package installation failed."
    return 1
}

cuda_version_from_home() {
    local cuda_home="$1"
    [ -n "$cuda_home" ] || return 1
    cuda_home="${cuda_home%/}"
    [ -x "$cuda_home/bin/nvcc" ] || return 1

    "$cuda_home/bin/nvcc" --version 2>/dev/null | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1
}

detect_active_cuda_version() {
    if [ -n "${ML_ENV_CUDA_VERSION:-}" ]; then
        echo "$ML_ENV_CUDA_VERSION"
        return 0
    fi

    local cuda_version=""
    if cuda_version=$(cuda_version_from_home "${CUDA_HOME:-}"); then
        echo "$cuda_version"
        return 0
    fi

    if cuda_version=$(cuda_version_from_home "${CUDA_PATH:-}"); then
        echo "$cuda_version"
        return 0
    fi

    if command -v nvcc >/dev/null 2>&1; then
        nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1
        return 0
    fi

    python - <<'PY' 2>/dev/null
import sys
try:
    import torch
except Exception:
    sys.exit(1)
if torch.version.cuda:
    print(torch.version.cuda)
    sys.exit(0)
sys.exit(1)
PY
}

install_sglang_cuda_129_wheels() {
    print_info "CUDA 12.9 detected; installing CUDA 12.9 PyTorch and SGLang kernel wheels..."

    run_uv_install --force-reinstall \
        torch==2.11.0 \
        torchaudio==2.11.0 \
        torchvision \
        --index-url https://download.pytorch.org/whl/cu129 || return 1

    run_uv_install --force-reinstall \
        sglang-kernel \
        --index-url https://docs.sglang.ai/whl/cu129/ || return 1

    run_uv_install --force-reinstall \
        sgl-deep-gemm \
        --index-url https://docs.sglang.ai/whl/cu129/ \
        --no-deps || return 1
}

install_bleeding_edge_sglang() {
    local expected_env="$1"
    ensure_active_environment_matches "$expected_env" || return 1

    local target_dir=""
    if [ -n "${SGLANG_DIR:-}" ]; then
        target_dir="$SGLANG_DIR"
    else
        target_dir="$VIRTUAL_ENV/sglang"
    fi

    if [ -e "$target_dir" ] && [ ! -d "$target_dir/.git" ]; then
        print_error "SGLang target exists but is not a git checkout: $target_dir"
        return 1
    fi

    if [ ! -d "$target_dir/.git" ]; then
        local parent_dir
        parent_dir=$(dirname "$target_dir")
        if [ ! -d "$parent_dir" ]; then
            run_command mkdir -p "$parent_dir" || return 1
        fi
        run_command git clone https://github.com/sgl-project/sglang.git "$target_dir" || return 1
    fi

    run_command git -C "$target_dir" fetch origin main --tags || return 1
    run_command git -C "$target_dir" checkout main || return 1
    run_command git -C "$target_dir" pull --ff-only origin main || return 1

    run_uv_install -U --reinstall --prerelease=allow -e "$target_dir/python[all]" || return 1

    local cuda_version=""
    cuda_version=$(detect_active_cuda_version || true)
    if [ "$cuda_version" = "12.9" ]; then
        install_sglang_cuda_129_wheels || return 1
    elif [ -n "$cuda_version" ]; then
        print_info "CUDA $cuda_version detected; no extra CUDA 12.9 wheel reinstall needed."
    else
        print_warning "Could not detect active CUDA version; skipping CUDA 12.9-specific wheel reinstall."
    fi
}

install_pinned_sglang_commit() {
    local expected_env="$1"
    local description="$2"
    local repository="$3"
    local commit="$4"

    ensure_active_environment_matches "$expected_env" || return 1
    print_info "Installing $description..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+$repository@$commit#subdirectory=python" || return 1
}

install_allenai_sglang() {
    install_pinned_sglang_commit \
        "allenai-sglang" \
        "AllenAI (SGLang) commit cef8a32b9de616c85b515c099fecfd1a81bbf8d0" \
        "https://github.com/sgl-project/sglang.git" \
        "cef8a32b9de616c85b515c099fecfd1a81bbf8d0"
}

install_arcee_sglang() {
    install_pinned_sglang_commit \
        "arcee-sglang" \
        "Arcee (SGLang) commit cef8a32b9de616c85b515c099fecfd1a81bbf8d0" \
        "https://github.com/sgl-project/sglang.git" \
        "cef8a32b9de616c85b515c099fecfd1a81bbf8d0"
}

install_cohere_sglang() {
    install_pinned_sglang_commit \
        "cohere-sglang" \
        "Cohere (SGLang) commit dd15fb57b5ef7d13419f92ddc9b241591b71c0b5" \
        "https://github.com/sgl-project/sglang.git" \
        "dd15fb57b5ef7d13419f92ddc9b241591b71c0b5"
}

install_datalab_sglang() {
    install_pinned_sglang_commit \
        "datalab-sglang" \
        "DataLab (SGLang) commit dd15fb57b5ef7d13419f92ddc9b241591b71c0b5" \
        "https://github.com/sgl-project/sglang.git" \
        "dd15fb57b5ef7d13419f92ddc9b241591b71c0b5"
}

install_microsoft_sglang() {
    install_pinned_sglang_commit \
        "microsoft-sglang" \
        "Microsoft (SGLang) commit dd15fb57b5ef7d13419f92ddc9b241591b71c0b5" \
        "https://github.com/sgl-project/sglang.git" \
        "dd15fb57b5ef7d13419f92ddc9b241591b71c0b5"
}

install_nvidia_deepseek_sglang() {
    print_info "Installing SGLang 0.5.16 for NVIDIA DeepSeek..."
    run_uv_install -U --prerelease=allow "sglang[all]==0.5.16" || return 1
}

install_nvidia_sglang() {
    install_pinned_sglang_commit \
        "nvidia-sglang" \
        "NVIDIA (SGLang) commit dd15fb57b5ef7d13419f92ddc9b241591b71c0b5" \
        "https://github.com/sgl-project/sglang.git" \
        "dd15fb57b5ef7d13419f92ddc9b241591b71c0b5" || return 1
    run_uv_install librosa || return 1
}

install_nvidia_sglang_pr_33554() {
    install_pinned_sglang_commit \
        "nvidia-sglang-pr-33554" \
        "NVIDIA (SGLang) PR 33554 commit ccfcdd93a8c21b21d37b6036f3071ff2d9171f9b" \
        "https://github.com/rystewart-nvidia/sglang.git" \
        "ccfcdd93a8c21b21d37b6036f3071ff2d9171f9b" || return 1
    run_uv_install librosa || return 1
}

install_nvidia_sglang_pr_34966() {
    install_pinned_sglang_commit \
        "nvidia-sglang-pr-34966" \
        "NVIDIA (SGLang) PR 34966 commit ef5d293e52375c75224ee9a5a373fe1daed56f84" \
        "https://github.com/mochgolf/sglang.git" \
        "ef5d293e52375c75224ee9a5a373fe1daed56f84"
}

install_poolside_sglang_pr_22513() {
    install_pinned_sglang_commit \
        "poolside-sglang-pr-22513" \
        "Poolside (SGLang) PR 22513 commit 693b32b73d5031bc82ec851659ae94bd02a2b5f6" \
        "https://github.com/Godmook/sglang.git" \
        "693b32b73d5031bc82ec851659ae94bd02a2b5f6"
}

install_primeintellect_sglang() {
    install_pinned_sglang_commit \
        "primeintellect-sglang" \
        "PrimeIntellect (SGLang) commit dd15fb57b5ef7d13419f92ddc9b241591b71c0b5" \
        "https://github.com/sgl-project/sglang.git" \
        "dd15fb57b5ef7d13419f92ddc9b241591b71c0b5"
}

install_qwen_sglang_pr_22121() {
    install_pinned_sglang_commit \
        "qwen-sglang-pr-22121" \
        "Qwen (SGLang) PR 22121 commit ce79bc7e3964613c87f79181353f09838d1c7459" \
        "https://github.com/Chevron7Locked/sglang.git" \
        "ce79bc7e3964613c87f79181353f09838d1c7459"
}

install_qwen_flash_next_sglang() {
    install_pinned_sglang_commit \
        "qwen-flash-next-sglang" \
        "Qwen Flash Next (SGLang) PR 36497 commit 73a255206f916366c8d26d4022f82ddfb0ab558d" \
        "https://github.com/sgl-project/sglang.git" \
        "73a255206f916366c8d26d4022f82ddfb0ab558d"
}

install_radixark_qwen_sglang() {
    install_pinned_sglang_commit \
        "radixark-qwen-sglang" \
        "RadixArk Qwen Flash Next (SGLang) PR 36497 commit 73a255206f916366c8d26d4022f82ddfb0ab558d" \
        "https://github.com/sgl-project/sglang.git" \
        "73a255206f916366c8d26d4022f82ddfb0ab558d" || return 1
    run_uv_install "transformers==5.12.1" "nvidia-modelopt[torch]==0.46.0" || return 1
}

install_radixark_sglang() {
    install_pinned_sglang_commit \
        "radixark-sglang" \
        "RadixArk (SGLang) PR 35292 commit 0c088029ccba502c6aa4c408cd516a706af5b253" \
        "https://github.com/alphabetc1/sglang.git" \
        "0c088029ccba502c6aa4c408cd516a706af5b253" || return 1
    run_uv_install "transformers==5.12.1" || return 1
}

install_redhatai_sglang() {
    install_pinned_sglang_commit \
        "redhatai-sglang" \
        "RedHatAI (SGLang) commit 05c584c44fb0450c894cf9d08a7827c10cd5b2c5" \
        "https://github.com/sgl-project/sglang.git" \
        "05c584c44fb0450c894cf9d08a7827c10cd5b2c5" || return 1
    run_uv_install "transformers==5.12.1" || return 1
}

install_redhat_sglang_pr_35809() {
    install_pinned_sglang_commit \
        "redhat-sglang-pr-35809" \
        "RedHat (SGLang) PR 35809 commit d5bd07850f6200eff1cf0529e5ba31de1fc3abff" \
        "https://github.com/fechaMe/sglang.git" \
        "d5bd07850f6200eff1cf0529e5ba31de1fc3abff" || return 1
    run_uv_install "transformers==5.12.1" || return 1
}

install_zyphra_legacy_sglang() {
    install_pinned_sglang_commit \
        "zyphra-legacy-sglang" \
        "Zyphra Legacy (SGLang) commit dd15fb57b5ef7d13419f92ddc9b241591b71c0b5" \
        "https://github.com/sgl-project/sglang.git" \
        "dd15fb57b5ef7d13419f92ddc9b241591b71c0b5"
}

install_zyphra_sglang() {
    install_pinned_sglang_commit \
        "zyphra-sglang" \
        "Zyphra (SGLang) commit 1cf2b8c54d81802abc15dcf23a29b9cc687bc01e" \
        "https://github.com/sgl-project/sglang.git" \
        "1cf2b8c54d81802abc15dcf23a29b9cc687bc01e"
}

install_zyphra_sglang_pr_32517() {
    install_pinned_sglang_commit \
        "zyphra-sglang-pr-32517" \
        "Zyphra (SGLang) PR 32517 commit a43c7793f95609db15cd1c4060de4e3424af171d" \
        "https://github.com/zaddle55/sglang.git" \
        "a43c7793f95609db15cd1c4060de4e3424af171d"
}

check_kt_kernel_build_dependencies() {
    local missing=()

    if ! command -v cmake >/dev/null 2>&1; then
        missing+=("cmake")
    fi
    if ! command -v pkg-config >/dev/null 2>&1; then
        missing+=("pkg-config")
    elif ! pkg-config --exists hwloc >/dev/null 2>&1; then
        missing+=("libhwloc-dev")
    fi

    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi

    print_error "Missing kt-kernel build dependencies: ${missing[*]}"
    print_info "Install them with your OS package manager, then rerun this script."
    print_info "On Debian/Ubuntu: sudo apt install -y cmake libhwloc-dev pkg-config"
    return 1
}

install_kt_kernel() {
    local ktransformers_dir="$1"
    local kt_kernel_dir="$ktransformers_dir/kt-kernel"

    if [ ! -d "$kt_kernel_dir" ]; then
        print_warning "kt-kernel directory not found at $kt_kernel_dir"
        return 1
    fi

    check_kt_kernel_build_dependencies || return 1
    run_command bash -c "cd \"$kt_kernel_dir\" && ./install.sh build"
}

install_flashinfer_python311_compatible() {
    local incompatible_package

    if ! python -c 'import sys; raise SystemExit(0 if sys.version_info < (3, 12) else 1)'; then
        return 0
    fi

    print_info "Installing FlashInfer 0.6.17 for Python 3.10/3.11 annotation compatibility..."
    run_uv_install --upgrade --no-deps "flashinfer-python==0.6.17" || return 1

    for incompatible_package in flashinfer-cubin flashinfer-jit-cache; do
        if python -c 'import importlib.metadata as m, sys; m.version(sys.argv[1])' \
            "$incompatible_package" >/dev/null 2>&1; then
            print_info "Removing incompatible $incompatible_package companion package..."
            run_command uv pip uninstall "$incompatible_package" || return 1
        fi
    done
}

install_vllm_pinned_commit_python311_compatible() {
    local source_commit="52be12cfac0c5a18ba906814b2d2bcadb40a9c4b"
    local source_dir=""

    if [ -z "${VIRTUAL_ENV:-}" ]; then
        print_error "No active virtual environment detected for the vLLM source checkout."
        return 1
    fi
    source_dir="$VIRTUAL_ENV/vllm"

    if [ -e "$source_dir" ] && [ ! -d "$source_dir/.git" ]; then
        print_error "vLLM target exists but is not a git checkout: $source_dir"
        return 1
    fi

    if [ ! -d "$source_dir/.git" ]; then
        run_command git clone https://github.com/vllm-project/vllm.git \
            "$source_dir" || return 1
    fi

    run_command git -C "$source_dir" fetch origin --tags || return 1
    run_command git -C "$source_dir" checkout --force "$source_commit" || return 1

    print_info "Installing pinned GitHub commit $source_commit from $source_dir..."
    VLLM_USE_PRECOMPILED=1 \
        VLLM_PRECOMPILED_WHEEL_COMMIT="$source_commit" \
        run_uv_install -U --reinstall --prerelease=allow \
        -e "$source_dir" --torch-backend=auto || return 1

    install_flashinfer_python311_compatible || return 1
}

install_allenai_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for AllenAI..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_arcee_deepgemm() {
    if [ -z "${VIRTUAL_ENV:-}" ]; then
        print_error "No active virtual environment detected for DeepGEMM install."
        return 1
    fi

    local vllm_ref="${1:-v0.18.0}"
    local deepgemm_installer="$VIRTUAL_ENV/install_deepgemm.sh"
    local deepgemm_installer_url="https://raw.githubusercontent.com/vllm-project/vllm/$vllm_ref/tools/install_deepgemm.sh"

    print_info "Downloading vLLM $vllm_ref DeepGEMM installer into $VIRTUAL_ENV..."
    run_command curl -fsSL "$deepgemm_installer_url" -o "$deepgemm_installer" || return 1
    run_command chmod +x "$deepgemm_installer" || return 1

    print_info "Installing vLLM $vllm_ref's pinned DeepGEMM build for Arcee..."
    run_command env VIRTUAL_ENV="$VIRTUAL_ENV" PATH="$VIRTUAL_ENV/bin:$PATH" \
        bash -c 'cd "$1" && bash "$2"' _ "$VIRTUAL_ENV" "$deepgemm_installer" || return 1
}

install_arcee_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for Arcee..."
    install_vllm_pinned_commit_python311_compatible || return 1
    install_arcee_deepgemm "52be12cfac0c5a18ba906814b2d2bcadb40a9c4b" || return 1
}

install_arcee_nvfp4_vllm() {
    print_info "Installing vLLM 0.18.0 for Arcee NVFP4..."
    run_uv_install -U "vllm==0.18.0" || return 1
    install_arcee_deepgemm "v0.18.0" || return 1
}

install_cohere_vllm() {
    print_info "Installing the pinned GitHub vLLM commit and Cohere Melody for Cohere..."
    install_vllm_pinned_commit_python311_compatible || return 1
    run_uv_install "transformers>=5,<6" || return 1
    run_uv_install "cohere_melody>=0.9.0" || return 1
}

install_datalab_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for DataLab..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_diffusiongemma_sglang() {
    print_info "Installing the DiffusionGemma SGLang commit..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@11ffa55479124f85aabeb6db264c3b337395a55d#subdirectory=python" || return 1
    run_uv_install --force-reinstall --no-deps "transformers==5.12.1" || return 1
}

install_gemma_sglang() {
    print_info "Installing the tested Gemma SGLang commit..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@f7d4e44d82ac35b9b10ce80348e4a5421f89435a#subdirectory=python" || return 1
    run_uv_install "git+https://github.com/huggingface/transformers.git@1423d22f7a3b62e8c70ad67b58ec25cd9b675897" || return 1
}

install_gemma_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for Gemma..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_glm_sglang() {
    print_info "Installing packages for GLM (SGLang)..."
    
    install_bleeding_edge_sglang glm-sglang || return 1
    run_uv_install "kernels==0.14.1"
}

install_glm_transformers() {
    print_info "Installing packages for GLM (Transformers)..."

    run_uv_install git+https://github.com/huggingface/transformers.git@76732b4e7120808ff989edbd16401f61fa6a0afa
}

install_glm_vllm() {
    print_info "Installing packages for GLM (vLLM)..."
    local packages=(
        "git+https://github.com/huggingface/transformers.git"
        "pre-commit>=4.2.0"
        "accelerate>=1.10.1"
    )

    run_uv_install -U vllm --index-url https://pypi.org/simple || return 1
    run_uv_install "${packages[@]}"
}

install_deepseek_lmdeploy() {
    print_info "Installing LMDeploy for DeepSeek..."
    local target_dir=""
    if [ -n "${LMDEPLOY_DIR:-}" ]; then
        target_dir="$LMDEPLOY_DIR"
    elif [ -n "${VIRTUAL_ENV:-}" ]; then
        target_dir="$VIRTUAL_ENV/lmdeploy"
    else
        target_dir="$HOME/lmdeploy"
    fi

    if [ -d "$target_dir/.git" ]; then
        print_info "Updating existing repository at $target_dir"
        run_command git -C "$target_dir" fetch origin || return 1
        run_command git -C "$target_dir" checkout support-dsv3 || return 1
        run_command git -C "$target_dir" pull --ff-only || return 1
    else
        local parent_dir
        parent_dir=$(dirname "$target_dir")
        if [ ! -d "$parent_dir" ]; then
            run_command mkdir -p "$parent_dir" || return 1
        fi
        run_command git clone -b support-dsv3 https://github.com/InternLM/lmdeploy.git "$target_dir" || return 1
    fi

    run_uv_install -e "$target_dir"
}

install_deepseek_ktransformers() {
    print_info "Installing KTransformers for DeepSeek..."
    ensure_active_environment_matches deepseek-ktransformers || return 1

    local ktransformers_dir=""
    if [ -n "${KTRANSFORMERS_DIR:-}" ]; then
        ktransformers_dir="$KTRANSFORMERS_DIR"
    elif [ -n "${VIRTUAL_ENV:-}" ]; then
        ktransformers_dir="$VIRTUAL_ENV/ktransformers"
    else
        ktransformers_dir="$HOME/ktransformers"
    fi

    if [ ! -d "$ktransformers_dir/.git" ]; then
        local parent_dir
        parent_dir=$(dirname "$ktransformers_dir")
        if [ ! -d "$parent_dir" ]; then
            run_command mkdir -p "$parent_dir" || return 1
        fi
        run_command git clone https://github.com/kvcache-ai/ktransformers.git "$ktransformers_dir" || return 1
    fi

    run_command git -C "$ktransformers_dir" submodule update --init --recursive || return 1

    install_kt_kernel "$ktransformers_dir" || return 1

    print_info "Installing SGLang for DeepSeek from ktransformers checkout..."

    if [ ! -x "$ktransformers_dir/install.sh" ]; then
        print_error "ktransformers installer not found or not executable at $ktransformers_dir/install.sh"
        return 1
    fi

    run_command bash -c "cd \"$ktransformers_dir\" && ./install.sh sglang --editable" || return 1
    run_pip_install "tilelang==0.1.8" || return 1
    run_pip_install "apache-tvm-ffi==0.1.9" || return 1
    run_pip_install --upgrade flashinfer-python flashinfer-cubin || return 1
    run_pip_install "transformers==4.57.1" || return 1

    print_info "Installing FlashMLA for DeepSeek V4 compressed attention..."
    local flash_mla_env=(
        env
        "NVCC_THREADS=${NVCC_THREADS:-8}"
    )

    local cuda_home="${CUDA_HOME:-${CUDA_PATH:-}}"
    if [ -z "$cuda_home" ] && command -v nvcc >/dev/null 2>&1; then
        cuda_home=$(cd -- "$(dirname -- "$(command -v nvcc)")/.." && pwd)
    fi

    if [ -z "$cuda_home" ] || [ ! -x "$cuda_home/bin/nvcc" ]; then
        print_error "No active CUDA toolkit with nvcc detected for FlashMLA."
        print_info "Activate an environment configured by 05_setup_env.sh/launch_env.sh with a CUDA toolkit selected."
        return 1
    fi

    flash_mla_env+=(
        "CUDA_HOME=$cuda_home"
        "CUDA_PATH=$cuda_home"
        "PATH=$cuda_home/bin:$PATH"
        "LD_LIBRARY_PATH=$cuda_home/lib:$cuda_home/lib64:${LD_LIBRARY_PATH:-}"
        "LIBRARY_PATH=$cuda_home/lib:$cuda_home/lib64:${LIBRARY_PATH:-}"
    )

    if [ -d "$cuda_home/include/cccl" ]; then
        flash_mla_env+=("CPATH=$cuda_home/include/cccl:${CPATH:-}")
    fi

    local gpu_name=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | tr '[:lower:]' '[:upper:]')
    fi
    if [[ "$gpu_name" != *"B200"* && "$gpu_name" != *"BLACKWELL"* ]]; then
        flash_mla_env+=("FLASH_MLA_DISABLE_SM100=1")
    fi

    run_command "${flash_mla_env[@]}" python -m pip install --no-build-isolation \
        'flash-mla @ git+https://github.com/deepseek-ai/FlashMLA.git@9241ae3ef9bac614dd25e45e507e089f888280e0' || return 1

    run_command python -c "import flash_mla; from flash_mla.flash_mla_interface import FlashMLASchedMeta; print('flash_mla import OK')" || return 1

    run_pip_install nvidia-cudnn-cu12==9.16.0.29 || return 1
}

install_deepseek_sglang() {
    print_info "Installing SGLang 0.5.16 for DeepSeek..."
    run_uv_install -U --prerelease=allow "sglang[all]==0.5.16" || return 1
}

install_deepseek_vllm() {
    print_info "Installing vLLM 0.25.0 for DeepSeek..."
    run_uv_install "vllm==0.25.0" || return 1
}

install_gptoss_sglang() {
    print_info "Installing the pinned SGLang main commit for GPT-OSS..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@834400705f2de2378a327121340f57e324ca5a36#subdirectory=python" || return 1
}

install_gptoss_transformers() {
    print_info "Installing Transformers stack for gpt-oss..."
    run_uv_install -U transformers accelerate torch triton==3.4 kernels
}

install_gptoss_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for GPT-OSS..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_ibm_sglang() {
    print_info "Installing SGLang 0.5.18 for IBM Granite..."
    run_uv_install -U --prerelease=allow "sglang[all]==0.5.18" || return 1
}

install_ibm_vllm() {
    print_info "Installing vLLM 0.25.0 for IBM Granite..."
    run_uv_install "vllm==0.25.0" || return 1
}

install_intel_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for Intel..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_kimi_ktransformers() {
    print_info "Installing KTransformers for Kimi..."

    local ktransformers_dir=""
    if [ -n "${KTRANSFORMERS_DIR:-}" ]; then
        ktransformers_dir="$KTRANSFORMERS_DIR"
    elif [ -n "${VIRTUAL_ENV:-}" ]; then
        ktransformers_dir="$VIRTUAL_ENV/ktransformers"
    else
        ktransformers_dir="$HOME/ktransformers"
    fi

    if [ ! -d "$ktransformers_dir/.git" ]; then
	local parent_dir
        parent_dir=$(dirname "$ktransformers_dir")
        if [ ! -d "$parent_dir" ]; then
            run_command mkdir -p "$parent_dir" || return 1
        fi
        run_command git clone https://github.com/kvcache-ai/ktransformers.git "$ktransformers_dir" || return 1
    fi

    run_command git -C "$ktransformers_dir" submodule update --init --recursive || return 1

    install_kt_kernel "$ktransformers_dir" || return 1

    print_info "Installing SGLang for Kimi..."

    local sglang_dir=""
    if [ -n "${SGLANG_DIR:-}" ]; then
        sglang_dir="$SGLANG_DIR"
    elif [ -n "${VIRTUAL_ENV:-}" ]; then
        sglang_dir="$VIRTUAL_ENV/sglang"
    else
        sglang_dir="$HOME/sglang"
    fi

    if [ ! -d "$sglang_dir/.git" ]; then
        local parent_dir
        parent_dir=$(dirname "$sglang_dir")
        if [ ! -d "$parent_dir" ]; then
            run_command mkdir -p "$parent_dir" || return 1
        fi
        run_command git clone https://github.com/kvcache-ai/sglang.git "$sglang_dir" || return 1
    fi

    run_pip_install -e "$sglang_dir/python[all]" || return 1
    run_pip_install nvidia-cudnn-cu12==9.16.0.29 || return 1
}
install_kimi_sglang() {
    print_info "Installing SGLang for Kimi..."
    install_bleeding_edge_sglang kimi-sglang || return 1
    run_uv_install remote_pdb
    run_uv_install imageio
    run_uv_install diffusers
    run_uv_install addict
    run_uv_install cache_dit
    run_uv_install nvidia-cudnn-cu12==9.16.0.29
}

install_kimi_vllm() {
    print_info "Installing vLLM for Kimi..."
    run_uv_install -U vllm --index-url https://pypi.org/simple || return 1
}

install_liquidai_sglang() {
    print_info "Installing the pinned SGLang main commit for LiquidAI..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@05c584c44fb0450c894cf9d08a7827c10cd5b2c5#subdirectory=python" || return 1
}

install_liquidai_sglang_pr_31041() {
    install_pinned_sglang_commit \
        "liquidai-sglang-pr-31041" \
        "LiquidAI (SGLang) PR 31041 commit c26ae043924fffe413df8a90329f8734869d7fd1" \
        "https://github.com/tugot17/sglang.git" \
        "c26ae043924fffe413df8a90329f8734869d7fd1"
}

install_liquidai_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for LiquidAI..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_inclusionai_sglang() {
    print_info "Installing the validated Ling 3.0 SGLang commit..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@e1a24a189fe4164596c3a6472e96715717df9012#subdirectory=python" || return 1
}

install_incoai_sglang() {
    install_pinned_sglang_commit \
        "incoai-sglang" \
        "IncoAI (SGLang) commit 05c584c44fb0450c894cf9d08a7827c10cd5b2c5" \
        "https://github.com/sgl-project/sglang.git" \
        "05c584c44fb0450c894cf9d08a7827c10cd5b2c5" || return 1
    run_uv_install "transformers==5.12.1" || return 1
}

install_inclusionai_transformers() {
    print_info "No package install configured for InclusionAI (Transformers) yet."
}

install_inclusionai_vllm() {
    local vllm_version="0.27.2rc1.dev113+g5cecfc013"
    local vllm_wheel="https://wheels.vllm.ai/5cecfc01375052698823fc401e31518fb32a981e/vllm-0.27.2rc1.dev113%2Bg5cecfc013-cp38-abi3-manylinux_2_28_x86_64.whl#sha256=7858cbbd1fbf426a6eac5a9e2dc3779e04ee63705f65c90ab5baca4705a4a638"

    print_info "Installing vLLM $vllm_version for InclusionAI from its immutable commit wheel..."
    run_uv_install --upgrade --reinstall --prerelease=allow \
        "$vllm_wheel" --torch-backend=auto || return 1
    install_flashinfer_python311_compatible || return 1
}

install_inclusionai_ling3_vllm() {
    local source_repo="https://github.com/inclusionAI/vllm-ling-v3.git"
    local source_commit="92c1041123ddd8b40ae6faf7eafabac71a4c0b34"
    local source_dir=""

    if [ -z "${VIRTUAL_ENV:-}" ]; then
        print_error "No active virtual environment detected for the InclusionAI Ling 3 vLLM checkout."
        return 1
    fi
    source_dir="$VIRTUAL_ENV/vllm-ling-v3"

    if [ -e "$source_dir" ] && [ ! -d "$source_dir/.git" ]; then
        print_error "InclusionAI Ling 3 vLLM target exists but is not a git checkout: $source_dir"
        return 1
    fi
    if [ ! -d "$source_dir/.git" ]; then
        run_command git clone "$source_repo" "$source_dir" || return 1
    fi

    run_command git -C "$source_dir" fetch origin "$source_commit" || return 1
    run_command git -C "$source_dir" checkout --force "$source_commit" || return 1
    print_info "Installing InclusionAI Ling 3 vLLM commit $source_commit from $source_dir..."
    VLLM_USE_PRECOMPILED=1 \
        run_uv_install -U --reinstall --prerelease=allow \
        -e "$source_dir" --torch-backend=auto || return 1
    install_flashinfer_python311_compatible || return 1
}

install_intel_sglang() {
    install_pinned_sglang_commit \
        "intel-sglang" \
        "Intel (SGLang) commit f7d4e44d82ac35b9b10ce80348e4a5421f89435a" \
        "https://github.com/sgl-project/sglang.git" \
        "f7d4e44d82ac35b9b10ce80348e4a5421f89435a" || return 1
    run_uv_install \
        "git+https://github.com/huggingface/transformers.git@1423d22f7a3b62e8c70ad67b58ec25cd9b675897" || return 1
}


install_meta_sglang() {
    print_info "Installing the pinned SGLang main commit for Meta..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@05c584c44fb0450c894cf9d08a7827c10cd5b2c5#subdirectory=python" || return 1
}

install_meta_vllm() {
    local vllm_version="0.27.2rc1.dev113+g5cecfc013"
    local vllm_wheel="https://wheels.vllm.ai/5cecfc01375052698823fc401e31518fb32a981e/vllm-0.27.2rc1.dev113%2Bg5cecfc013-cp38-abi3-manylinux_2_28_x86_64.whl#sha256=7858cbbd1fbf426a6eac5a9e2dc3779e04ee63705f65c90ab5baca4705a4a638"

    print_info "Installing vLLM $vllm_version for Meta from its immutable commit wheel..."
    ensure_active_environment_matches meta-vllm || return 1
    run_uv_install --upgrade --reinstall --prerelease=allow \
        "$vllm_wheel" --torch-backend=auto || return 1
    install_flashinfer_python311_compatible || return 1
    run_uv_install timm || return 1
}

install_microsoft_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for Microsoft..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_minimax_sglang() {
    print_info "Installing SGLang for MiniMax..."

    install_bleeding_edge_sglang minimax-sglang || return 1
}

install_minimax_transformers() {
    print_info "Installing Transformers for MiniMax..."
    run_uv_install "transformers==4.57.1" "torch" "accelerate" "--torch-backend=auto"
}

install_minimax_vllm() {
    print_info "Installing vLLM for MiniMax..."
    run_uv_install -U vllm --index-url https://pypi.org/simple || return 1
}

install_mistralai_sglang() {
    install_pinned_sglang_commit \
        "mistralai-sglang" \
        "MistralAI (SGLang) commit dd15fb57b5ef7d13419f92ddc9b241591b71c0b5" \
        "https://github.com/sgl-project/sglang.git" \
        "dd15fb57b5ef7d13419f92ddc9b241591b71c0b5"
}

install_mistralai_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for MistralAI..."
    install_vllm_pinned_commit_python311_compatible || return 1
}



install_nanbeige_sglang() {
    local source_commit="3e59d89e53490d3b6957cb72754abf6a98c2b8a8"
    print_info "Installing the pinned Nanbeige SGLang fork commit $source_commit..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/Nanbeige/sglang.git@${source_commit}#subdirectory=python" || return 1
}

install_nanbeige_vllm() {
    local source_commit="62f6de733d7ae63b759329993bc209e67afdf431"

    print_info "Installing the proven Nanbeige vLLM commit $source_commit..."
    ensure_active_environment_matches nanbeige-vllm || return 1

    local target_dir="$VIRTUAL_ENV/vllm"

    if [ -e "$target_dir" ] && [ ! -d "$target_dir/.git" ]; then
        print_error "vLLM target exists but is not a git checkout: $target_dir"
        return 1
    fi

    if [ ! -d "$target_dir/.git" ]; then
        run_command git clone -b nanbeige42 \
            https://github.com/Nanbeige/vllm.git "$target_dir" || return 1
    fi

    run_command git -C "$target_dir" fetch origin nanbeige42 --tags || return 1
    run_command git -C "$target_dir" checkout --force "$source_commit" || return 1

    run_pip_install -e "$target_dir" || return 1
}



install_nemotron_trtllm() {
    print_info "Installing TRT-LLM dependencies for Nemotron..."
    run_uv_install torch==2.9.1 openai==2.6.1 requests
}

install_nvidia_nemotron() {
    print_info "Installing the pinned GitHub vLLM commit for NVIDIA Nemotron..."
    install_vllm_pinned_commit_python311_compatible || return 1

    if [ -z "${VIRTUAL_ENV:-}" ]; then
        print_error "No active virtual environment detected for DeepGEMM install."
        return 1
    fi

    local deepgemm_installer="$VIRTUAL_ENV/install_deepgemm.sh"
    local deepgemm_installer_url="https://raw.githubusercontent.com/vllm-project/vllm/v0.20.0/tools/install_deepgemm.sh"

    print_info "Installing the proven vLLM 0.20.0 DeepGEMM companion build for NVIDIA Nemotron..."
    run_command curl -fsSL "$deepgemm_installer_url" -o "$deepgemm_installer" || return 1
    run_command env VIRTUAL_ENV="$VIRTUAL_ENV" PATH="$VIRTUAL_ENV/bin:$PATH" \
        bash "$deepgemm_installer" || return 1
}

install_nvidia_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for NVIDIA..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_poolside_sglang() {
    print_info "Installing the pinned SGLang main commit for Poolside..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@834400705f2de2378a327121340f57e324ca5a36#subdirectory=python" || return 1
}

install_poolside_laguna_xs_vllm() {
    print_info "Installing vLLM 0.26.0 for Poolside Laguna XS..."
    run_uv_install "vllm==0.26.0" || return 1
}

install_poolside_vllm() {
    print_info "Installing vLLM 0.27.1 for Poolside..."
    run_uv_install -U "vllm==0.27.1" || return 1
    install_flashinfer_python311_compatible || return 1
}

install_primeintellect_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for PrimeIntellect..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_qwen_ktransformers() {
    print_info "Installing KTransformers stack for Qwen..."
    ensure_active_environment_matches qwen-ktransformers || return 1

    run_pip_install --upgrade --force-reinstall \
        'torch==2.9.1' \
        'torchvision==0.24.1' \
        'torchaudio==2.9.1' \
        'sglang-kt==0.5.2.post2' \
        'tilelang' \
        'kt-kernel==0.5.2' || return 1

    run_pip_install --force-reinstall --no-deps 'nvidia-cudnn-cu12==9.16.0.29'
}

install_qwen_sglang() {
    print_info "Installing the validated Qwen DFlash2 SGLang commit..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@1cf2b8c54d81802abc15dcf23a29b9cc687bc01e#subdirectory=python" || return 1
}

install_qwen_transformers() {
    print_info "Installing Transformers stack for Qwen..."
    run_uv_install "transformers>=4.51.0" "torch>=2.6"
}

install_qwen_flash_next_vllm() {
    local source_commit="f561eca6ca4f3f79808a696b1521cb76dc8aafa2"

    ensure_active_environment_matches qwen-flash-next-vllm || return 1
    print_info "Installing vLLM PR 53899 commit $source_commit for Qwen Flash Next..."
    run_uv_install -U --reinstall --prerelease=allow \
        "vllm @ git+https://github.com/peakcrosser7/vllm.git@$source_commit" || return 1
    install_flashinfer_python311_compatible || return 1
}

install_qwen_vllm() {
    print_info "Installing the pinned GitHub vLLM commit for Qwen..."
    install_vllm_pinned_commit_python311_compatible || return 1
}

install_redhatai_vllm() {
    local vllm_version="0.27.2rc1.dev113+g5cecfc013"
    local vllm_wheel="https://wheels.vllm.ai/5cecfc01375052698823fc401e31518fb32a981e/vllm-0.27.2rc1.dev113%2Bg5cecfc013-cp38-abi3-manylinux_2_28_x86_64.whl#sha256=7858cbbd1fbf426a6eac5a9e2dc3779e04ee63705f65c90ab5baca4705a4a638"

    print_info "Installing vLLM $vllm_version for RedHatAI from its immutable commit wheel..."
    ensure_active_environment_matches redhatai-vllm || return 1
    run_uv_install --upgrade --reinstall --prerelease=allow \
        "$vllm_wheel" --torch-backend=auto || return 1
    install_flashinfer_python311_compatible || return 1
    run_uv_install timm || return 1
}

install_gemma3n_vllm() {
    print_info "Installing the model-card validated vLLM stack for Gemma 3n..."
    ensure_active_environment_matches gemma3n-vllm || return 1
    run_uv_install --upgrade --reinstall \
        "vllm==0.10.0" \
        "transformers==4.53.2" \
        "numpy==2.2.6" \
        "timm" \
        --torch-backend=auto || return 1
}

install_stepfun_sglang() {
    print_info "Installing the pinned SGLang main commit for StepFun..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@834400705f2de2378a327121340f57e324ca5a36#subdirectory=python" || return 1
}

install_stepfun_vllm() {
    print_info "Installing the pinned GitHub vLLM commit and required Transformers 5 for StepFun..."
    install_vllm_pinned_commit_python311_compatible || return 1
    run_uv_install "transformers>=5,<6" || return 1
}


install_zlab_sglang() {
    print_info "Installing the pinned SGLang main commit for z-lab DFlash recipes..."
    run_uv_install -U --reinstall --prerelease=allow \
        "sglang[all] @ git+https://github.com/sgl-project/sglang.git@834400705f2de2378a327121340f57e324ca5a36#subdirectory=python" || return 1
    run_uv_install \
        "git+https://github.com/huggingface/transformers.git@1423d22f7a3b62e8c70ad67b58ec25cd9b675897" || return 1
}
install_zlab_sglang_pr_35209() {
    install_pinned_sglang_commit \
        "z-lab-sglang-pr-35209" \
        "z-lab (SGLang) PR 35209 commit 6283bde44381262b893d0141a529e58041a5d54d" \
        "https://github.com/SubSir/sglang.git" \
        "6283bde44381262b893d0141a529e58041a5d54d"
    run_uv_install "transformers==5.12.1" || return 1
}


install_zyphra_vllm() {
    local source_commit="b1b99a08b20f858035894f7f2a8080c556423844"

    print_info "Installing the proven Zyphra vLLM commit $source_commit..."
    ensure_active_environment_matches zyphra-vllm || return 1
    run_pip_install "vllm @ git+https://github.com/Zyphra/vllm.git@$source_commit" || return 1
}

install_zyphra_legacy_vllm() {
    local source_commit="8df704c5258830b18ca19722bcfd40357b410f66"

    print_info "Installing the proven Zyphra Legacy vLLM commit $source_commit..."
    ensure_active_environment_matches zyphra-legacy-vllm || return 1
    run_pip_install "vllm @ git+https://github.com/Zyphra/vllm.git@$source_commit" || return 1
}

install_dflash_vllm_for_environment() {
    local environment_name="$1"
    local owner_name="$2"
    local upstream_commit="31840cf3ead3632f3c99db4a24e4aba39ad54ef6"
    local proven_commit="c3dabcddc328e00990892370317d36cda31745e6"
    local binary_commit="9842d701450214d4b78cd9aefb8eee0c616bce33"
    local source_dir=""
    local actual_commit=""

    print_info "Installing the proven DFlash vLLM patchset $proven_commit for $owner_name..."
    ensure_active_environment_matches "$environment_name" || return 1
    source_dir="$VIRTUAL_ENV/vllm"

    if [ -e "$source_dir" ] && [ ! -d "$source_dir/.git" ]; then
        print_error "vLLM target exists but is not a git checkout: $source_dir"
        return 1
    fi

    if [ ! -d "$source_dir/.git" ]; then
        run_command git clone --filter=blob:none \
            https://github.com/vllm-project/vllm.git "$source_dir" || return 1
    fi

    run_command git -C "$source_dir" fetch origin \
        refs/pull/52816/head --tags || return 1
    run_command git -C "$source_dir" checkout --force "$upstream_commit" || return 1

    print_command "git -C $source_dir apply DFlash compatibility patch"
    if git -C "$source_dir" apply <<'DFLASH_VLLM_PATCH'
diff --git a/vllm/model_executor/layers/attention/attention.py b/vllm/model_executor/layers/attention/attention.py
index b4831e2a0b..cf19311915 100644
--- a/vllm/model_executor/layers/attention/attention.py
+++ b/vllm/model_executor/layers/attention/attention.py
@@ -247,6 +247,7 @@ class Attention(nn.Module, AttentionLayerBase):
         attn_type: str = AttentionType.DECODER,
         kv_sharing_target_layer_name: str | None = None,
         mm_prefix_clamp_sliding_window: bool = False,
+        use_mm_prefix: bool | None = None,
         attn_backend: type[AttentionBackend] | None = None,
         head_size_v: int | None = None,
         **extra_impl_args,
@@ -333,9 +334,15 @@ class Attention(nn.Module, AttentionLayerBase):
         self.sliding_window = sliding_window
         self.has_sink = extra_impl_args.get("sinks") is not None
 
-        # NOTE: model_config may be None during certain tests
+        # NOTE: model_config may be None during certain tests. Draft models can
+        # opt out because they process text/query tokens only and must not
+        # inherit a multimodal-prefix requirement from the target model.
         model_config = vllm_config.model_config
-        self.use_mm_prefix = model_config is not None and model_config.is_mm_prefix_lm
+        self.use_mm_prefix = (
+            model_config is not None and model_config.is_mm_prefix_lm
+            if use_mm_prefix is None
+            else use_mm_prefix
+        )
 
         # During model initialization, the default dtype is set as the model
         # weight and activation dtype.
diff --git a/vllm/model_executor/models/qwen3_dflash.py b/vllm/model_executor/models/qwen3_dflash.py
index 410204490e..aab8d8c9c8 100644
--- a/vllm/model_executor/models/qwen3_dflash.py
+++ b/vllm/model_executor/models/qwen3_dflash.py
@@ -255,6 +255,7 @@ class DFlashQwen3Attention(nn.Module):
             prefix=f"{prefix}.attn",
             attn_type=attn_type,
             sinks=self.attention_sink_bias,
+            use_mm_prefix=False,
         )
         self.causal = causal
         self.q_norm = RMSNorm(self.head_dim, eps=rms_norm_eps)
@@ -425,6 +426,13 @@ class DFlashQwen3Model(nn.Module):
             prefix=maybe_prefix(prefix, "embed_tokens"),
         )
 
+        target_config = vllm_config.model_config.hf_text_config
+        self.embed_normalizer: float | None = None
+        if str(getattr(target_config, "model_type", "")).startswith("gemma4"):
+            # Gemma4 scales token embeddings by sqrt(hidden_size). DFlash
+            # shares the target embeddings, so the draft path must match.
+            self.embed_normalizer = target_config.hidden_size**0.5
+
         # Masked query slots are fed to the draft as `mask_token_id`. Most DFlash
         # checkpoints will have the mask embedding in the vocabulary embedding table
         # at that slot id. Some checkpoints (XiaomiMiMo/MiMo-V2.5-Pro-FP4-DFlash) ship
@@ -477,6 +485,8 @@ class DFlashQwen3Model(nn.Module):
             # Replace masked slots with the dedicated mask embedding.
             is_mask = (input_ids == self.mask_token_id).unsqueeze(-1)
             embeds = torch.where(is_mask, self.mask_embedding.to(embeds.dtype), embeds)
+        if self.embed_normalizer is not None:
+            embeds = embeds * self.embed_normalizer
         return embeds
 
     def _build_context_kv_buffers(
@@ -728,7 +738,9 @@ class DFlashQwen3ForCausalLM(Qwen3ForCausalLM):
             prefix=maybe_prefix(prefix, "lm_head"),
         )
         self.logits_processor = LogitsProcessor(
-            self.config.draft_vocab_size, scale=logit_scale
+            self.config.draft_vocab_size,
+            scale=logit_scale,
+            soft_cap=getattr(self.config, "final_logit_softcapping", None),
         )
         target_vocab_size = vllm_config.model_config.get_vocab_size()
         if self.config.draft_vocab_size != target_vocab_size:
diff --git a/vllm/v1/attention/backends/triton_attn.py b/vllm/v1/attention/backends/triton_attn.py
index 4b1c167e7f..014a390dba 100644
--- a/vllm/v1/attention/backends/triton_attn.py
+++ b/vllm/v1/attention/backends/triton_attn.py
@@ -119,8 +119,8 @@ class TritonAttentionMetadataBuilder(AttentionMetadataBuilder[TritonAttentionMet
         self.num_heads_q = get_num_attention_heads_from_layers(
             vllm_config, layer_names
         ) or model_config.get_num_attention_heads(vllm_config.parallel_config)
-        self.num_heads_kv = model_config.get_num_kv_heads(vllm_config.parallel_config)
-        self.headdim = model_config.get_head_size()
+        self.num_heads_kv = kv_cache_spec.num_kv_heads
+        self.headdim = kv_cache_spec.head_size
 
         # Check if CUDA Graphs are enabled for decode
         self.decode_cudagraph_enabled = (
DFLASH_VLLM_PATCH
    then
        :
    else
        print_error "Failed to apply the proven DFlash vLLM compatibility patch."
        return 1
    fi

    run_command git -C "$source_dir" add \
        vllm/model_executor/layers/attention/attention.py \
        vllm/model_executor/models/qwen3_dflash.py \
        vllm/v1/attention/backends/triton_attn.py || return 1

    run_command env \
        "GIT_AUTHOR_NAME=OMP Integration" \
        "GIT_AUTHOR_EMAIL=omp@localhost" \
        "GIT_AUTHOR_DATE=2026-08-19T14:39:58+00:00" \
        "GIT_COMMITTER_NAME=OMP Integration" \
        "GIT_COMMITTER_EMAIL=omp@localhost" \
        "GIT_COMMITTER_DATE=2026-08-19T14:39:58+00:00" \
        git -C "$source_dir" commit --no-gpg-sign \
        -m "Port Gemma4 DFlash fixes onto DFlash2 branch" || return 1

    actual_commit=$(git -C "$source_dir" rev-parse HEAD) || return 1
    if [ "$actual_commit" != "$proven_commit" ]; then
        print_error "Recreated DFlash vLLM commit is $actual_commit; expected $proven_commit."
        return 1
    fi

    VLLM_USE_PRECOMPILED=1 \
        VLLM_PRECOMPILED_WHEEL_COMMIT="$binary_commit" \
        run_uv_install -U --reinstall --prerelease=allow \
        -e "$source_dir" --torch-backend=auto || return 1

    install_flashinfer_python311_compatible || return 1
}

install_incoai_vllm() {
    install_dflash_vllm_for_environment "incoai-vllm" "IncoAI" || return 1
}

install_zlab_vllm() {
    install_dflash_vllm_for_environment "z-lab-vllm" "z-lab" || return 1
}

perform_environment_action() {
    case "$1" in
        allenai-sglang)
            install_allenai_sglang || return 1
            ;;
        allenai-vllm)
            install_allenai_vllm || return 1
            ;;
        arcee-nvfp4-vllm)
            install_arcee_nvfp4_vllm || return 1
            ;;
        arcee-sglang)
            install_arcee_sglang || return 1
            ;;
        arcee-vllm)
            install_arcee_vllm || return 1
            ;;
        cohere-sglang)
            install_cohere_sglang || return 1
            ;;
        cohere-vllm)
            install_cohere_vllm || return 1
            ;;
        datalab-sglang)
            install_datalab_sglang || return 1
            ;;
        datalab-vllm)
            install_datalab_vllm || return 1
            ;;
        deepseek-ktransformers)
            install_deepseek_ktransformers || return 1
            ;;
        deepseek-lmdeploy)
            install_deepseek_lmdeploy || return 1
            ;;
        deepseek-sglang)
            install_deepseek_sglang || return 1
            ;;
        deepseek-vllm)
            install_deepseek_vllm || return 1
            ;;
        diffusiongemma-sglang)
            install_diffusiongemma_sglang || return 1
            ;;
        gemma-sglang)
            install_gemma_sglang || return 1
            ;;
        gemma-vllm)
            install_gemma_vllm || return 1
            ;;
        glm-sglang)
            install_glm_sglang || return 1
            ;;
        glm-transformers)
            install_glm_transformers || return 1
            ;;
        glm-vllm)
            install_glm_vllm || return 1
            ;;
        gpt-oss-sglang)
            install_gptoss_sglang || return 1
            ;;
        gpt-oss-transformers)
            install_gptoss_transformers || return 1
            ;;
        gpt-oss-vllm)
            install_gptoss_vllm || return 1
            ;;
        ibm-sglang)
            install_ibm_sglang || return 1
            ;;
        ibm-vllm)
            install_ibm_vllm || return 1
            ;;
        inclusionai-sglang)
            install_inclusionai_sglang || return 1
            ;;
        inclusionai-transformers)
            install_inclusionai_transformers || return 1
            ;;
        inclusionai-vllm)
            install_inclusionai_vllm || return 1
            ;;
        inclusionai-ling3-vllm)
            install_inclusionai_ling3_vllm || return 1
            ;;
        incoai-sglang)
            install_incoai_sglang || return 1
            ;;
        incoai-vllm)
            install_incoai_vllm || return 1
            ;;
        intel-sglang)
            install_intel_sglang || return 1
            ;;
        intel-vllm)
            install_intel_vllm || return 1
            ;;
        kimi-ktransformers)
            install_kimi_ktransformers || return 1
            ;;
        kimi-sglang)
            install_kimi_sglang || return 1
            ;;
        kimi-vllm)
            install_kimi_vllm || return 1
            ;;
        liquidai-sglang)
            install_liquidai_sglang || return 1
            ;;
        liquidai-sglang-pr-31041)
            install_liquidai_sglang_pr_31041 || return 1
            ;;
        liquidai-vllm)
            install_liquidai_vllm || return 1
            ;;
        meta-sglang)
            install_meta_sglang || return 1
            ;;
        meta-vllm)
            install_meta_vllm || return 1
            ;;
        microsoft-sglang)
            install_microsoft_sglang || return 1
            ;;
        microsoft-vllm)
            install_microsoft_vllm || return 1
            ;;
        minimax-sglang)
            install_minimax_sglang || return 1
            ;;
        minimax-transformers)
            install_minimax_transformers || return 1
            ;;
        minimax-vllm)
            install_minimax_vllm || return 1
            ;;
        mistralai-sglang)
            install_mistralai_sglang || return 1
            ;;
        mistralai-vllm)
            install_mistralai_vllm || return 1
            ;;
        nanbeige-sglang)
            install_nanbeige_sglang || return 1
            ;;
        nanbeige-vllm)
            install_nanbeige_vllm || return 1
            ;;
        nemotron-trtllm)
            install_nemotron_trtllm || return 1
            ;;
        nvidia-deepseek-sglang)
            install_nvidia_deepseek_sglang || return 1
            ;;
        nvidia-nemotron)
            install_nvidia_nemotron || return 1
            ;;
        nvidia-sglang)
            install_nvidia_sglang || return 1
            ;;
        nvidia-sglang-pr-33554)
            install_nvidia_sglang_pr_33554 || return 1
            ;;
        nvidia-sglang-pr-34966)
            install_nvidia_sglang_pr_34966 || return 1
            ;;
        nvidia-vllm)
            install_nvidia_vllm || return 1
            ;;
        poolside-laguna-xs-vllm)
            install_poolside_laguna_xs_vllm || return 1
            ;;
        poolside-sglang)
            install_poolside_sglang || return 1
            ;;
        poolside-sglang-pr-22513)
            install_poolside_sglang_pr_22513 || return 1
            ;;
        poolside-vllm)
            install_poolside_vllm || return 1
            ;;
        primeintellect-sglang)
            install_primeintellect_sglang || return 1
            ;;
        primeintellect-vllm)
            install_primeintellect_vllm || return 1
            ;;
        qwen-flash-next-sglang)
            install_qwen_flash_next_sglang || return 1
            ;;
        qwen-flash-next-vllm)
            install_qwen_flash_next_vllm || return 1
            ;;
        qwen-ktransformers)
            install_qwen_ktransformers || return 1
            ;;
        qwen-sglang)
            install_qwen_sglang || return 1
            ;;
        qwen-sglang-pr-22121)
            install_qwen_sglang_pr_22121 || return 1
            ;;
        qwen-transformers)
            install_qwen_transformers || return 1
            ;;
        qwen-vllm)
            install_qwen_vllm || return 1
            ;;
        radixark-qwen-sglang)
            install_radixark_qwen_sglang || return 1
            ;;
        radixark-sglang)
            install_radixark_sglang || return 1
            ;;
        redhatai-sglang)
            install_redhatai_sglang || return 1
            ;;
        redhat-sglang-pr-35809)
            install_redhat_sglang_pr_35809 || return 1
            ;;
        redhatai-vllm)
            install_redhatai_vllm || return 1
            ;;
        gemma3n-vllm)
            install_gemma3n_vllm || return 1
            ;;
        stepfun-sglang)
            install_stepfun_sglang || return 1
            ;;
        stepfun-vllm)
            install_stepfun_vllm || return 1
            ;;
        z-lab-sglang)
            install_zlab_sglang || return 1
            ;;
        z-lab-sglang-pr-35209)
            install_zlab_sglang_pr_35209 || return 1
            ;;
        z-lab-vllm)
            install_zlab_vllm || return 1
            ;;
        zyphra-legacy-sglang)
            install_zyphra_legacy_sglang || return 1
            ;;
        zyphra-legacy-vllm)
            install_zyphra_legacy_vllm || return 1
            ;;
        zyphra-sglang)
            install_zyphra_sglang || return 1
            ;;
        zyphra-sglang-pr-32517)
            install_zyphra_sglang_pr_32517 || return 1
            ;;
        zyphra-vllm)
            install_zyphra_vllm || return 1
            ;;
        *)
            print_info "No automated package actions configured for this environment."
            ;;
    esac

    return 0
}

main() {
    local override=""
    local show_help=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                return 1
                ;;
            *)
                if [ -n "$override" ]; then
                    print_error "Only one environment may be specified."
                    return 1
                fi
                override="$1"
                shift
                ;;
        esac
    done

    if [ "$show_help" = true ]; then
        echo "Usage: ./06_install_packages.sh [ENV_NAME]"
        echo
        print_env_options
        return 0
    fi

    local env_type=""

    if [ -n "$override" ]; then
        if env_type=$(resolve_env_type "$override"); then
            print_info "Environment override provided: $env_type"
            if ! activate_environment_override "$env_type"; then
                return 1
            fi
        else
            print_warning "Environment override '$override' is not managed by this script."
            print_info "Nothing to configure in 06_install_packages.sh."
            return 0
        fi
    else
        if ! env_type=$(detect_environment); then
            if [ -n "${VIRTUAL_ENV:-}" ]; then
                print_warning "Active virtual environment '$VIRTUAL_ENV' is not managed by this script."
            else
                print_info "No active virtual environment detected."
            fi
            print_info "Nothing to configure in 06_install_packages.sh."
            return 0
        fi
    fi

    if [ -n "${VIRTUAL_ENV:-}" ]; then
        print_info "Virtual environment: $VIRTUAL_ENV"
    fi

    echo
    handle_environment "$env_type"
    echo

    if ! perform_environment_action "$env_type"; then
        print_error "Environment handling failed."
        return 1
    fi

}

main "$@"
exit $?
