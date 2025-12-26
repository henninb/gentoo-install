#!/bin/bash
#
# Phase 03: Base System Configuration
# Configures locale, timezone, hostname, and systemd settings
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 03: Base System Configuration"

# Configuration
HOSTNAME="${HOSTNAME:-gentoo}"
TIMEZONE="${TIMEZONE:-America/Chicago}"
LOCALE="${LOCALE:-en_US.UTF-8}"

# This phase should run in chroot
if ! in_chroot; then
    error "This phase must be run inside the chroot environment"
    error "Please chroot into /mnt/gentoo first"
    exit 1
fi

# Configure locale
log "Configuring locale: ${LOCALE}"
if grep -q "^${LOCALE}" /etc/locale.gen 2>/dev/null; then
    log "Locale already in locale.gen"
else
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi

# Generate locales
run_logged locale-gen

# Set system locale (write directly to locale.conf)
log "Writing /etc/locale.conf"
cat > /etc/locale.conf <<EOF
LANG=${LOCALE}
LC_COLLATE=C
EOF

# Configure timezone
log "Setting timezone: ${TIMEZONE}"
if command_exists timedatectl; then
    run_logged timedatectl set-timezone "${TIMEZONE}"
    run_logged timedatectl set-ntp yes
else
    # Fallback for non-systemd or pre-boot
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
fi

# Configure hostname
log "Setting hostname: ${HOSTNAME}"
if command_exists hostnamectl; then
    run_logged hostnamectl set-hostname "${HOSTNAME}"
else
    echo "${HOSTNAME}" > /etc/hostname
fi

# Update /etc/hosts
if ! grep -q "${HOSTNAME}" /etc/hosts; then
    log "Adding ${HOSTNAME} to /etc/hosts"
    cat >> /etc/hosts <<EOF
127.0.0.1 ${HOSTNAME}.lan ${HOSTNAME}
::1       ${HOSTNAME}.lan ${HOSTNAME}
EOF
fi

# Set keymap (write directly to vconsole.conf)
log "Configuring keymap"
cat > /etc/vconsole.conf <<EOF
KEYMAP=us
EOF

# Validate
validate_locale

success "Base system configuration completed"
