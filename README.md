# Compute Setup

A quick & simple way to stage an Ubuntu / RHEL NVIDIA node for ML workloads, including building & serving inference cookbook recipes for Large Language Models & Visual-Language Models. Stage for a bare-metal server, virtual machine, or rental cloud provider setup (Verda, Massed Compute, Prime Intellect, etc).

AMD & additional hardware vendor support is in the works.

Clone this repo and run `setup.sh` to display the below terminal interface. All options are selected by default with the ability to choose or omit packages / services, single or multiple CUDA versions, Python, Astral UV, & coding CLIs.

Any CUDA, Node.js 24, or Python installation through this setup replaces existing defaults, using Node Version Manager (NVM) for managing Node.js 24 & Simple Python Version Management (Pyenv) for managing Python. CUDA drivers are installed and/or updated to the latest version within a CUDA installation.

<img width="500" height="507" alt="yoniq_setup" src="https://github.com/user-attachments/assets/ccbe2513-8eaa-4bf0-8ba5-f4b29825a800" />

***

### Installation Guide:

`setup.sh` runs up to 4 installer files:<br><br>
`01_install_dependencies.sh`<br>
`02_install_cuda.sh`<br>
`03_install_python.sh`<br>
`04_install_coding_clis.sh`

The `/workspace` is the default repo directory used in this guide, yet you're at liberty to chose any other path for the installation.

##### Cloning the Repo onto a GPU Instance with a Root user:
```
mkdir -p /workspace
cd /workspace
git clone https://github.com/keennay/gpu-setup.git
cd gpu-setup
./setup.sh
```
##### Cloning the Repo onto a GPU Instance with an Ubuntu (non-Root) user:
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
- curl, wget, zip, unzip, less, vim, nano, tmux, git, git-lfs, htop, nvtop, ripgrep, shellcheck, bubblewrap, ffmpeg

#### Core build dependencies for ML and Python packages (required):
- build-essential, gcc, g++, make, cmake, pkg-config, protobuf-compiler, libclang-dev, numactl, libnuma-dev, libhwloc-dev, libssl-dev, libffi-dev, liblzma-dev, libbz2-dev, libreadline-dev, libsqlite3-dev, libncurses-dev, zlib1g-dev

#### Additional services (optional):
- Docker, Node.js 24 (NVM managed), pnpm, Bun, Go, Rust, Zig, Neovim, Tmux

#### CUDA (optional):
- CUDA 13.0 is selected by default. For a custom install you can type either any CUDA version number or to 10 version numbers with the 1st number in the list set as the default system-wide CUDA version

#### Pyenv, Pyenv managed Python, & Astral UV (optional):
- Python 3.11.16 is selected by default. For a custom install you an type any other version of Python in full major.mino.macro format (3.**.**). Pyenv is first installed following the desired Python version. Astral UV is provided as an installation option if selected.

#### Coding CLIs (optional):
- Arcee nac, Claude Code, DeepSeek Harness, Gemini CLI, Grok Build, Kimi Code, Meta Muse Code, MiMo Code, OMP, OpenAI Codex, OpenCode, Pi, Prime Intellect Agent, Qwen Code

***

### Additional Tools:

#### Change Between Python Environments:
`source ./launch_env.sh`

#### Install any selection of open-weights models or input your desired repo:
`./model_download.sh` or example with repo: `./model_download.sh Qwen/Qwen3.8-27B`

#### Check for any model snapshot / blob updates for existing repos:
`./check_model_updates.sh`
