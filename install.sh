#!/bin/bash
#
# Gentoo Desktop Automated Installer
# Phase-based orchestrator for reproducible, resumable Gentoo installation
#
# Usage:
#   ./install.sh [phase]       # Run specific phase or all phases
#   ./install.sh --reset       # Clear completion state and start over
#   ./install.sh --list        # List all phases and their status
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_DIR="${SCRIPT_DIR}/phases"
LIB_DIR="${SCRIPT_DIR}/lib"
STATE_DIR="${SCRIPT_DIR}/state"
CONFIG_DIR="${SCRIPT_DIR}/config"
PHASE_MARKER="${STATE_DIR}/.completed_phases"
LOG_FILE="${STATE_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

# Source libraries
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=lib/validators.sh
source "${LIB_DIR}/validators.sh"
# shellcheck source=lib/preflight.sh
source "${LIB_DIR}/preflight.sh"

# Set up error and interrupt handling
setup_error_handling
setup_interrupt_handling

# Ensure state directory exists
mkdir -p "${STATE_DIR}"

# Phase definitions
PHASES=(
    "01-partition"
    "02-bootstrap"
    "03-base-config"
    "04-portage"
    "05-kernel"
    "06-bootloader"
    "07-system-pkgs"
    "08-users"
    "09-desktop"
    "10-audit"
)

# Check if a phase has been completed
phase_completed() {
    local phase=$1
    grep -q "^${phase}$" "${PHASE_MARKER}" 2>/dev/null
}

# Mark a phase as completed
mark_phase_completed() {
    local phase=$1
    echo "${phase}" >> "${PHASE_MARKER}"
    log "Phase ${phase} marked as completed"
}

# Run a single phase
run_phase() {
    local phase=$1
    local phase_script="${PHASE_DIR}/${phase}.sh"

    if [ ! -f "${phase_script}" ]; then
        error "Phase script not found: ${phase_script}"
        return 1
    fi

    if phase_completed "${phase}"; then
        log "Phase ${phase} already completed, skipping"
        return 0
    fi

    log "=========================================="
    log "Starting phase: ${phase}"
    log "=========================================="

    if bash "${phase_script}"; then
        mark_phase_completed "${phase}"
        log "Phase ${phase} completed successfully"
        return 0
    else
        error "Phase ${phase} failed!"
        return 1
    fi
}

# List all phases and their status
list_phases() {
    echo "Gentoo Installation Phases:"
    echo
    for phase in "${PHASES[@]}"; do
        if phase_completed "${phase}"; then
            echo "  [✓] ${phase}"
        else
            echo "  [ ] ${phase}"
        fi
    done
    echo
}

# Reset installation state
reset_state() {
    warn "This will reset all phase completion state."
    read -p "Are you sure? (yes/no): " -r
    if [[ $REPLY == "yes" ]]; then
        rm -f "${PHASE_MARKER}"
        log "Installation state has been reset"
    else
        log "Reset cancelled"
    fi
}

