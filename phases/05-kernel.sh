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

        # Install and configure installkernel with dracut USE flag
        log "Configuring installkernel with dracut support..."
        mkdir -p /etc/portage/package.use
        echo "sys-kernel/installkernel dracut" >> /etc/portage/package.use/kernel

        # Install linux-firmware first (needed by kernel postinst)
        log "Installing linux-firmware (required for hardware support)..."
        emerge -v --update --newuse sys-kernel/linux-firmware

        # Install installkernel with dracut support
        log "Installing installkernel..."
        emerge -v --update --newuse sys-kernel/installkernel

        # Install dracut (required by installkernel)
        log "Installing dracut (required for initramfs generation)..."
        emerge -v --update --newuse sys-kernel/dracut

        # Now install the kernel (skip postinst to avoid installation issues)
        log "Emerging gentoo-kernel-bin (this may take several minutes)..."
        log "Installing with FEATURES='-postinst' to avoid postinst issues..."

        # Install without running postinst scripts
        FEATURES="-postinst" emerge -v --update --newuse --autounmask-write --autounmask-continue sys-kernel/gentoo-kernel-bin

        # Manually copy kernel files to /boot
        log "Manually installing kernel files to /boot..."

        # Find the latest kernel version
        KERNEL_VER=$(ls -1 /lib/modules/ | sort -V | tail -1)

        if [ -n "$KERNEL_VER" ]; then
            log "Found kernel version: $KERNEL_VER"

            # Copy kernel and initramfs to /boot
            if [ -f "/usr/src/linux-${KERNEL_VER}/arch/x86/boot/bzImage" ]; then
                cp "/usr/src/linux-${KERNEL_VER}/arch/x86/boot/bzImage" "/boot/vmlinuz-${KERNEL_VER}"
                log "Copied kernel to /boot/vmlinuz-${KERNEL_VER}"
            elif [ -f "/boot/vmlinuz-${KERNEL_VER}-gentoo-dist" ]; then
                log "Kernel already in /boot"
            fi

            # Generate initramfs with dracut if not present
            if [ ! -f "/boot/initramfs-${KERNEL_VER}.img" ] && [ ! -f "/boot/initramfs-${KERNEL_VER}-gentoo-dist.img" ]; then
                log "Generating initramfs with dracut..."
                dracut --kver "${KERNEL_VER}" "/boot/initramfs-${KERNEL_VER}.img" || warn "Dracut failed, but continuing..."
            fi
        else
            warn "Could not determine kernel version, skipping manual installation"
        fi
        ;;

    genkernel)
        log "Installing kernel sources and building with genkernel"
        log "WARNING: This will take a long time (30-60 minutes)"

        # Install kernel sources
        log "Installing gentoo-sources"
        emerge -v --update --newuse sys-kernel/gentoo-sources

        # Install genkernel
        log "Installing genkernel"
        emerge -v --update --newuse sys-kernel/genkernel

        # Install linux-firmware
        log "Installing linux-firmware"
        emerge -v --update --newuse sys-kernel/linux-firmware

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

        log "Installing gentoo-sources"
        emerge -v --update --newuse sys-kernel/gentoo-sources

        error "Manual kernel build is not automated. Please build your kernel and re-run this phase."
        exit 1
        ;;

    *)
        error "Unknown KERNEL_METHOD: ${KERNEL_METHOD}"
        error "Valid options: bin, genkernel, manual"
        exit 1
        ;;
esac

# Comprehensive kernel validation
log "Validating kernel installation..."

KERNEL_VALID=true

# Check 1: Kernel image exists in /boot
if ls /boot/vmlinuz-* 1>/dev/null 2>&1; then
    KERNEL_FILE=$(ls -t /boot/vmlinuz-* | head -1)
    KERNEL_SIZE=$(stat -c%s "$KERNEL_FILE" 2>/dev/null || echo "0")

    if [ "$KERNEL_SIZE" -gt 1000000 ]; then  # Should be > 1MB
        success "✓ Kernel image found: $KERNEL_FILE ($(numfmt --to=iec $KERNEL_SIZE))"
    else
        error "✗ Kernel image is too small or missing: $KERNEL_FILE"
        KERNEL_VALID=false
    fi
else
    error "✗ No kernel image found in /boot"
    KERNEL_VALID=false
fi

# Check 2: Initramfs exists
if ls /boot/initramfs-* 1>/dev/null 2>&1 || ls /boot/initrd-* 1>/dev/null 2>&1; then
    INITRD_FILE=$(ls -t /boot/initramfs-* /boot/initrd-* 2>/dev/null | head -1)
    INITRD_SIZE=$(stat -c%s "$INITRD_FILE" 2>/dev/null || echo "0")

    if [ "$INITRD_SIZE" -gt 1000000 ]; then  # Should be > 1MB
        success "✓ Initramfs found: $INITRD_FILE ($(numfmt --to=iec $INITRD_SIZE))"
    else
        warn "⚠ Initramfs exists but seems small: $INITRD_FILE"
    fi
else
    warn "⚠ No initramfs found (may cause boot issues)"
fi

# Check 3: Kernel modules exist
if [ -d /lib/modules ] && [ "$(ls -A /lib/modules)" ]; then
    KERNEL_VER=$(ls -1 /lib/modules/ | sort -V | tail -1)
    MODULE_COUNT=$(find /lib/modules/$KERNEL_VER -name "*.ko*" 2>/dev/null | wc -l)

    if [ "$MODULE_COUNT" -gt 100 ]; then
        success "✓ Kernel modules found: $MODULE_COUNT modules for version $KERNEL_VER"
    else
        warn "⚠ Found only $MODULE_COUNT modules (expected more)"
    fi
else
    error "✗ No kernel modules found in /lib/modules"
    KERNEL_VALID=false
fi

# Check 4: Boot partition is writable
if touch /boot/.test 2>/dev/null; then
    rm -f /boot/.test
    success "✓ Boot partition is writable"
else
    error "✗ Boot partition is not writable"
    KERNEL_VALID=false
fi

# Final result
echo ""
if [ "$KERNEL_VALID" = true ]; then
    success "Kernel installation completed and validated successfully"
    log "You can verify with: ls -lh /boot/"
else
    error "Kernel validation failed - some critical files are missing"
    error "Boot may fail. Please review the errors above."
    exit 1
fi
