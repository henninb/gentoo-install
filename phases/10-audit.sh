#!/bin/bash
#
# Phase 10: Installation Audit (Optional)
# Comprehensive verification of installation completeness
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validators.sh"
source "${SCRIPT_DIR}/lib/audit.sh"

section "Phase 10: Installation Audit"

# Configuration
DISK="${DISK:-/dev/sda}"
REPORT_FILE="${SCRIPT_DIR}/state/audit-report-$(date +%Y%m%d-%H%M%S).txt"

log "Running comprehensive installation audit"
log "This will verify all aspects of the installation"
echo

if run_complete_audit "${DISK}" "${REPORT_FILE}"; then
    success "Installation audit PASSED"
    log "Full report: ${REPORT_FILE}"
    exit 0
else
    warn "Installation audit found issues"
    error "Review the report: ${REPORT_FILE}"
    error "You may need to manually fix issues or re-run failed phases"

    if confirm "Continue anyway (mark audit phase as complete)?"; then
        warn "Audit phase marked complete despite issues"
        exit 0
    else
        error "Audit phase failed - fix issues and re-run"
        exit 1
    fi
fi
