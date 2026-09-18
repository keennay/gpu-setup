#!/bin/bash
# Script: 04_install_coding_clis.sh
# Purpose: Install coding CLIs and their config files

set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_OWNER_USER="${SUDO_USER:-$USER}"
CONFIG_OWNER_GROUP="$(id -gn "$CONFIG_OWNER_USER" 2>/dev/null || echo "$CONFIG_OWNER_USER")"
CONFIG_HOME="$(eval echo "~$CONFIG_OWNER_USER")"
CONFIG_ROOT="$CONFIG_HOME/.config"

ensure_config_ownership() {
    local config_root="$1"

    if [ -z "$config_root" ]; then
        print_warning "Config root not set; skipping config setup"
        return 1
    fi

    if [ ! -d "$config_root" ]; then
        if ! mkdir -p "$config_root"; then
            print_warning "Failed to create $config_root without sudo; skipping config setup"
            return 1
        fi
    fi

    local owner group
    owner=$(stat -c '%U' "$config_root" 2>/dev/null)
    group=$(stat -c '%G' "$config_root" 2>/dev/null)

    if [ "$owner" != "$CONFIG_OWNER_USER" ] || [ "$group" != "$CONFIG_OWNER_GROUP" ]; then
        print_warning "$config_root is owned by $owner:$group; skipping config setup to avoid sudo"
        return 1
    fi

    if [ ! -w "$config_root" ]; then
        print_warning "$config_root is not writable; skipping config setup"
        return 1
    fi

    return 0
}

warn_on_ownership_mismatch() {
    local target="$1"

    if [ -e "$target" ]; then
        local owner group
        owner=$(stat -c '%U' "$target" 2>/dev/null)
        group=$(stat -c '%G' "$target" 2>/dev/null)

        if [ "$owner" != "$CONFIG_OWNER_USER" ] || [ "$group" != "$CONFIG_OWNER_GROUP" ]; then
            print_warning "$target is owned by $owner:$group; leaving ownership unchanged to avoid sudo"
        fi
    fi
}

prompt_yes_no() {
    local result_var="$1"
    local prompt="$2"
    local answer

    if [ "$AUTO_YES" = true ]; then
        printf -v "$result_var" "y"
    else
        read -r -p "$prompt" answer
        printf -v "$result_var" "%s" "$answer"
    fi
}

load_nvm_node() {
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        return
    fi

    export NVM_DIR="${NVM_DIR:-$CONFIG_HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
        if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
            nvm use 24 >/dev/null 2>&1 || nvm use node >/dev/null 2>&1 || true
        fi
    fi
}

# Parse arguments
AUTO_YES=false
SELECT_ALL=false
SELECT_ARCEE=false
SELECT_CLAUDE=false
SELECT_DEEPSEEK=false
SELECT_GEMINI=false
SELECT_GROK=false
SELECT_KIMI=false
SELECT_MUSE=false
SELECT_MIMO=false
SELECT_MCODE=false
SELECT_OMP=false
SELECT_CODEX=false
SELECT_OPENCODE=false
SELECT_PI=false
SELECT_PRIME=false
SELECT_QWEN=false
SELECTION_MADE=false

print_usage() {
    echo "Usage: $0 [-y|--auto] (--all | CLI flags...)"
    echo "  -y, --auto  Automatically install selected CLIs"
    echo "  --all       Select every coding CLI"
    echo "  --arcee     Select Arcee nac"
    echo "  --claude    Select Claude Code"
    echo "  --deepseek  Select DeepSeek Harness"
    echo "  --gemini    Select Gemini CLI"
    echo "  --grok      Select Grok Build"
    echo "  --kimi      Select Kimi Code"
    echo "  --muse      Select Meta Muse Code"
    echo "  --mimo      Select MiMo Code"
    echo "  --mcode     Select MiniMax Code"
    echo "  --omp       Select OMP"
    echo "  --codex     Select OpenAI Codex"
    echo "  --opencode  Select OpenCode"
    echo "  --pi        Select Pi"
    echo "  --prime     Select Prime Intellect Agent"
    echo "  --qwen      Select Qwen Code"
    echo "  -h, --help  Show this help message"
}

