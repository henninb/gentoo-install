#!/bin/bash
#
# Phase 06: Bootloader Installation
# Installs and configures GRUB
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 06: Bootloader Installation"

# Configuration
BOOTLOADER_ID="${BOOTLOADER_ID:-gentoo-new}"
EFI_DIR="${EFI_DIR:-/boot/efi}"

# This phase should run in chroot
if ! in_chroot; then
    error "This phase must be run inside the chroot environment"
    exit 1
fi

wait_for_network

# Install GRUB if not already installed
if ! package_installed "sys-boot/grub"; then
    log "Installing GRUB"
    run_logged emerge --update --newuse sys-boot/grub:2
fi

# Ensure EFI directory is mounted
if ! mountpoint -q "${EFI_DIR}"; then
    error "EFI partition not mounted at ${EFI_DIR}"
    exit 1
fi

# Install GRUB to EFI partition
log "Installing GRUB to EFI partition"
if [ -d "${EFI_DIR}/EFI/${BOOTLOADER_ID}" ]; then
    warn "GRUB already installed, reinstalling"
    run_logged grub-install --target=x86_64-efi \
        --efi-directory="${EFI_DIR}" \
        --bootloader-id="${BOOTLOADER_ID}" \
        --recheck
else
    run_logged grub-install --target=x86_64-efi \
        --efi-directory="${EFI_DIR}" \
        --bootloader-id="${BOOTLOADER_ID}"
fi

# Generate GRUB configuration
log "Generating GRUB configuration"
run_logged grub-mkconfig -o /boot/grub/grub.cfg

# Validate
validate_bootloader

success "Bootloader installation completed"
