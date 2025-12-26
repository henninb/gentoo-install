#!/bin/bash
# destroy-vm.sh - Automated VM destruction for Gentoo installer testing
# Supports virt-manager (libvirt/QEMU/KVM) VMs

set -e

# Configuration
VM_NAME="${VM_NAME:-gentoo-test}"
VM_DISK_PATH="${VM_DISK_PATH:-$HOME/.local/share/libvirt/images/${VM_NAME}.qcow2}"
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///session}"  # Use session mode by default
DELETE_SNAPSHOTS="${DELETE_SNAPSHOTS:-true}"
FORCE="${FORCE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy a virtual machine created for Gentoo installer testing.

OPTIONS:
    -n, --name NAME         VM name (default: gentoo-test)
    -p, --disk-path PATH    Path for VM disk (default: ~/.local/share/libvirt/images/NAME.qcow2)
    --session               Use qemu:///session (user VMs, default)
    --system                Use qemu:///system (system VMs, requires permissions)
    --keep-snapshots        Keep VM snapshots (default: delete all)
    --keep-disk             Keep disk file (default: delete)
    -f, --force             Force deletion without confirmation
    -h, --help              Show this help message

ENVIRONMENT VARIABLES:
    VM_NAME, VM_DISK_PATH, LIBVIRT_URI, DELETE_SNAPSHOTS, FORCE

EXAMPLES:
    # Destroy VM with default name
    $0

    # Destroy specific VM
    $0 --name my-gentoo-vm

    # Destroy VM but keep disk
    $0 --keep-disk

    # Force destroy without confirmation
    $0 --force

    # Destroy system VM
    $0 --system --name gentoo-test

REQUIREMENTS:
    - libvirt, virsh installed
    - VM must exist in specified libvirt connection

EOF
}

check_requirements() {
    print_info "Checking requirements..."

    local missing=()

    for cmd in virsh; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required commands: ${missing[*]}"
        print_error "Install packages: libvirt"
        exit 1
    fi

    # Check if user can access libvirt
    if ! virsh --connect "$LIBVIRT_URI" list &> /dev/null; then
        print_error "Cannot connect to libvirt ($LIBVIRT_URI)"
        if [ "$LIBVIRT_URI" = "qemu:///system" ]; then
            print_error "You may need to add your user to the 'libvirt' group:"
            print_error "  sudo usermod -aG libvirt \$USER"
            print_error "  newgrp libvirt"
        else
            print_error "Make sure libvirtd is running:"
            print_error "  sudo systemctl start libvirtd"
        fi
        exit 1
    fi

    print_info "All requirements met"
}

confirm_deletion() {
    if [ "$FORCE" = true ]; then
        return 0
    fi

    echo ""
    print_warn "You are about to destroy the following VM:"
    echo "  VM Name:        $VM_NAME"
    echo "  Libvirt URI:    $LIBVIRT_URI"
    echo "  Disk Path:      $VM_DISK_PATH"
    echo "  Delete Disk:    ${DELETE_DISK:-true}"
    echo "  Delete Snaps:   $DELETE_SNAPSHOTS"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Destruction cancelled"
        exit 0
    fi
}

destroy_vm() {
    local vm_name="$1"

    print_info "Checking for VM: $vm_name"

    # Check if VM exists
    if ! virsh --connect "$LIBVIRT_URI" list --all | grep -q "$vm_name"; then
        print_warn "VM $vm_name does not exist in $LIBVIRT_URI"

        # Still check if disk exists
        if [ -f "$VM_DISK_PATH" ] && [ "${DELETE_DISK:-true}" = true ]; then
            print_info "Found orphaned disk file: $VM_DISK_PATH"
            print_info "Removing disk..."
            rm -f "$VM_DISK_PATH"
            print_info "Disk removed successfully"
        fi

        return 0
    fi

    # Delete snapshots if requested
    if [ "$DELETE_SNAPSHOTS" = true ]; then
        print_info "Checking for snapshots..."
        local snapshots
        snapshots=$(virsh --connect "$LIBVIRT_URI" snapshot-list "$vm_name" --name 2>/dev/null || true)

        if [ -n "$snapshots" ]; then
            print_info "Found snapshots, deleting..."
            while IFS= read -r snapshot; do
                if [ -n "$snapshot" ]; then
                    print_info "  Deleting snapshot: $snapshot"
                    virsh --connect "$LIBVIRT_URI" snapshot-delete "$vm_name" "$snapshot"
                fi
            done <<< "$snapshots"
            print_info "All snapshots deleted"
        else
            print_info "No snapshots found"
        fi
    fi

    # Check if running and destroy
    if virsh --connect "$LIBVIRT_URI" list --state-running | grep -q "$vm_name"; then
        print_info "VM is running, destroying..."
        virsh --connect "$LIBVIRT_URI" destroy "$vm_name"
        print_info "VM destroyed (powered off)"
    else
        print_info "VM is not running"
    fi

    # Undefine VM
    print_info "Undefining VM..."
    # Try with --nvram first (for UEFI VMs), fall back to without
    if ! virsh --connect "$LIBVIRT_URI" undefine "$vm_name" --nvram 2>/dev/null; then
        virsh --connect "$LIBVIRT_URI" undefine "$vm_name"
    fi
    print_info "VM undefined successfully"

    # Delete disk if requested
    if [ "${DELETE_DISK:-true}" = true ]; then
        if [ -f "$VM_DISK_PATH" ]; then
            print_info "Removing disk: $VM_DISK_PATH"
            rm -f "$VM_DISK_PATH"
            print_info "Disk removed successfully"
        else
            print_info "Disk file not found: $VM_DISK_PATH"
        fi
    else
        print_info "Keeping disk file: $VM_DISK_PATH"
    fi
}

# Parse command line arguments
DELETE_DISK=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            VM_NAME="$2"
            shift 2
            ;;
        -p|--disk-path)
            VM_DISK_PATH="$2"
            shift 2
            ;;
        --session)
            LIBVIRT_URI="qemu:///session"
            shift
            ;;
        --system)
            LIBVIRT_URI="qemu:///system"
            shift
            ;;
        --keep-snapshots)
            DELETE_SNAPSHOTS=false
            shift
            ;;
        --keep-disk)
            DELETE_DISK=false
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Update disk path if default and name changed
if [[ "$VM_DISK_PATH" == "$HOME/.local/share/libvirt/images/gentoo-test.qcow2" ]] && [ "$VM_NAME" != "gentoo-test" ]; then
    VM_DISK_PATH="$HOME/.local/share/libvirt/images/${VM_NAME}.qcow2"
fi

# Main execution
check_requirements
confirm_deletion
destroy_vm "$VM_NAME"

print_info "VM destruction complete!"
