#!/bin/bash
#
# Phase 08: User Configuration
# Creates users and configures sudo/doas
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 08: User Configuration"

# Configuration
PRIMARY_USER="${PRIMARY_USER:-henninb}"

# This phase should run in chroot
if ! in_chroot; then
    error "This phase must be run inside the chroot environment"
    exit 1
fi

# Create primary user
if id "${PRIMARY_USER}" &>/dev/null; then
    log "User ${PRIMARY_USER} already exists"
else
    log "Creating user ${PRIMARY_USER}"
    useradd -m -G users,wheel "${PRIMARY_USER}"

    log "Setting password for ${PRIMARY_USER}"
    echo "Please enter password for ${PRIMARY_USER}:"
    passwd "${PRIMARY_USER}"
fi

# Ensure user is in wheel group
if groups "${PRIMARY_USER}" | grep -q wheel; then
    log "User ${PRIMARY_USER} already in wheel group"
else
    log "Adding ${PRIMARY_USER} to wheel group"
    usermod -aG wheel "${PRIMARY_USER}"
fi

# Set root password
log "Setting root password"
echo "Please enter password for root:"
passwd root

# Configure sudo
if [ -f /etc/sudoers ]; then
    if grep -q "^%wheel ALL=(ALL:ALL) NOPASSWD: ALL" /etc/sudoers; then
        log "sudo already configured for wheel group"
    else
        log "Configuring sudo for wheel group"
        backup_file /etc/sudoers
        cat >> /etc/sudoers <<'EOF'

# Added by Gentoo installer
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
EOF
    fi
fi

# Configure doas
if command_exists doas; then
    if [ -f /etc/doas.conf ]; then
        if grep -q "^permit nopass ${PRIMARY_USER}" /etc/doas.conf; then
            log "doas already configured for ${PRIMARY_USER}"
        else
            log "Configuring doas for ${PRIMARY_USER}"
            backup_file /etc/doas.conf
            cat >> /etc/doas.conf <<EOF

# Added by Gentoo installer
permit nopass ${PRIMARY_USER} as root
EOF
            chmod 600 /etc/doas.conf
        fi
    else
        log "Creating doas configuration"
        cat > /etc/doas.conf <<EOF
# doas configuration
permit nopass ${PRIMARY_USER} as root
EOF
        chmod 600 /etc/doas.conf
    fi
fi

# Validate
validate_users

success "User configuration completed"
