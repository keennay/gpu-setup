#!/bin/bash
# Script: 02_install_cuda.sh
# Purpose: Check and install CUDA/NVIDIA dependencies for ML environment
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_command() { echo -e "${BLUE}[RUN]${NC} $1"; }

is_valid_cuda_version_arg() {
    [[ "$1" =~ ^[0-9]+$ || "$1" =~ ^[0-9]+\.[0-9]+$ || "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]]
}
cuda_version_stream() {
    local version="$1"
    local major="${version%%.*}"
    local remainder="${version#*.}"
    local minor="0"

    if [ "$remainder" != "$version" ]; then
        minor="${remainder%%.*}"
    fi

    printf '%s.%s\n' "$major" "$minor"
}
cuda_normalize_requested_version() {
    local version="$1"
    if [[ "$version" =~ ^[0-9]+$ ]]; then
        version="${version}.0"
    fi
    printf '%s\n' "$version"
}

cuda_requested_version_is_exact() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]]
}


cuda_installed_version_matches_request() {
    local requested_version
    local requested_base
    local installed_version

    requested_version=$(cuda_normalize_requested_version "$1")
    requested_base="${requested_version%%-*}"

    # A release-qualified request cannot be proven from the installed toolkit
    # inventory, which records toolkit versions but not package release suffixes.
    if [[ "$requested_version" == *-* ]]; then
        return 1
    fi

    for installed_version in "${INSTALLED_CUDA_VERSIONS[@]}"; do
        if cuda_requested_version_is_exact "$requested_version"; then
            [ "$installed_version" = "$requested_base" ] && return 0
        elif [ "$(cuda_version_stream "$installed_version")" = "$(cuda_version_stream "$requested_version")" ]; then
            return 0
        fi
    done

    return 1
}



CUDA_CACHE_DIR="$(mktemp -d /tmp/cuda-cache.XXXXXX)"
if [ -z "$CUDA_CACHE_DIR" ] || [ ! -d "$CUDA_CACHE_DIR" ]; then
    print_error "Could not create temporary CUDA download directory under /tmp"
    exit 1
fi
cleanup_cuda_cache() {
    if [[ "$CUDA_CACHE_DIR" == /tmp/cuda-cache.* ]] && [ -d "$CUDA_CACHE_DIR" ]; then
        rm -rf "$CUDA_CACHE_DIR"
    fi
}
trap cleanup_cuda_cache EXIT
CUDA_PACKAGE_DOWNLOADS=()
CONFIGURED_UBUNTU_CUDA_REPOS=()
INSTALLED_CUDA_VERSIONS=()
INSTALLED_CUDA_VERSIONS_DISPLAY="None"
CUDA_DEFAULT_CANDIDATE_VERSIONS=()
CUDA_DEFAULT_CANDIDATE_DIRS=()
PREINSTALL_CUDA_DEFAULT_VERSION=""
SUDO_PREFIX=""
PREFLIGHT_MODE=false
CUDA_PREFLIGHT_OS_SUPPORTED=false
CUDA_PREFLIGHT_FETCH_AVAILABLE=false
CUDA_PREFLIGHT_PARSER_AVAILABLE=true
declare -A CUDA_PREFLIGHT_UBUNTU_STATUS
declare -A CUDA_PREFLIGHT_UBUNTU_PACKAGES
declare -A CUDA_PREFLIGHT_RHEL_STATUS
declare -A CUDA_PREFLIGHT_RHEL_PRIMARY_FILES
declare -A CUDA_PREFLIGHT_RHEL_PRIMARY_URLS
declare -a CUDA_PREFLIGHT_SUCCESSFUL_STREAMS=()
declare -a CUDA_PREFLIGHT_REQUESTED_VERSIONS=()

# Detect the highest CUDA toolkit package stream available in the provided repositories
detect_latest_cuda_version() {
    local repo_list=("$@")
    local version_candidates=""

    if ! command -v curl &> /dev/null; then
        echo ""
        return 1
    fi

    for repo in "${repo_list[@]}"; do
        if [ -z "$repo" ]; then
            continue
        fi

        if [ "$OS_TYPE" = "ubuntu" ]; then
            local packages_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/Packages"
            version_candidates=$(curl -fsSL "$packages_url" 2>/dev/null | \
                grep -oP '^Package: cuda-toolkit-\K[0-9]+-[0-9]+$' | \
                tr '-' '.' | \
                sort -V | uniq)
        elif [ "$OS_TYPE" = "rhel" ]; then
            local primary_url
            primary_url=$(get_rhel_primary_url "$repo")
            if [ -z "$primary_url" ]; then
                continue
            fi
            version_candidates=$(curl -fsSL "$primary_url" 2>/dev/null | \
                gzip -dc 2>/dev/null | \
                grep -oP '<name>cuda-toolkit-\K[0-9]+-[0-9]+(?=</name>)' | \
                tr '-' '.' | \
                sort -V | uniq)
        fi

        if [ -n "$version_candidates" ]; then
            echo "$version_candidates" | tail -1
            return 0
        fi
    done

    echo ""
    return 1
}

