#!/bin/bash
#
# Common library functions for Gentoo installer
# Provides logging, error handling, and utility functions
#

# Ensure LOG_FILE is set by parent script
: "${LOG_FILE:=/tmp/gentoo-install.log}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log levels
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo -e "${BLUE}INFO:${NC} $*"
    echo "${msg}" >> "${LOG_FILE}"
}

warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*"
    echo -e "${YELLOW}WARN:${NC} $*" >&2
    echo "${msg}" >> "${LOG_FILE}"
}

error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo -e "${RED}ERROR:${NC} $*" >&2
    echo "${msg}" >> "${LOG_FILE}"
}

success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
    echo -e "${GREEN}✓${NC} $*"
    echo "${msg}" >> "${LOG_FILE}"
}

die() {
    error "$@"
    error "Installation cannot continue"
    error "Check log file: ${LOG_FILE}"
    exit 1
}

# Trap handler for errors
error_handler() {
    local line_no=$1
    local bash_lineno=$2
    local last_command="${BASH_COMMAND}"

    error "Command failed at line ${line_no}: ${last_command}"
    error "Exit code: $?"

    # Show last 10 lines of log if available
    if [ -f "${LOG_FILE}" ]; then
        error "Last log entries:"
        tail -n 10 "${LOG_FILE}" >&2
    fi
}

# Set up error trapping
setup_error_handling() {
    set -euo pipefail
    trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND"' ERR
}

# Cleanup handler for interrupts
cleanup_handler() {
    warn "Installation interrupted by user"
    log "You can resume by running the installer again"
    log "Completed phases will be skipped automatically"
    exit 130
}

setup_interrupt_handling() {
    trap cleanup_handler SIGINT SIGTERM
}

# Execute command and log output
run_logged() {
    local cmd="$*"
    log "Executing: ${cmd}"

    if eval "${cmd}" >> "${LOG_FILE}" 2>&1; then
        return 0
    else
        local exit_code=$?
        error "Command failed (exit ${exit_code}): ${cmd}"
        return ${exit_code}
    fi
}

# Check if running in chroot
in_chroot() {
    [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]
}

# Check if running as root
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root"
    fi
}

# Confirm action with user
confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-no}"

    if [ "${default}" = "yes" ]; then
        prompt="${prompt} [Y/n]: "
    else
        prompt="${prompt} [y/N]: "
    fi

    read -p "${prompt}" -r
    case "${REPLY}" in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        "") [ "${default}" = "yes" ] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Wait for network connectivity
wait_for_network() {
    local max_attempts=30
    local attempt=1

    log "Waiting for network connectivity..."

    while [ ${attempt} -le ${max_attempts} ]; do
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            success "Network is available"
            return 0
        fi
        log "Network not ready, attempt ${attempt}/${max_attempts}"
        sleep 2
        ((attempt++))
    done

    error "Network timeout after ${max_attempts} attempts"
    return 1
}

# Backup a file before modifying
backup_file() {
    local file=$1
    local backup_dir="${2:-/tmp/gentoo-install-backup}"

    if [ ! -f "${file}" ]; then
        warn "Cannot backup ${file}: file does not exist"
        return 1
    fi

    mkdir -p "${backup_dir}"
    local backup_path="${backup_dir}/$(basename "${file}").$(date +%Y%m%d-%H%M%S)"

    cp -a "${file}" "${backup_path}"
    log "Backed up ${file} to ${backup_path}"
}

# Check if package is installed
package_installed() {
    local pkg=$1
    if in_chroot; then
        equery list "${pkg}" >/dev/null 2>&1
    else
        # When not in chroot, check in /mnt/gentoo
        [ -d "/mnt/gentoo/var/db/pkg/${pkg}" ] 2>/dev/null
    fi
}

# Retry a command with exponential backoff
retry() {
    local max_attempts=${1}
    shift
    local cmd=("$@")
    local attempt=1
    local delay=1

    while [ ${attempt} -le ${max_attempts} ]; do
        if "${cmd[@]}"; then
            return 0
        fi

        warn "Command failed (attempt ${attempt}/${max_attempts}), retrying in ${delay}s..."
        sleep ${delay}
        delay=$((delay * 2))
        ((attempt++))
    done

    error "Command failed after ${max_attempts} attempts: ${cmd[*]}"
    return 1
}

# Pretty print a section header
section() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title} - 2) / 2 ))

    echo
    printf '%*s' "${width}" '' | tr ' ' '='
    echo
    printf "%*s %s %*s\n" ${padding} '' "${title}" ${padding} ''
    printf '%*s' "${width}" '' | tr ' ' '='
    echo
}

export -f log warn error success die run_logged in_chroot require_root
export -f confirm command_exists wait_for_network backup_file package_installed
export -f retry section error_handler setup_error_handling cleanup_handler
export -f setup_interrupt_handling
