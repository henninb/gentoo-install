#!/bin/bash
#
# Pre-flight validation checks
# Verifies system prerequisites before installation begins
#

# Source common functions if not already loaded
if ! declare -f log >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=lib/common.sh
    source "${SCRIPT_DIR}/common.sh"
fi

# Check if running with sufficient privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This installer must be run as root"
        return 1
    fi
    return 0
}

# Check for required commands
check_required_commands() {
    local required_cmds=(
        "parted"
        "mkfs.fat"
        "mkfs.ext4"
        "mount"
        "curl"
        "tar"
        "sha256sum"
        "chroot"
    )

    local missing=()

    for cmd in "${required_cmds[@]}"; do
        if ! command_exists "${cmd}"; then
            missing+=("${cmd}")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required commands: ${missing[*]}"
        error "Please install these tools before running the installer"
        return 1
    fi

    return 0
}

# Check network connectivity
check_network() {
    log "Checking network connectivity..."

    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        error "No network connectivity detected"
        error "Please configure network before running the installer"
        return 1
    fi

    # Try to reach Gentoo mirror
    if ! curl -sL --max-time 10 -I https://www.gentoo.org/ >/dev/null 2>&1; then
        warn "Cannot reach gentoo.org"
        warn "Check your DNS configuration or firewall"
        if ! confirm "Continue anyway?"; then
            return 1
        fi
    fi

    return 0
}

# Check disk space
check_disk_space() {
    local disk="${1:-/dev/sda}"
    local min_size_gb=20  # Minimum 20GB recommended

    if [ ! -b "${disk}" ]; then
        error "Disk ${disk} not found"
        return 1
    fi

    local size_bytes
    size_bytes=$(blockdev --getsize64 "${disk}" 2>/dev/null || echo 0)
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))

    log "Disk ${disk} size: ${size_gb}GB"

    if [ "${size_gb}" -lt "${min_size_gb}" ]; then
        error "Disk is too small (${size_gb}GB < ${min_size_gb}GB minimum)"
        return 1
    fi

    return 0
}

# Check available memory
check_memory() {
    local min_mem_mb=2048  # Minimum 2GB RAM recommended

    local mem_mb
    mem_mb=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')

    log "Available memory: ${mem_mb}MB"

    if [ "${mem_mb}" -lt "${min_mem_mb}" ]; then
        warn "Low memory detected (${mem_mb}MB < ${min_mem_mb}MB recommended)"
        warn "Installation may be slow or fail during compilation"
        if ! confirm "Continue anyway?"; then
            return 1
        fi
    fi

    return 0
}

# Check CPU cores for MAKEOPTS
check_cpu_cores() {
    local cores
    cores=$(nproc 2>/dev/null || echo 1)

    log "CPU cores detected: ${cores}"

    if [ "${cores}" -lt 2 ]; then
        warn "Single-core CPU detected - compilation will be very slow"
    fi

    # Suggest MAKEOPTS
    local suggested_jobs=$((cores + 1))
    log "Recommended MAKEOPTS: -j${suggested_jobs}"

    return 0
}

# Check boot mode (UEFI vs BIOS)
check_boot_mode() {
    if [ -d /sys/firmware/efi ]; then
        log "Boot mode: UEFI"
        export BOOT_MODE="UEFI"
    else
        log "Boot mode: BIOS (Legacy)"
        export BOOT_MODE="BIOS"
        warn "This installer is configured for UEFI boot"
        warn "BIOS boot may require manual bootloader configuration"
        if ! confirm "Continue with BIOS boot?"; then
            return 1
        fi
    fi

    return 0
}

# Check for existing installations
check_existing_install() {
    local disk="${1:-/dev/sda}"

    # Check if disk has partitions
    if parted "${disk}" print 2>/dev/null | grep -q "Partition Table"; then
        warn "Disk ${disk} appears to have existing partitions"

        # Try to detect existing installations
        for part in "${disk}"?*; do
            [ -b "${part}" ] || continue

            local fstype
            fstype=$(blkid -s TYPE -o value "${part}" 2>/dev/null)

            if [ -n "${fstype}" ]; then
                warn "Found ${fstype} filesystem on ${part}"
            fi
        done

        error "DATA WILL BE DESTROYED!"
        if ! confirm "Are you ABSOLUTELY SURE you want to continue?" "no"; then
            return 1
        fi

        if ! confirm "Type 'yes' to confirm data destruction:" "no"; then
            return 1
        fi
    fi

    return 0
}

# Validate environment variables
check_environment() {
    log "Validating environment configuration..."

    # Optional: Check if critical env vars are set
    local warnings=0

    if [ -z "${DISK:-}" ]; then
        warn "DISK not set, will default to /dev/sda"
        ((warnings++))
    fi

    if [ -z "${HOSTNAME:-}" ]; then
        warn "HOSTNAME not set, will default to 'gentoo'"
        ((warnings++))
    fi

    if [ -z "${PRIMARY_USER:-}" ]; then
        warn "PRIMARY_USER not set, will default to 'henninb'"
        ((warnings++))
    fi

    if [ "${warnings}" -gt 0 ]; then
        log "You can set environment variables before running:"
        log "  export DISK=/dev/nvme0n1"
        log "  export HOSTNAME=myhostname"
        log "  export PRIMARY_USER=myuser"
        echo
    fi

    return 0
}

# Run all pre-flight checks
run_preflight_checks() {
    local disk="${1:-${DISK:-/dev/sda}}"

    section "Pre-flight Checks"

    local checks=(
        "check_root"
        "check_required_commands"
        "check_boot_mode"
        "check_network"
        "check_memory"
        "check_cpu_cores"
        "check_disk_space ${disk}"
        "check_environment"
    )

    local failed=0

    for check in "${checks[@]}"; do
        if ! eval "${check}"; then
            ((failed++))
        fi
    done

    if [ "${failed}" -gt 0 ]; then
        error "${failed} pre-flight check(s) failed"
        return 1
    fi

    success "All pre-flight checks passed"
    return 0
}

export -f check_root check_required_commands check_network check_disk_space
export -f check_memory check_cpu_cores check_boot_mode check_existing_install
export -f check_environment run_preflight_checks
