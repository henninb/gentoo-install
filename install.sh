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

# Main execution
main() {
    log "Gentoo Automated Installer started"
    log "Log file: ${LOG_FILE}"

    # Run pre-flight checks before starting installation
    # Skip pre-flight for utility commands
    case "${1:-}" in
        --list|--reset|--help|-h)
            # Skip pre-flight for these commands
            ;;
        01-partition|"")
            # Run pre-flight checks only for phases that need them
            if ! phase_completed "01-partition"; then
                if ! run_preflight_checks "${DISK:-/dev/sda}"; then
                    error "Pre-flight checks failed"
                    error "Please resolve the issues above before continuing"
                    exit 1
                fi
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
