#!/bin/bash
#
# Comprehensive installation audit
# Verifies all aspects of the Gentoo installation
#

# Source common functions if not already loaded
if ! declare -f log >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=lib/common.sh
    source "${SCRIPT_DIR}/common.sh"
fi

# Audit results tracking
AUDIT_PASS=0
AUDIT_WARN=0
AUDIT_FAIL=0
AUDIT_RESULTS=()

# Add audit result
audit_result() {
    local status=$1  # PASS, WARN, FAIL
    local category=$2
    local message=$3

    case "${status}" in
        PASS)
            ((AUDIT_PASS++))
            success "[PASS] ${category}: ${message}"
            ;;
        WARN)
            ((AUDIT_WARN++))
            warn "[WARN] ${category}: ${message}"
            ;;
        FAIL)
            ((AUDIT_FAIL++))
            error "[FAIL] ${category}: ${message}"
            ;;
    esac

    AUDIT_RESULTS+=("${status}|${category}|${message}")
}

# Check if running in target system (chroot or booted)
audit_detect_environment() {
    if [ -f /.dockerenv ]; then
        log "Environment: Docker container"
        export AUDIT_ENV="docker"
    elif [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]; then
        log "Environment: Chroot"
        export AUDIT_ENV="chroot"
    elif [ -f /mnt/gentoo/etc/gentoo-release ]; then
        log "Environment: Live system (booted from install media)"
        export AUDIT_ENV="live"
    else
        log "Environment: Booted Gentoo system"
        export AUDIT_ENV="booted"
    fi
}

# Audit: Disk partitioning
audit_disk_partitioning() {
    section "Auditing Disk Partitioning"

    local disk="${1:-/dev/sda}"
    local boot_part="${disk}1"
    local root_part="${disk}2"

    # Check if partitions exist
    if [ -b "${boot_part}" ]; then
        audit_result PASS "Disk" "Boot partition exists: ${boot_part}"
    else
        audit_result FAIL "Disk" "Boot partition missing: ${boot_part}"
        return
    fi

    if [ -b "${root_part}" ]; then
        audit_result PASS "Disk" "Root partition exists: ${root_part}"
    else
        audit_result FAIL "Disk" "Root partition missing: ${root_part}"
        return
    fi

    # Check filesystem types
    local boot_fstype=$(blkid -s TYPE -o value "${boot_part}" 2>/dev/null)
    if [ "${boot_fstype}" = "vfat" ]; then
        audit_result PASS "Disk" "Boot partition is FAT32"
    else
        audit_result FAIL "Disk" "Boot partition is not FAT32 (found: ${boot_fstype})"
    fi

    local root_fstype=$(blkid -s TYPE -o value "${root_part}" 2>/dev/null)
    if [ "${root_fstype}" = "ext4" ]; then
        audit_result PASS "Disk" "Root partition is ext4"
    else
        audit_result WARN "Disk" "Root partition is not ext4 (found: ${root_fstype})"
    fi

    # Check partition sizes
    local boot_size=$(blockdev --getsize64 "${boot_part}" 2>/dev/null)
    local boot_size_mb=$((boot_size / 1024 / 1024))
    if [ "${boot_size_mb}" -ge 512 ]; then
        audit_result PASS "Disk" "Boot partition size adequate: ${boot_size_mb}MB"
    else
        audit_result WARN "Disk" "Boot partition small: ${boot_size_mb}MB (512MB+ recommended)"
    fi

    local root_size=$(blockdev --getsize64 "${root_part}" 2>/dev/null)
    local root_size_gb=$((root_size / 1024 / 1024 / 1024))
    if [ "${root_size_gb}" -ge 20 ]; then
        audit_result PASS "Disk" "Root partition size adequate: ${root_size_gb}GB"
    else
        audit_result WARN "Disk" "Root partition small: ${root_size_gb}GB (20GB+ recommended)"
    fi
}

