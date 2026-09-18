#!/usr/bin/env bash
set -euo pipefail

# Run upgrade scripts found next to this script, independent of current directory.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

scripts=(
  "upgrade_arcee.sh"
  "upgrade_claude.sh"
  "upgrade_deepseek.sh"
  "upgrade_gemini.sh"
  "upgrade_grok.sh"
  "upgrade_kimi.sh"
  "upgrade_muse.sh"
  "upgrade_mimo.sh"
  "upgrade_mcode.sh"
  "upgrade_omp.sh"
  "upgrade_codex.sh"
  "upgrade_opencode.sh"
  "upgrade_pi.sh"
  "upgrade_prime.sh"
  "upgrade_qwen.sh"
)

for script in "${scripts[@]}"; do
  script_path="$script_dir/$script"
  if [[ -x "$script_path" ]]; then
    echo "==> Running $script_path"
    "$script_path"
  elif [[ -f "$script_path" ]]; then
    echo "==> Running $script_path with bash"
    bash "$script_path"
  else
    echo "Skipping $script (not found in $script_dir)" >&2
  fi
done