# Interactive configuration prompt
prompt_configuration() {
    echo "=========================================="
    echo "Gentoo Installer Configuration"
    echo "=========================================="
    echo

    # Set defaults
    : "${KERNEL_METHOD:=bin}"
    : "${PRIMARY_USER:=henninb}"
    : "${HOSTNAME:=gentoo}"

    # Detect available disks
    echo "Detecting available disks..."
    echo
    local disks=()

    # Try lsblk first
    if command -v lsblk &> /dev/null; then
        while IFS= read -r line; do
            # Parse the line - lsblk outputs: NAME SIZE TYPE
            local disk=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $2}')
            local type=$(echo "$line" | awk '{print $3}')

            if [ "$type" = "disk" ]; then
                disks+=("$disk")
                echo "  [$((${#disks[@]}))] /dev/$disk - $size"
            fi
        done < <(lsblk -ndo NAME,SIZE,TYPE 2>/dev/null)
    fi

    # Fallback: check for common disk devices directly
    if [ ${#disks[@]} -eq 0 ]; then
        echo "  Using fallback detection..."
        for dev in /dev/vd[a-z] /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
            if [ -b "$dev" ]; then
                local disk=$(basename "$dev")
                local size=""
                if [ -f "/sys/block/$disk/size" ]; then
                    local sectors=$(cat "/sys/block/$disk/size")
                    local gb=$((sectors / 2 / 1024 / 1024))
                    size="${gb}G"
                fi
                disks+=("$disk")
                echo "  [$((${#disks[@]}))] /dev/$disk${size:+ - $size}"
            fi
        done
    fi

    echo

    # Prompt for disk if not set
    if [ -z "${DISK:-}" ]; then
        if [ ${#disks[@]} -eq 0 ]; then
            error "No disks detected!"
            exit 1
        elif [ ${#disks[@]} -eq 1 ]; then
            DISK="/dev/${disks[0]}"
            echo "Only one disk detected: $DISK"
            read -p "Use $DISK? (yes/no) [yes]: " -r confirm
            confirm=${confirm:-yes}
            if [[ ! $confirm =~ ^(yes|y|YES|Y)$ ]]; then
                error "Installation cancelled"
                exit 1
            fi
        else
            echo "⚠️  WARNING: The selected disk will be COMPLETELY ERASED!"
            echo
            read -p "Select disk number [1]: " -r disk_num
            disk_num=${disk_num:-1}

            if [ "$disk_num" -lt 1 ] || [ "$disk_num" -gt ${#disks[@]} ]; then
                error "Invalid disk selection"
                exit 1
            fi

            DISK="/dev/${disks[$((disk_num-1))]}"
            echo
            echo "Selected: $DISK"
            read -p "⚠️  Are you SURE you want to erase $DISK? (yes/no): " -r confirm
            if [[ ! $confirm == "yes" ]]; then
                error "Installation cancelled"
                exit 1
            fi
        fi
    fi

    # Show configuration summary
    echo
    echo "=========================================="
    echo "Configuration Summary:"
    echo "=========================================="
    echo "  Disk:          $DISK"
    echo "  Hostname:      $HOSTNAME"
    echo "  Primary User:  $PRIMARY_USER"
    echo "  Kernel Method: $KERNEL_METHOD (binary kernel)"
    echo "=========================================="
    echo

    # Export for use in phases
    export DISK
    export HOSTNAME
    export PRIMARY_USER
    export KERNEL_METHOD
}

# Main execution
main() {
    log "Gentoo Automated Installer started"
    log "Log file: ${LOG_FILE}"

    # Prompt for configuration and run pre-flight checks before starting installation
    # Skip for utility commands
    case "${1:-}" in
        --list|--reset|--help|-h|--audit)
            # Skip configuration prompt and pre-flight for these commands
            ;;
        01-partition|"")
            # Prompt for configuration if not already set
            if ! phase_completed "01-partition"; then
                prompt_configuration

                # Run pre-flight checks with the configured disk
                if ! run_preflight_checks "${DISK}"; then
                    error "Pre-flight checks failed"
                    error "Please resolve the issues above before continuing"
                    exit 1
                fi
            fi
            ;;
        *)
            # For other specific phases, ensure configuration is set
            if [ -z "${DISK:-}" ] || [ -z "${HOSTNAME:-}" ] || [ -z "${PRIMARY_USER:-}" ]; then
                prompt_configuration
            fi
            ;;
    esac

    case "${1:-}" in
        --list)
            list_phases
            exit 0
            ;;
        --reset)
            reset_state
            exit 0
            ;;
        --audit)
            # Run audit standalone
            exec "${SCRIPT_DIR}/audit.sh" "${DISK:-/dev/sda}"
            ;;
        --help|-h)
            echo "Usage: $0 [phase|--list|--reset|--help]"
            echo
            echo "Options:"
            echo "  phase      Run a specific phase (e.g., 01-partition)"
            echo "  --list     Show all phases and completion status"
            echo "  --reset    Clear completion state and start over"
            echo "  --audit    Run comprehensive installation audit"
            echo "  --help     Show this help message"
            echo
            echo "Configuration:"
            echo "  The installer will interactively prompt for configuration."
            echo "  Defaults:"
            echo "    HOSTNAME=\"gentoo\""
            echo "    PRIMARY_USER=\"henninb\""
            echo "    KERNEL_METHOD=\"bin\" (binary kernel)"
            echo "    DISK=<prompted interactively>"
            echo
            echo "  Override defaults with environment variables:"
            echo "    DISK=\"/dev/sda\" HOSTNAME=\"myhost\" ./install.sh"
            echo
            echo "If no arguments provided, runs all incomplete phases in order."
            echo
            echo "Note: Phase 10 (audit) is optional and can be run separately:"
            echo "  ./audit.sh              # Standalone audit"
            echo "  ./install.sh 10-audit   # As part of installation"
            exit 0
            ;;
        "")
            # Run all phases
            for phase in "${PHASES[@]}"; do
                if ! run_phase "${phase}"; then
                    error "Installation halted due to phase failure"
                    exit 1
                fi
            done
            log "=========================================="
            log "All phases completed successfully!"
            log "=========================================="
            ;;
        *)
            # Run specific phase
            if [[ " ${PHASES[*]} " =~ " ${1} " ]]; then
                run_phase "${1}"
            else
                error "Unknown phase: ${1}"
                echo "Run '$0 --list' to see available phases"
                exit 1
            fi
            ;;
    esac
}

main "$@"