# Audit: Mount points
audit_mounts() {
    section "Auditing Mount Points"

    local root_mount="/"
    local boot_mount="/boot/efi"

    if [ "${AUDIT_ENV}" = "live" ]; then
        root_mount="/mnt/gentoo"
        boot_mount="/mnt/gentoo/boot/efi"
    fi

    # Check root mount
    if mountpoint -q "${root_mount}"; then
        audit_result PASS "Mounts" "Root filesystem mounted at ${root_mount}"
    else
        audit_result FAIL "Mounts" "Root filesystem not mounted at ${root_mount}"
    fi

    # Check boot mount
    if mountpoint -q "${boot_mount}"; then
        audit_result PASS "Mounts" "Boot partition mounted at ${boot_mount}"
    else
        audit_result FAIL "Mounts" "Boot partition not mounted at ${boot_mount}"
    fi

    # Check fstab
    local fstab="${root_mount}/etc/fstab"
    if [ -f "${fstab}" ]; then
        if grep -q "/boot/efi" "${fstab}"; then
            audit_result PASS "Mounts" "/etc/fstab contains boot entry"
        else
            audit_result WARN "Mounts" "/etc/fstab missing boot entry"
        fi

        if grep -q "^UUID=" "${fstab}" || grep -q "^/dev/" "${fstab}"; then
            audit_result PASS "Mounts" "/etc/fstab has root entry"
        else
            audit_result WARN "Mounts" "/etc/fstab may be missing root entry"
        fi
    else
        audit_result FAIL "Mounts" "/etc/fstab does not exist"
    fi
}

# Audit: Base system files
audit_base_system() {
    section "Auditing Base System"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Check critical directories
    local critical_dirs=(
        "${root}/bin"
        "${root}/etc"
        "${root}/usr"
        "${root}/var"
        "${root}/home"
        "${root}/root"
        "${root}/tmp"
    )

    for dir in "${critical_dirs[@]}"; do
        if [ -d "${dir}" ]; then
            audit_result PASS "System" "Critical directory exists: ${dir}"
        else
            audit_result FAIL "System" "Critical directory missing: ${dir}"
        fi
    done

    # Check Gentoo release file
    if [ -f "${root}/etc/gentoo-release" ]; then
        local version=$(cat "${root}/etc/gentoo-release")
        audit_result PASS "System" "Gentoo release: ${version}"
    else
        audit_result FAIL "System" "/etc/gentoo-release missing"
    fi

    # Check os-release
    if [ -f "${root}/etc/os-release" ]; then
        audit_result PASS "System" "/etc/os-release exists"
    else
        audit_result WARN "System" "/etc/os-release missing"
    fi
}

# Audit: Locale and timezone
audit_locale_timezone() {
    section "Auditing Locale and Timezone"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Check locale.gen
    if [ -f "${root}/etc/locale.gen" ]; then
        if grep -q "^en_US.UTF-8" "${root}/etc/locale.gen"; then
            audit_result PASS "Locale" "en_US.UTF-8 enabled in locale.gen"
        else
            audit_result WARN "Locale" "en_US.UTF-8 not enabled in locale.gen"
        fi
    else
        audit_result FAIL "Locale" "/etc/locale.gen missing"
    fi

    # Check timezone
    if [ -L "${root}/etc/localtime" ]; then
        local tz_target=$(readlink "${root}/etc/localtime")
        audit_result PASS "Locale" "Timezone configured: ${tz_target}"
    else
        audit_result WARN "Locale" "Timezone not configured (no /etc/localtime symlink)"
    fi

    # Check hostname
    if [ -f "${root}/etc/hostname" ]; then
        local hostname=$(cat "${root}/etc/hostname")
        if [ -n "${hostname}" ] && [ "${hostname}" != "localhost" ]; then
            audit_result PASS "Locale" "Hostname configured: ${hostname}"
        else
            audit_result WARN "Locale" "Hostname not configured or is localhost"
        fi
    else
        audit_result FAIL "Locale" "/etc/hostname missing"
    fi

    # Check /etc/hosts
    if [ -f "${root}/etc/hosts" ]; then
        if grep -q "127.0.0.1.*localhost" "${root}/etc/hosts"; then
            audit_result PASS "Locale" "/etc/hosts has localhost entry"
        else
            audit_result WARN "Locale" "/etc/hosts missing localhost entry"
        fi
    else
        audit_result FAIL "Locale" "/etc/hosts missing"
    fi
}

