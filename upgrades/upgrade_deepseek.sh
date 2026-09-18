#!/usr/bin/env bash
set -euo pipefail

deepseek_dir="$HOME/deepseek-harness"

for required_command in git node pnpm; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "DeepSeek Harness requires $required_command; install it or add it to PATH before running this upgrade." >&2
    exit 1
  fi
done

if [[ -e "$deepseek_dir" && ! -d "$deepseek_dir/.git" ]]; then
  echo "Cannot install DeepSeek Harness: $deepseek_dir already exists and is not a Git checkout." >&2
  exit 1
elif [[ -d "$deepseek_dir/.git" ]]; then
  git -C "$deepseek_dir" pull --ff-only
else
  git clone https://github.com/deepseek-ai/deepseek-harness.git "$deepseek_dir"
fi

cd -- "$deepseek_dir"
pnpm install
pnpm run build