get_rhel_primary_url() {
    local repo="$1"
    local repomd_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/repodata/repomd.xml"
    local primary_rel

    primary_rel=$(curl -fsSL "$repomd_url" 2>/dev/null | awk '
        BEGIN { RS="</data>" }
        /<data type="primary">/ {
            if (match($0, /location href="[^"]+"/)) {
                rel = substr($0, RSTART, RLENGTH)
                sub(/^.*href="/, "", rel)
                sub(/"$/, "", rel)
                print rel
                exit
            }
        }
    ')

    if [ -z "$primary_rel" ]; then
        echo ""
        return 1
    fi

    echo "https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/${primary_rel}"
    return 0
}

setup_ubuntu_cuda_repo() {
    local repo="$1"
    local packages_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/Packages"
    local keyring_filename
    local keyring_path
    local keyring_basename
    local keyring_file
    local keyring_url
    local configured_repo

    for configured_repo in "${CONFIGURED_UBUNTU_CUDA_REPOS[@]}"; do
        if [ "$configured_repo" = "$repo" ]; then
            return 0
        fi
    done


    keyring_filename=$(curl -fsSL "$packages_url" 2>/dev/null | awk '
        $1 == "Package:" && $2 == "cuda-keyring" { pkgmatch=1; next }
        pkgmatch && $1 == "Filename:" { print $2; exit }
        pkgmatch && $0 == "" { pkgmatch=0 }
    ')

    if [ -z "$keyring_filename" ]; then
        print_warning "Could not determine cuda-keyring package for $repo"
        return 1
    fi

    keyring_path=${keyring_filename#./}
    keyring_basename=$(basename "$keyring_filename")
    keyring_file="${CUDA_CACHE_DIR}/${repo}-${keyring_basename}"
    keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/${keyring_path}"

    if [ ! -f "$keyring_file" ]; then
        print_info "Downloading CUDA repository keyring from NVIDIA..."
        if wget -O "$keyring_file" "$keyring_url"; then
            CUDA_PACKAGE_DOWNLOADS+=("$keyring_file")
        else
            print_warning "Failed to download $keyring_url"
            rm -f "$keyring_file"
            return 1
        fi
    else
        print_info "Using temporary CUDA repository keyring: $keyring_file"
    fi

    print_info "Configuring NVIDIA CUDA APT repository for $repo..."
    if ! ${SUDO_PREFIX}dpkg -i "$keyring_file"; then
        print_warning "Failed to install CUDA repository keyring from $keyring_file"
        return 1
    fi

    print_info "Updating package index before CUDA installation..."
    if ! $PKG_UPDATE_CMD; then
        print_warning "Package index update failed after enabling NVIDIA CUDA repository"
        return 1
    fi
    CONFIGURED_UBUNTU_CUDA_REPOS+=("$repo")

    return 0
}

ubuntu_package_candidate_version() {
    local package_name="$1"
    local candidate repository
    local candidates=()

    candidate=$(apt-cache policy "$package_name" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
    if [ -n "$candidate" ] && [ "$candidate" != "(none)" ]; then
        candidates+=("$candidate")
    fi
    if [ "$PREFLIGHT_MODE" = true ]; then
        # Include repositories the selected toolkit installation will configure,
        # without adding them to APT merely to inspect driver availability.
        for repository in "${CUDA_REPO_VERSIONS[@]}"; do
            if [ "${CUDA_PREFLIGHT_UBUNTU_STATUS[$repository]:-}" = ok ]; then
                candidate=$(cuda_preflight_find_ubuntu_candidate \
                    "${CUDA_PREFLIGHT_UBUNTU_PACKAGES[$repository]}" "$package_name" "")
                [ -z "$candidate" ] || candidates+=("$candidate")
            fi
        done
    fi
    printf '%s\n' "${candidates[@]}" | sort -V | tail -1
}

resolve_ubuntu_driver_package() {
    local cuda_stream="$1"

    if ! command -v apt-cache &> /dev/null; then
        echo ""
        return 1
    fi

    local latest_driver_package
    for latest_driver_package in "nvidia-open" "nvidia-driver-open" "cuda-drivers" "nvidia-driver"; do
        local latest_driver_candidate
        latest_driver_candidate=$(ubuntu_package_candidate_version "$latest_driver_package")
        if [ -n "$latest_driver_candidate" ] && [ "$latest_driver_candidate" != "(none)" ]; then
            echo "$latest_driver_package"
            return 0
        fi
    done

    print_warning "Generic latest NVIDIA driver packages were not found in APT metadata; trying CUDA stream-specific packages." >&2

    local driver_branch=""
    if [ -n "$cuda_stream" ]; then
        local runtime_package="cuda-runtime-$(echo "$cuda_stream" | sed 's/\./-/g')"
        driver_branch=$(apt-cache depends "$runtime_package" 2>/dev/null | awk '
            $1 == "Depends:" {
                if ($2 == "libnvidia-compute") {
                    print "generic"
                    exit
                }
                if ($2 ~ /^libnvidia-compute-[0-9]+$/) {
                    sub(/^libnvidia-compute-/, "", $2)
                    print $2
                    exit
                }
            }
        ')
    fi

    if [ -n "$driver_branch" ] && [ "$driver_branch" != "generic" ]; then
        local versioned_driver_package
        for versioned_driver_package in "nvidia-driver-${driver_branch}-open" "cuda-drivers-${driver_branch}" "nvidia-driver-${driver_branch}"; do
            local versioned_driver_candidate
            versioned_driver_candidate=$(ubuntu_package_candidate_version "$versioned_driver_package")
            if [ -n "$versioned_driver_candidate" ] && [ "$versioned_driver_candidate" != "(none)" ]; then
                echo "$versioned_driver_package"
                return 0
            fi
        done
    fi

    echo ""
    return 1
}

resolve_rhel_driver_package() {
    local version_major
    version_major=$(echo "$OS_VERSION_ID" | cut -d. -f1)
    version_major=${version_major:-9}

    local repo_candidates=("rhel${version_major}")
    if [ "$version_major" -gt 8 ]; then
        repo_candidates+=("rhel8")
    fi

    local repo
    for repo in "${repo_candidates[@]}"; do
        local primary_url
        primary_url=$(get_rhel_primary_url "$repo")
        if [ -z "$primary_url" ]; then
            continue
        fi

        local candidate_lines
        candidate_lines=$(curl -fsSL "$primary_url" 2>/dev/null | gzip -dc 2>/dev/null | awk -v pkg="nvidia-open" '
            BEGIN { RS="</package>" }
            $0 ~ "<name>" pkg "</name>" {
                version = ""
                release = ""
                location = ""
                if (match($0, /<version [^>]*ver="[^"]+"/)) {
                    tmp = substr($0, RSTART, RLENGTH)
                    sub(/^.*ver="/, "", tmp)
                    sub(/".*$/, "", tmp)
                    version = tmp
                }
                if (match($0, /<version [^>]*rel="[^"]+"/)) {
                    tmp = substr($0, RSTART, RLENGTH)
                    sub(/^.*rel="/, "", tmp)
                    sub(/".*$/, "", tmp)
                    release = tmp
                }
                if (match($0, /<location href="[^"]+"/)) {
                    tmp = substr($0, RSTART, RLENGTH)
                    sub(/^.*href="/, "", tmp)
                    sub(/".*$/, "", tmp)
                    location = tmp
                }
                if (version != "" && location != "") {
                    if (release != "") {
                        version = version "-" release
                    }
                    print version "\t" location
                }
            }
        ')

        if [ -z "$candidate_lines" ]; then
            continue
        fi

        local selected_line
        selected_line=$(printf "%s\n" "$candidate_lines" | sort -V -k1,1 | tail -1)

        local selected_driver_path
        selected_driver_path=$(printf "%s" "$selected_line" | cut -f2)
        if [ -z "$selected_driver_path" ]; then
            continue
        fi

        local driver_rpm_basename
        driver_rpm_basename=$(basename "$selected_driver_path")
        local driver_rpm_file="${CUDA_CACHE_DIR}/${driver_rpm_basename}"
        local driver_rpm_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/${selected_driver_path}"

        if [ ! -f "$driver_rpm_file" ]; then
            print_info "Downloading latest NVIDIA open driver package from NVIDIA repository..." >&2
            if wget -O "$driver_rpm_file" "$driver_rpm_url"; then
                CUDA_PACKAGE_DOWNLOADS+=("$driver_rpm_file")
            else
                print_warning "Failed to download $driver_rpm_url" >&2
                rm -f "$driver_rpm_file"
                continue
            fi
        else
            print_info "Using temporary NVIDIA driver package: $driver_rpm_file" >&2
        fi

        echo "$driver_rpm_file"
        return 0
    done

    echo "nvidia-open"
    return 0
}

rhel_package_candidate_version() {
    local package_name="$1"
    local candidate repository
    local cache_args=()
    local candidates=()

    if [ "$PREFLIGHT_MODE" = true ]; then
        cache_args=(-C)
    fi
    if command -v dnf &> /dev/null; then
        candidate=$(dnf "${cache_args[@]}" repoquery --latest-limit 1 --qf '%{version}-%{release}' "$package_name" 2>/dev/null)
        [ -z "$candidate" ] || candidates+=("$candidate")
    elif command -v repoquery &> /dev/null; then
        candidate=$(repoquery "${cache_args[@]}" --qf '%{version}-%{release}' "$package_name" 2>/dev/null)
        [ -z "$candidate" ] || candidates+=("$candidate")
    fi
    if [ "$PREFLIGHT_MODE" = true ]; then
        for repository in "${CUDA_REPO_VERSIONS[@]}"; do
            if [ "${CUDA_PREFLIGHT_RHEL_STATUS[$repository]:-}" = ok ]; then
                candidate=$(cuda_preflight_find_rhel_candidate \
                    "${CUDA_PREFLIGHT_RHEL_PRIMARY_FILES[$repository]}" "$package_name" "")
                [ -z "$candidate" ] || candidates+=("${candidate%%$'\t'*}")
            fi
        done
    fi
    printf '%s\n' "${candidates[@]}" | sort -V | tail -1
}

install_resolved_driver_package() {
    local driver_package="$1"

    if [ "$OS_TYPE" = "rhel" ] && [ ! -f "$driver_package" ] && [ "$driver_package" = "nvidia-open" ] && command -v dnf &> /dev/null; then
        ${SUDO_PREFIX}dnf install -y --best "$driver_package"
        return $?
    fi

    $PKG_INSTALL_CMD "$driver_package"
}

has_nvidia_pci_devices() {
    if command -v lspci &> /dev/null && lspci 2>/dev/null | grep -qi 'NVIDIA'; then
        return 0
    fi

    return 1
}

has_nvidia_kernel_driver() {
    if command -v lsmod &> /dev/null && lsmod 2>/dev/null | grep -q '^nvidia'; then
        return 0
    fi

    if [ -e /proc/driver/nvidia/version ] || [ -e /sys/module/nvidia/version ]; then
        return 0
    fi

    return 1
}

ensure_nvidia_driver_build_prereqs() {
    if [ "$OS_TYPE" = "ubuntu" ]; then
        local headers_pkg="linux-headers-$(uname -r)"
        local headers_candidate
        if dpkg -s "$headers_pkg" &> /dev/null; then
            print_info "  ✓ Kernel headers already installed: $headers_pkg"
            return 0
        fi

        headers_candidate=$(apt-cache policy "$headers_pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
        if [ -z "$headers_candidate" ] || [ "$headers_candidate" = "(none)" ]; then
            print_error "Cannot install the NVIDIA driver without matching kernel headers: $headers_pkg"
            return 1
        fi

        print_info "Installing kernel headers required for NVIDIA DKMS: $headers_pkg"
        if ! $PKG_INSTALL_CMD "$headers_pkg"; then
            print_warning "Failed to install $headers_pkg."
            return 1
        fi

        return 0
    fi

    if [ "$OS_TYPE" = "rhel" ]; then
        local kernel_devel_pkg="kernel-devel-$(uname -r)"
        local kernel_headers_pkg="kernel-headers-$(uname -r)"
        local missing_prereqs=()

        if ! rpm -q "$kernel_devel_pkg" &> /dev/null; then
            missing_prereqs+=("$kernel_devel_pkg")
        fi
        if ! rpm -q "$kernel_headers_pkg" &> /dev/null; then
            missing_prereqs+=("$kernel_headers_pkg")
        fi

        if [ ${#missing_prereqs[@]} -eq 0 ]; then
            print_info "  ✓ Kernel headers already installed for $(uname -r)"
            return 0
        fi

        print_info "Installing kernel development packages required for NVIDIA DKMS: ${missing_prereqs[*]}"
        if ! $PKG_INSTALL_CMD "${missing_prereqs[@]}"; then
            print_warning "Failed to install kernel development prerequisites: ${missing_prereqs[*]}"
            return 1
        fi
    fi

    return 0
}

install_nvidia_driver_for_gpu_support() {
    local cuda_stream="$1"
    local driver_package=""
    local driver_package_display=""
    local driver_package_installed_version=""
    local driver_package_candidate_version=""
    local driver_package_needs_update=false
    local driver_install_reason=""
    local driver_ready=false
    local kernel_driver_loaded=false
    local kernel_driver_was_loaded=false

    if ! has_nvidia_pci_devices; then
        print_info "No NVIDIA GPU detected via PCI enumeration; skipping driver installation."
        return 0
    fi

    if command -v nvidia-smi &> /dev/null && nvidia-smi >/dev/null 2>&1; then
        driver_ready=true
    fi

    if has_nvidia_kernel_driver; then
        kernel_driver_loaded=true
        kernel_driver_was_loaded=true
    fi

    case "$OS_TYPE" in
        ubuntu)
            driver_package=$(resolve_ubuntu_driver_package "$cuda_stream")
            ;;
        rhel)
            driver_package=$(resolve_rhel_driver_package "$cuda_stream")
            ;;
    esac

    if [ -z "$driver_package" ]; then
        if [ "$driver_ready" = true ]; then
            print_warning "No driver update candidate was resolved; retaining the working NVIDIA driver."
        else
            print_error "Could not resolve the NVIDIA driver required for CUDA workloads."
            INSTALL_SUCCESS=false
        fi
        return 0
    fi

    driver_package_display="$driver_package"
    if [ -f "$driver_package" ]; then
        driver_package_display=$(basename "$driver_package")
    fi

    case "$OS_TYPE" in
        ubuntu)
            if command -v dpkg-query &> /dev/null; then
                driver_package_installed_version=$(dpkg-query -W -f='${Status} ${Version}\n' "$driver_package" 2>/dev/null | awk '
                    $1 == "install" && $2 == "ok" && $3 == "installed" {
                        print $4
                        exit
                    }
                ')
            fi

            if command -v apt-cache &> /dev/null; then
                driver_package_candidate_version=$(ubuntu_package_candidate_version "$driver_package")
            fi

            if [ -z "$driver_package_installed_version" ]; then
                driver_package_needs_update=true
                driver_install_reason="required driver package is not installed"
            elif [ -n "$driver_package_candidate_version" ] && [ "$driver_package_candidate_version" != "(none)" ] && [ "$driver_package_candidate_version" != "$driver_package_installed_version" ]; then
                driver_package_needs_update=true
                driver_install_reason="newer candidate $driver_package_candidate_version is available (installed: $driver_package_installed_version)"
            fi
            ;;
        rhel)
            if command -v rpm &> /dev/null; then
                if [ -f "$driver_package" ]; then
                    local rpm_name=""
                    local rpm_version=""
                    rpm_name=$(rpm -qp --qf '%{NAME}\n' "$driver_package" 2>/dev/null)
                    rpm_version=$(rpm -qp --qf '%{VERSION}-%{RELEASE}\n' "$driver_package" 2>/dev/null)
                    if [ -n "$rpm_name" ] && rpm -q "$rpm_name" &> /dev/null; then
                        driver_package_installed_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$rpm_name" 2>/dev/null | head -1)
                    fi
                    if [ -z "$driver_package_installed_version" ]; then
                        driver_package_needs_update=true
                        driver_install_reason="required driver package is not installed"
                    elif [ -n "$rpm_version" ] && [ "$driver_package_installed_version" != "$rpm_version" ]; then
                        driver_package_needs_update=true
                        driver_install_reason="newer candidate $rpm_version is available (installed: $driver_package_installed_version)"
                    fi
                else
                    if rpm -q "$driver_package" &> /dev/null; then
                        driver_package_installed_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$driver_package" 2>/dev/null | head -1)
                    fi
                    driver_package_candidate_version=$(rhel_package_candidate_version "$driver_package")
                    if [ -z "$driver_package_installed_version" ]; then
                        driver_package_needs_update=true
                        driver_install_reason="required driver package is not installed"
                    elif [ -n "$driver_package_candidate_version" ] && [ "$driver_package_installed_version" != "$driver_package_candidate_version" ]; then
                        driver_package_needs_update=true
                        driver_install_reason="newer candidate $driver_package_candidate_version is available (installed: $driver_package_installed_version)"
                    fi
                fi
            fi
            ;;
    esac

    if [ "$driver_package_needs_update" = true ]; then
        local install_driver="y"
        if [ "$AUTO_YES" = true ]; then
            print_info "Automatic mode enabled (-y): installing/upgrading $driver_package_display"
        else
            read -p "Install or upgrade latest NVIDIA driver package $driver_package_display ($driver_install_reason)? (y/n): " install_driver
        fi

        if [[ ! "$install_driver" =~ ^[Yy]$ ]]; then
            print_warning "Skipped NVIDIA driver installation/upgrade. CUDA apps may not work until the driver is installed."
            return 0
        fi

        if ! ensure_nvidia_driver_build_prereqs; then
            INSTALL_SUCCESS=false
            return 0
        fi

        print_info "Installing/upgrading NVIDIA driver package: $driver_package_display"
        if ! install_resolved_driver_package "$driver_package"; then
            print_warning "Failed to install $driver_package_display."
            INSTALL_SUCCESS=false
            return 0
        fi
    elif [ "$driver_ready" = true ]; then
        print_info "NVIDIA driver package is already active and up to date: $driver_package_display"
        return 0
    else
        if [ "$kernel_driver_loaded" = true ]; then
            print_warning "NVIDIA kernel driver appears to be loaded, but nvidia-smi is not ready."
        else
            print_warning "NVIDIA GPU detected, but the NVIDIA kernel driver is not loaded."
            print_info "CUDA packages do not install the running kernel driver by themselves."
        fi
        print_info "Desired NVIDIA driver package is already installed: $driver_package_display"
    fi

    if command -v modprobe &> /dev/null; then
        print_info "Attempting to load NVIDIA kernel modules..."
        ${SUDO_PREFIX}modprobe nvidia >/dev/null 2>&1 || true
        ${SUDO_PREFIX}modprobe nvidia_uvm >/dev/null 2>&1 || true
    fi

    if command -v nvidia-smi &> /dev/null && nvidia-smi >/dev/null 2>&1; then
        if [ "$driver_package_needs_update" = true ] && [ "$kernel_driver_was_loaded" = true ]; then
            print_warning "NVIDIA driver packages were upgraded while a kernel driver was already loaded."
            print_warning "A reboot is recommended before relying on the upgraded NVIDIA driver."
        else
            print_info "✓ NVIDIA driver is active and responding to nvidia-smi"
        fi
        return 0
    fi

    if has_nvidia_kernel_driver; then
        if [ "$driver_package_needs_update" = true ]; then
            print_warning "NVIDIA driver packages were installed or upgraded, but nvidia-smi is still not ready."
        else
            print_warning "NVIDIA driver packages are installed, but nvidia-smi is still not ready."
        fi
    else
        if [ "$driver_package_needs_update" = true ]; then
            print_warning "NVIDIA driver packages were installed or upgraded, but the kernel module is still not loaded."
        else
            print_warning "NVIDIA kernel driver is still not loaded."
        fi
    fi
    print_warning "A reboot may be required before the NVIDIA driver becomes active."
    return 0
}

collect_installed_cuda_versions() {
    INSTALLED_CUDA_VERSIONS=()
    local packages=()
    local cuda_dir

    if [ "$OS_TYPE" = "ubuntu" ]; then
        if command -v dpkg &> /dev/null; then
            mapfile -t packages < <(dpkg -l 'cuda' 'cuda-[0-9]*' 'cuda-toolkit*' 2>/dev/null | awk '/^ii/ {print $2}')
        fi
    elif [ "$OS_TYPE" = "rhel" ]; then
        if command -v rpm &> /dev/null; then
            mapfile -t packages < <(rpm -qa 'cuda' 'cuda-[0-9]*' 'cuda-toolkit*' 2>/dev/null)
        fi
    fi

    for pkg in "${packages[@]}"; do
        if [[ $pkg =~ ^cuda-([0-9]+(-[0-9]+){1,3})$ ]]; then
            local version_suffix=${pkg#cuda-}
            version_suffix=${version_suffix%%.*}
            if [[ $version_suffix =~ ^[0-9]+(-[0-9]+){1,3}$ ]]; then
                local version=${version_suffix//-/.}
                INSTALLED_CUDA_VERSIONS+=("$version")
            fi
        elif [[ $pkg =~ ^cuda-toolkit- ]]; then
            local version_suffix=${pkg#cuda-toolkit-}
            version_suffix=${version_suffix%%.*}
            if [[ $version_suffix =~ ^[0-9]+(-[0-9]+){1,3}$ ]]; then
                local version=${version_suffix//-/.}
                INSTALLED_CUDA_VERSIONS+=("$version")
            fi
        elif [[ $pkg == cuda || $pkg == cuda-toolkit ]]; then
            if [ -n "$CURRENT_CUDA_VERSION_NORMALIZED" ]; then
                INSTALLED_CUDA_VERSIONS+=("$CURRENT_CUDA_VERSION_NORMALIZED")
            fi
        fi
    done

    for cuda_dir in /usr/local/cuda-*; do
        if [ ! -d "$cuda_dir" ]; then
            continue
        fi

        local dir_version=${cuda_dir##*/cuda-}
        if [[ $dir_version =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
            INSTALLED_CUDA_VERSIONS+=("$dir_version")
        fi
    done

    if [ ${#INSTALLED_CUDA_VERSIONS[@]} -gt 0 ]; then
        mapfile -t INSTALLED_CUDA_VERSIONS < <(printf "%s
" "${INSTALLED_CUDA_VERSIONS[@]}" | awk '!seen[$0]++' | sort -V)
        INSTALLED_CUDA_VERSIONS_DISPLAY=$(printf "%s" "${INSTALLED_CUDA_VERSIONS[0]}")
        for version in "${INSTALLED_CUDA_VERSIONS[@]:1}"; do
            INSTALLED_CUDA_VERSIONS_DISPLAY+=", $version"
        done
    else
        INSTALLED_CUDA_VERSIONS_DISPLAY="None"
    fi
}

collect_cuda_default_candidates() {
    CUDA_DEFAULT_CANDIDATE_VERSIONS=()
    CUDA_DEFAULT_CANDIDATE_DIRS=()

    local candidate_lines=()
    local cuda_dir
    for cuda_dir in /usr/local/cuda-*; do
        if [ ! -d "$cuda_dir" ]; then
            continue
        fi

        local dir_version=${cuda_dir##*/cuda-}
        if [[ $dir_version =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
            candidate_lines+=("${dir_version}	${cuda_dir}")
        fi
    done

    if [ ${#candidate_lines[@]} -eq 0 ]; then
        return 0
    fi

    local version
    local path
    while IFS=$'\t' read -r version path; do
        if [ -n "$version" ] && [ -n "$path" ]; then
            CUDA_DEFAULT_CANDIDATE_VERSIONS+=("$version")
            CUDA_DEFAULT_CANDIDATE_DIRS+=("$path")
        fi
    done < <(printf "%s\n" "${candidate_lines[@]}" | awk '!seen[$1]++' | sort -V -k1,1)
}

get_cuda_default_version_for_link() {
    local link_path="$1"

    if [ ! -e "$link_path" ]; then
        echo ""
        return 0
    fi

    local current_target
    current_target=$(readlink -f "$link_path" 2>/dev/null)
    if [ -z "$current_target" ]; then
        echo ""
        return 0
    fi

    local current_version=${current_target##*/cuda-}
    if [[ $current_version =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
        echo "$current_version"
        return 0
    fi

    echo ""
}

get_current_cuda_default_version() {
    get_cuda_default_version_for_link "/usr/local/cuda"
}

cuda_alternative_group_exists() {
    local alternative_name="$1"

    command -v update-alternatives &> /dev/null || return 1
    update-alternatives --display "$alternative_name" >/dev/null 2>&1
}

cuda_alternative_has_path() {
    local alternative_name="$1"
    local cuda_dir="$2"

    cuda_alternative_group_exists "$alternative_name" || return 1
    update-alternatives --display "$alternative_name" 2>/dev/null | awk -v path="$cuda_dir" '
        $1 == path { found=1 }
        END { exit !found }
    '
}

set_cuda_default_link() {
    local alternative_name="$1"
    local link_path="$2"
    local version="$3"
    local allow_symlink_fallback="${4:-false}"
    local cuda_dir="/usr/local/cuda-${version}"

    if [ ! -d "$cuda_dir" ]; then
        print_warning "Cannot set CUDA $version as default because $cuda_dir was not found."
        return 1
    fi

    if cuda_alternative_group_exists "$alternative_name"; then
        if ! cuda_alternative_has_path "$alternative_name" "$cuda_dir"; then
            print_warning "$cuda_dir is not registered with update-alternatives group $alternative_name; leaving $link_path unchanged."
            return 1
        fi

        if ${SUDO_PREFIX}update-alternatives --set "$alternative_name" "$cuda_dir"; then
            print_info "Set $alternative_name default: $link_path -> $cuda_dir"
            return 0
        fi

        print_warning "Failed to set update-alternatives group $alternative_name to $cuda_dir"
        return 1
    fi

    if [ "$allow_symlink_fallback" != true ]; then
        return 0
    fi

    if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
        print_warning "$link_path exists and is not a symlink; leaving CUDA default unchanged."
        print_warning "Set the default manually after reviewing $link_path."
        return 1
    fi

    if ${SUDO_PREFIX}ln -sfnT "$cuda_dir" "$link_path"; then
        print_info "Set CUDA default: $link_path -> $cuda_dir"
        return 0
    fi

    print_warning "Failed to set $link_path -> $cuda_dir"
    return 1
}

set_default_cuda_version() {
    local version="$1"
    local major_version=${version%%.*}
    local result=0

    set_cuda_default_link "cuda" "/usr/local/cuda" "$version" true || result=1

    if cuda_alternative_group_exists "cuda-${major_version}"; then
        set_cuda_default_link "cuda-${major_version}" "/usr/local/cuda-${major_version}" "$version" false || true
    fi

    return "$result"
}

restore_preinstall_cuda_default() {
    local current_default
    current_default=$(get_current_cuda_default_version)

    if [ -n "$PREINSTALL_CUDA_DEFAULT_VERSION" ]; then
        if [ "$current_default" = "$PREINSTALL_CUDA_DEFAULT_VERSION" ]; then
            return 0
        fi
        if [ ! -d "/usr/local/cuda-${PREINSTALL_CUDA_DEFAULT_VERSION}" ]; then
            print_warning "Cannot restore the pre-install CUDA default because /usr/local/cuda-${PREINSTALL_CUDA_DEFAULT_VERSION} is missing."
            return 1
        fi

        print_info "Restoring pre-install CUDA default ($PREINSTALL_CUDA_DEFAULT_VERSION)."
        set_default_cuda_version "$PREINSTALL_CUDA_DEFAULT_VERSION"
        return $?
    fi

    if [ "$PREINSTALL_CUDA_DEFAULT_WAS_SYMLINK" = true ]; then
        if [ "$(readlink /usr/local/cuda 2>/dev/null)" != "$PREINSTALL_CUDA_DEFAULT_LINK_TARGET" ]; then
            print_info "Restoring pre-install /usr/local/cuda symlink."
            ${SUDO_PREFIX}ln -sfnT "$PREINSTALL_CUDA_DEFAULT_LINK_TARGET" /usr/local/cuda
        fi
        return $?
    fi

    if [ "$PREINSTALL_CUDA_DEFAULT_EXISTED" = false ] && [ -L /usr/local/cuda ]; then
        print_info "Removing package-selected CUDA default because no version was marked with -d."
        ${SUDO_PREFIX}rm -f /usr/local/cuda
    fi
}

prompt_for_default_cuda_version() {
    collect_installed_cuda_versions
    collect_cuda_default_candidates

    if [ ${#CUDA_DEFAULT_CANDIDATE_VERSIONS[@]} -eq 0 ]; then
        print_warning "No versioned CUDA toolkit directories found under /usr/local; leaving CUDA default unchanged."
        return 0
    fi

    restore_preinstall_cuda_default || return 1

    print_info "Installed CUDA versions detected: $INSTALLED_CUDA_VERSIONS_DISPLAY"

    local current_default
    current_default=$(get_current_cuda_default_version)
    if [ "$AUTO_YES" = true ]; then
        print_info "Automatic mode enabled (-y): setting CUDA $TARGET_CUDA_VERSION_NORMALIZED as the default."
        set_default_cuda_version "$TARGET_CUDA_VERSION_NORMALIZED"
        return $?
    fi



    echo "Choose the CUDA version to make default for /usr/local/cuda:"
    local index
    for index in "${!CUDA_DEFAULT_CANDIDATE_VERSIONS[@]}"; do
        local version="${CUDA_DEFAULT_CANDIDATE_VERSIONS[$index]}"
        local path="${CUDA_DEFAULT_CANDIDATE_DIRS[$index]}"
        local marker=""
        if [ "$version" = "$current_default" ]; then
            marker=" (current default)"
        fi
        echo "  $((index + 1))) CUDA $version - $path$marker"
    done

    local skip_choice=$(( ${#CUDA_DEFAULT_CANDIDATE_VERSIONS[@]} + 1 ))
    echo "  $skip_choice) Leave current default unchanged"

    local default_choice
    read -r -p "Enter choice (1-$skip_choice): " default_choice
    while ! [[ "$default_choice" =~ ^[0-9]+$ ]] || [ "$default_choice" -lt 1 ] || [ "$default_choice" -gt "$skip_choice" ]; do
        read -r -p "Please enter a number from 1 to $skip_choice: " default_choice
    done

    if [ "$default_choice" -eq "$skip_choice" ]; then
        print_info "Leaving CUDA default unchanged."
        return 0
    fi

    local selected_index=$((default_choice - 1))
    set_default_cuda_version "${CUDA_DEFAULT_CANDIDATE_VERSIONS[$selected_index]}"
}

# Track overall success
INSTALL_SUCCESS=true
CURRENT_CUDA_VERSION_NORMALIZED=""

# Parse arguments
AUTO_YES=false
CUDA_VERSION_ARGS=()
CUDA_VERSION_STREAMS=()
DEFAULT_CUDA_VERSION_ARG=""
DEFAULT_CUDA_VERSION_STREAM=""
LAST_ARGUMENT_WAS_VERSION=false

for arg in "$@"; do
    case "$arg" in
        -y|--auto)
            AUTO_YES=true
            LAST_ARGUMENT_WAS_VERSION=false
            ;;
        --preflight)
            PREFLIGHT_MODE=true
            LAST_ARGUMENT_WAS_VERSION=false
            ;;
        -d)
            if [ "$LAST_ARGUMENT_WAS_VERSION" != true ]; then
                print_error "-d must immediately follow the CUDA version it should make default."
                exit 1
            fi
            if [ -n "$DEFAULT_CUDA_VERSION_ARG" ]; then
                print_error "Only one CUDA version can be marked as default with -d."
                exit 1
            fi
            default_index=$(( ${#CUDA_VERSION_ARGS[@]} - 1 ))
            DEFAULT_CUDA_VERSION_ARG="${CUDA_VERSION_ARGS[$default_index]}"
            DEFAULT_CUDA_VERSION_STREAM="${CUDA_VERSION_STREAMS[$default_index]}"
            LAST_ARGUMENT_WAS_VERSION=false
            ;;
        -h|--help)
            echo "Usage: $0 [--preflight] [-y|--auto] [cuda-version [-d] ...]"
            echo "  --preflight     Check CUDA prerequisites without installing or modifying the system"
            echo "  -y, --auto      Install requested CUDA versions without confirmation"
            echo "  -d              Make the immediately preceding CUDA version the default"
            echo "  cuda-version    CUDA version to install (up to 10 distinct major.minor streams)"
            echo ""
            echo "Multiple CUDA versions require exactly one -d marker."
            echo "A single CUDA version may omit -d to leave the current default unchanged."
            echo "Examples:"
            echo "  $0 -y 13.0 -d"
            echo "  $0 -y 13.0 -d 12.0 13.3"
            echo "  $0 13.0 -d 12.0"
            exit 0
            ;;
        -*)
            print_error "Invalid option: $arg"
            exit 1
            ;;
        *)
            if ! is_valid_cuda_version_arg "$arg"; then
                print_error "Invalid argument: $arg"
                print_error "CUDA version must be numeric, such as 12.9, 13, 13.0.1, or 13.0.2-1."
                exit 1
            fi

            if [ "${#CUDA_VERSION_ARGS[@]}" -ge 10 ]; then
                print_error "At most 10 CUDA versions can be installed in one run."
                exit 1
            fi

            version_stream="$(cuda_version_stream "$arg")"
            for existing_stream in "${CUDA_VERSION_STREAMS[@]}"; do
                if [ "$existing_stream" = "$version_stream" ]; then
                    print_error "CUDA versions must use distinct major.minor streams; $version_stream was provided more than once."
                    exit 1
                fi
            done

            CUDA_VERSION_ARGS+=("$arg")
            CUDA_VERSION_STREAMS+=("$version_stream")
            LAST_ARGUMENT_WAS_VERSION=true
            ;;
    esac

done

if [ "${#CUDA_VERSION_ARGS[@]}" -gt 1 ] && [ -z "$DEFAULT_CUDA_VERSION_ARG" ]; then
    print_error "Multiple CUDA versions require one version followed immediately by -d."
    exit 1
fi
if [ "$PREFLIGHT_MODE" = true ]; then
    if ! source "$(dirname -- "${BASH_SOURCE[0]}")/preflight.sh"; then
        print_error "Cannot load shared preflight helper."
        exit 1
    fi
    SETUP_PLANNED_CORE="${SETUP_PLANNED_CORE:-0}"
    if [ "$SETUP_PLANNED_CORE" != 1 ]; then
        SETUP_PLANNED_CORE=0
    fi
    preflight_init "CUDA installer"
fi


# OS/package manager detection
OS_TYPE=""
PKG_INSTALL_CMD=""
PKG_UPDATE_CMD=""
PKG_QUERY_CMD=""
OS_ID=""
OS_NAME=""
OS_VERSION_ID=""

detect_os_package_manager() {
    if [ ! -f /etc/os-release ]; then
        return 1
    fi

    source /etc/os-release
    OS_ID="$ID"
    OS_NAME="$NAME"
    OS_VERSION_ID="$VERSION_ID"
    local version_major
    version_major=$(echo "$VERSION_ID" | cut -d. -f1)

    SUDO_PREFIX="sudo "
    if [ "$(id -u)" -eq 0 ]; then
        SUDO_PREFIX=""
    fi

    if [ "$ID" = "ubuntu" ]; then
        if [ "$version_major" -lt 22 ]; then
            return 1
        fi
        OS_TYPE="ubuntu"
        PKG_INSTALL_CMD="${SUDO_PREFIX}apt install -y"
        PKG_UPDATE_CMD="${SUDO_PREFIX}apt update"
        PKG_QUERY_CMD="dpkg -l"
        return 0
    fi

    if [[ "$ID" =~ ^(rhel|rocky|almalinux)$ ]]; then
        if [ "$version_major" -lt 9 ]; then
            return 1
        fi
        OS_TYPE="rhel"
        if command -v dnf &> /dev/null; then
            PKG_INSTALL_CMD="${SUDO_PREFIX}dnf install -y"
            PKG_UPDATE_CMD="${SUDO_PREFIX}dnf makecache"
        else
            PKG_INSTALL_CMD="${SUDO_PREFIX}yum install -y"
            PKG_UPDATE_CMD="${SUDO_PREFIX}yum makecache"
        fi
        PKG_QUERY_CMD="rpm -qa"
        return 0
    fi

    return 1
}

print_info "Checking OS version..."
if ! detect_os_package_manager; then
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot determine OS version. /etc/os-release not found."
        if [ "$PREFLIGHT_MODE" = true ]; then
            preflight_error "Cannot determine OS: /etc/os-release not found."
        fi
    elif [ "$OS_ID" = "ubuntu" ]; then
        print_error "This script requires Ubuntu 22.04 or newer. Detected: $OS_ID $OS_VERSION_ID"
        if [ "$PREFLIGHT_MODE" = true ]; then
            preflight_error "Unsupported Ubuntu release: $OS_ID $OS_VERSION_ID (requires 22.04 or newer)."
        fi
    elif [[ "$OS_ID" =~ ^(rhel|rocky|almalinux)$ ]]; then
        print_error "This script requires RHEL/Rocky/AlmaLinux 9 or newer. Detected: $OS_ID $OS_VERSION_ID"
        if [ "$PREFLIGHT_MODE" = true ]; then
            preflight_error "Unsupported RHEL-family release: $OS_ID $OS_VERSION_ID (requires 9 or newer)."
        fi
    else
        print_error "Unsupported OS. This script supports Ubuntu 22.04+ and RHEL/Rocky/AlmaLinux 9+. Detected: $OS_ID $OS_VERSION_ID"
        if [ "$PREFLIGHT_MODE" = true ]; then
            preflight_error "Unsupported OS: $OS_ID $OS_VERSION_ID."
        fi
    fi
    if [ "$PREFLIGHT_MODE" != true ]; then
        exit 1
    fi
else
    CUDA_PREFLIGHT_OS_SUPPORTED=true
fi

if [ -n "$OS_TYPE" ]; then
    if [ "$OS_TYPE" = "ubuntu" ]; then
        print_info "✓ Ubuntu $OS_VERSION_ID detected"
    else
        print_info "✓ $OS_NAME $OS_VERSION_ID detected"
    fi
fi
# Check CUDA driver and toolkit
print_info "Checking CUDA driver and toolkit..."

# Check for NVIDIA driver and get supported CUDA version
DRIVER_CUDA_VERSION=""
if command -v nvidia-smi &> /dev/null; then
    # Extract CUDA version supported by driver from nvidia-smi output
    DRIVER_CUDA_VERSION=$(nvidia-smi | grep -oP 'CUDA Version:\s*\K[0-9]+\.[0-9]+' | head -1)
    if [ -n "$DRIVER_CUDA_VERSION" ]; then
        print_info "  ✓ NVIDIA driver detected - supports CUDA up to version $DRIVER_CUDA_VERSION"
    else
        print_warning "  ⚠ NVIDIA driver detected but couldn't determine CUDA version support"
    fi
else
    print_warning "  ⚠ No NVIDIA driver detected (nvidia-smi not found)"
    print_info "  Will default to CUDA 12.9 for modern NVIDIA GPU compatibility"
fi

# Check for CUDA toolkit (nvcc)
if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $6}' | cut -d',' -f1)
    print_info "  ✓ CUDA toolkit (nvcc) - version $CUDA_VERSION"
    
    # Check if installed CUDA version needs upgrade to 12.9
    CUDA_VERSION_WITHOUT_PREFIX="${CUDA_VERSION#V}"
    CUDA_VERSION_MAJOR="${CUDA_VERSION_WITHOUT_PREFIX%%.*}"
    CUDA_VERSION_REMAINDER="${CUDA_VERSION_WITHOUT_PREFIX#*.}"
    CUDA_VERSION_MINOR="${CUDA_VERSION_REMAINDER%%.*}"
    CURRENT_CUDA_VERSION_NORMALIZED="${CUDA_VERSION_MAJOR}.${CUDA_VERSION_MINOR}"
    
    if [ "$CUDA_VERSION_MAJOR" -gt 12 ] || { [ "$CUDA_VERSION_MAJOR" -eq 12 ] && [ "$CUDA_VERSION_MINOR" -ge 9 ]; }; then
        print_info "  ✓ CUDA version $CUDA_VERSION meets the recommended baseline"
    else
        print_info "  CUDA version $CUDA_VERSION detected; upgrade options will be offered"
    fi
else
    if [ "$PREFLIGHT_MODE" = true ]; then
        print_info "  CUDA toolkit (nvcc) is not currently installed; requested toolkit candidates will be checked."
    else
        print_error "  ✗ CUDA toolkit (nvcc)"
    fi
fi

collect_installed_cuda_versions
PREINSTALL_CUDA_DEFAULT_VERSION=$(get_current_cuda_default_version)

echo ""
if command -v nvcc &> /dev/null; then
    print_info "CUDA toolkit detected - reinstall, upgrade, or downgrade options available."
else
    print_warning "CUDA toolkit (nvcc) not found - required for GPU-optimized packages"
fi
echo ""

# Install/Upgrade CUDA toolkit
echo ""

build_cuda_repo_versions() {
    CUDA_REPO_VERSIONS=()

    if [ "$OS_TYPE" = "ubuntu" ]; then
        local version_year="${VERSION_ID%%.*}"
        local version_month="${VERSION_ID#*.}"
        local year
        local month

        CUDA_REPO_VERSIONS=("ubuntu${version_year}${version_month}")
        for year in $(seq "$version_year" -2 22); do
            if [ "$year" -eq "$version_year" ]; then
                for month in $(seq "$version_month" -2 4); do
                    [ "$month" -lt 10 ] && month="0$month"
                    CUDA_REPO_VERSIONS+=("ubuntu${year}${month}")
                done
            else
                CUDA_REPO_VERSIONS+=("ubuntu${year}10")
                CUDA_REPO_VERSIONS+=("ubuntu${year}04")
            fi
        done
    elif [ "$OS_TYPE" = "rhel" ]; then
        CUDA_REPO_VERSIONS=("rhel9" "rhel8")
    fi

    if [ "${#CUDA_REPO_VERSIONS[@]}" -gt 0 ]; then
        mapfile -t CUDA_REPO_VERSIONS < <(printf "%s\n" "${CUDA_REPO_VERSIONS[@]}" | awk '!seen[$0]++')
        print_info "Will try CUDA repositories in order: ${CUDA_REPO_VERSIONS[*]}"
    fi
}
cuda_preflight_check_tools() {
    local planned="${SETUP_PLANNED_CORE:-0}"
    local command_name

    CUDA_PREFLIGHT_PARSER_AVAILABLE=true
    for command_name in awk sort grep sed cut tr uniq tail head basename readlink uname; do
        if ! command -v "$command_name" &> /dev/null; then
            CUDA_PREFLIGHT_PARSER_AVAILABLE=false
        fi
        preflight_command "$command_name" "$planned" || true
    done

    if preflight_can_fetch; then
        CUDA_PREFLIGHT_FETCH_AVAILABLE=true
        preflight_info "HTTP metadata fetch available (curl or wget)."
    else
        CUDA_PREFLIGHT_FETCH_AVAILABLE=false
        if [ "$planned" = 1 ]; then
            preflight_defer "CUDA repository metadata checks are deferred because curl and wget are scheduled by the core dependency stage."
        else
            preflight_error "CUDA repository metadata requires curl or wget."
        fi
    fi

    if [ "$OS_TYPE" = "ubuntu" ]; then
        preflight_command apt 0 || true
        preflight_command dpkg 0 || true
        preflight_command apt-cache 0 || true
        preflight_command dpkg-query 0 || true
    elif [ "$OS_TYPE" = "rhel" ]; then
        preflight_command rpm 0 || true
        if command -v dnf &> /dev/null; then
            preflight_command dnf 0 || true
        else
            preflight_command yum 0 || true
        fi
        if ! command -v gzip &> /dev/null; then
            CUDA_PREFLIGHT_PARSER_AVAILABLE=false
        fi
        preflight_command gzip "$planned" || true
    fi
}

cuda_preflight_load_ubuntu_metadata() {
    local repo="$1"
    local packages_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/Packages"
    local payload

    if [ -n "${CUDA_PREFLIGHT_UBUNTU_STATUS[$repo]:-}" ]; then
        return 0
    fi
    if [ "$CUDA_PREFLIGHT_FETCH_AVAILABLE" != true ]; then
        CUDA_PREFLIGHT_UBUNTU_STATUS["$repo"]="deferred"
        return 0
    fi

    if ! payload=$(preflight_fetch "$packages_url"); then
        CUDA_PREFLIGHT_UBUNTU_STATUS["$repo"]="unreachable"
        return 0
    fi

    if [ -z "$payload" ]; then
        CUDA_PREFLIGHT_UBUNTU_STATUS["$repo"]="unreachable"
        return 0
    fi

    CUDA_PREFLIGHT_UBUNTU_PACKAGES["$repo"]="$payload"
    CUDA_PREFLIGHT_UBUNTU_STATUS["$repo"]="ok"
}

cuda_preflight_load_rhel_metadata() {
    local repo="$1"
    local repomd_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/repodata/repomd.xml"
    local repomd_file="${CUDA_CACHE_DIR}/preflight-${repo}-repomd.xml"
    local primary_rel=""
    local primary_url=""
    local primary_file="${CUDA_CACHE_DIR}/preflight-${repo}-primary.xml.gz"
    local primary_text_file="${CUDA_CACHE_DIR}/preflight-${repo}-primary.xml"

    if [ -n "${CUDA_PREFLIGHT_RHEL_STATUS[$repo]:-}" ]; then
        return 0
    fi
    if [ "$CUDA_PREFLIGHT_FETCH_AVAILABLE" != true ]; then
        CUDA_PREFLIGHT_RHEL_STATUS["$repo"]="deferred"
        return 0
    fi
    if [ "$CUDA_PREFLIGHT_PARSER_AVAILABLE" != true ]; then
        if [ "${SETUP_PLANNED_CORE:-0}" = 1 ]; then
            CUDA_PREFLIGHT_RHEL_STATUS["$repo"]="deferred"
        else
            CUDA_PREFLIGHT_RHEL_STATUS["$repo"]="unreadable"
        fi
        return 0
    fi

    if ! preflight_fetch "$repomd_url" > "$repomd_file"; then
        CUDA_PREFLIGHT_RHEL_STATUS["$repo"]="unreachable"
        rm -f "$repomd_file"
        return 0
    fi

    primary_rel=$(awk '
        BEGIN { RS="</data>" }
        /<data type="primary">/ {
            if (match($0, /location href="[^"]+"/)) {
                rel = substr($0, RSTART, RLENGTH)
                sub(/^.*href="/, "", rel)
                sub(/"$/, "", rel)
                print rel
                exit
            }
        }
    ' "$repomd_file")
    if [ -z "$primary_rel" ]; then
        CUDA_PREFLIGHT_RHEL_STATUS["$repo"]="unreadable"
        return 0
    fi

    primary_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/${primary_rel}"
    if ! preflight_fetch "$primary_url" > "$primary_file"; then
        CUDA_PREFLIGHT_RHEL_STATUS["$repo"]="unreachable"
        rm -f "$primary_file"
        return 0
    fi
    if ! gzip -dc "$primary_file" > "$primary_text_file" 2>/dev/null; then
        CUDA_PREFLIGHT_RHEL_STATUS["$repo"]="unreadable"
        return 0
    fi

    CUDA_PREFLIGHT_RHEL_PRIMARY_FILES["$repo"]="$primary_text_file"
    CUDA_PREFLIGHT_RHEL_PRIMARY_URLS["$repo"]="$primary_url"
    CUDA_PREFLIGHT_RHEL_STATUS["$repo"]="ok"
}

cuda_preflight_find_ubuntu_candidate() {
    local payload="$1"
    local package_name="$2"
    local requested_version="$3"

    printf '%s\n' "$payload" | awk -v pkg="$package_name" -v requested="$requested_version" '
        function matches(version, wanted, len) {
            if (wanted == "") {
                return 1
            }
            if (wanted ~ /-/) {
                return version == wanted
            }
            len = length(wanted)
            return version == wanted || substr(version, 1, len + 1) == wanted "-"
        }
        $1 == "Package:" && $2 == pkg { pkgmatch=1; next }
        pkgmatch && $1 == "Version:" {
            if (matches($2, requested)) {
                print $2
            }
        }
        pkgmatch && $0 == "" { pkgmatch=0 }
    ' | sort -V | tail -1
}

cuda_preflight_find_rhel_candidate() {
    local metadata_file="$1"
    local package_name="$2"
    local requested_version="$3"

    awk -v pkg="$package_name" -v requested="$requested_version" '
        function matches(version, wanted, len) {
            if (wanted == "") {
                return 1
            }
            if (wanted ~ /-/) {
                return version == wanted
            }
            len = length(wanted)
            return version == wanted || substr(version, 1, len + 1) == wanted "-"
        }
        BEGIN { RS="</package>" }
        $0 ~ "<name>" pkg "</name>" {
            version = ""
            release = ""
            location = ""
            if (match($0, /ver="[^"]+"/)) {
                version = substr($0, RSTART, RLENGTH)
                sub(/^ver="/, "", version)
                sub(/"$/, "", version)
            }
            if (match($0, /rel="[^"]+"/)) {
                release = substr($0, RSTART, RLENGTH)
                sub(/^rel="/, "", release)
                sub(/"$/, "", release)
            }
            if (match($0, /href="[^"]+"/)) {
                location = substr($0, RSTART, RLENGTH)
                sub(/^href="/, "", location)
                sub(/"$/, "", location)
            }
            if (release != "") {
                version = version "-" release
            }
            if (version != "" && location != "" && matches(version, requested)) {
                print version "\t" location
            }
        }
    ' "$metadata_file" | sort -V -k1,1 | tail -1
}

cuda_preflight_check_requested_version() {
    local requested_version="$1"
    local target_version
    local target_stream
    local target_exact_version=""
    local cuda_package_stream
    local repo
    local status
    local candidate
    local saw_metadata=false
    local saw_unreachable=false
    local saw_deferred=false
    local found=false

    target_version=$(cuda_normalize_requested_version "$requested_version")
    target_stream=$(cuda_version_stream "$target_version")
    cuda_requested_version_is_exact "$target_version" && target_exact_version="$target_version"
    cuda_package_stream="${target_stream//./-}"

    if cuda_installed_version_matches_request "$target_version"; then
        preflight_info "CUDA $requested_version is already installed and will be reused."
        CUDA_PREFLIGHT_SUCCESSFUL_STREAMS+=("$target_stream")
        return 0
    fi

    for repo in "${CUDA_REPO_VERSIONS[@]}"; do
        [ -n "$repo" ] || continue
        candidate=""
        if [ "$OS_TYPE" = "ubuntu" ]; then
            cuda_preflight_load_ubuntu_metadata "$repo"
            status="${CUDA_PREFLIGHT_UBUNTU_STATUS[$repo]:-unreachable}"
            case "$status" in
                deferred)
                    saw_deferred=true
                    ;;
                ok)
                    if [ "$CUDA_PREFLIGHT_PARSER_AVAILABLE" = true ]; then
                        saw_metadata=true
                        candidate=$(cuda_preflight_find_ubuntu_candidate \
                            "${CUDA_PREFLIGHT_UBUNTU_PACKAGES[$repo]}" \
                            "cuda-toolkit-${cuda_package_stream}" "$target_exact_version")
                    elif [ "${SETUP_PLANNED_CORE:-0}" = 1 ]; then
                        saw_deferred=true
                    else
                        saw_unreachable=true
                    fi
                    ;;
                *)
                    saw_unreachable=true
                    ;;
            esac
        elif [ "$OS_TYPE" = "rhel" ]; then
            cuda_preflight_load_rhel_metadata "$repo"
            status="${CUDA_PREFLIGHT_RHEL_STATUS[$repo]:-unreachable}"
            case "$status" in
                deferred)
                    saw_deferred=true
                    ;;
                ok)
                    saw_metadata=true
                    if [ "$CUDA_PREFLIGHT_PARSER_AVAILABLE" = true ]; then
                        candidate=$(cuda_preflight_find_rhel_candidate \
                            "${CUDA_PREFLIGHT_RHEL_PRIMARY_FILES[$repo]}" \
                            "cuda-toolkit-${cuda_package_stream}" "$target_exact_version")
                    fi
                    ;;
                *)
                    saw_unreachable=true
                    ;;
            esac
        fi

        if [ -n "$candidate" ]; then
            preflight_info "CUDA $requested_version is available from repository $repo (candidate: ${candidate%%$'\t'*})."
            found=true
            break
        fi
    done

    if [ "$found" = true ]; then
        CUDA_PREFLIGHT_SUCCESSFUL_STREAMS+=("$target_stream")
        return 0
    fi

    if [ "$saw_metadata" = true ]; then
        if [ "$saw_unreachable" = true ]; then
            preflight_error "CUDA $requested_version was absent from reachable repository metadata; one or more fallback metadata endpoints were unreachable."
        else
            preflight_error "CUDA $requested_version is not available in the reachable CUDA repository metadata."
        fi
    elif [ "$saw_unreachable" = true ]; then
        preflight_error "CUDA $requested_version could not be checked because all CUDA repository metadata endpoints were unreachable."
    elif [ "$saw_deferred" = true ]; then
        preflight_defer "CUDA $requested_version repository metadata check deferred until the core fetch tools are installed."
    else
        preflight_error "No CUDA repositories were available to check CUDA $requested_version."
    fi
}

cuda_preflight_check_driver() {
    local driver_package=""
    local installed_version=""
    local candidate_version=""
    local headers_package headers_candidate repository candidate
    local driver_ready=false
    local cuda_stream="${DEFAULT_CUDA_VERSION_STREAM:-}"
    local headers_packages=()

    if ! command -v lspci &> /dev/null || ! has_nvidia_pci_devices; then
        preflight_info "No NVIDIA GPU detected via PCI enumeration; the normal installer will skip driver installation."
        return 0
    fi
    if command -v nvidia-smi &> /dev/null && nvidia-smi >/dev/null 2>&1; then
        driver_ready=true
    fi
    if [ -z "$cuda_stream" ] && (( ${#CUDA_PREFLIGHT_REQUESTED_VERSIONS[@]} )); then
        cuda_stream=$(cuda_version_stream "${CUDA_PREFLIGHT_REQUESTED_VERSIONS[0]}")
    fi

    if [ "$OS_TYPE" = ubuntu ]; then
        driver_package=$(resolve_ubuntu_driver_package "$cuda_stream")
        if [ -n "$driver_package" ]; then
            candidate_version=$(ubuntu_package_candidate_version "$driver_package")
            installed_version=$(dpkg-query -W -f='${Status} ${Version}\n' "$driver_package" 2>/dev/null | awk '
                $1 == "install" && $2 == "ok" && $3 == "installed" { print $4; exit }
            ')
        fi
        headers_packages=("linux-headers-$(uname -r)")
    else
        driver_package=nvidia-open
        for repository in "rhel${VERSION_ID%%.*}" rhel8; do
            cuda_preflight_load_rhel_metadata "$repository"
            if [ "${CUDA_PREFLIGHT_RHEL_STATUS[$repository]:-}" = ok ]; then
                candidate=$(cuda_preflight_find_rhel_candidate \
                    "${CUDA_PREFLIGHT_RHEL_PRIMARY_FILES[$repository]}" "$driver_package" "")
                if [ -n "$candidate" ]; then
                    candidate_version="${candidate%%$'\t'*}"
                    break
                fi
            fi
        done
        if [ -z "$candidate_version" ]; then
            candidate_version=$(rhel_package_candidate_version "$driver_package")
        fi
        if rpm -q "$driver_package" >/dev/null 2>&1; then
            installed_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$driver_package" 2>/dev/null)
        fi
        headers_packages=("kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)")
    fi

    if [ -z "$candidate_version" ]; then
        if [ "$driver_ready" = true ] && { [ "$OS_TYPE" = ubuntu ] || [ -n "$installed_version" ]; }; then
            preflight_info "The host NVIDIA driver is working; no driver update candidate was resolved."
        elif [ "${SETUP_PLANNED_CORE:-0}" = 1 ]; then
            preflight_defer "NVIDIA driver candidate must be checked again after the planned core tools/package metadata refresh."
        else
            preflight_error "NVIDIA GPU is present, but a working driver or an installable driver candidate could not be confirmed."
        fi
        return 0
    fi
    if [ "$installed_version" = "$candidate_version" ]; then
        preflight_info "NVIDIA driver package $driver_package already matches the available candidate."
        return 0
    fi
    # A responding nvidia-smi does not mean no upgrade: normal installation
    # upgrades an older driver package and therefore still needs kernel headers.
    preflight_info "Checking prerequisites for NVIDIA driver $driver_package $candidate_version"
    for headers_package in "${headers_packages[@]}"; do
        if [ "$OS_TYPE" = ubuntu ]; then
            dpkg -s "$headers_package" >/dev/null 2>&1 && continue
            headers_candidate=$(ubuntu_package_candidate_version "$headers_package")
        else
            rpm -q "$headers_package" >/dev/null 2>&1 && continue
            headers_candidate=$(rhel_package_candidate_version "$headers_package")
        fi
        if [ -n "$headers_candidate" ]; then
            preflight_info "Matching kernel headers are available: $headers_package"
        elif [ "${SETUP_PLANNED_CORE:-0}" = 1 ]; then
            preflight_defer "$headers_package availability must be rechecked after the core package metadata refresh."
        else
            preflight_error "NVIDIA driver installation requires $headers_package, but no matching package candidate is available."
        fi
    done
}

cuda_preflight_check_mutation_paths() {
    local bashrc_path="${HOME:-/root}/.bashrc"

    [ "${#CUDA_PREFLIGHT_REQUESTED_VERSIONS[@]}" -gt 0 ] || return 0
    if [ "$(id -u)" -eq 0 ]; then
        preflight_writable "/usr/local" || true
    else
        preflight_info "Default CUDA links will use the checked sudo privilege; no unprivileged /usr/local write is required."
    fi
    preflight_writable "$bashrc_path" || true
}

run_cuda_preflight() {
    local architecture
    local requested_version

    preflight_info "Running CUDA preflight; no package, repository, default-link, shell, or driver changes will be made."
    architecture=$(uname -m 2>/dev/null || printf 'unknown')
    if [ "$architecture" != "x86_64" ]; then
        preflight_error "Unsupported architecture: $architecture (CUDA repository URLs are available only for x86_64)."
    else
        preflight_info "Supported architecture detected: x86_64."
    fi

    preflight_privileges || true
    cuda_preflight_check_tools
    collect_installed_cuda_versions

    if [ "$CUDA_PREFLIGHT_OS_SUPPORTED" != true ]; then
        preflight_info "Skipping CUDA repository and driver checks because the operating system is unsupported."
        return 0
    fi
    if [ "${#CUDA_REPO_VERSIONS[@]}" -eq 0 ]; then
        preflight_error "No CUDA repository fallback candidates could be built for this operating system."
    fi

    CUDA_PREFLIGHT_REQUESTED_VERSIONS=("${CUDA_VERSION_ARGS[@]}")
    if [ "${#CUDA_PREFLIGHT_REQUESTED_VERSIONS[@]}" -eq 0 ]; then
        preflight_defer "No explicit CUDA version selection was supplied; interactive latest/custom selection remains unchanged."
    else
        for requested_version in "${CUDA_PREFLIGHT_REQUESTED_VERSIONS[@]}"; do
            cuda_preflight_check_requested_version "$requested_version"
        done
    fi

    cuda_preflight_check_mutation_paths
    cuda_preflight_check_driver
}


install_cuda_toolkit_version() {
    local requested_version="$1"
    local target_version="$requested_version"
    local target_major
    local target_remainder
    local target_minor
    local target_stream
    local target_exact_version=""
    local cuda_package_stream
    local repo_version
    local cuda_installed=false

    if [[ "$target_version" =~ ^[0-9]+$ ]]; then
        target_version="${target_version}.0"
    fi

    target_major="${target_version%%.*}"
    target_remainder="${target_version#*.}"
    target_minor="${target_remainder%%.*}"
    target_stream="${target_major}.${target_minor}"
    if [[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]]; then
        target_exact_version="$target_version"
    fi
    if cuda_installed_version_matches_request "$target_version"; then
        print_info "CUDA $target_version is already installed; reusing the matching toolkit."
        LAST_INSTALLED_CUDA_STREAM="$target_stream"
        return 0
    fi


    if [ -n "$DRIVER_CUDA_VERSION" ]; then
        local driver_major="${DRIVER_CUDA_VERSION%%.*}"
        local driver_minor="${DRIVER_CUDA_VERSION#*.}"
        if [ "$target_major" -gt "$driver_major" ] || { [ "$target_major" -eq "$driver_major" ] && [ "$target_minor" -gt "$driver_minor" ]; }; then
            print_warning "Selected CUDA version $target_version may exceed driver support ($DRIVER_CUDA_VERSION). Installation may fail unless the driver is updated."
        else
            print_info "Driver support check passed for CUDA $target_version."
        fi
    else
        print_warning "Driver capabilities unknown; proceeding with CUDA $target_version."
    fi

    cuda_package_stream="${target_stream//./-}"
    for repo_version in "${CUDA_REPO_VERSIONS[@]}"; do
        [ -z "$repo_version" ] && continue
        print_info "Attempting CUDA $target_version installation from NVIDIA repository: $repo_version"

        if [ "$OS_TYPE" = "ubuntu" ]; then
            local packages_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo_version}/x86_64/Packages"
            local package_version
            local cuda_apt_package
            local cuda_apt_package_spec

            package_version=$(curl -fsSL "$packages_url" 2>/dev/null | awk -v pkg="cuda-toolkit-${cuda_package_stream}" -v requested_version="$target_exact_version" '
                function matches_requested(version, requested, len) {
                    if (requested == "") {
                        return 1
                    }
                    if (requested ~ /-/) {
                        return version == requested
                    }
                    len = length(requested)
                    return (version == requested || substr(version, 1, len + 1) == requested "-")
                }
                $1 == "Package:" && $2 == pkg { pkgmatch=1; next }
                pkgmatch && $1 == "Version:" {
                    if (matches_requested($2, requested_version)) {
                        print $2
                    }
                }
                pkgmatch && $0 == "" { pkgmatch=0 }
            ' | sort -V | tail -1)

            if [ -z "$package_version" ]; then
                if [ -n "$target_exact_version" ]; then
                    print_warning "Could not determine package version for cuda-toolkit-${cuda_package_stream} matching $target_exact_version from $repo_version"
                else
                    print_warning "Could not determine package version for cuda-toolkit-${cuda_package_stream} from $repo_version"
                fi
                continue
            fi

            if ! setup_ubuntu_cuda_repo "$repo_version"; then
                continue
            fi

            cuda_apt_package="cuda-toolkit-${cuda_package_stream}"
            cuda_apt_package_spec="$cuda_apt_package"
            if [ -n "$target_exact_version" ]; then
                cuda_apt_package_spec="${cuda_apt_package}=${package_version}"
                print_info "Resolved CUDA toolkit package version: $package_version"
            else
                print_info "Resolved CUDA toolkit package stream: $cuda_apt_package (latest matching package version: $package_version)"
            fi

            print_info "Installing CUDA toolkit package from NVIDIA repository..."
            if [ -n "$target_exact_version" ]; then
                if ${SUDO_PREFIX}apt install -y --allow-downgrades "$cuda_apt_package_spec"; then
                    cuda_installed=true
                else
                    print_warning "Failed to install CUDA toolkit package $cuda_apt_package_spec"
                fi
            elif $PKG_INSTALL_CMD "$cuda_apt_package_spec"; then
                cuda_installed=true
            else
                print_warning "Failed to install CUDA toolkit package $cuda_apt_package_spec"
            fi
        elif [ "$OS_TYPE" = "rhel" ]; then
            local primary_url
            local rpm_relative_path
            local rpm_file_basename
            local cuda_rpm_file
            local cuda_rpm_url

            primary_url=$(get_rhel_primary_url "$repo_version")
            if [ -z "$primary_url" ]; then
                print_warning "Could not locate repository metadata for $repo_version"
                continue
            fi

            rpm_relative_path=$(curl -fsSL "$primary_url" 2>/dev/null | gzip -dc 2>/dev/null | awk -v pkg="cuda-toolkit-${cuda_package_stream}" -v requested_version="$target_exact_version" '
                function matches_requested(version, requested, len) {
                    if (requested == "") {
                        return 1
                    }
                    if (requested ~ /-/) {
                        return version == requested
                    }
                    len = length(requested)
                    return (version == requested || substr(version, 1, len + 1) == requested "-")
                }
                /<package/ { pkgmatch=0; version_ok=0 }
                $0 ~ "<name>" pkg "</name>" {
                    pkgmatch=1
                    version_ok=(requested_version == "")
                }
                pkgmatch && /<version / {
                    version=""
                    release=""
                    version_ok=0
                    if (match($0, /ver="([^"]+)"/, arr)) {
                        version=arr[1]
                    }
                    if (match($0, /rel="([^"]+)"/, arr)) {
                        release=arr[1]
                    }
                    if (release != "") {
                        version=version "-" release
                    }
                    if (matches_requested(version, requested_version)) {
                        version_ok=1
                    }
                }
                pkgmatch && /<location href=/ && version_ok == 1 {
                    match($0, /href="([^"]+)"/, arr)
                    if (arr[1] != "") {
                        print arr[1]
                        exit
                    }
                }
            ')

            if [ -z "$rpm_relative_path" ]; then
                if [ -n "$target_exact_version" ]; then
                    print_warning "Could not locate CUDA toolkit package metadata for $repo_version matching $target_exact_version"
                else
                    print_warning "Could not locate CUDA toolkit package metadata for $repo_version"
                fi
                continue
            fi

            rpm_file_basename=$(basename "$rpm_relative_path")
            cuda_rpm_file="${CUDA_CACHE_DIR}/${repo_version}-${rpm_file_basename}"
            cuda_rpm_url="https://developer.download.nvidia.com/compute/cuda/repos/${repo_version}/x86_64/$rpm_relative_path"

            if [ ! -f "$cuda_rpm_file" ]; then
                print_info "Downloading CUDA toolkit package from NVIDIA..."
                if wget -O "$cuda_rpm_file" "$cuda_rpm_url"; then
                    CUDA_PACKAGE_DOWNLOADS+=("$cuda_rpm_file")
                else
                    print_warning "Failed to download $cuda_rpm_url"
                    rm -f "$cuda_rpm_file"
                    continue
                fi
            else
                print_info "Using temporary CUDA toolkit package: $cuda_rpm_file"
            fi

            if [ "$RHEL_METADATA_REFRESHED" = false ]; then
                print_info "Refreshing package metadata before CUDA installation..."
                if ! $PKG_UPDATE_CMD; then
                    print_warning "Package metadata refresh failed; CUDA installation may require manual dependency resolution"
                fi
                RHEL_METADATA_REFRESHED=true
            fi

            print_info "Installing CUDA toolkit package..."
            if $PKG_INSTALL_CMD "$cuda_rpm_file"; then
                cuda_installed=true
            else
                print_warning "Failed to install CUDA toolkit from $cuda_rpm_file"
            fi
        fi

        if [ "$cuda_installed" = true ]; then
            break
        fi
    done

    if [ "$cuda_installed" = true ]; then
        print_info "✓ CUDA $target_version installed successfully"
        LAST_INSTALLED_CUDA_STREAM="$target_stream"
        return 0
    fi

    print_error "Failed to install CUDA $target_version"
    print_info "Manual installer: https://developer.nvidia.com/cuda-downloads"
    return 1
}

configure_cuda_environment() {
    local cuda_home_in_bashrc=false
    local cuda_path_in_bashrc=false
    local cuda_ld_library_path_in_bashrc=false
    local add_cuda_env="n"

    if grep -q 'CUDA_HOME="/usr/local/cuda"' ~/.bashrc 2>/dev/null; then
        cuda_home_in_bashrc=true
    fi
    if grep -q "/usr/local/cuda/bin" ~/.bashrc 2>/dev/null; then
        cuda_path_in_bashrc=true
    fi
    if grep -q "/usr/local/cuda/lib64" ~/.bashrc 2>/dev/null; then
        cuda_ld_library_path_in_bashrc=true
    fi

    if [ "$cuda_home_in_bashrc" = true ] && [ "$cuda_path_in_bashrc" = true ] && [ "$cuda_ld_library_path_in_bashrc" = true ]; then
        return 0
    fi

    if [ "$AUTO_YES" = true ]; then
        add_cuda_env="y"
    else
        read -r -p "Add CUDA environment variables to ~/.bashrc? (y/n): " add_cuda_env
    fi

    if [[ "$add_cuda_env" =~ ^[Yy]$ ]]; then
        if ! printf '\n' >> ~/.bashrc; then
            print_error "Failed to update ~/.bashrc with CUDA environment settings."
            return 1
        fi
        if ! grep -q '^# CUDA toolkit$' ~/.bashrc 2>/dev/null; then
            if ! printf '%s\n' '# CUDA toolkit' >> ~/.bashrc; then
                print_error "Failed to write the CUDA toolkit marker to ~/.bashrc."
                return 1
            fi
        fi
        if [ "$cuda_home_in_bashrc" = false ]; then
            if ! printf '%s\n' 'export CUDA_HOME="/usr/local/cuda"' >> ~/.bashrc; then
                print_error "Failed to write CUDA_HOME to ~/.bashrc."
                return 1
            fi
        fi
        if [ "$cuda_path_in_bashrc" = false ]; then
            if ! printf '%s\n' 'export PATH="/usr/local/cuda/bin:$PATH"' >> ~/.bashrc; then
                print_error "Failed to write CUDA PATH to ~/.bashrc."
                return 1
            fi
        fi
        if [ "$cuda_ld_library_path_in_bashrc" = false ]; then
            if ! printf '%s\n' 'export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"' >> ~/.bashrc; then
                print_error "Failed to write CUDA library path to ~/.bashrc."
                return 1
            fi
        fi
        print_info "Added CUDA environment variables to ~/.bashrc"
        print_info "Run 'source ~/.bashrc' or start a new terminal to use nvcc"
    else
        print_info "Skipped adding CUDA environment variables"
    fi
}
TARGET_CUDA_VERSION_DEFAULT="12.9"
CURRENT_CUDA_DISPLAY="None"
if command -v nvcc &> /dev/null; then
    CURRENT_CUDA_DISPLAY="$CUDA_VERSION"
fi


if [ -n "$DRIVER_CUDA_VERSION" ]; then
    print_info "Driver reports CUDA compatibility up to version $DRIVER_CUDA_VERSION"
else
    print_info "No NVIDIA driver version detected; proceeding without driver compatibility data"
fi

build_cuda_repo_versions
if [ "$PREFLIGHT_MODE" = true ]; then
    run_cuda_preflight
    preflight_finish
    preflight_status=$?
    exit "$preflight_status"
fi


LATEST_CUDA_VERSION=""
if [ "${#CUDA_VERSION_ARGS[@]}" -eq 0 ]; then
    LATEST_CUDA_VERSION=$(detect_latest_cuda_version "${CUDA_REPO_VERSIONS[@]}")
    if [ -z "$LATEST_CUDA_VERSION" ]; then
        print_warning "Unable to determine the latest CUDA version automatically; defaulting to $TARGET_CUDA_VERSION_DEFAULT."
        LATEST_CUDA_VERSION="$TARGET_CUDA_VERSION_DEFAULT"
    else
        print_info "Latest CUDA version detected from repositories: $LATEST_CUDA_VERSION"
    fi
fi

print_info "Installed CUDA versions detected: $INSTALLED_CUDA_VERSIONS_DISPLAY"
print_info "Current CUDA version: $CURRENT_CUDA_DISPLAY"

EXPLICIT_CUDA_REQUEST=false
CUDA_INSTALL_REQUESTED=false
REQUESTED_CUDA_VERSIONS=()

if [ "${#CUDA_VERSION_ARGS[@]}" -gt 0 ]; then
    EXPLICIT_CUDA_REQUEST=true
    REQUESTED_CUDA_VERSIONS=("${CUDA_VERSION_ARGS[@]}")

    request_display=""
    for request_index in "${!CUDA_VERSION_ARGS[@]}"; do
        request_label="${CUDA_VERSION_ARGS[$request_index]}"
        if [ "${CUDA_VERSION_STREAMS[$request_index]}" = "$DEFAULT_CUDA_VERSION_STREAM" ]; then
            request_label="$request_label (default)"
        fi
        if [ -n "$request_display" ]; then
            request_display+=", "
        fi
        request_display+="$request_label"
    done

    if [ "$AUTO_YES" = true ]; then
        CUDA_INSTALL_REQUESTED=true
        print_info "Automatic mode enabled (-y): installing requested CUDA versions: $request_display"
    else
        read -r -p "Install requested CUDA versions ($request_display)? (y/n): " INSTALL_REQUESTED_CUDAS
        if [[ "$INSTALL_REQUESTED_CUDAS" =~ ^[Yy]$ ]]; then
            CUDA_INSTALL_REQUESTED=true
        else
            print_info "Skipped requested CUDA installations."
        fi
    fi
else
    CUDA_CHOICE_ACTION=""
    echo "Choose CUDA installation option:"
    if [ "$CURRENT_CUDA_DISPLAY" = "None" ]; then
        echo "  1) Install latest version ($LATEST_CUDA_VERSION)"
        echo "  2) Install custom version"
        echo "  3) Skip CUDA installation"
        read -r -p "Enter choice (1/2/3): " CUDA_CHOICE
        while [[ ! "$CUDA_CHOICE" =~ ^[123]$ ]]; do
            read -r -p "Please enter 1, 2, or 3: " CUDA_CHOICE
        done
        case $CUDA_CHOICE in
            1) CUDA_CHOICE_ACTION="latest" ;;
            2) CUDA_CHOICE_ACTION="custom" ;;
            3) CUDA_CHOICE_ACTION="skip" ;;
        esac
    else
        echo "  1) Keep current version"
        echo "  2) Install latest version ($LATEST_CUDA_VERSION)"
        echo "  3) Install custom version"
        echo "  4) Skip CUDA installation"
        read -r -p "Enter choice (1/2/3/4): " CUDA_CHOICE
        while [[ ! "$CUDA_CHOICE" =~ ^[1234]$ ]]; do
            read -r -p "Please enter 1, 2, 3, or 4: " CUDA_CHOICE
        done
        case $CUDA_CHOICE in
            1) CUDA_CHOICE_ACTION="keep" ;;
            2) CUDA_CHOICE_ACTION="latest" ;;
            3) CUDA_CHOICE_ACTION="custom" ;;
            4) CUDA_CHOICE_ACTION="skip" ;;
        esac
    fi

    case $CUDA_CHOICE_ACTION in
        keep)
            print_info "Keeping existing CUDA toolkit ($CURRENT_CUDA_DISPLAY)."
            ;;
        latest)
            latest_stream="$(cuda_version_stream "$LATEST_CUDA_VERSION")"
            latest_already_present=false
            for installed_version in "${INSTALLED_CUDA_VERSIONS[@]}"; do
                if [ "$(cuda_version_stream "$installed_version")" = "$latest_stream" ]; then
                    latest_already_present=true
                    break
                fi
            done
            if [ "$latest_already_present" = true ]; then
                print_info "Latest CUDA version $LATEST_CUDA_VERSION is already installed; no action needed."
            else
                CUDA_INSTALL_REQUESTED=true
                REQUESTED_CUDA_VERSIONS=("$LATEST_CUDA_VERSION")
            fi
            ;;
        custom)
            while true; do
                read -r -p "Enter desired CUDA version (e.g. 13, 13.0, 13.0.1, or 13.0.2-1): " CUSTOM_VERSION
                if is_valid_cuda_version_arg "$CUSTOM_VERSION"; then
                    CUDA_INSTALL_REQUESTED=true
                    REQUESTED_CUDA_VERSIONS=("$CUSTOM_VERSION")
                    break
                fi
                print_error "Invalid version number. Use major, major.minor, major.minor.patch, or major.minor.patch-release."
            done
            ;;
        skip)
            print_info "Skipping CUDA toolkit installation per user selection."
            ;;
    esac
fi

PREINSTALL_CUDA_DEFAULT_EXISTED=false
PREINSTALL_CUDA_DEFAULT_WAS_SYMLINK=false
PREINSTALL_CUDA_DEFAULT_LINK_TARGET=""
if [ -e /usr/local/cuda ] || [ -L /usr/local/cuda ]; then
    PREINSTALL_CUDA_DEFAULT_EXISTED=true
fi
if [ -L /usr/local/cuda ]; then
    PREINSTALL_CUDA_DEFAULT_WAS_SYMLINK=true
    PREINSTALL_CUDA_DEFAULT_LINK_TARGET="$(readlink /usr/local/cuda)"
fi

LAST_INSTALLED_CUDA_STREAM=""
ANY_CUDA_INSTALLED=false
RHEL_METADATA_REFRESHED=false
SUCCESSFUL_CUDA_STREAMS=()

cuda_default_target_is_healthy() {
    local successful_stream

    for successful_stream in "${SUCCESSFUL_CUDA_STREAMS[@]}"; do
        if [ "$successful_stream" = "$DEFAULT_CUDA_VERSION_STREAM" ]; then
            return 0
        fi
    done

    if [ -n "$DEFAULT_CUDA_VERSION_ARG" ] && cuda_installed_version_matches_request "$DEFAULT_CUDA_VERSION_ARG"; then
        return 0
    fi

    return 1
}


if [ "$CUDA_INSTALL_REQUESTED" = true ]; then
    for requested_cuda_version in "${REQUESTED_CUDA_VERSIONS[@]}"; do
        if install_cuda_toolkit_version "$requested_cuda_version"; then
            ANY_CUDA_INSTALLED=true
            successful_stream="$(cuda_version_stream "$(cuda_normalize_requested_version "$requested_cuda_version")")"
            SUCCESSFUL_CUDA_STREAMS+=("$successful_stream")
        else
            INSTALL_SUCCESS=false
            print_error "Stopping after the first failed CUDA toolkit prerequisite."
            break
        fi
    done
fi

if [ "$ANY_CUDA_INSTALLED" = true ] && [ "$INSTALL_SUCCESS" = true ]; then
    if [ "$EXPLICIT_CUDA_REQUEST" = true ]; then
        if [ -n "$DEFAULT_CUDA_VERSION_STREAM" ]; then
            if ! cuda_default_target_is_healthy; then
                print_error "Refusing to activate CUDA $DEFAULT_CUDA_VERSION_STREAM as default because its requested toolkit was not successfully installed or reused."
                INSTALL_SUCCESS=false
            else
                print_info "Setting explicitly selected CUDA default: $DEFAULT_CUDA_VERSION_STREAM"
                if ! set_default_cuda_version "$DEFAULT_CUDA_VERSION_STREAM"; then
                    print_error "Failed to set CUDA $DEFAULT_CUDA_VERSION_STREAM as the default."
                    INSTALL_SUCCESS=false
                fi
            fi
        elif ! restore_preinstall_cuda_default; then
            print_error "Failed to preserve the pre-install CUDA default."
            INSTALL_SUCCESS=false
        fi
    else
        TARGET_CUDA_VERSION_NORMALIZED="$LAST_INSTALLED_CUDA_STREAM"
        if ! prompt_for_default_cuda_version; then
            print_error "Failed to configure the selected CUDA default."
            INSTALL_SUCCESS=false
        fi
    fi

    if [ -e /usr/local/cuda ]; then
        if ! configure_cuda_environment; then
            print_error "CUDA environment configuration failed."
            INSTALL_SUCCESS=false
        fi
    else
        print_warning "No /usr/local/cuda default is set; skipping CUDA environment configuration."
    fi
fi

if [ "$INSTALL_SUCCESS" = true ]; then
    DRIVER_CUDA_STREAM="$(get_current_cuda_default_version)"
    if [ -z "$DRIVER_CUDA_STREAM" ]; then
        DRIVER_CUDA_STREAM="$CURRENT_CUDA_VERSION_NORMALIZED"
    fi
    if [ -z "$DRIVER_CUDA_STREAM" ]; then
        DRIVER_CUDA_STREAM="$LAST_INSTALLED_CUDA_STREAM"
    fi
    install_nvidia_driver_for_gpu_support "$DRIVER_CUDA_STREAM"
fi

echo ""
if [ "$INSTALL_SUCCESS" = true ]; then
    if [ "${#CUDA_PACKAGE_DOWNLOADS[@]}" -gt 0 ]; then
        echo ""
        print_info "CUDA support package(s) downloaded temporarily: ${CUDA_PACKAGE_DOWNLOADS[*]}"
        cleanup_cuda_cache
        print_info "Deleted temporary CUDA download directory: $CUDA_CACHE_DIR"
    fi
    print_info "✓ Installation complete!"
else
    print_error "❌ Installation had errors - check messages above"
    exit 1
fi