for arg in "$@"; do
    case "$arg" in
        -y|--auto) AUTO_YES=true ;;
        --all) SELECT_ALL=true; SELECTION_MADE=true ;;
        --arcee) SELECT_ARCEE=true; SELECTION_MADE=true ;;
        --claude) SELECT_CLAUDE=true; SELECTION_MADE=true ;;
        --deepseek) SELECT_DEEPSEEK=true; SELECTION_MADE=true ;;
        --gemini) SELECT_GEMINI=true; SELECTION_MADE=true ;;
        --grok) SELECT_GROK=true; SELECTION_MADE=true ;;
        --kimi) SELECT_KIMI=true; SELECTION_MADE=true ;;
        --muse) SELECT_MUSE=true; SELECTION_MADE=true ;;
        --mimo) SELECT_MIMO=true; SELECTION_MADE=true ;;
        --mcode) SELECT_MCODE=true; SELECTION_MADE=true ;;
        --omp) SELECT_OMP=true; SELECTION_MADE=true ;;
        --codex) SELECT_CODEX=true; SELECTION_MADE=true ;;
        --opencode) SELECT_OPENCODE=true; SELECTION_MADE=true ;;
        --pi) SELECT_PI=true; SELECTION_MADE=true ;;
        --prime) SELECT_PRIME=true; SELECTION_MADE=true ;;
        --qwen) SELECT_QWEN=true; SELECTION_MADE=true ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $arg"
            print_usage
            exit 1
            ;;
    esac
done

if [ "$SELECTION_MADE" = false ]; then
    print_error "Select at least one coding CLI flag or use --all."
    print_usage
    exit 1
fi

section_selected() {
    local selected="$1"
    [ "$SELECT_ALL" = true ] || [ "$selected" = true ]
}

curl_cli_selected() {
    section_selected "$SELECT_ARCEE" ||
        section_selected "$SELECT_CLAUDE" ||
        section_selected "$SELECT_GROK" ||
        section_selected "$SELECT_KIMI" ||
        section_selected "$SELECT_MUSE" ||
        section_selected "$SELECT_MIMO" ||
        section_selected "$SELECT_MCODE" ||
        section_selected "$SELECT_OMP" ||
        section_selected "$SELECT_CODEX" ||
        section_selected "$SELECT_OPENCODE" ||
        section_selected "$SELECT_PRIME" ||
        section_selected "$SELECT_QWEN"
}

print_info "Coding CLI Installer"
echo ""

if section_selected "$SELECT_DEEPSEEK" ||
   section_selected "$SELECT_GEMINI" ||
   section_selected "$SELECT_PI" ||
   section_selected "$SELECT_PRIME"; then
    load_nvm_node
fi

NODE_AVAILABLE=false
NPM_AVAILABLE=false
PNPM_AVAILABLE=false
if command -v node &> /dev/null; then
    NODE_AVAILABLE=true
fi
if command -v npm &> /dev/null; then
    NPM_AVAILABLE=true
fi
if command -v pnpm &> /dev/null; then
    PNPM_AVAILABLE=true
fi

if section_selected "$SELECT_DEEPSEEK" &&
   { [ "$NODE_AVAILABLE" = false ] || [ "$PNPM_AVAILABLE" = false ]; }; then
    print_warning "Skipping DeepSeek Harness: Node.js or pnpm was not found."
fi
if section_selected "$SELECT_GEMINI" &&
   { [ "$NODE_AVAILABLE" = false ] || [ "$NPM_AVAILABLE" = false ]; }; then
    print_warning "Skipping Gemini CLI: Node.js or npm was not found."
fi
if section_selected "$SELECT_PI" &&
   { [ "$NODE_AVAILABLE" = false ] || [ "$NPM_AVAILABLE" = false ]; }; then
    print_warning "Skipping Pi: Node.js or npm was not found."
fi
if section_selected "$SELECT_PRIME" &&
   { [ "$NODE_AVAILABLE" = false ] || [ "$NPM_AVAILABLE" = false ]; }; then
    print_warning "Skipping Prime Intellect Agent: Node.js or npm was not found."
fi

