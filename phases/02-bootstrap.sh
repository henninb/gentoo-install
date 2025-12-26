#!/bin/bash
#
# Phase 02: Bootstrap Stage3
# Mounts partitions, downloads and extracts stage3 tarball
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 02: Bootstrap Stage3"

# Configuration
DISK="${DISK:-/dev/sda}"
BOOT_PART="${DISK}1"
ROOT_PART="${DISK}2"
MOUNT_ROOT="/mnt/gentoo"

# US mirrors (try in order)
US_MIRRORS=(
    "https://gentoo.osuosl.org"
    "https://mirrors.rit.edu/gentoo"
    "https://mirror.leaseweb.com/gentoo"
    "https://distfiles.gentoo.org"
)

MIRROR_BASE="${MIRROR_BASE:-${US_MIRRORS[0]}}"
STAGE3_PROFILE="${STAGE3_PROFILE:-desktop-systemd}"  # Options: desktop-systemd, systemd, openrc, desktop-openrc
STAGE3_PATTERN="stage3-amd64-${STAGE3_PROFILE}-*.tar.xz"

# Function to get latest stage3 URL
get_latest_stage3_url() {
    local mirror="$1"
    local profile="$2"
    local autobuilds="${mirror}/releases/amd64/autobuilds"
    local latest_file="latest-stage3-amd64-${profile}.txt"

    log "Fetching latest stage3 information for profile: ${profile}"

    # Download the latest file index
    local latest_path
    latest_path=$(curl -sL "${autobuilds}/${latest_file}" | \
        grep -v '^#' | \
        grep -v '^$' | \
        grep -v '^-' | \
        grep '\.tar\.' | \
        head -n1 | \
        awk '{print $1}')

    if [ -z "${latest_path}" ]; then
        error "Failed to determine latest stage3 path"
        return 1
    fi

    local full_url="${autobuilds}/${latest_path}"
    log "Latest stage3 URL: ${full_url}"
    echo "${full_url}"
}

require_root
wait_for_network

# Check if already mounted
if mountpoint -q "${MOUNT_ROOT}"; then
    log "${MOUNT_ROOT} already mounted"
else
    log "Mounting root partition"
    mkdir -p "${MOUNT_ROOT}"
    run_logged mount "${ROOT_PART}" "${MOUNT_ROOT}"
fi

if mountpoint -q "${MOUNT_ROOT}/boot/efi"; then
    log "${MOUNT_ROOT}/boot/efi already mounted"
else
    log "Mounting boot partition"
    mkdir -p "${MOUNT_ROOT}/boot/efi"
    run_logged mount "${BOOT_PART}" "${MOUNT_ROOT}/boot/efi"
fi

validate_mounts

# Check if stage3 already extracted
if validate_stage3 "${MOUNT_ROOT}" 2>/dev/null; then
    warn "Stage3 appears to already be extracted"
    if ! confirm "Re-extract stage3? This will overwrite existing files"; then
        log "Skipping stage3 extraction"
        exit 0
    fi
fi

cd "${MOUNT_ROOT}"

# Download stage3 if not already present
if ls ${STAGE3_PATTERN} 1>/dev/null 2>&1; then
    log "Stage3 tarball already downloaded"
    STAGE3_FILE=$(ls ${STAGE3_PATTERN} | head -n1)
else
    log "Downloading latest stage3 tarball"

    DOWNLOAD_SUCCESS=false

    # Get latest stage3 URL (use provided URL or auto-detect)
    if [ -n "${STAGE3_URL:-}" ]; then
        log "Using provided STAGE3_URL: ${STAGE3_URL}"
        DOWNLOAD_URL="${STAGE3_URL}"

        # Clean the URL (remove any whitespace or newlines)
        DOWNLOAD_URL=$(echo "${DOWNLOAD_URL}" | tr -d '[:space:]')
        STAGE3_FILE=$(basename "${DOWNLOAD_URL}")

        log "Downloading: ${STAGE3_FILE}"
        log "From: ${DOWNLOAD_URL}"
        log "This may take several minutes depending on your connection..."

        if curl -L --fail --progress-bar -o "${STAGE3_FILE}" "${DOWNLOAD_URL}"; then
            DOWNLOAD_SUCCESS=true
        fi
    else
        # Try each mirror in sequence
        log "Auto-detecting latest stage3 tarball from US mirrors"

        for mirror in "${US_MIRRORS[@]}"; do
            log "Trying mirror: ${mirror}"

            DOWNLOAD_URL=$(get_latest_stage3_url "${mirror}" "${STAGE3_PROFILE}" 2>/dev/null)
            if [ $? -ne 0 ] || [ -z "${DOWNLOAD_URL}" ]; then
                warn "Failed to get stage3 URL from ${mirror}, trying next mirror..."
                continue
            fi

            # Clean the URL (remove any whitespace or newlines)
            DOWNLOAD_URL=$(echo "${DOWNLOAD_URL}" | tr -d '[:space:]')
            STAGE3_FILE=$(basename "${DOWNLOAD_URL}")

            log "Downloading: ${STAGE3_FILE}"
            log "From: ${DOWNLOAD_URL}"
            log "This may take several minutes depending on your connection..."

            if curl -L --fail --progress-bar -o "${STAGE3_FILE}" "${DOWNLOAD_URL}"; then
                DOWNLOAD_SUCCESS=true
                success "Downloaded from ${mirror}"
                break
            else
                warn "Download failed from ${mirror}, trying next mirror..."
                rm -f "${STAGE3_FILE}"  # Clean up partial download
            fi
        done
    fi

    if [ "${DOWNLOAD_SUCCESS}" != "true" ]; then
        error "Failed to download stage3 tarball from all mirrors"
        error "You can try manually downloading from:"
        error "  https://www.gentoo.org/downloads/"
        error "And placing the .tar.xz file in ${MOUNT_ROOT}/"
        exit 1
    fi

    # Download and verify checksums (optional but recommended)
    log "Downloading checksums for verification"
    CHECKSUM_URL="${DOWNLOAD_URL}.sha256"
    if curl -sL "${CHECKSUM_URL}" -o "${STAGE3_FILE}.sha256"; then
        log "Verifying checksum..."
        if sha256sum -c "${STAGE3_FILE}.sha256" 2>/dev/null | grep -q OK; then
            success "Checksum verification passed"
        else
            warn "Checksum verification failed or not available"
            if ! confirm "Continue anyway?"; then
                exit 1
            fi
        fi
    else
        warn "Checksum file not available, skipping verification"
    fi
fi

# Extract stage3
log "Extracting stage3 tarball: ${STAGE3_FILE}"
log "This may take several minutes..."

if ! tar xJpf "${STAGE3_FILE}" --xattrs --numeric-owner 2>&1 | tee -a "${LOG_FILE}"; then
    error "Failed to extract stage3 tarball"
    error "The tarball may be corrupted. Try deleting it and re-running this phase."
    exit 1
fi

# Clean up tarball to save space (optional)
if confirm "Delete stage3 tarball to save space?" "no"; then
    rm -f "${STAGE3_FILE}" "${STAGE3_FILE}.sha256"
    log "Stage3 tarball deleted"
fi

# Generate fstab
log "Generating fstab"
if command_exists genfstab; then
    run_logged genfstab -U "${MOUNT_ROOT}" ">>" "${MOUNT_ROOT}/etc/fstab"
else
    warn "genfstab not available, you will need to create /etc/fstab manually"
fi

# Validate
validate_stage3 "${MOUNT_ROOT}"

success "Stage3 bootstrap completed"
