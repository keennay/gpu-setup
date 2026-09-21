<img width="500" height="507" alt="compute" src="https://github.com/user-attachments/assets/93ef9cd8-3380-4f4f-8652-f9dfb27e4bb6" />

***

[Go to Installation Guide](#installation-guide)

[Go to Inference Cookbook Recipes](#inference-cookbook-recipes)

[Go to Included Skills](#included-skills)

[Go to Additional Tools](#additional-tools)

***

## Introduction

This repo provides a quick & simple way to stage an Ubuntu / RHEL NVIDIA node for ML workloads, including building & serving inference cookbook recipes for Large Language Models & Visual-Language Models. Setup and stage a bare-metal server, virtual machine, or rental cloud provider setup (Verda, Massed Compute, Prime Intellect, etc). AMD & additional hardware vendor support is in the works.

An [installation guide](#installation-guide) is provided with steps to clone this repo and run `setup.sh` to display the above terminal interface. All options are selected by default with the ability to choose or omit packages / services, single or multiple CUDA versions, Python, Astral UV, & coding CLIs.

You can also select the minimal installation of [basic Linux essentials](#basic-linux-essentials-required) & [core build dependencies](#core-build-dependencies-for-ml-and-python-packages-required). This option completely bypasses the installation of additional packages / services, CUDA, Python, Astral UV, & coding CLIs. 

Installing CUDA, Node.js 24, or Python through this guide replaces existing defaults, using Node Version Manager (NVM) for managing Node.js 24 & Simple Python Version Management (Pyenv) for managing Python. CUDA drivers are installed and/or updated to the latest version within a CUDA installation.

[Inference cookbook recipes](#inference-cookbook-recipes) are also included for a variety of the popular Large Language Model & Visual-Language model companies. These exist as bash scripts and automatically create new Python environments within the $HOME directory upon execution, while installing pinned versions of either SGLang or vLLM + any additional packages necessary for a proper inference deployment. Additionally each script has the ability customize specific flags based off CUDA architecture target.

New recipes can be created using [the provided skills](#included-skills) within this repo, added to your coding CLI of choice, and building them based off the existing recipes.

***

## Installation Guide:

`setup.sh` runs up to 4 installer files:<br><br>
`installers/01_install_dependencies.sh`<br>
`installers/02_install_cuda.sh`<br>
`installers/03_install_python.sh`<br>
`installers/04_install_coding_clis.sh`

The `/workspace` is the default repo directory used in this guide, yet you're at liberty to choose any other path for the installation.

#### Clone the Repo onto a GPU Instance with a Root user:
```
mkdir -p /workspace
cd /workspace
git clone https://github.com/keennay/gpu-setup.git
cd gpu-setup
./setup.sh
```
#### Clone the Repo onto a GPU Instance with an Ubuntu (non-Root) user:
```
sudo mkdir -p /workspace
sudo chown -R ubuntu:ubuntu /workspace
cd /workspace
git clone https://github.com/keennay/gpu-setup.git
cd gpu-setup
./setup.sh
```

The below are each package / service provided across the installers.

#### Basic Linux essentials (required):
- curl, wget, zip, unzip, less, vim, nano, tmux, git, git-lfs, gh, htop, nvtop, ripgrep, shellcheck, bubblewrap, ffmpeg

#### Core build dependencies for ML and Python packages (required):
- build-essential, gcc, g++, make, cmake, pkg-config, protobuf-compiler, libclang-dev, numactl, libnuma-dev, libhwloc-dev, libssl-dev, libffi-dev, liblzma-dev, libbz2-dev, libreadline-dev, libsqlite3-dev, libncurses-dev, zlib1g-dev

#### Additional services (optional):
- Docker, Node.js 24 (NVM managed), pnpm, Bun, Go, Rust, Zig, Neovim, Tmux

#### CUDA (optional):
- CUDA 13.0 is selected by default. For a custom install you can type either any CUDA version number, or up to 10 version numbers with the 1st number in the list set as the default system-wide CUDA version

#### Pyenv, Pyenv managed Python, & Astral UV (optional):
- Python 3.11.16 is selected by default. For a custom install you can type any other version of Python in full major.mino.macro format (3.**.**). Pyenv is first installed following the desired Python version. Astral UV is provided as an installation option if selected.

#### Coding CLIs (optional):
- Arcee nac, Claude Code, DeepSeek Harness, Gemini CLI, Grok Build, Kimi Code, Meta Muse Code, MiMo Code, MiniMax Code, OMP, OpenAI Codex, OpenCode, Pi, Prime Intellect Agent, Qwen Code

***

## Inference Cookbook Recipes:

Inference cookbook recipes are provided for the following model companies as bash scripts:
- Allen Institute for AI, Arcee AI, Cohere, Datalab, DeepSeek, Dots Studio, Google, IBM Granite, Inclusion Ai, Inco AI, Inferact, Intel, Liquid AI, Meta, Microsoft, MiniMax, Mistral AI, Moonshot AI, Nanbeige, Nex-AGI, NVIDIA, OpenAI, Prime Intellect, Poolside, Qwen, RadixArk, Red Hat AI, StepFun, Tencent, Thinking Machines Lab, Xiaomi, Z Lab, Z.ai, Zyphra

All scripts follow a singular format, allowing easy replicability for newer models & hardware architecture. Specific flags are also defined by CUDA architecture target, allowing the same script to run on multiple hardware, with a singular architecture per launch. As of now each script & model launch was tested on 1x, 2x, 4x, and 8x NVIDIA H200s, with future support for sm100, sm103, sm120, & sm121 architecture GPUs.

Below are the CUDA architecture specific flags:

| SGLang Flag | vLLM Flag | Script Env |
| --- | --- | --- |
| --attention-backend | --attention-backend | BACKEND_ATTENTION_SM* |
| --fp8-gemm-backend | --linear-backend | BACKEND_FP8_GEMM_SM* |
| --fp8-gemm-backend | --linear-backend | BACKEND_FP4_GEMM_SM* |
| --moe-runner-backend | --moe-backend | BACKEND_MOE_RUNNER_SM* |
| --mem-fraction-static | --gpu-mem-util | GPU_MEM_UTIL_VALUE_SM* |
| --tp | --tensor-parallel-size | TENSOR_PARALLEL_SIZE_SM* |

***

## Included Skills:

- llm-vlm-cookbook-recipe-source
  - Prioritize retrieving inference recipes from SGLang & vLLM's Cookbook recipe sites, with the HuggingFace model card as the fallback
    - https://docs.sglang.io/cookbook/
    - https://recipes.vllm.ai/
- llm-vlm-cookbook-recipe-creation-and-update
  - The process for generating inference recipes using the `llm-vlm-cookbook-recipe-source` skill as the guide
- llm-inference-bench-creation-and-update
  - The tool for creating beautiful pre-fill / decode benchmark tables & additional metrics by the wonderful crew over at Local Inference Lab
    - https://github.com/local-inference-lab/llm-inference-bench
    - https://x.com/YourLocalAILab
***

## Additional Tools:

#### Change Between Python Environments:
`source ./launch_env.sh`

#### Install any selection of open-weights models or input your desired repo:
`./model_download.sh` or example with repo: `./model_download.sh Qwen/Qwen3.8-27B`

#### Check for any model snapshot / blob updates for existing repos:
`./check_model_updates.sh`
