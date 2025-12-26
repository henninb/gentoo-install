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

        # Configure kernel-install before installing the kernel
        log "Configuring kernel-install..."
        mkdir -p /etc/kernel

        # Tell kernel-install to use /boot for kernels (not /boot/efi)
        # This is critical for the postinst to succeed
        cat > /etc/kernel/install.conf <<'EOF'
# Configuration for kernel-install
# See kernel-install(8) for details

# Install kernels to /boot, not /boot/efi
layout=bls
# BOOT_ROOT can be set to override where kernels are installed
EOF

        # Ensure /boot directory exists (kernels go here, not /boot/efi)
        mkdir -p /boot

        # Create the directory structure kernel-install expects
        mkdir -p /boot/loader/entries
        mkdir -p /usr/lib/kernel/install.d

        # Now install the kernel (postinst should work now)
        log "Emerging gentoo-kernel-bin (this may take several minutes)..."

        # Try to install normally first (let postinst run)
        if emerge -v --update --newuse --autounmask-write --autounmask-continue sys-kernel/gentoo-kernel-bin; then
            log "Kernel installed successfully via emerge postinst"
        else
            warn "Kernel postinst failed, trying with FEATURES=-postinst and manual installation..."

            # Fallback: install without postinst and do it manually
            FEATURES="-postinst" emerge -v --update --newuse --autounmask-write --autounmask-continue sys-kernel/gentoo-kernel-bin || {
                error "Failed to install kernel even with FEATURES=-postinst"
                exit 1
            }
        fi

        # Check if kernel was installed, if not do it manually
        log "Verifying kernel installation in /boot..."

        # Find the latest kernel version
        KERNEL_VER=$(ls -1 /lib/modules/ | sort -V | tail -1)

        if [ -n "$KERNEL_VER" ]; then
            log "Found kernel version: $KERNEL_VER"

            # Check if kernel is already in /boot (from successful postinst)
            if ls /boot/vmlinuz-* 1>/dev/null 2>&1; then
                log "Kernel already installed in /boot (postinst succeeded)"
            else
                # Manual installation needed
                log "Manually installing kernel to /boot..."

                # Find kernel image in various possible locations
                KERNEL_SRC_PATHS=(
                    "/usr/src/linux-${KERNEL_VER}/arch/x86/boot/bzImage"
                    "/usr/src/linux-${KERNEL_VER%-gentoo*}/arch/x86/boot/bzImage"
                    "/lib/modules/${KERNEL_VER}/vmlinuz"
                    "/lib/modules/${KERNEL_VER}/build/arch/x86/boot/bzImage"
                )

                KERNEL_FOUND=false
                for kernel_path in "${KERNEL_SRC_PATHS[@]}"; do
                    if [ -f "$kernel_path" ]; then
                        cp "$kernel_path" "/boot/vmlinuz-${KERNEL_VER}"
                        log "Copied kernel from $kernel_path to /boot/vmlinuz-${KERNEL_VER}"
                        KERNEL_FOUND=true
                        break
                    fi
                done

                if [ "$KERNEL_FOUND" = false ]; then
                    # For gentoo-kernel-bin, kernel might be pre-built elsewhere
                    # Extract it from the package if needed
                    warn "Could not find pre-built kernel, this may be expected for gentoo-kernel-bin"
                fi
            fi

            # Check if initramfs already exists (from successful postinst)
            if ls /boot/initramfs-* 1>/dev/null 2>&1 || ls /boot/initrd-* 1>/dev/null 2>&1; then
                log "Initramfs already exists in /boot (postinst succeeded)"
            else
                # Generate initramfs with dracut
                log "Generating initramfs with dracut for kernel ${KERNEL_VER}..."

                # Try different initramfs naming conventions
                INITRAMFS_NAME="/boot/initramfs-${KERNEL_VER}.img"

                if dracut --force --kver "${KERNEL_VER}" "${INITRAMFS_NAME}"; then
                    success "Initramfs generated: ${INITRAMFS_NAME}"
                else
                    warn "Dracut failed, trying alternate method..."
                    # Fallback: try without explicit kernel version
                    dracut --force "${INITRAMFS_NAME}" || warn "Initramfs generation failed, system may not boot without it"
                fi
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
        KERNEL_SIZE_MB=$((KERNEL_SIZE / 1024 / 1024))
        success "✓ Kernel image found: $KERNEL_FILE (${KERNEL_SIZE_MB}MB)"
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
        INITRD_SIZE_MB=$((INITRD_SIZE / 1024 / 1024))
        success "✓ Initramfs found: $INITRD_FILE (${INITRD_SIZE_MB}MB)"
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
