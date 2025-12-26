#!/bin/bash
#
# Validator functions for Gentoo installer
# Provides state validation and sanity checks between phases
#

# Source common functions if not already loaded
if ! declare -f log >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=lib/common.sh
    source "${SCRIPT_DIR}/common.sh"
fi

# Validate disk partitioning
validate_partitions() {
    local disk="${1:-/dev/sda}"
    local boot_part="${disk}1"
    local root_part="${disk}2"

    log "Validating disk partitions on ${disk}"

    # Check if partitions exist
    if [ ! -b "${boot_part}" ]; then
        error "Boot partition ${boot_part} not found"
        return 1
    fi

    if [ ! -b "${root_part}" ]; then
        error "Root partition ${root_part} not found"
        return 1
    fi

    # Check filesystem types
    if ! blkid "${boot_part}" | grep -q "TYPE=\"vfat\""; then
        error "Boot partition ${boot_part} is not FAT32"
        return 1
    fi

    if ! blkid "${root_part}" | grep -q "TYPE=\"ext4\""; then
        error "Root partition ${root_part} is not ext4"
        return 1
    fi

    success "Disk partitions validated"
    return 0
}

# Validate mount points
validate_mounts() {
    log "Validating mount points"

    if ! mountpoint -q /mnt/gentoo; then
        error "/mnt/gentoo is not mounted"
        return 1
    fi

    if ! mountpoint -q /mnt/gentoo/boot/efi; then
        error "/mnt/gentoo/boot/efi is not mounted"
        return 1
    fi

    success "Mount points validated"
    return 0
}

# Validate stage3 extraction
validate_stage3() {
    local root_dir="${1:-/mnt/gentoo}"

    log "Validating stage3 installation at ${root_dir}"

    local required_dirs=(
        "${root_dir}/bin"
        "${root_dir}/etc"
        "${root_dir}/usr"
        "${root_dir}/var"
        "${root_dir}/home"
    )

    for dir in "${required_dirs[@]}"; do
        if [ ! -d "${dir}" ]; then
            error "Required directory missing: ${dir}"
            return 1
        fi
    done

    if [ ! -f "${root_dir}/etc/portage/make.conf" ]; then
        error "Portage not found in stage3"
        return 1
    fi

    success "Stage3 installation validated"
    return 0
}

# Validate chroot environment
validate_chroot() {
    log "Validating chroot environment"

    if ! in_chroot; then
        error "Not running in chroot environment"
        return 1
    fi

    # Check essential mounts in chroot
    if ! mountpoint -q /proc; then
        error "/proc not mounted in chroot"
        return 1
    fi

    if ! mountpoint -q /sys; then
        error "/sys not mounted in chroot"
        return 1
    fi

    if [ ! -f /etc/resolv.conf ] || [ ! -s /etc/resolv.conf ]; then
        warn "/etc/resolv.conf is missing or empty"
    fi

    success "Chroot environment validated"
    return 0
}

# Validate Portage configuration
validate_portage_config() {
    log "Validating Portage configuration"

    local config_files=(
        "/etc/portage/make.conf"
        "/etc/portage/repos.conf/gentoo.conf"
    )

    for file in "${config_files[@]}"; do
        if [ ! -f "${file}" ]; then
            error "Required config file missing: ${file}"
            return 1
        fi
    done

    # Check if Portage tree is synced
    if [ ! -d "/var/db/repos/gentoo/profiles" ]; then
        error "Portage tree not synced"
        return 1
    fi

    success "Portage configuration validated"
    return 0
}

# Validate kernel installation
validate_kernel() {
    log "Validating kernel installation"

    # Check for kernel binary
    if ! ls /boot/vmlinuz-* >/dev/null 2>&1; then
        error "No kernel found in /boot"
        return 1
    fi

    # Check for initramfs
    if ! ls /boot/initramfs-* >/dev/null 2>&1; then
        warn "No initramfs found in /boot (may be intentional)"
    fi

    # Check kernel sources if using manual build
    if [ -d /usr/src/linux ]; then
        if [ ! -f /usr/src/linux/.config ]; then
            warn "Kernel sources present but not configured"
        fi
    fi

    success "Kernel installation validated"
    return 0
}

# Validate bootloader installation
validate_bootloader() {
    log "Validating bootloader installation"

    # Check GRUB installation
    if [ ! -d /boot/efi/EFI/gentoo-new ]; then
        error "GRUB not installed to EFI partition"
        return 1
    fi

    if [ ! -f /boot/grub/grub.cfg ]; then
        error "GRUB configuration not generated"
        return 1
    fi

    # Verify grub.cfg contains kernel entry
    if ! grep -q "vmlinuz" /boot/grub/grub.cfg; then
        error "GRUB config does not contain kernel entry"
        return 1
    fi

    success "Bootloader installation validated"
    return 0
}

# Validate system packages
validate_system_packages() {
    log "Validating system packages"

    local critical_packages=(
        "sys-apps/systemd"
        "sys-boot/grub"
        "net-misc/dhcpcd"
    )

    for pkg in "${critical_packages[@]}"; do
        if ! package_installed "${pkg}"; then
            error "Critical package not installed: ${pkg}"
            return 1
        fi
    done

    success "System packages validated"
    return 0
}

# Validate user configuration
validate_users() {
    log "Validating user configuration"

    # Check if non-root user exists
    if ! grep -q "^henninb:" /etc/passwd; then
        error "User henninb not found"
        return 1
    fi

    # Check if user is in wheel group
    if ! groups henninb | grep -q wheel; then
        warn "User henninb not in wheel group"
    fi

    # Check sudo/doas configuration
    if [ ! -f /etc/sudoers ] && [ ! -f /etc/doas.conf ]; then
        warn "Neither sudo nor doas is configured"
    fi

    success "User configuration validated"
    return 0
}

# Validate network configuration
validate_network() {
    log "Validating network configuration"

    # Check if network service is enabled
    if command_exists systemctl; then
        if ! systemctl is-enabled dhcpcd >/dev/null 2>&1 && \
           ! systemctl is-enabled NetworkManager >/dev/null 2>&1; then
            warn "No network service is enabled"
        fi
    fi

    success "Network configuration validated"
    return 0
}

# Validate locale and timezone
validate_locale() {
    log "Validating locale configuration"

    if [ ! -f /etc/locale.gen ]; then
        error "/etc/locale.gen not found"
        return 1
    fi

    if ! grep -q "^en_US.UTF-8" /etc/locale.gen; then
        warn "en_US.UTF-8 locale not enabled"
    fi

    # Check timezone
    if [ ! -L /etc/localtime ]; then
        warn "Timezone not configured"
    fi

    success "Locale configuration validated"
    return 0
}

export -f validate_partitions validate_mounts validate_stage3 validate_chroot
export -f validate_portage_config validate_kernel validate_bootloader
export -f validate_system_packages validate_users validate_network validate_locale
