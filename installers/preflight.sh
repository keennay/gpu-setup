#!/bin/bash
# Shared checks only: sourcing this file does not install or configure anything.

preflight_init() {
    PREFLIGHT_LABEL="$1"
    PREFLIGHT_ERRORS=()
    PREFLIGHT_DEFERRED=()
    printf '\nPreflight: %s\n' "$PREFLIGHT_LABEL"
}

preflight_info() {
    printf '  [OK] %s\n' "$1"
}

preflight_error() {
    PREFLIGHT_ERRORS+=("$1")
    printf '  [BLOCKED] %s\n' "$1" >&2
}

preflight_defer() {
    PREFLIGHT_DEFERRED+=("$1")
    printf '  [DEFERRED] %s\n' "$1"
    if [ -n "${SETUP_PREFLIGHT_DEFERRED_FILE:-}" ]; then
        if ! printf '%s\n' "$1" >> "$SETUP_PREFLIGHT_DEFERRED_FILE"; then
            preflight_error "Could not record the deferred check for setup"
            return 1
        fi
    fi
}

preflight_finish() {
    local message
    if (( ${#PREFLIGHT_ERRORS[@]} )); then
        printf '\n%s preflight: %d blocker(s)\n' "$PREFLIGHT_LABEL" "${#PREFLIGHT_ERRORS[@]}" >&2
        for message in "${PREFLIGHT_ERRORS[@]}"; do
            printf '  - %s\n' "$message" >&2
        done
        return 1
    fi
    if (( ${#PREFLIGHT_DEFERRED[@]} )); then
        printf '%s preflight: no known blockers; %d check(s) require the planned core tools.\n' \
            "$PREFLIGHT_LABEL" "${#PREFLIGHT_DEFERRED[@]}"
    else
        printf '%s preflight: passed.\n' "$PREFLIGHT_LABEL"
    fi
}

preflight_command() {
    local command_name="$1"
    local planned="${2:-0}"
    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi
    if [ "$planned" = 1 ]; then
        preflight_info "$command_name will be installed by an earlier selected step"
        return 0
    fi
    preflight_error "Required command is missing and not scheduled for installation: $command_name"
    return 1
}

preflight_writable() {
    local target="$1"
    local parent="$1"
    if [ -z "$target" ]; then
        preflight_error "An installation destination is empty"
        return 1
    fi
    while [ ! -e "$parent" ] && [ ! -L "$parent" ]; do
        parent=$(dirname -- "$parent")
    done
    if [ "$parent" != "$target" ] && [ ! -d "$parent" ]; then
        preflight_error "Installation destination has a non-directory parent: $target ($parent)"
        return 1
    fi
    if [ ! -w "$parent" ]; then
        preflight_error "Installation destination is not writable: $target (existing path: $parent)"
        return 1
    fi
}

preflight_privileges() {
    if (( EUID == 0 )); then
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true 2>/dev/null; then
        preflight_error "System installation requires root or working sudo access (authenticate with sudo -v)"
        return 1
    fi
}

preflight_can_fetch() {
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1
}

preflight_fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 60 -- "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=30 --tries=1 -- "$1"
    else
        printf 'Cannot retrieve metadata without curl or wget: %s\n' "$1" >&2
        return 1
    fi
}

# Probe alternatives without recording a blocker until every candidate fails.
preflight_probe_url() {
    local url="$1"
    local http_status result
    if command -v curl >/dev/null 2>&1; then
        if http_status=$(curl -fsSLI --connect-timeout 10 --max-time 60 -o /dev/null -w '%{http_code}' -- "$url" 2>/dev/null); then
            return 0
        fi
        # Some servers support GET but not HEAD. Keep the fallback bounded.
        if [ "$http_status" = 405 ] || [ "$http_status" = 501 ]; then
            result=0
            http_status=$(curl -fsSL --range 0-0 --max-filesize 1048576 \
                --connect-timeout 10 --max-time 60 -o /dev/null -w '%{http_code}' -- "$url" 2>/dev/null) || result=$?
            if (( result == 0 )) || { (( result == 63 )) && [[ "$http_status" = 2?? ]]; }; then
                return 0
            fi
        fi
    elif command -v wget >/dev/null 2>&1 && wget --spider -q --timeout=30 --tries=1 -- "$url"; then
        return 0
    fi
    return 1
}

preflight_url() {
    local label="$1"
    local url="$2"
    if ! preflight_can_fetch; then
        if [ "${SETUP_PLANNED_CORE:-0}" = 1 ]; then
            preflight_defer "$label: source check requires curl/wget from the core dependency step ($url)"
            return 0
        fi
        preflight_error "$label: cannot check source without curl or wget ($url)"
        return 1
    fi

    if preflight_probe_url "$url"; then
        preflight_info "$label source is reachable"
        return 0
    fi
    preflight_error "$label: source is unavailable or could not be checked; verify the URL/network before retrying ($url)"
    return 1
}
