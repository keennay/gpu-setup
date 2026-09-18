#!/usr/bin/env bash
set -euo pipefail

curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
