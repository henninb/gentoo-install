#!/bin/bash
#
# Phase 09: Desktop Environment (Optional)
# Installs Hyprland and complete desktop environment
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 09: Desktop Environment"

# This phase should run in chroot
if ! in_chroot; then
    error "This phase must be run inside the chroot environment"
    exit 1
fi

wait_for_network

# Enable GURU overlay for Hyprland packages
log "Enabling GURU repository for Hyprland packages"

if ! package_installed "app-eselect/eselect-repository"; then
    run_logged emerge --update --newuse app-eselect/eselect-repository
fi

# Enable GURU overlay
if eselect repository list | grep -q "guru.*enabled"; then
    log "GURU repository already enabled"
else
    log "Enabling GURU repository"
    run_logged eselect repository enable guru
fi

# Sync GURU repository
log "Syncing GURU repository (this may take a few minutes)"
run_logged emaint sync -r guru

# Install desktop packages from list
DESKTOP_PACKAGES_FILE="${SCRIPT_DIR}/config/desktop-packages.txt"

if [ ! -f "${DESKTOP_PACKAGES_FILE}" ]; then
    warn "Desktop packages file not found: ${DESKTOP_PACKAGES_FILE}"
    warn "Skipping desktop installation"
    exit 0
fi

log "Installing desktop packages from ${DESKTOP_PACKAGES_FILE}"
log "NOTE: This will take a LONG time (1-3 hours depending on hardware)"

FAILURES=""
SKIPPED=""

while IFS= read -r pkg || [ -n "$pkg" ]; do
    # Skip empty lines and comments
    [[ -z "${pkg}" || "${pkg}" =~ ^[[:space:]]*# ]] && continue

    # Trim whitespace
    pkg=$(echo "${pkg}" | xargs)

    if package_installed "${pkg}"; then
        log "${pkg} already installed"
    else
        log "Installing ${pkg}..."

        # Try to install, but don't fail the whole phase if one package fails
        if emerge --update --newuse "${pkg}"; then
            success "${pkg} installed successfully"
        else
            # Check if package exists
            if ! emerge --search "^${pkg}$" | grep -q "Latest version available"; then
                warn "${pkg} not found in repositories (may need overlay or keyword)"
                SKIPPED="${SKIPPED}\n  - ${pkg}"
            else
                error "Failed to install ${pkg}"
                FAILURES="${FAILURES}\n  - ${pkg}"
            fi
        fi
    fi
done < "${DESKTOP_PACKAGES_FILE}"

# Build and install swww (wallpaper daemon) from source
log "Building swww wallpaper daemon from source"

SWWW_DIR="${HOME}/projects/github.com/Horus645"
mkdir -p "${SWWW_DIR}"

if [ ! -d "${SWWW_DIR}/swww" ]; then
    log "Cloning swww repository"
    cd "${SWWW_DIR}"
    git clone https://github.com/Horus645/swww.git
fi

cd "${SWWW_DIR}/swww"
log "Building swww (this may take a few minutes)"
if cargo build --release; then
    log "Installing swww binaries"
    cp -v target/release/swww /usr/bin/
    cp -v target/release/swww-daemon /usr/bin/
    success "swww installed successfully"
else
    warn "Failed to build swww, skipping"
    FAILURES="${FAILURES}\n  - swww (custom build)"
fi

# Enable display manager or session manager services if needed
log "Checking for display manager services"
if package_installed "x11-misc/sddm"; then
    log "Enabling SDDM display manager"
    systemctl enable sddm
elif package_installed "x11-misc/lightdm"; then
    log "Enabling LightDM display manager"
    systemctl enable lightdm
else
    log "No display manager found - you'll need to start Hyprland manually"
    log "Tip: Add 'exec Hyprland' to your shell profile or use a login manager"
fi

# Report results
echo
section "Desktop Installation Summary"

if [ -n "${FAILURES}" ]; then
    warn "The following packages failed to install:"
    echo -e "${FAILURES}"
fi

if [ -n "${SKIPPED}" ]; then
    warn "The following packages were skipped (not found):"
    echo -e "${SKIPPED}"
fi

if [ -z "${FAILURES}" ] && [ -z "${SKIPPED}" ]; then
    success "All desktop packages installed successfully!"
else
    warn "Desktop installation completed with some issues"
    warn "Review the failures above and install manually if needed"
fi

success "Desktop environment installation completed"
log "You may want to configure Hyprland, Waybar, and other dotfiles next"