if curl_cli_selected && ! command -v curl &> /dev/null; then
    print_error "curl not found - install basic Linux essentials first by running ./installers/01_install_dependencies.sh"
    exit 1
fi

print_info "Available coding CLIs to install:"
print_info "  1. Arcee nac (nac)"
print_info "  2. Claude Code (@anthropic-ai/claude-code)"
print_info "  3. DeepSeek Harness (dsh)"
print_info "  4. Gemini CLI (@google/gemini-cli)"
print_info "  5. Grok Build (grok)"
print_info "  6. Kimi Code"
print_info "  7. Meta Muse Code"
print_info "  8. MiMo Code"
print_info "  9. MiniMax Code (mcode)"
print_info "  10. OMP (omp)"
print_info "  11. OpenAI Codex (@openai/codex)"
print_info "  12. OpenCode (opencode-ai)"
print_info "  13. Pi"
print_info "  14. Prime Intellect Agent"
print_info "  15. Qwen Code"
echo ""

if section_selected "$SELECT_ARCEE"; then
    # Arcee nac
    prompt_yes_no INSTALL_NAC "  Install Arcee nac? (y/n): "
    if [[ "$INSTALL_NAC" =~ ^[Yy]$ ]]; then
        print_info "Installing Arcee nac..."
        if curl -fsSL https://raw.githubusercontent.com/arcee-ai/nac/main/scripts/install.sh | sh; then
            print_info "Arcee nac installed"
        else
            print_warning "Failed to install Arcee nac"
        fi
    fi
fi

if section_selected "$SELECT_CLAUDE"; then
    # Claude Code
    prompt_yes_no INSTALL_CLAUDE "  Install Claude Code? (y/n): "
    if [[ "$INSTALL_CLAUDE" =~ ^[Yy]$ ]]; then
        print_info "Installing Claude Code..."
        if curl -fsSL https://claude.ai/install.sh | bash; then
            print_info "Claude Code installed"
            CLAUDE_BIN_DIR="$HOME/.local/bin"
            CLAUDE_PATH_EXPORT='export PATH="$HOME/.local/bin:$PATH"'
            BASHRC_PATH="$HOME/.bashrc"
            if ! grep -Fqx "$CLAUDE_PATH_EXPORT" "$BASHRC_PATH" 2>/dev/null; then
                if printf '\n%s\n' "$CLAUDE_PATH_EXPORT" >> "$BASHRC_PATH"; then
                    print_info "Added $CLAUDE_BIN_DIR to PATH in $BASHRC_PATH"
                else
                    print_warning "Claude Code installed, but failed to add $CLAUDE_BIN_DIR to PATH in $BASHRC_PATH"
                fi
            fi
            case ":$PATH:" in
                *":$CLAUDE_BIN_DIR:"*) ;;
                *) export PATH="$CLAUDE_BIN_DIR:$PATH" ;;
            esac
        else
            print_warning "Failed to install Claude Code"
        fi
    fi
fi

if section_selected "$SELECT_DEEPSEEK" &&
   [ "$NODE_AVAILABLE" = true ] &&
   [ "$PNPM_AVAILABLE" = true ]; then
    # DeepSeek Harness
    prompt_yes_no INSTALL_DEEPSEEK "  Install DeepSeek Harness? (y/n): "
    if [[ "$INSTALL_DEEPSEEK" =~ ^[Yy]$ ]]; then
        DEEPSEEK_HARNESS_DIR="$HOME/deepseek-harness"
        DEEPSEEK_READY=true

        if ! command -v git &> /dev/null; then
            print_warning "git not found - cannot install DeepSeek Harness"
            DEEPSEEK_READY=false
        elif [ -e "$DEEPSEEK_HARNESS_DIR" ] && [ ! -d "$DEEPSEEK_HARNESS_DIR/.git" ]; then
            print_warning "Cannot clone DeepSeek Harness because $DEEPSEEK_HARNESS_DIR already exists and is not a Git checkout"
            DEEPSEEK_READY=false
        elif [ -d "$DEEPSEEK_HARNESS_DIR/.git" ]; then
            print_info "Using existing DeepSeek Harness checkout at $DEEPSEEK_HARNESS_DIR"
        else
            print_info "Cloning DeepSeek Harness into $DEEPSEEK_HARNESS_DIR..."
            if ! git clone https://github.com/deepseek-ai/deepseek-harness.git "$DEEPSEEK_HARNESS_DIR"; then
                print_warning "Failed to clone DeepSeek Harness"
                DEEPSEEK_READY=false
            fi
        fi

        if [ "$DEEPSEEK_READY" = true ]; then
            print_info "Installing and building DeepSeek Harness..."
            if (
                cd "$DEEPSEEK_HARNESS_DIR" &&
                pnpm install &&
                pnpm run build
            ); then
                print_info "DeepSeek Harness installed"
                print_info "Run it with: cd \"$DEEPSEEK_HARNESS_DIR\" && pnpm dsh web"
            else
                print_warning "Failed to install or build DeepSeek Harness"
            fi
        fi
    fi
