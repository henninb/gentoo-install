#!/bin/bash
#
# Standalone Gentoo Installation Audit Script
# Verifies installation completeness and correctness
#
# Usage:
#   ./audit.sh [disk] [report-file]
#
# Examples:
#   ./audit.sh                          # Audit with defaults
#   ./audit.sh /dev/nvme0n1             # Audit specific disk
#   ./audit.sh /dev/sda custom-report.txt  # Custom report file
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
STATE_DIR="${SCRIPT_DIR}/state"
LOG_FILE="${STATE_DIR}/audit-$(date +%Y%m%d-%H%M%S).log"

# Ensure state directory exists
mkdir -p "${STATE_DIR}"

# Source libraries
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=lib/audit.sh
source "${LIB_DIR}/audit.sh"

# Configuration
DISK="${1:-${DISK:-/dev/sda}}"
REPORT_FILE="${2:-${STATE_DIR}/audit-report-$(date +%Y%m%d-%H%M%S).txt}"

# Main
main() {
    log "Gentoo Installation Audit"
    log "Log file: ${LOG_FILE}"
    log "Report file: ${REPORT_FILE}"
    echo

    if run_complete_audit "${DISK}" "${REPORT_FILE}"; then
        echo
        success "Audit completed successfully!"
        echo
        echo "Review full report: ${REPORT_FILE}"
        exit 0
    else
        echo
        error "Audit found issues - review report for details"
        echo
        echo "Report: ${REPORT_FILE}"
        exit 1
    fi
}

main "$@"
