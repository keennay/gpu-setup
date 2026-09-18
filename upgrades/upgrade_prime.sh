#!/usr/bin/env bash
set -euo pipefail

curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh | PRIME_AGENT_INSTALLER_PLAIN=1 PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 setsid --wait sh