# Audit: Portage configuration
audit_portage() {
    section "Auditing Portage Configuration"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Check Portage tree
    if [ -d "${root}/var/db/repos/gentoo/profiles" ]; then
        audit_result PASS "Portage" "Portage tree synced"

        # Count packages in tree
        local pkg_count=$(find "${root}/var/db/repos/gentoo" -name "*.ebuild" 2>/dev/null | wc -l)
        audit_result PASS "Portage" "Portage tree contains ${pkg_count} ebuilds"
    else
        audit_result FAIL "Portage" "Portage tree not synced"
    fi

    # Check make.conf
    if [ -f "${root}/etc/portage/make.conf" ]; then
        audit_result PASS "Portage" "make.conf exists"

        # Check for critical settings
        if grep -q "^USE=" "${root}/etc/portage/make.conf"; then
            audit_result PASS "Portage" "USE flags configured"
        else
            audit_result WARN "Portage" "No USE flags set in make.conf"
        fi

        if grep -q "^MAKEOPTS=" "${root}/etc/portage/make.conf"; then
            local makeopts=$(grep "^MAKEOPTS=" "${root}/etc/portage/make.conf")
            audit_result PASS "Portage" "MAKEOPTS configured: ${makeopts}"
        else
            audit_result WARN "Portage" "MAKEOPTS not configured"
        fi
    else
        audit_result FAIL "Portage" "make.conf missing"
    fi

    # Check profile
    if [ -L "${root}/etc/portage/make.profile" ]; then
        local profile=$(readlink "${root}/etc/portage/make.profile")
        audit_result PASS "Portage" "Profile selected: ${profile}"
    else
        audit_result WARN "Portage" "No profile selected"
    fi
}

# Audit: Kernel
audit_kernel() {
    section "Auditing Kernel"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Check for kernel files
    if ls "${root}/boot/vmlinuz-"* >/dev/null 2>&1; then
        local kernel_count=$(ls "${root}/boot/vmlinuz-"* | wc -l)
        local kernel_file=$(ls -t "${root}/boot/vmlinuz-"* | head -n1)
        audit_result PASS "Kernel" "Kernel installed: ${kernel_file}"

        if [ "${kernel_count}" -gt 1 ]; then
            audit_result WARN "Kernel" "Multiple kernels found (${kernel_count})"
        fi
    else
        audit_result FAIL "Kernel" "No kernel found in /boot"
    fi

    # Check for initramfs
    if ls "${root}/boot/initramfs-"* >/dev/null 2>&1; then
        audit_result PASS "Kernel" "Initramfs found"
    else
        audit_result WARN "Kernel" "No initramfs (may be intentional)"
    fi

    # Check kernel sources if present
    if [ -d "${root}/usr/src/linux" ]; then
        if [ -f "${root}/usr/src/linux/.config" ]; then
            audit_result PASS "Kernel" "Kernel sources configured"
        else
            audit_result WARN "Kernel" "Kernel sources present but not configured"
        fi
    fi

    # If booted, check running kernel
    if [ "${AUDIT_ENV}" = "booted" ]; then
        local running_kernel=$(uname -r)
        audit_result PASS "Kernel" "Running kernel: ${running_kernel}"

        # Check if running kernel matches installed
        if [ -f "/boot/vmlinuz-${running_kernel}" ]; then
            audit_result PASS "Kernel" "Running kernel matches installed kernel"
        else
            audit_result WARN "Kernel" "Running kernel differs from installed kernel"
        fi
    fi
}

# Audit: Bootloader
audit_bootloader() {
    section "Auditing Bootloader"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Check GRUB installation
    if [ -d "${root}/boot/grub" ]; then
        audit_result PASS "Bootloader" "GRUB directory exists"
    else
        audit_result FAIL "Bootloader" "GRUB directory missing"
        return
    fi

    # Check grub.cfg
    if [ -f "${root}/boot/grub/grub.cfg" ]; then
        audit_result PASS "Bootloader" "GRUB configuration exists"

        # Check for kernel entries
        if grep -q "vmlinuz" "${root}/boot/grub/grub.cfg"; then
            audit_result PASS "Bootloader" "GRUB config has kernel entries"
        else
            audit_result FAIL "Bootloader" "GRUB config missing kernel entries"
        fi

        # Check for multiple boot entries
        local entry_count=$(grep -c "^menuentry" "${root}/boot/grub/grub.cfg" 2>/dev/null || echo 0)
        if [ "${entry_count}" -gt 0 ]; then
            audit_result PASS "Bootloader" "GRUB has ${entry_count} boot entries"
        else
            audit_result WARN "Bootloader" "No menuentry found in grub.cfg"
        fi
    else
        audit_result FAIL "Bootloader" "grub.cfg missing"
    fi

    # Check EFI installation
    if [ -d "${root}/boot/efi/EFI" ]; then
        local efi_dirs=$(ls "${root}/boot/efi/EFI" 2>/dev/null | grep -v "BOOT" | head -n1)
        if [ -n "${efi_dirs}" ]; then
            audit_result PASS "Bootloader" "GRUB EFI files installed: ${efi_dirs}"
        else
            audit_result WARN "Bootloader" "No EFI boot entries found"
        fi
    else
        audit_result WARN "Bootloader" "No EFI directory (may be BIOS boot)"
    fi
}

