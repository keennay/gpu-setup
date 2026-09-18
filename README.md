# Compute Setup

A quick & simple way to stage an Ubuntu / RHEL based NVIDIA GPU node for inference & ML workloads. Use for your own bare-metal / VM server or rental cloud provider (Verda, Massed Compute, Prime Intellect, etc).

AMD & additional hardware vendor support is in the works.

Clone this repo and run `setup.sh` to display the below terminal interface. All options are selected by default, yet you can pick and choose whichever dependencies, single or multiple CUDA versions, Python version, and coding CLIs you want to install.

Any CUDA, Node.js 24, or Python installations through this setup replace existing defaults, using Node Version Manager (NVM) & Simple Python Version Management (pyenv) for managing Node.js 24 & Python respectively. CUDA drivers are installed / updated to the latest version with a CUDA installation.

<img width="500" height="507" alt="yoniq_setup" src="https://github.com/user-attachments/assets/ccbe2513-8eaa-4bf0-8ba5-f4b29825a800" />

***

#### Installation:

`setup.sh` runs up to 4 installer files:<br><br>
`01_install_dependencies.sh`<br>
`02_install_cuda.sh`<br>
`03_install_python.sh`<br>
`04_install_coding_clis.sh`

#### What This Installs:

This repo provides a series of bash script installers for updating & upgrading installed Linux packages,

Basic Linux essentials:
- curl, wget, zip, unzip, less, vim, nano, tmux, git, git-lfs, htop, nvtop, ripgrep, shellcheck, bubblewrap, ffmpeg

Core build dependencies for ML and Python packages:
- build-essential, gcc, g++, make, cmake, pkg-config, protobuf-compiler, libclang-dev, numactl, libnuma-dev, libhwloc-dev, libssl-dev, libffi-dev, liblzma-dev, libbz2-dev, libreadline-dev, libsqlite3-dev, libncurses-dev, zlib1g-dev

Additional installs:
- Docker, Node.js 24 (NVM managed), pnpm, Bun, Go, Rust, Zig, Neovim, Tmux

CUDA, Python (pyenv managed), and Astral UV

Coding CLIs:
- Arcee nac, Claude Code, DeepSeek Harness, Gemini CLI, Grok Build, Kimi Code, Meta Muse Code, MiMo Code, OMP, OpenAI Codex, OpenCode, Pi, Prime Intellect Agent, Qwen Code

***

### Detailed Guide:
#### 1. Login your GPU node.
The `/workspace` is the default repo directory used in this guide, yet you're at liberty to chose any other path for the installation.

#### 2. Create the work directory & clone the repo:
##### GPU Instance with Root user:
```
mkdir -p /workspace
cd /workspace
git clone https://github.com/keennay/gpu-setup.git
cd gpu-setup
./setup.sh
```
##### GPU Instance with Ubuntu (non-Root) user:
```
sudo mkdir -p /workspace
sudo chown -R ubuntu:ubuntu /workspace
cd /workspace
git clone https://github.com/keennay/gpu-setup.git
cd gpu-setup
./setup.sh
```
#### 3: Install Linux Dependency Packages
```
./01_install_dependencies.sh
```
**Detailed Steps:**
1) Update & upgrade Linux packages
2) Install Linux essential packages:
    * curl, wget, zip, unzip, less, vim, nano, tmux, git, git-lfs, htop, nvtop, ripgrep, bubblegrep
3) Install ShellCheck shell script linter
4) Install Linux core/build dependencies:
    * build-essential, gcc, g++, make, cmake, pkg-config, protobuf-compiler, numactl, libnuma-dev, libhwloc-dev, libssl-dev, libffi-dev, liblzma-dev, libbz2-dev, libreadline-dev, libsqlite3-dev, libncurses-dev, zlib1g-dev
5) Copy Tmux config to ~/.configs/tmux.conf
6) Install nvm (Node Version Manager)
7) Install Node.js 24 via nvm
8) Install Bun JavaScript runtime
9) Install Go
10) Install Rustup
111) Install Neovim
    * Alias vi & vim to Neovim
    * Install Neovim configs
#### 4: Install Coding CLIs
```
./02_install_coding_clis.sh
```
This installs the following coding CLIs: Claude Code, Gemini CLI, Grok Build, OMP, OpenAI Codex, & OpenCode
#### 5: Install one or multiple versions of CUDA
```
./03_install_cuda.sh
```
#### 6: Install Pyenv, Python, and UV
```
./04_install_python.sh
```
#### 7: Setup your Python environment
```
source ./05_setup_env.sh
```
This includes a selection of Python environments customed tailored for:

1) DeepSeek (KTransformers, LMDeploy, SGLang, vLLM)
2) Gemma (SGLang, vLLM)
3) GLM (KTransformers, SGLang, Transformers, vLLM)
4) GPT-OSS (Transformers, vLLM)
5) Kimi (KTransformers, SGLang, vLLM)
6) Ling (SGLang, Transformers, vLLM)
7) Minimax (KTransformers, SGLang, Transformers, vLLM)
8) Nemotron (SGLang, TRTLLM, vLLM)
9) Qwen (KTransformers, SGLang, Transformers, vLLM)
10) Custom UV environment
11) Custom PIP environment
    
#### 8: Install Python environment packages
```
./06_install_packages.sh
```
This installs the Python packages corresponding with the currently active Python environment from the prior steps. This is updated periodically.
***

### Additional Tools:

#### Change Between Python Environments
`source ./launch_env.sh`

#### Install any selection of open-weights models or input your desired repo:
`./model_install.sh` or example with repo: `./model_install.sh Qwen/Qwen3.6-27B`
To download only changed blobs for an update, activate the verified revision, and remove older cached snapshots: `./model_install.sh REPO_ID --update-and-prune`

#### Check for updates for any of your local HuggingFace repo of open-weights models:
`./check_model_updates.sh`

#### Template for Running Inference for Models (Also Downloads if model doesn't exist in HuggingFace PATH):
`./recipes/***.sh`
