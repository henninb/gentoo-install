#!/bin/bash
#
# Phase 01: Disk Partitioning
# Creates GPT partition table and filesystems
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"

section "Phase 01: Disk Partitioning"

# Configuration
DISK="${DISK:-/dev/sda}"
BOOT_PART="${DISK}1"
ROOT_PART="${DISK}2"

require_root

# Check if already partitioned
if validate_partitions "${DISK}" 2>/dev/null; then
    warn "Disk appears to already be partitioned correctly"
    if ! confirm "Repartition anyway? This will DESTROY ALL DATA"; then
        log "Skipping partitioning"
        exit 0
    fi
fi

log "Partitioning ${DISK}"

# Create GPT partition table
run_logged parted "${DISK}" mklabel gpt

# Create partitions
# 1GB EFI boot partition
run_logged parted "${DISK}" mkpart primary 1 1024
# Remaining space for root
run_logged parted "${DISK}" mkpart primary 1024 100%

# Format partitions
log "Formatting boot partition (FAT32)"
run_logged mkfs.fat -F32 "${BOOT_PART}"

log "Formatting root partition (ext4)"
run_logged mkfs.ext4 -j -b 4096 "${ROOT_PART}"

# Validate results
validate_partitions "${DISK}"

success "Disk partitioning completed"