# Audit: System packages
audit_system_packages() {
    section "Auditing System Packages"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Critical packages to check
    local critical_packages=(
        "sys-apps/systemd"
        "sys-boot/grub"
        "app-admin/sudo"
        "net-misc/dhcpcd"
        "sys-apps/util-linux"
        "app-shells/bash"
    )

    for pkg in "${critical_packages[@]}"; do
        if [ -d "${root}/var/db/pkg/${pkg}"-* ] 2>/dev/null; then
            audit_result PASS "Packages" "${pkg} installed"
        else
            audit_result WARN "Packages" "${pkg} not installed"
        fi
    done

    # Count total installed packages
    if [ -d "${root}/var/db/pkg" ]; then
        local pkg_count=$(find "${root}/var/db/pkg" -mindepth 2 -maxdepth 2 -type d | wc -l)
        audit_result PASS "Packages" "Total packages installed: ${pkg_count}"

        if [ "${pkg_count}" -lt 100 ]; then
            audit_result WARN "Packages" "Low package count (${pkg_count}), installation may be incomplete"
        fi
    fi
}

# Audit: Users and permissions
audit_users() {
    section "Auditing Users and Permissions"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Check passwd file
    if [ -f "${root}/etc/passwd" ]; then
        # Check for root
        if grep -q "^root:" "${root}/etc/passwd"; then
            audit_result PASS "Users" "Root user exists"
        else
            audit_result FAIL "Users" "Root user missing"
        fi

        # Check for non-root users
        local user_count=$(grep -v "^root:" "${root}/etc/passwd" | grep -v "nologin" | grep -v "false" | wc -l)
        if [ "${user_count}" -gt 0 ]; then
            audit_result PASS "Users" "${user_count} regular user(s) configured"
        else
            audit_result WARN "Users" "No regular users configured"
        fi
    else
        audit_result FAIL "Users" "/etc/passwd missing"
    fi

    # Check shadow file
    if [ -f "${root}/etc/shadow" ]; then
        # Check if root has password
        if grep "^root:" "${root}/etc/shadow" | grep -q -v "^root:\*"; then
            audit_result PASS "Users" "Root password is set"
        else
            audit_result WARN "Users" "Root password may not be set"
        fi
    else
        audit_result FAIL "Users" "/etc/shadow missing"
    fi

    # Check sudo/doas configuration
    if [ -f "${root}/etc/sudoers" ]; then
        if grep -q "^%wheel.*ALL" "${root}/etc/sudoers"; then
            audit_result PASS "Users" "sudo configured for wheel group"
        else
            audit_result WARN "Users" "sudo not configured for wheel group"
        fi
    fi

    if [ -f "${root}/etc/doas.conf" ]; then
        audit_result PASS "Users" "doas configured"
    fi

    if [ ! -f "${root}/etc/sudoers" ] && [ ! -f "${root}/etc/doas.conf" ]; then
        audit_result WARN "Users" "Neither sudo nor doas configured"
    fi
}

# Audit: Services
audit_services() {
    section "Auditing Services"

    # Only meaningful if booted into the system
    if [ "${AUDIT_ENV}" != "booted" ]; then
        audit_result WARN "Services" "Service audit skipped (not running in booted system)"
        return
    fi

    # Check critical services
    local critical_services=(
        "sshd"
        "dhcpcd"
        "cronie"
    )

    for service in "${critical_services[@]}"; do
        if systemctl is-enabled "${service}" >/dev/null 2>&1; then
            audit_result PASS "Services" "${service} is enabled"

            if systemctl is-active "${service}" >/dev/null 2>&1; then
                audit_result PASS "Services" "${service} is running"
            else
                audit_result WARN "Services" "${service} is enabled but not running"
            fi
        else
            audit_result WARN "Services" "${service} is not enabled"
        fi
    done
}

# Audit: Network configuration
audit_network() {
    section "Auditing Network"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Check resolv.conf
    if [ -f "${root}/etc/resolv.conf" ]; then
        if grep -q "^nameserver" "${root}/etc/resolv.conf"; then
            audit_result PASS "Network" "DNS configured in /etc/resolv.conf"
        else
            audit_result WARN "Network" "/etc/resolv.conf has no nameservers"
        fi
    else
        audit_result WARN "Network" "/etc/resolv.conf missing"
    fi

    # If booted, check connectivity
    if [ "${AUDIT_ENV}" = "booted" ]; then
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            audit_result PASS "Network" "Internet connectivity working"
        else
            audit_result FAIL "Network" "No internet connectivity"
        fi

        if ping -c 1 -W 2 gentoo.org >/dev/null 2>&1; then
            audit_result PASS "Network" "DNS resolution working"
        else
            audit_result WARN "Network" "DNS resolution not working"
        fi
    fi
}

