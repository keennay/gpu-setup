# Compute Setup

<img width="500" height="507" alt="yoniq_setup" src="https://github.com/user-attachments/assets/ccbe2513-8eaa-4bf0-8ba5-f4b29825a800" />


The fastest way to stage an Ubuntu 24 / RHEL Linux based GPU node

This repo provides a series of bash script installers for: updating & upgrading installed linux packages, essential & core/build Linux packages (Tmux, Node.js, Bun, Go, Rust, Neovim, CUDA, Python, UV), Coding CLIs (Claude Code, Gemini CLI, Grok Build, OMP Coding Agent, OpenAI Code, & OpenCode), as well as Python environment setups for your inference engines of choice (KTransformers, SGLang, vLLM, etc). Any of the prior packages can be skipped during the installation stage. Detailed info with each installation package can be found within the installation guide below.

#### Staging Files:
`01_install_dependencies.sh`<br>
`02_install_coding_clis.sh`<br>
`03_install_cuda.sh`<br>
`04_install_python.sh`<br>
`05_setup_env.sh`<br>
`06_install_packages.sh`

***

### Installation Guide:
#### 1. Login your GPU node.
The default work directory for the scripts is `/workspace`. Edit as needed.

#### 2. Create the /workspace directory & clone the repo:
##### GPU Instance with Root user (For ex: Runpod, Verda):
```
mkdir -p /workspace
cd /workspace
git clone https://github.com/keennay/gpu-cluster-setup.git
mv gpu-cluster-setup scripts
cd scripts
```
##### GPU Instance with Ubuntu user (For ex: Prime Intellect):
```
sudo mkdir -p /workspace
sudo chown -R ubuntu:ubuntu /workspace
cd /workspace
git clone https://github.com/keennay/gpu-cluster-setup.git
mv gpu-cluster-setup scripts
cd scripts
```
#### 3: Install Linux Dependecy Packages
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
5) Install ibtop (InfiniBand monitoring tool)
6) Copy Tmux config to ~/.configs/tmux.conf
7) Install nvm (Node Version Manager)
8) Install Node.js 24 via nvm
9) Install Bun JavaScript runtime
10) Install Go
11) Install Rustup
12) Install Neovim
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
