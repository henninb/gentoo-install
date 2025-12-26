#!/bin/bash
#
# Phase 04: Portage Configuration
# Syncs Portage tree and applies custom configurations
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 04: Portage Configuration"

# This phase should run in chroot
if ! in_chroot; then
    error "This phase must be run inside the chroot environment"
    exit 1
fi

wait_for_network

# Sync Portage tree
log "Syncing Portage tree (this may take several minutes)"
if [ ! -d /var/db/repos/gentoo/profiles ]; then
    run_logged emerge-webrsync
else
    log "Portage tree already synced, updating"
    retry 3 emerge --sync
fi

# Read news items
if command_exists eselect; then
    log "Checking Gentoo news"
    eselect news read --quiet new 2>/dev/null || true
fi

# Apply custom Portage configurations from config directory
CONFIG_SOURCE="${SCRIPT_DIR}/config"

if [ -d "${CONFIG_SOURCE}" ]; then
    log "Applying Portage configurations from ${CONFIG_SOURCE}"

    # Backup existing configs
    backup_file /etc/portage/make.conf

    # Copy make.conf
    if [ -f "${CONFIG_SOURCE}/make.conf" ]; then
        log "Installing make.conf"
        cp -v "${CONFIG_SOURCE}/make.conf" /etc/portage/make.conf
    fi

    # Create package.* directories if they don't exist
    mkdir -p /etc/portage/package.{accept_keywords,unmask,mask,use,license,env}

    # Copy package.accept_keywords
    if [ -f "${CONFIG_SOURCE}/package.accept_keywords" ]; then
        log "Installing package.accept_keywords"
        cp -v "${CONFIG_SOURCE}/package.accept_keywords" \
            /etc/portage/package.accept_keywords/zzz-custom
    fi

    # Copy package.unmask
    if [ -f "${CONFIG_SOURCE}/package.unmask" ]; then
        log "Installing package.unmask"
        cp -v "${CONFIG_SOURCE}/package.unmask" \
            /etc/portage/package.unmask/zzz-custom
    fi

    # Copy package.mask
    if [ -f "${CONFIG_SOURCE}/package.mask" ]; then
        log "Installing package.mask"
        cp -v "${CONFIG_SOURCE}/package.mask" \
            /etc/portage/package.mask/zzz-custom
    fi

    # Copy package.use directory if it exists
    if [ -d "${CONFIG_SOURCE}/package.use" ]; then
        log "Installing package.use files"
        cp -rv "${CONFIG_SOURCE}/package.use/"* /etc/portage/package.use/
    fi

    # Copy package.license if it exists
    if [ -f "${CONFIG_SOURCE}/package.license" ]; then
        log "Installing package.license"
        cp -v "${CONFIG_SOURCE}/package.license" /etc/portage/package.license
    fi

    # Copy package.env if it exists
    if [ -f "${CONFIG_SOURCE}/package.env" ]; then
        log "Installing package.env"
        cp -v "${CONFIG_SOURCE}/package.env" /etc/portage/package.env
    fi
else
    warn "Config directory ${CONFIG_SOURCE} not found, using defaults"
fi

# Update Portage to process new configurations
log "Updating Portage configuration"
run_logged emerge --info

# Optionally run etc-update to handle any config file updates
if command_exists etc-update; then
    log "Running etc-update (using automatic mode)"
    # Use --automode -5 to automatically merge trivial changes
    etc-update --automode -5 || true
fi

# Validate
validate_portage_config

success "Portage configuration completed"