fi

if section_selected "$SELECT_GEMINI" &&
   [ "$NODE_AVAILABLE" = true ] &&
   [ "$NPM_AVAILABLE" = true ]; then
    # Gemini CLI
    prompt_yes_no INSTALL_GEMINI "  Install Gemini CLI? (y/n): "
    if [[ "$INSTALL_GEMINI" =~ ^[Yy]$ ]]; then
        print_info "Installing Gemini CLI..."
        if npm install -g @google/gemini-cli; then
            print_info "Gemini CLI installed"
        else
            print_warning "Failed to install Gemini CLI"
        fi
    fi
fi

if section_selected "$SELECT_GROK"; then
    # Grok Build
    prompt_yes_no INSTALL_GROK "  Install Grok Build? (y/n): "
    if [[ "$INSTALL_GROK" =~ ^[Yy]$ ]]; then
        print_info "Installing Grok Build..."
        if curl -fsSL https://x.ai/cli/install.sh | bash; then
            print_info "Grok Build installed"
        else
            print_warning "Failed to install Grok Build"
        fi
    fi
fi

if section_selected "$SELECT_KIMI"; then
    # Kimi Code
    prompt_yes_no INSTALL_KIMI "  Install Kimi Code? (y/n): "
    if [[ "$INSTALL_KIMI" =~ ^[Yy]$ ]]; then
        print_info "Installing Kimi Code..."
        if curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash; then
            print_info "Kimi Code installed"
        else
            print_warning "Failed to install Kimi Code"
        fi
    fi
fi

if section_selected "$SELECT_MUSE"; then
    # Meta Muse Code
    prompt_yes_no INSTALL_MUSE "  Install Meta Muse Code? (y/n): "
    if [[ "$INSTALL_MUSE" =~ ^[Yy]$ ]]; then
        print_info "Installing Meta Muse Code..."
        if curl -fsSL https://dev.meta.ai/install.sh | bash; then
            print_info "Meta Muse Code installed"
        else
            print_warning "Failed to install Meta Muse Code"
        fi
    fi
fi

if section_selected "$SELECT_MIMO"; then
    # MiMo Code
    prompt_yes_no INSTALL_MIMO "  Install MiMo Code? (y/n): "
    if [[ "$INSTALL_MIMO" =~ ^[Yy]$ ]]; then
        print_info "Installing MiMo Code..."
        if curl -fsSL https://mimo.xiaomi.com/install | bash; then
            print_info "MiMo Code installed"
        else
            print_warning "Failed to install MiMo Code"
        fi
    fi
fi

if section_selected "$SELECT_MCODE"; then
    # MiniMax Code
    prompt_yes_no INSTALL_MCODE "  Install MiniMax Code? (y/n): "
    if [[ "$INSTALL_MCODE" =~ ^[Yy]$ ]]; then
        print_info "Installing MiniMax Code..."
        if curl -fsSL https://filecdn.minimax.chat/public/install.sh | bash; then
            print_info "MiniMax Code installed"
        else
            print_warning "Failed to install MiniMax Code"
        fi
    fi
fi

