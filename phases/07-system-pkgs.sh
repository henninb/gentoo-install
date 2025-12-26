#!/bin/bash
#
# Phase 07: System Packages
# Installs essential system packages from declarative list
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 07: System Packages"

# This phase should run in chroot
if ! in_chroot; then
    error "This phase must be run inside the chroot environment"
    exit 1
fi

wait_for_network

# Essential system packages
ESSENTIAL_PACKAGES=(
    "app-admin/sudo"
    "app-admin/doas"
    "app-admin/sysklogger"
    "net-misc/dhcpcd"
    "sys-process/cronie"
    "sys-apps/mlocate"
    "app-portage/gentoolkit"
)

log "Installing essential system packages"

FAILURES=""
for pkg in "${ESSENTIAL_PACKAGES[@]}"; do
    if package_installed "${pkg}"; then
        log "${pkg} already installed"
    else
        log "Installing ${pkg}"
        if ! emerge --update --newuse "${pkg}"; then
            error "Failed to install ${pkg}"
            FAILURES="${FAILURES} ${pkg}"
        fi
    done
done

# Install additional packages from world.txt if it exists
WORLD_FILE="${SCRIPT_DIR}/config/world.txt"
if [ -f "${WORLD_FILE}" ]; then
    log "Installing packages from ${WORLD_FILE}"

    while IFS= read -r pkg || [ -n "$pkg" ]; do
        # Skip empty lines and comments
        [[ -z "${pkg}" || "${pkg}" =~ ^[[:space:]]*# ]] && continue

        # Trim whitespace
        pkg=$(echo "${pkg}" | xargs)

        if package_installed "${pkg}"; then
            log "${pkg} already installed"
        else
            log "Installing ${pkg}"
            if ! emerge --update --newuse "${pkg}"; then
                error "Failed to install ${pkg}"
                FAILURES="${FAILURES} ${pkg}"
            fi
        fi
    done < "${WORLD_FILE}"
else
    warn "No world.txt found at ${WORLD_FILE}, skipping additional packages"
fi

# Enable system services
log "Enabling system services"

SERVICES=(
    "sshd"
    "dhcpcd"
    "cronie"
)

for service in "${SERVICES[@]}"; do
    if systemctl is-enabled "${service}" >/dev/null 2>&1; then
        log "${service} already enabled"
    else
        log "Enabling ${service}"
        systemctl enable "${service}" || warn "Failed to enable ${service}"
    fi
done

# Report failures
if [ -n "${FAILURES}" ]; then
    error "The following packages failed to install:${FAILURES}"
    error "You may need to investigate and install them manually"
    exit 1
fi

# Validate
validate_system_packages

success "System packages installation completed"
