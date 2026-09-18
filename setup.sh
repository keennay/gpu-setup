#!/bin/bash

if (( $# != 0 )); then
    printf 'Usage: ./setup.sh\n' >&2
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPENDENCY_INSTALLER="$SCRIPT_DIR/installers/01_install_dependencies.sh"
CUDA_INSTALLER="$SCRIPT_DIR/installers/02_install_cuda.sh"
PYTHON_INSTALLER="$SCRIPT_DIR/installers/03_install_python.sh"
CLI_INSTALLER="$SCRIPT_DIR/installers/04_install_coding_clis.sh"
INSTALLERS=(
    "$DEPENDENCY_INSTALLER"
    "$CUDA_INSTALLER"
    "$PYTHON_INSTALLER"
    "$CLI_INSTALLER"
)

for installer in "${INSTALLERS[@]}"; do
    if [ ! -r "$installer" ]; then
        printf 'Error: required installer not readable: %s\n' "$installer" >&2
        exit 1
    fi
done

if [ "${TERM:-dumb}" = dumb ]; then
    printf 'Error: an interactive VT100-compatible terminal is required.\n' >&2
    exit 1
fi

TTY_FD=8
TTY_OPEN=0
TUI_ACTIVE=0
SAVED_STTY=""
WINCH_PENDING=0

if ! { exec 8<>/dev/tty; } 2>/dev/null; then
    printf 'Error: an interactive VT100-compatible terminal is required.\n' >&2
    exit 1
fi
TTY_OPEN=1
DEPENDENCY_LABELS=(
    "Docker"
    "Node.js 24"
    "pnpm"
    "Bun"
    "Go"
    "Rust"
    "Zig"
    "Neovim"
    "Tmux"
)
DEPENDENCY_FLAGS=(
    "--docker"
    "--node"
    "--pnpm"
    "--bun"
    "--go"
    "--rust"
    "--zig"
    "--neovim"
    "--tmux"
)
DEPENDENCY_SELECTED=(1 1 1 1 1 1 1 1 1)

CLI_LABELS=(
    "Arcee nac"
    "Claude Code"
    "DeepSeek Harness"
    "Gemini CLI"
    "Grok Build"
    "Kimi Code"
    "Meta Muse Code"
    "MiMo Code"
    "MiniMax Code"
    "OMP"
    "OpenAI Codex"
    "OpenCode"
    "Pi"
    "Prime Intellect Agent"
    "Qwen Code"
)
CLI_FLAGS=(
    "--arcee"
    "--claude"
    "--deepseek"
    "--gemini"
    "--grok"
    "--kimi"
    "--muse"
    "--mimo"
    "--mcode"
    "--omp"
    "--codex"
    "--opencode"
    "--pi"
    "--prime"
    "--qwen"
)
CLI_SELECTED=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1)
ASTRAL_UV_SELECTED=1

all_dependencies_selected() {
    local selected

    for selected in "${DEPENDENCY_SELECTED[@]}"; do
        if (( ! selected )); then
            return 1
        fi
    done
    return 0
}

all_clis_selected() {
    local selected

    for selected in "${CLI_SELECTED[@]}"; do
        if (( ! selected )); then
            return 1
        fi
    done
    return 0
}

install_defaults_selected() {
    all_dependencies_selected &&
        (( ASTRAL_UV_SELECTED )) &&
        all_clis_selected &&
        [ "$cuda_choice" = "default" ] &&
        [ "$python_choice" = "default" ]
}
CUDA_DEFAULT_VERSION="13.0"
PYTHON_DEFAULT_VERSION="3.11.16"
CUDA_GUIDANCE_LINE_ONE="Select 13.0 or type a custom CUDA version >= 12.8."
CUDA_GUIDANCE_LINE_TWO="Up to 10 CUDA versions can be installed, comma separated, with the"
CUDA_GUIDANCE_LINE_THREE="first in the list as the default CUDA option"
PYTHON_GUIDANCE="Select 3.11.16 or type a custom Python version >= 3.11"
CONTROLS_TEXT="Click/Arrows/Tab move  Space select  Enter activate  i install  q cancel"
cuda_choice="default"
python_choice="default"
cuda_buffer=""
python_buffer=""
editing=""
status_message=""

PANEL_WIDTH=80
PANEL_HEIGHT=38
MIN_COLUMNS=80
MIN_ROWS=38
FIELD_WIDTH=45
terminal_rows=21
terminal_columns=80
panel_top=1
panel_left=1
terminal_too_small=0
focus_index=0
FLASH_ENABLED=1
FLASH_PHASE=0
FLASH_TIMEOUT_COUNT=0
FLASH_INTERVAL_TICKS=8
FOCUSED_TEXT=""
if [ -n "${NO_COLOR:-}" ]; then
    STYLE_RESET=""
    STYLE_BORDER=""
    STYLE_TITLE=""
    STYLE_FOCUS_PRIMARY=""
    STYLE_FOCUS_ALTERNATE=""
    FLASH_ENABLED=0
    STYLE_SELECTED=""
    STYLE_MUTED=""
    STYLE_ALERT=""
else
    STYLE_RESET=$'\033[0m'
    STYLE_BORDER=$'\033[38;5;243m'
    STYLE_TITLE=$'\033[1;38;5;81m'
    STYLE_FOCUS_PRIMARY=$'\033[1;38;5;16;48;5;81m'
    STYLE_FOCUS_ALTERNATE=$'\033[1;38;5;231;48;5;25m'
    STYLE_SELECTED=$'\033[1;38;5;114m'
    STYLE_MUTED=$'\033[38;5;245m'
    STYLE_ALERT=$'\033[1;38;5;203m'
fi


FOCUS_CONTROLS=(
    "install"
    "cancel"
    "install_defaults"
    "dependency:0"
    "dependency:1"
    "dependency:2"
    "dependency:3"
    "dependency:4"
    "dependency:5"
    "dependency:6"
    "dependency:7"
    "dependency:8"
    "cuda_default"
    "cuda_custom"
    "cuda_field"
    "python_default"
    "python_custom"
    "python_field"
    "astral_uv"
    "cli:0"
    "cli:1"
    "cli:2"
    "cli:3"
    "cli:4"
    "cli:5"
    "cli:6"
    "cli:7"
    "cli:8"
    "cli:9"
    "cli:10"
    "cli:11"
    "cli:12"
    "cli:13"
    "cli:14"
)
HITBOX_CONTROLS=()
HITBOX_ROWS=()
HITBOX_LEFTS=()
HITBOX_RIGHTS=()
MOUSE_BUTTON=0
MOUSE_COLUMN=0
MOUSE_ROW=0
MOUSE_CONTROL=""
CUDA_FIELD_BOX=""
PYTHON_FIELD_BOX=""


terminal_size() {
    local size=""
    local rows=""
    local columns=""

    if (( TTY_OPEN )) && size="$(stty size <&"$TTY_FD" 2>/dev/null)"; then
        read -r rows columns <<<"$size"
        if [[ "$rows" =~ ^[1-9][0-9]*$ && "$columns" =~ ^[1-9][0-9]*$ ]]; then
            terminal_rows=$((10#$rows))
            terminal_columns=$((10#$columns))
            return
        fi
    fi

    if [[ "${LINES:-}" =~ ^[1-9][0-9]*$ && "${COLUMNS:-}" =~ ^[1-9][0-9]*$ ]]; then
        terminal_rows=$((10#$LINES))
        terminal_columns=$((10#$COLUMNS))
        return
    fi

    terminal_rows=21
    terminal_columns=80
}

center_content() {
    local text="$1"
    local width=$((PANEL_WIDTH - 2))
    local left
    local right

    if (( ${#text} > width )); then
        text="${text:0:width}"
    fi
    left=$(( (width - ${#text}) / 2 ))
    right=$((width - ${#text} - left))
    printf -v CENTERED_CONTENT '%*s%s%*s' "$left" "" "$text" "$right" ""
}
align_with_controls() {
    local text="$1"
    local width=$((PANEL_WIDTH - 2))
    local left=$(( (width - ${#CONTROLS_TEXT}) / 2 ))
    local available=$((width - left))

    printf -v ALIGNED_CONTENT '%*s%-*.*s' "$left" "" "$available" "$available" "$text"
}


append_separator() {
    local title="$1"
    local dash_count=$((PANEL_WIDTH - ${#title} - 5))
    local dashes

    printf -v dashes '%*s' "$dash_count" ""
    PANEL_LINES+=("├─ $title ${dashes// /─}┤")
}

control_text() {
    local control="$1"
    local text="$2"

    if [ "${FOCUS_CONTROLS[$focus_index]}" = "$control" ]; then
        CONTROL_TEXT="> $text"
        FOCUSED_TEXT="$CONTROL_TEXT"
    else
        CONTROL_TEXT="  $text"
    fi
}

checkbox_text() {
    local control="$1"
    local selected="$2"
    local label="$3"
    local mark=" "

    if (( selected )); then
        mark="X"
    fi
    control_text "$control" "[${mark}] $label"
}

render_field() {
    local value="$1"
    local active="$2"
    local visible="$value"
    local visible_width=$((FIELD_WIDTH - 1))

    if (( ${#value} > FIELD_WIDTH )); then
        if (( active )); then
            visible="<${value: -visible_width}"
        else
            visible="${value:0:visible_width}>"
        fi
    fi
    printf -v RENDERED_FIELD "%-${FIELD_WIDTH}.${FIELD_WIDTH}s" "$visible"
}
append_blank_line() {
    local blank

    printf -v blank '%*s' "$((PANEL_WIDTH - 2))" ""
    PANEL_LINES+=("│${blank}│")
}
register_control_hitbox() {
    local control="$1"
    local text="$2"
    local row=$(( ${#PANEL_LINES[@]} - 1 ))
    local line="${PANEL_LINES[$row]}"
    local prefix
    local left

    if [ -z "$text" ] || [[ "$line" != *"$text"* ]]; then
        return
    fi

    prefix="${line%%"$text"*}"
    left=${#prefix}
    HITBOX_CONTROLS+=("$control")
    HITBOX_ROWS+=("$row")
    HITBOX_LEFTS+=("$left")
    HITBOX_RIGHTS+=("$((left + ${#text} - 1))")
}
control_is_enabled() {
    if [ "$1" = "install_defaults" ] && install_defaults_selected; then
        return 1
    fi
    return 0
}

set_focus_control() {
    local control="$1"
    local control_index

    for control_index in "${!FOCUS_CONTROLS[@]}"; do
        if [ "${FOCUS_CONTROLS[$control_index]}" = "$control" ]; then
            focus_index=$control_index
            return 0
        fi
    done
    return 1
}


focus_mouse_control() {
    local row=$((MOUSE_ROW - panel_top))
    local column=$((MOUSE_COLUMN - panel_left))
    local hitbox_index

    MOUSE_CONTROL=""
    if (( row < 0 || row >= PANEL_HEIGHT || column < 0 || column >= PANEL_WIDTH )); then
        return 1
    fi

    for hitbox_index in "${!HITBOX_CONTROLS[@]}"; do
        if (( row != HITBOX_ROWS[hitbox_index] ||
              column < HITBOX_LEFTS[hitbox_index] ||
              column > HITBOX_RIGHTS[hitbox_index] )); then
            continue
        fi

        MOUSE_CONTROL="${HITBOX_CONTROLS[$hitbox_index]}"
        if ! control_is_enabled "$MOUSE_CONTROL"; then
            continue
        fi
        if set_focus_control "$MOUSE_CONTROL"; then
            FLASH_PHASE=0
            FLASH_TIMEOUT_COUNT=0
            status_message=""
            return 0
        fi
    done

    MOUSE_CONTROL=""
    return 1
}



build_panel() {
    local all_selected=0
    local selected_mark=" "
    local install_text
    local cancel_text
    local content
    local custom_text
    local custom_installation_text
    local default_text
    local field_text
    local active
    local row
    local column
    local index
    local -a cells
    local border
    local title="YONIQ Compute Setup"

    PANEL_LINES=()
    HITBOX_CONTROLS=()
    HITBOX_ROWS=()
    HITBOX_LEFTS=()
    HITBOX_RIGHTS=()
    FOCUSED_TEXT=""
    printf -v border '%*s' "$((PANEL_WIDTH - ${#title} - 5))" ""
    PANEL_LINES+=("┌─ $title ${border// /─}┐")

    control_text "install" "[ Install ]"
    install_text="$CONTROL_TEXT"
    control_text "cancel" "[ Cancel ]"
    cancel_text="$CONTROL_TEXT"
    center_content "$install_text $cancel_text"
    PANEL_LINES+=("│${CENTERED_CONTENT}│")
    register_control_hitbox "install" "$install_text"
    register_control_hitbox "cancel" "$cancel_text"
    append_blank_line

    append_separator "Selection"
    if install_defaults_selected; then
        all_selected=1
        selected_mark=" "
        CONTROL_TEXT="  [X] Install Defaults"
    else
        selected_mark="X"
        control_text "install_defaults" "[ ] Install Defaults"
    fi
    printf -v content '%-25.25s' "$CONTROL_TEXT"
    center_content "$content"
    PANEL_LINES+=("│${CENTERED_CONTENT}│")
    if (( ! all_selected )); then
        register_control_hitbox "install_defaults" "$CONTROL_TEXT"
    fi
    custom_installation_text="  [${selected_mark}] Custom Installation"
    center_content "$custom_installation_text"
    PANEL_LINES+=("│${CENTERED_CONTENT}│")

    append_separator "Install / Update Dependencies"
    append_blank_line
    for ((row = 0; row < 3; row++)); do
        cells=("" "" "")
        for ((column = 0; column < 3; column++)); do
            index=$((row * 3 + column))
            if (( index < ${#DEPENDENCY_LABELS[@]} )); then
                checkbox_text "dependency:$index" "${DEPENDENCY_SELECTED[$index]}" "${DEPENDENCY_LABELS[$index]}"
                cells[column]="$CONTROL_TEXT"
            fi
        done
        printf -v content '%-25.25s%-25.25s%-26.26s' "${cells[0]}" "${cells[1]}" "${cells[2]}"
        PANEL_LINES+=("│ ${content} │")
        for ((column = 0; column < 3; column++)); do
            index=$((row * 3 + column))
            if (( index < ${#DEPENDENCY_LABELS[@]} )); then
                register_control_hitbox "dependency:$index" "${cells[$column]}"
            fi
        done
    done
    append_blank_line

    append_separator "CUDA Version"
    append_blank_line
    selected_mark=" "
    if [ "$cuda_choice" = "default" ]; then
        selected_mark="x"
    fi
    control_text "cuda_default" "(${selected_mark}) $CUDA_DEFAULT_VERSION"
    default_text="$CONTROL_TEXT"
    selected_mark=" "
    if [ "$cuda_choice" = "custom" ]; then
        selected_mark="x"
    fi
    control_text "cuda_custom" "(${selected_mark}) Custom"
    custom_text="$CONTROL_TEXT"
    active=0
    if [ "$editing" = "cuda" ]; then
        active=1
    fi
    render_field "$cuda_buffer" "$active"
    CUDA_FIELD_BOX="[${RENDERED_FIELD}]"
    control_text "cuda_field" "$CUDA_FIELD_BOX"
    field_text="$CONTROL_TEXT"
    printf -v content '%-11.11s %s %s  ' "$default_text" "$custom_text" "$field_text"
    PANEL_LINES+=("│ ${content} │")
    register_control_hitbox "cuda_default" "$default_text"
    register_control_hitbox "cuda_custom" "$custom_text"
    register_control_hitbox "cuda_field" "$CUDA_FIELD_BOX"
    append_blank_line
    align_with_controls "$CUDA_GUIDANCE_LINE_ONE"
    PANEL_LINES+=("│${ALIGNED_CONTENT}│")
    align_with_controls "$CUDA_GUIDANCE_LINE_TWO"
    PANEL_LINES+=("│${ALIGNED_CONTENT}│")
    align_with_controls "$CUDA_GUIDANCE_LINE_THREE"
    PANEL_LINES+=("│${ALIGNED_CONTENT}│")

    append_blank_line
    append_separator "Python Version"
    append_blank_line
    selected_mark=" "
    if [ "$python_choice" = "default" ]; then
        selected_mark="x"
    fi
    control_text "python_default" "(${selected_mark}) $PYTHON_DEFAULT_VERSION"
    default_text="$CONTROL_TEXT"
    selected_mark=" "
    if [ "$python_choice" = "custom" ]; then
        selected_mark="x"
    fi
    control_text "python_custom" "(${selected_mark}) Custom"
    custom_text="$CONTROL_TEXT"
    active=0
    if [ "$editing" = "python" ]; then
        active=1
    fi
    render_field "$python_buffer" "$active"
    PYTHON_FIELD_BOX="[${RENDERED_FIELD}]"
    control_text "python_field" "$PYTHON_FIELD_BOX"
    field_text="$CONTROL_TEXT"
    printf -v content '%-13.13s %s %s' "$default_text" "$custom_text" "$field_text"
    PANEL_LINES+=("│ ${content} │")
    register_control_hitbox "python_default" "$default_text"
    register_control_hitbox "python_custom" "$custom_text"
    register_control_hitbox "python_field" "$PYTHON_FIELD_BOX"
    checkbox_text "astral_uv" "$ASTRAL_UV_SELECTED" "Astral UV"
    printf -v content '%-76.76s' "$CONTROL_TEXT"
    PANEL_LINES+=("│ ${content} │")
    register_control_hitbox "astral_uv" "$CONTROL_TEXT"
    append_blank_line
    align_with_controls "$PYTHON_GUIDANCE"
    PANEL_LINES+=("│${ALIGNED_CONTENT}│")

    append_blank_line
    append_separator "Coding CLIs"
    append_blank_line
    for ((row = 0; row < 5; row++)); do
        cells=("" "" "")
        for ((column = 0; column < 3; column++)); do
            index=$((row * 3 + column))
            if (( index < ${#CLI_LABELS[@]} )); then
                checkbox_text "cli:$index" "${CLI_SELECTED[$index]}" "${CLI_LABELS[$index]}"
                cells[column]="$CONTROL_TEXT"
            fi
        done
        if (( row == 4 )); then
            printf -v content '%-25.25s%-27.27s%-24.24s' "${cells[0]}" "${cells[1]}" "${cells[2]}"
        else
            printf -v content '%-25.25s%-25.25s%-26.26s' "${cells[0]}" "${cells[1]}" "${cells[2]}"
        fi
        PANEL_LINES+=("│ ${content} │")
        for ((column = 0; column < 3; column++)); do
            index=$((row * 3 + column))
            if (( index < ${#CLI_LABELS[@]} )); then
                register_control_hitbox "cli:$index" "${cells[$column]}"
            fi
        done
    done
    append_blank_line

    append_separator "Controls"
    if [ -n "$status_message" ]; then
        center_content "$status_message"
    else
        center_content "$CONTROLS_TEXT"
    fi
    PANEL_LINES+=("│${CENTERED_CONTENT}│")
    printf -v border '%*s' "$((PANEL_WIDTH - 2))" ""
    PANEL_LINES+=("└${border// /─}┘")
}
style_panel_line() {
    local line="$1"
    local line_index="$2"
    local title=""
    local body
    local before
    local after
    local is_border=0
    local focused
    local focus_style
    local disabled_field=""

    case "$line_index" in
        0)
            title="YONIQ Compute Setup"
            is_border=1
            ;;
        3)
            title="Selection"
            is_border=1
            ;;
        6)
            title="Install / Update Dependencies"
            is_border=1
            ;;
        12)
            title="CUDA Version"
            is_border=1
            ;;
        20)
            title="Python Version"
            is_border=1
            ;;
        27)
            title="Coding CLIs"
            is_border=1
            ;;
        35)
            title="Controls"
            is_border=1
            ;;
        37)
            is_border=1
            ;;
    esac

    if (( is_border )); then
        if [ -n "$title" ]; then
            before="${line%%"$title"*}"
            after="${line#*"$title"}"
            STYLED_LINE="${STYLE_BORDER}${before}${STYLE_TITLE}${title}${STYLE_BORDER}${after}${STYLE_RESET}"
        else
            STYLED_LINE="${STYLE_BORDER}${line}${STYLE_RESET}"
        fi
        return
    fi

    body="${line#│}"
    body="${body%│}"
    if (( line_index == 36 )); then
        if [ -n "$status_message" ]; then
            body="${STYLE_ALERT}${body}${STYLE_RESET}"
        else
            body="${STYLE_MUTED}${body}${STYLE_RESET}"
        fi
    elif (( line_index == 4 )) && install_defaults_selected; then
        body="${STYLE_MUTED}${body}${STYLE_RESET}"
    elif (( line_index == 5 || line_index == 16 || line_index == 17 || line_index == 18 || line_index == 25 )); then
        body="${STYLE_MUTED}${body}${STYLE_RESET}"
    else
        if [ -n "$FOCUSED_TEXT" ] && [[ "$body" == *"$FOCUSED_TEXT"* ]]; then
            before="${body%%"$FOCUSED_TEXT"*}"
            after="${body#*"$FOCUSED_TEXT"}"
            before="${before//"[X]"/${STYLE_SELECTED}[X]${STYLE_RESET}}"
            before="${before//"(x)"/${STYLE_SELECTED}(x)${STYLE_RESET}}"
            after="${after//"[X]"/${STYLE_SELECTED}[X]${STYLE_RESET}}"
            after="${after//"(x)"/${STYLE_SELECTED}(x)${STYLE_RESET}}"
            focused="${FOCUSED_TEXT/#>/›}"
            if (( FLASH_PHASE )); then
                focus_style="$STYLE_FOCUS_ALTERNATE"
            else
                focus_style="$STYLE_FOCUS_PRIMARY"
            fi
            body="${before}${focus_style}${focused}${STYLE_RESET}${after}"
        else
            body="${body//"[X]"/${STYLE_SELECTED}[X]${STYLE_RESET}}"
            body="${body//"(x)"/${STYLE_SELECTED}(x)${STYLE_RESET}}"
        fi
    fi
    if (( line_index == 14 )) && [ "$cuda_choice" != "custom" ]; then
        disabled_field="$CUDA_FIELD_BOX"
    elif (( line_index == 22 )) && [ "$python_choice" != "custom" ]; then
        disabled_field="$PYTHON_FIELD_BOX"
    fi
    if [ -n "$disabled_field" ] && [[ "$body" == *"$disabled_field"* ]]; then
        before="${body%%"$disabled_field"*}"
        after="${body#*"$disabled_field"}"
        body="${before}${STYLE_MUTED}${disabled_field}${STYLE_RESET}${after}"
    fi
    STYLED_LINE="${STYLE_BORDER}│${STYLE_RESET}${body}${STYLE_BORDER}│${STYLE_RESET}"
}


draw_screen() {
    local message
    local message_row
    local message_column
    local line_index
    local cursor_row
    local cursor_column
    local cursor_offset
    local buffer_length
    local clear_screen="${1:-1}"

    terminal_size
    if (( clear_screen )); then
        printf '\033[0m\033[?25l\033[2J\033[H' >&"$TTY_FD"
    else
        printf '\033[0m\033[?25l' >&"$TTY_FD"
    fi

    if (( terminal_columns < MIN_COLUMNS || terminal_rows < MIN_ROWS )); then
        terminal_too_small=1
        message="Terminal too small: need ${MIN_COLUMNS}x${MIN_ROWS}, have ${terminal_columns}x${terminal_rows}"
        message_row=$(( (terminal_rows + 1) / 2 ))
        message_column=$(( (terminal_columns - ${#message}) / 2 + 1 ))
        if (( message_row < 1 )); then
            message_row=1
        fi
        if (( message_column < 1 )); then
            message_column=1
        fi
        printf '\033[%d;%dH%s%s%s' \
            "$message_row" \
            "$message_column" \
            "$STYLE_ALERT" \
            "$message" \
            "$STYLE_RESET" >&"$TTY_FD"
        return
    fi

    terminal_too_small=0
    panel_top=$(( (terminal_rows - PANEL_HEIGHT) / 2 + 1 ))
    panel_left=$(( (terminal_columns - PANEL_WIDTH) / 2 + 1 ))
    build_panel
    for ((line_index = 0; line_index < ${#PANEL_LINES[@]}; line_index++)); do
        style_panel_line "${PANEL_LINES[$line_index]}" "$line_index"
        printf '\033[%d;%dH%s' \
            "$((panel_top + line_index))" \
            "$panel_left" \
            "$STYLED_LINE" >&"$TTY_FD"
    done

    if [ "$editing" = "cuda" ]; then
        buffer_length=${#cuda_buffer}
        cursor_offset=$buffer_length
        if (( cursor_offset > FIELD_WIDTH - 1 )); then
            cursor_offset=$((FIELD_WIDTH - 1))
        fi
        cursor_row=$((panel_top + 14))
        cursor_column=$((panel_left + 30 + cursor_offset))
        printf '\033[?25h\033[%d;%dH' "$cursor_row" "$cursor_column" >&"$TTY_FD"
    elif [ "$editing" = "python" ]; then
        buffer_length=${#python_buffer}
        cursor_offset=$buffer_length
        if (( cursor_offset > FIELD_WIDTH - 1 )); then
            cursor_offset=$((FIELD_WIDTH - 1))
        fi
        cursor_row=$((panel_top + 22))
        cursor_column=$((panel_left + 32 + cursor_offset))
        printf '\033[?25h\033[%d;%dH' "$cursor_row" "$cursor_column" >&"$TTY_FD"
    fi
}
version_at_least() {
    local major_value
    local minor_value
    local minimum_major_value
    local minimum_minor_value

    major_value=$((10#$1))
    minor_value=$((10#$2))
    minimum_major_value=$((10#$3))
    minimum_minor_value=$((10#$4))
    (( major_value > minimum_major_value ||
        (major_value == minimum_major_value && minor_value >= minimum_minor_value) ))
}

validate_cuda_versions() {
    local buffer="$1"
    local cuda_pattern='^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?(\.(0|[1-9][0-9]*))?$'
    local token
    local major
    local remainder
    local minor
    local stream
    local existing_stream
    local -a versions
    local -a streams=()

    CUDA_VERSION_ARGS=()
    if [ -z "$buffer" ] || [[ "$buffer" == ,* || "$buffer" == *, || "$buffer" == *,,* ]]; then
        status_message="Enter 1-10 comma-separated CUDA versions."
        return 1
    fi

    IFS=',' read -r -a versions <<<"$buffer"
    if (( ${#versions[@]} < 1 || ${#versions[@]} > 10 )); then
        status_message="Enter 1-10 comma-separated CUDA versions."
        return 1
    fi

    for token in "${versions[@]}"; do
        if (( ${#token} > 16 )); then
            status_message="CUDA version entries are limited to 16 characters."
            return 1
        fi
        if [[ ! "$token" =~ $cuda_pattern ]]; then
            status_message="Invalid CUDA version: $token."
            return 1
        fi

        major="${token%%.*}"
        remainder="${token#*.}"
        minor="0"
        if [ "$remainder" != "$token" ]; then
            minor="${remainder%%.*}"
        fi
        if ! version_at_least "$major" "$minor" 12 8; then
            status_message="CUDA versions must be 12.8 or newer: $token."
            return 1
        fi

        stream="$((10#$major)).$((10#$minor))"
        for existing_stream in "${streams[@]}"; do
            if [ "$existing_stream" = "$stream" ]; then
                status_message="CUDA major.minor streams must be unique: $stream."
                return 1
            fi
        done
        streams+=("$stream")
    done

    CUDA_VERSION_ARGS=("${versions[@]}")
    status_message=""
    return 0
}

validate_python_version() {
    local buffer="$1"
    local python_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    local major
    local remainder
    local minor

    if [[ ! "$buffer" =~ $python_pattern ]]; then
        status_message="Python must be major.minor.patch, for example 3.11.16."
        return 1
    fi

    major="${buffer%%.*}"
    remainder="${buffer#*.}"
    minor="${remainder%%.*}"
    if ! version_at_least "$major" "$minor" 3 11; then
        status_message="Python version must be 3.11 or newer."
        return 1
    fi

    status_message=""
    return 0
}

read_sgr_mouse_event() {
    local payload=""
    local byte=""
    local mouse_pattern='^([0-9]+);([0-9]+);([0-9]+)([Mm])$'

    while (( ${#payload} < 32 )); do
        if ! IFS= read -r -s -n 1 -t 0.05 -u "$TTY_FD" byte; then
            if (( WINCH_PENDING )); then
                KEY="resize"
                return 0
            fi
            return 1
        fi
        payload+="$byte"
        if [ "$byte" = "M" ] || [ "$byte" = "m" ]; then
            break
        fi
    done

    if [[ ! "$payload" =~ $mouse_pattern ]]; then
        return 1
    fi

    MOUSE_BUTTON=$((10#${BASH_REMATCH[1]}))
    MOUSE_COLUMN=$((10#${BASH_REMATCH[2]}))
    MOUSE_ROW=$((10#${BASH_REMATCH[3]}))
    if (( MOUSE_COLUMN < 1 || MOUSE_ROW < 1 )); then
        return 1
    fi

    if [ "${BASH_REMATCH[4]}" = "M" ] &&
       (( (MOUSE_BUTTON & 3) == 0 &&
          (MOUSE_BUTTON & 32) == 0 &&
          (MOUSE_BUTTON & 64) == 0 )); then
        KEY="mouse"
    else
        KEY="mouse_ignore"
    fi
    return 0
}

read_key() {
    local byte=""
    local second=""
    local third=""
    local read_status=0

    KEY=""
    KEY_CHAR=""
    MOUSE_CONTROL=""
    if (( WINCH_PENDING )); then
        KEY="resize"
        return 0
    fi

    while true; do
        read_status=0
        IFS= read -r -s -n 1 -t 0.1 -u "$TTY_FD" byte || read_status=$?
        if (( read_status == 0 )); then
            FLASH_TIMEOUT_COUNT=0
            break
        fi
        if (( WINCH_PENDING )); then
            KEY="resize"
            return 0
        fi
        if (( read_status > 128 )); then
            if (( FLASH_ENABLED )); then
                FLASH_TIMEOUT_COUNT=$((FLASH_TIMEOUT_COUNT + 1))
                if (( FLASH_TIMEOUT_COUNT >= FLASH_INTERVAL_TICKS )); then
                    FLASH_TIMEOUT_COUNT=0
                    KEY="flash"
                    return 0
                fi
            fi
            continue
        fi
        return 1
    done

    case "$byte" in
        "")
            KEY="enter"
            ;;
        $'\r')
            KEY="enter"
            ;;
        $'\t')
            KEY="next"
            ;;
        " ")
            KEY="space"
            ;;
        $'\177'|$'\b')
            KEY="backspace"
            ;;
        $'\033')
            if ! IFS= read -r -s -n 1 -t 0.04 -u "$TTY_FD" second; then
                if (( WINCH_PENDING )); then
                    KEY="resize"
                else
                    KEY="escape"
                fi
                return 0
            fi
            if (( WINCH_PENDING )); then
                KEY="resize"
                return 0
            fi
            if [ "$second" != "[" ] && [ "$second" != "O" ]; then
                KEY="unknown"
                return 0
            fi
            if ! IFS= read -r -s -n 1 -t 0.01 -u "$TTY_FD" third; then
                if (( WINCH_PENDING )); then
                    KEY="resize"
                else
                    KEY="unknown"
                fi
                return 0
            fi
            if [ "$second$third" = "[<" ]; then
                if ! read_sgr_mouse_event; then
                    KEY="unknown"
                fi
                return 0
            fi
            case "$second$third" in
                "[A"|"OA") KEY="previous" ;;
                "[B"|"OB") KEY="next" ;;
                "[C"|"OC") KEY="next" ;;
                "[D"|"OD") KEY="previous" ;;
                "[Z") KEY="previous" ;;
                *) KEY="unknown" ;;
            esac
            ;;
        *)
            KEY="character"
            KEY_CHAR="$byte"
            ;;
    esac
    return 0
}

move_focus() {
    local direction="$1"
    local control_count=${#FOCUS_CONTROLS[@]}

    while true; do
        if [ "$direction" = "next" ]; then
            focus_index=$(( (focus_index + 1) % control_count ))
        else
            focus_index=$(( (focus_index - 1 + control_count) % control_count ))
        fi
        if control_is_enabled "${FOCUS_CONTROLS[$focus_index]}"; then
            break
        fi
    done
    FLASH_PHASE=0
    FLASH_TIMEOUT_COUNT=0
    status_message=""
}
append_version_character() {
    local kind="$1"
    local character="$2"
    local buffer
    local max_length
    local invalid_message
    local length_message

    if [ "$kind" = "cuda" ]; then
        buffer="$cuda_buffer"
        max_length=169
        invalid_message="Invalid CUDA character; use digits, dots, and commas only."
        length_message="CUDA input is limited to 169 characters."
    else
        buffer="$python_buffer"
        max_length=16
        invalid_message="Invalid Python character; use digits and dots only."
        length_message="Python input is limited to 16 characters."
    fi

    case "$character" in
        [0-9])
            ;;
        ".")
            if [[ "$buffer" != *[0-9] ]]; then
                status_message="Enter a digit before a dot; consecutive dots are not allowed."
                return
            fi
            ;;
        ",")
            if [ "$kind" != "cuda" ]; then
                status_message="$invalid_message"
                return
            fi
            if [[ "$buffer" != *[0-9] ]]; then
                status_message="Enter a CUDA version before a comma; consecutive separators are not allowed."
                return
            fi
            ;;
        *)
            status_message="$invalid_message"
            return
            ;;
    esac

    if (( ${#buffer} >= max_length )); then
        status_message="$length_message"
        return
    fi
    if [ "$kind" = "cuda" ]; then
        cuda_buffer+="$character"
    else
        python_buffer+="$character"
    fi
    status_message=""
}


edit_version() {
    local kind="$1"
    local saved_choice="$2"
    local saved_buffer="$3"
    local current_buffer

    editing="$kind"
    if [ "$kind" = "cuda" ]; then
        cuda_choice="custom"
    else
        python_choice="custom"
    fi
    draw_screen

    while true; do
        if ! read_key; then
            editing=""
            return 2
        fi

        if [ "$KEY" = "resize" ]; then
            WINCH_PENDING=0
            draw_screen
            continue
        fi
        if [ "$KEY" = "flash" ]; then
            FLASH_PHASE=$((1 - FLASH_PHASE))
            if (( ! terminal_too_small )); then
                draw_screen 0
            fi
            continue
        fi

        if (( terminal_too_small )); then
            if [ "$KEY" = "escape" ] || { [ "$KEY" = "character" ] && [ "$KEY_CHAR" = "q" ]; }; then
                editing=""
                return 3
            fi
            draw_screen
            continue
        fi

        case "$KEY" in
            mouse)
                if focus_mouse_control && [ "$MOUSE_CONTROL" != "${kind}_field" ]; then
                    if [ "$MOUSE_CONTROL" = "${kind}_default" ] ||
                       [ "$MOUSE_CONTROL" = "install_defaults" ]; then
                        editing=""
                        status_message=""
                        activate_focused "mouse"
                        return $?
                    fi

                    if [ "$kind" = "cuda" ]; then
                        current_buffer="$cuda_buffer"
                    else
                        current_buffer="$python_buffer"
                    fi

                    if [ -z "$current_buffer" ]; then
                        if [ "$kind" = "cuda" ]; then
                            cuda_choice="default"
                        else
                            python_choice="default"
                        fi
                        editing=""
                        status_message=""
                        if [ "$MOUSE_CONTROL" = "${kind}_custom" ]; then
                            return 0
                        fi
                    elif [ "$kind" = "cuda" ]; then
                        if validate_cuda_versions "$cuda_buffer"; then
                            editing=""
                        else
                            set_focus_control "cuda_field"
                        fi
                    elif validate_python_version "$python_buffer"; then
                        editing=""
                    else
                        set_focus_control "python_field"
                    fi

                    if [ -z "$editing" ]; then
                        if [ "$MOUSE_CONTROL" = "cuda_field" ]; then
                            kind="cuda"
                            saved_choice="$cuda_choice"
                            saved_buffer="$cuda_buffer"
                            cuda_choice="custom"
                            editing="$kind"
                        elif [ "$MOUSE_CONTROL" = "python_field" ]; then
                            kind="python"
                            saved_choice="$python_choice"
                            saved_buffer="$python_buffer"
                            python_choice="custom"
                            editing="$kind"
                        else
                            activate_focused "mouse"
                            return $?
                        fi
                    fi
                fi
                ;;
            mouse_ignore)
                continue
                ;;
            escape)
                if [ "$kind" = "cuda" ]; then
                    cuda_choice="$saved_choice"
                    cuda_buffer="$saved_buffer"
                else
                    python_choice="$saved_choice"
                    python_buffer="$saved_buffer"
                fi
                editing=""
                status_message=""
                return 0
                ;;
            enter)
                if [ "$kind" = "cuda" ]; then
                    if validate_cuda_versions "$cuda_buffer"; then
                        editing=""
                        return 0
                    fi
                elif validate_python_version "$python_buffer"; then
                    editing=""
                    return 0
                fi
                ;;
            backspace)
                if [ "$kind" = "cuda" ]; then
                    cuda_buffer="${cuda_buffer%?}"
                else
                    python_buffer="${python_buffer%?}"
                fi
                status_message=""
                ;;
            character)
                append_version_character "$kind" "$KEY_CHAR"
                ;;
            *)
                if [ "$kind" = "cuda" ]; then
                    status_message="Invalid CUDA character; use digits, dots, and commas only."
                else
                    status_message="Invalid Python character; use digits and dots only."
                fi
                ;;
        esac
        draw_screen
    done
}


select_install_defaults() {
    local index

    for ((index = 0; index < ${#DEPENDENCY_SELECTED[@]}; index++)); do
        DEPENDENCY_SELECTED[index]=1
    done
    for ((index = 0; index < ${#CLI_SELECTED[@]}; index++)); do
        CLI_SELECTED[index]=1
    done
    ASTRAL_UV_SELECTED=1
    cuda_choice="default"
    cuda_buffer=""
    python_choice="default"
    python_buffer=""
}

refresh_runtime_paths() {
    local candidate
    local path_entry
    local path_contains_candidate
    local -a candidates=()
    local -a path_entries=()

    if [ -n "${PNPM_HOME:-}" ]; then
        candidates+=("$PNPM_HOME")
    fi
    if [ -n "${HOME:-}" ] && [ "${PNPM_HOME:-}" != "$HOME/.local/share/pnpm" ]; then
        candidates+=("$HOME/.local/share/pnpm")
    fi

    for candidate in "${candidates[@]}"; do
        if [ ! -d "$candidate" ] || [ ! -x "$candidate/pnpm" ]; then
            continue
        fi

        PNPM_HOME="$candidate"
        export PNPM_HOME
        path_contains_candidate=0
        IFS=':' read -r -a path_entries <<<"${PATH:-}"
        for path_entry in "${path_entries[@]}"; do
            if [ "$path_entry" = "$candidate" ]; then
                path_contains_candidate=1
                break
            fi
        done
        if (( ! path_contains_candidate )); then
            PATH="$candidate${PATH:+:$PATH}"
            export PATH
        fi
        return
    done
}

run_command() {
    local step_label="$1"
    local script_path="$2"
    local script_name="${2##*/}"
    local status

    shift 2
    printf '%s' "$step_label"
    printf ' %q' /bin/bash "$script_path" "$@"
    printf '\n'
    if /bin/bash "$script_path" "$@"; then
        return 0
    else
        status=$?
    fi

    printf 'Error: %s failed with status %d.\n' "$script_name" "$status" >&2
    return "$status"
}

perform_installation() {
    local edit_status
    local index
    local cli_selected_count=0
    local -a dependency_args=(-y)
    local -a cuda_args=(-y)
    local -a python_args=(-y)
    local -a cli_args=(-y)

    if [ "$cuda_choice" = "custom" ] && ! validate_cuda_versions "$cuda_buffer"; then
        set_focus_control "cuda_field"
        FLASH_PHASE=0
        FLASH_TIMEOUT_COUNT=0
        edit_version "cuda" "$cuda_choice" "$cuda_buffer"
        edit_status=$?
        if (( edit_status == 2 )); then
            terminal_input_closed
            return 1
        fi
        if (( edit_status == 3 )); then
            cancel_installation
            return 0
        fi
        return 1
    fi
    if [ "$python_choice" = "custom" ] && ! validate_python_version "$python_buffer"; then
        set_focus_control "python_field"
        FLASH_PHASE=0
        FLASH_TIMEOUT_COUNT=0
        edit_version "python" "$python_choice" "$python_buffer"
        edit_status=$?
        if (( edit_status == 2 )); then
            terminal_input_closed
            return 1
        fi
        if (( edit_status == 3 )); then
            cancel_installation
            return 0
        fi
        return 1
    fi

    if all_dependencies_selected; then
        dependency_args+=("--all")
    else
        for ((index = 0; index < ${#DEPENDENCY_SELECTED[@]}; index++)); do
            if (( DEPENDENCY_SELECTED[index] )); then
                dependency_args+=("${DEPENDENCY_FLAGS[$index]}")
            fi
        done
    fi

    if [ "$cuda_choice" = "default" ]; then
        cuda_args+=("$CUDA_DEFAULT_VERSION" "-d")
    else
        cuda_args+=("${CUDA_VERSION_ARGS[0]}" "-d")
        for ((index = 1; index < ${#CUDA_VERSION_ARGS[@]}; index++)); do
            cuda_args+=("${CUDA_VERSION_ARGS[$index]}")
        done
    fi

    if (( ASTRAL_UV_SELECTED )); then
        python_args+=("--uv")
    fi
    if [ "$python_choice" = "default" ]; then
        python_args+=("$PYTHON_DEFAULT_VERSION")
    else
        python_args+=("$python_buffer")
    fi

    for ((index = 0; index < ${#CLI_SELECTED[@]}; index++)); do
        if (( CLI_SELECTED[index] )); then
            cli_selected_count=$((cli_selected_count + 1))
        fi
    done
    if (( cli_selected_count == ${#CLI_SELECTED[@]} )); then
        cli_args+=("--all")
    elif (( cli_selected_count > 0 )); then
        for ((index = 0; index < ${#CLI_SELECTED[@]}; index++)); do
            if (( CLI_SELECTED[index] )); then
                cli_args+=("${CLI_FLAGS[$index]}")
            fi
        done
    fi

    leave_tui
    run_command "[1/4]" "$DEPENDENCY_INSTALLER" "${dependency_args[@]}" || return $?
    run_command "[2/4]" "$CUDA_INSTALLER" "${cuda_args[@]}" || return $?
    run_command "[3/4]" "$PYTHON_INSTALLER" "${python_args[@]}" || return $?

    refresh_runtime_paths
    if (( cli_selected_count == 0 )); then
        printf '[4/4] Skipping coding CLIs (none selected)\n'
    else
        run_command "[4/4]" "$CLI_INSTALLER" "${cli_args[@]}" || return $?
    fi

    printf 'Installation complete.\n'
    printf 'A system reboot is recommended before using the installed environment.\n'
    return 0
}


activate_focused() {
    local control="${FOCUS_CONTROLS[$focus_index]}"
    local index

    if ! control_is_enabled "$control"; then
        return 0
    fi

    status_message=""
    case "$control" in
        install)
            perform_installation
            ;;
        cancel)
            return 3
            ;;
        install_defaults)
            if ! install_defaults_selected; then
                select_install_defaults
            fi
            ;;
        dependency:*)
            index="${control#dependency:}"
            DEPENDENCY_SELECTED[index]=$((1 - DEPENDENCY_SELECTED[index]))
            ;;
        cuda_default)
            cuda_choice="default"
            cuda_buffer=""
            ;;
        cuda_custom)
            cuda_choice="custom"
            ;;
        cuda_field)
            edit_version "cuda" "$cuda_choice" "$cuda_buffer"
            ;;
        python_default)
            python_choice="default"
            python_buffer=""
            ;;
        python_custom)
            python_choice="custom"
            ;;
        python_field)
            edit_version "python" "$python_choice" "$python_buffer"
            ;;
        astral_uv)
            ASTRAL_UV_SELECTED=$((1 - ASTRAL_UV_SELECTED))
            ;;
        cli:*)
            index="${control#cli:}"
            CLI_SELECTED[index]=$((1 - CLI_SELECTED[index]))
            ;;
    esac
}




leave_tui() {
    trap - EXIT
    trap '' INT TERM HUP WINCH
    if (( TUI_ACTIVE )); then
        if [ -n "$SAVED_STTY" ]; then
            stty "$SAVED_STTY" <&"$TTY_FD" 2>/dev/null || true
        fi
        printf '\033[0m\033[?1000l\033[?1006l\033[?25h\033[?1049l' >&"$TTY_FD"
        TUI_ACTIVE=0
    fi

    if (( TTY_OPEN )); then
        exec 8>&-
        TTY_OPEN=0
    fi

    trap - INT TERM HUP WINCH
}

handle_signal() {
    local status="$1"

    leave_tui
    exit "$status"
}

enter_tui() {
    if ! SAVED_STTY="$(stty -g <&"$TTY_FD" 2>/dev/null)" || [ -z "$SAVED_STTY" ]; then
        if (( TTY_OPEN )); then
            exec 8>&-
            TTY_OPEN=0
        fi
        printf 'Error: an interactive VT100-compatible terminal is required.\n' >&2
        return 1
    fi

    TUI_ACTIVE=1
    trap 'leave_tui' EXIT
    trap 'handle_signal 130' INT
    trap 'handle_signal 143' TERM
    trap 'handle_signal 129' HUP
    trap 'WINCH_PENDING=1' WINCH

    if ! stty -echo -icanon min 1 time 0 <&"$TTY_FD" 2>/dev/null; then
        leave_tui
        printf 'Error: an interactive VT100-compatible terminal is required.\n' >&2
        return 1
    fi

    printf '\033[?1049h\033[?1006h\033[?1000h\033[2J\033[H\033[?25l' >&"$TTY_FD"
}
cancel_installation() {
    leave_tui
    printf 'Installation cancelled.\n'
    return 0
}

terminal_input_closed() {
    leave_tui
    printf 'Error: terminal input closed.\n' >&2
    return 1
}

run_tui() {
    local activation_status

    draw_screen
    while true; do
        if ! read_key; then
            terminal_input_closed
            return 1
        fi

        if [ "$KEY" = "resize" ]; then
            WINCH_PENDING=0
            draw_screen
            continue
        fi
        if [ "$KEY" = "flash" ]; then
            FLASH_PHASE=$((1 - FLASH_PHASE))
            if (( ! terminal_too_small )); then
                draw_screen 0
            fi
            continue
        fi

        if (( terminal_too_small )); then
            if [ "$KEY" = "escape" ] || { [ "$KEY" = "character" ] && [ "$KEY_CHAR" = "q" ]; }; then
                cancel_installation
                return 0
            fi
            draw_screen
            continue
        fi

        case "$KEY" in
            mouse)
                if focus_mouse_control; then
                    activate_focused "mouse"
                    activation_status=$?
                    if (( activation_status == 2 )); then
                        terminal_input_closed
                        return 1
                    fi
                    if (( activation_status == 3 )); then
                        cancel_installation
                        return 0
                    fi
                    if (( ! TUI_ACTIVE )); then
                        return "$activation_status"
                    fi
                fi
                ;;
            mouse_ignore)
                continue
                ;;
            next)
                move_focus "next"
                ;;
            previous)
                move_focus "previous"
                ;;
            space|enter)
                activate_focused "$KEY"
                activation_status=$?
                if (( activation_status == 2 )); then
                    terminal_input_closed
                    return 1
                fi
                if (( activation_status == 3 )); then
                    cancel_installation
                    return 0
                fi
                if (( ! TUI_ACTIVE )); then
                    return "$activation_status"
                fi
                ;;
            escape)
                cancel_installation
                return 0
                ;;
            character)
                case "$KEY_CHAR" in
                    i)
                        perform_installation
                        activation_status=$?
                        if (( ! TUI_ACTIVE )); then
                            return "$activation_status"
                        fi
                        ;;
                    q)
                        cancel_installation
                        return 0
                        ;;
                esac
                ;;
        esac
        draw_screen
    done
}


if ! enter_tui; then
    exit 1
fi
run_tui
exit $?