if section_selected "$SELECT_OMP"; then
    # OMP
    prompt_yes_no INSTALL_OMP "  Install OMP? (y/n): "
    if [[ "$INSTALL_OMP" =~ ^[Yy]$ ]]; then
        print_info "Installing OMP..."
        if curl -fsSL https://omp.sh/install | sh; then
            print_info "OMP installed"
        else
            print_warning "Failed to install OMP"
        fi
    fi
fi

if section_selected "$SELECT_CODEX"; then
    # OpenAI Codex
    prompt_yes_no INSTALL_CODEX "  Install OpenAI Codex? (y/n): "
    if [[ "$INSTALL_CODEX" =~ ^[Yy]$ ]]; then
        print_info "Installing OpenAI Codex..."
        if curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh; then
            print_info "OpenAI Codex installed"
        else
            print_warning "Failed to install OpenAI Codex"
        fi
    fi
fi

if section_selected "$SELECT_OPENCODE"; then
    # OpenCode
    prompt_yes_no INSTALL_OPENCODE "  Install OpenCode? (y/n): "
    if [[ "$INSTALL_OPENCODE" =~ ^[Yy]$ ]]; then
        print_info "Installing OpenCode..."
        if curl -fsSL https://opencode.ai/install | bash; then
            print_info "OpenCode installed"

            OPENCODE_CONFIG_SOURCE="$SCRIPT_DIR/../configs/opencode.json"

            if [ -f "$OPENCODE_CONFIG_SOURCE" ]; then
                print_info "Setting up OpenCode config..."
                if ensure_config_ownership "$CONFIG_ROOT"; then
                    OPENCODE_CONFIG_DIR="$CONFIG_ROOT/opencode"
                    OPENCODE_CONFIG_TARGET="$OPENCODE_CONFIG_DIR/opencode.json"
                    mkdir -p "$OPENCODE_CONFIG_DIR"
                    if cp "$OPENCODE_CONFIG_SOURCE" "$OPENCODE_CONFIG_TARGET"; then
                        warn_on_ownership_mismatch "$OPENCODE_CONFIG_DIR"
                        print_info "OpenCode config copied to $OPENCODE_CONFIG_TARGET"
                    else
                        print_warning "Failed to copy OpenCode config"
                    fi
                else
                    print_warning "Skipping OpenCode config setup due to ownership issues"
                fi
            else
                print_warning "OpenCode config not found at $OPENCODE_CONFIG_SOURCE"
            fi
        else
            print_warning "Failed to install OpenCode"
        fi
    fi
fi

if section_selected "$SELECT_PI" &&
   [ "$NODE_AVAILABLE" = true ] &&
   [ "$NPM_AVAILABLE" = true ]; then
    # Pi
    prompt_yes_no INSTALL_PI "  Install Pi? (y/n): "
    if [[ "$INSTALL_PI" =~ ^[Yy]$ ]]; then
        print_info "Installing Pi..."
        if npm install --global --ignore-scripts --no-fund --no-audit --progress=false @earendil-works/pi-coding-agent; then
            print_info "Pi installed"
        else
            print_warning "Failed to install Pi"
        fi
    fi
fi

if section_selected "$SELECT_PRIME" &&
   [ "$NODE_AVAILABLE" = true ] &&
   [ "$NPM_AVAILABLE" = true ]; then
    # Prime Intellect Agent
    prompt_yes_no INSTALL_PRIME "  Install Prime Intellect Agent? (y/n): "
    if [[ "$INSTALL_PRIME" =~ ^[Yy]$ ]]; then
        print_info "Installing Prime Intellect Agent..."
        if curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh | PRIME_AGENT_INSTALLER_PLAIN=1 PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 setsid --wait sh; then
            print_info "Prime Intellect Agent installed"
        else
            print_warning "Failed to install Prime Intellect Agent"
        fi
    fi
fi

if section_selected "$SELECT_QWEN"; then
    # Qwen Code
    prompt_yes_no INSTALL_QWEN "  Install Qwen Code? (y/n): "
    if [[ "$INSTALL_QWEN" =~ ^[Yy]$ ]]; then
        print_info "Installing Qwen Code..."
        if curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh | bash; then
            print_info "Qwen Code installed"
        else
            print_warning "Failed to install Qwen Code"
        fi
    fi
fi

echo ""
print_info "Coding CLI installation complete"
