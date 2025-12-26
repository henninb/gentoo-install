#!/bin/bash
#
# Phase 05: Kernel Installation
# Installs and builds the kernel
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 05: Kernel Installation"

# Configuration
KERNEL_METHOD="${KERNEL_METHOD:-bin}"  # 'bin' for gentoo-kernel-bin, 'genkernel' for manual build

# This phase should run in chroot
if ! in_chroot; then
    error "This phase must be run inside the chroot environment"
    exit 1
fi

wait_for_network

case "${KERNEL_METHOD}" in
    bin)
        log "Installing binary kernel (gentoo-kernel-bin)"
        log "This is faster but less customizable"

        if package_installed "sys-kernel/gentoo-kernel-bin"; then
            log "Binary kernel already installed"
        else
            run_logged emerge --update --newuse sys-kernel/gentoo-kernel-bin
        fi

        # Also install linux-firmware
        if ! package_installed "sys-kernel/linux-firmware"; then
            log "Installing linux-firmware"
            run_logged emerge --update --newuse sys-kernel/linux-firmware
        fi
        ;;

    genkernel)
        log "Installing kernel sources and building with genkernel"
        log "WARNING: This will take a long time (30-60 minutes)"

        # Install kernel sources
        if ! package_installed "sys-kernel/gentoo-sources"; then
            log "Installing gentoo-sources"
            run_logged emerge --update --newuse sys-kernel/gentoo-sources
        fi

        # Install genkernel
        if ! package_installed "sys-kernel/genkernel"; then
            log "Installing genkernel"
            run_logged emerge --update --newuse sys-kernel/genkernel
        fi

        # Install linux-firmware
        if ! package_installed "sys-kernel/linux-firmware"; then
            log "Installing linux-firmware"
            run_logged emerge --update --newuse sys-kernel/linux-firmware
        fi

        # Set kernel source
        run_logged eselect kernel list
        run_logged eselect kernel set 1

        # Build kernel
        # Check if custom config exists
        CUSTOM_CONFIG="${SCRIPT_DIR}/config/kernel.config"
        if [ -f "${CUSTOM_CONFIG}" ]; then
            log "Using custom kernel configuration"
            cp "${CUSTOM_CONFIG}" /usr/src/linux/.config
            run_logged genkernel --kernel-config=/usr/src/linux/.config --install all
        else
            log "Building kernel with default configuration"
            run_logged genkernel --install all
        fi
        ;;

    manual)
        log "Manual kernel build mode"
        warn "You will need to configure and build the kernel yourself"
        warn "Ensure sys-kernel/gentoo-sources is installed and configured"

        if ! package_installed "sys-kernel/gentoo-sources"; then
            run_logged emerge --update --newuse sys-kernel/gentoo-sources
        fi

        error "Manual kernel build is not automated. Please build your kernel and re-run this phase."
        exit 1
        ;;

    *)
        error "Unknown KERNEL_METHOD: ${KERNEL_METHOD}"
        error "Valid options: bin, genkernel, manual"
        exit 1
        ;;
esac

# Validate
validate_kernel

success "Kernel installation completed"