# Audit: Desktop environment (optional)
audit_desktop() {
    section "Auditing Desktop Environment"

    local root="/"
    [ "${AUDIT_ENV}" = "live" ] && root="/mnt/gentoo"

    # Check for Hyprland
    if [ -f "${root}/usr/bin/Hyprland" ]; then
        audit_result PASS "Desktop" "Hyprland installed"
    else
        audit_result WARN "Desktop" "Hyprland not installed (desktop phase may not have run)"
        return
    fi

    # Check desktop components
    local desktop_components=(
        "waybar"
        "kitty"
        "wofi"
    )

    for component in "${desktop_components[@]}"; do
        if [ -f "${root}/usr/bin/${component}" ]; then
            audit_result PASS "Desktop" "${component} installed"
        else
            audit_result WARN "Desktop" "${component} not installed"
        fi
    done

    # Check wayland session
    if [ -f "${root}/usr/share/wayland-sessions/hyprland.desktop" ]; then
        audit_result PASS "Desktop" "Hyprland session file exists"
    else
        audit_result WARN "Desktop" "Hyprland session file missing"
    fi
}

# Generate audit report
generate_audit_report() {
    local report_file="${1:-/tmp/gentoo-audit-report.txt}"

    section "Audit Report"

    {
        echo "======================================"
        echo "  Gentoo Installation Audit Report"
        echo "======================================"
        echo
        echo "Date: $(date)"
        echo "Environment: ${AUDIT_ENV}"
        echo "Hostname: $(hostname 2>/dev/null || echo "unknown")"
        echo
        echo "Summary:"
        echo "  ✓ Passed:  ${AUDIT_PASS}"
        echo "  ⚠ Warnings: ${AUDIT_WARN}"
        echo "  ✗ Failed:  ${AUDIT_FAIL}"
        echo
        echo "======================================"
        echo

        # Group results by category
        for category in "Disk" "Mounts" "System" "Locale" "Portage" "Kernel" "Bootloader" "Packages" "Users" "Services" "Network" "Desktop"; do
            local has_results=false
            for result in "${AUDIT_RESULTS[@]}"; do
                if echo "${result}" | grep -q "|${category}|"; then
                    if [ "${has_results}" = false ]; then
                        echo "=== ${category} ==="
                        has_results=true
                    fi
                    echo "${result}" | sed 's/|/ - /'
                fi
            done
            [ "${has_results}" = true ] && echo
        done

    } | tee "${report_file}"

    log "Audit report saved to: ${report_file}"

    # Return status
    if [ "${AUDIT_FAIL}" -gt 0 ]; then
        return 1
    elif [ "${AUDIT_WARN}" -gt 5 ]; then
        return 2
    else
        return 0
    fi
}

# Run complete audit
run_complete_audit() {
    local disk="${1:-/dev/sda}"
    local report_file="${2:-state/audit-report-$(date +%Y%m%d-%H%M%S).txt}"

    section "Running Complete Installation Audit"

    audit_detect_environment

    # Run all audit checks
    audit_disk_partitioning "${disk}"
    audit_mounts
    audit_base_system
    audit_locale_timezone
    audit_portage
    audit_kernel
    audit_bootloader
    audit_system_packages
    audit_users
    audit_services
    audit_network
    audit_desktop

    # Generate report
    generate_audit_report "${report_file}"

    local status=$?

    echo
    if [ "${status}" -eq 0 ]; then
        success "Audit PASSED - Installation appears complete and correct"
        return 0
    elif [ "${status}" -eq 2 ]; then
        warn "Audit PASSED with WARNINGS - Review warnings above"
        return 0
    else
        error "Audit FAILED - Critical issues found, installation incomplete"
        return 1
    fi
}

export -f audit_result audit_detect_environment audit_disk_partitioning
export -f audit_mounts audit_base_system audit_locale_timezone audit_portage
export -f audit_kernel audit_bootloader audit_system_packages audit_users
export -f audit_services audit_network audit_desktop generate_audit_report
export -f run_complete_audit
