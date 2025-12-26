#!/bin/bash
# create-vm.sh - Automated VM creation for Gentoo installer testing
# Supports virt-manager (libvirt/QEMU/KVM) for testing the automated installer

set -e

# Configuration
VM_NAME="${VM_NAME:-gentoo-test}"
VM_MEMORY="${VM_MEMORY:-4096}"  # MB
VM_CPUS="${VM_CPUS:-4}"
VM_DISK_SIZE="${VM_DISK_SIZE:-40}"  # GB
# Use user's home directory by default to avoid permission issues
VM_DISK_PATH="${VM_DISK_PATH:-$HOME/.local/share/libvirt/images/${VM_NAME}.qcow2}"
ISO_PATH="${ISO_PATH:-}"  # Path to Arch Linux ISO or other live ISO
ISO_DOWNLOAD_DIR="${ISO_DOWNLOAD_DIR:-$HOME/Downloads}"  # Where to download ISO
NETWORK="${NETWORK:-}"  # libvirt network to use (empty = auto-detect)
GRAPHICS="${GRAPHICS:-spice}"  # spice, vnc, or none
AUTO_DOWNLOAD="${AUTO_DOWNLOAD:-false}"  # Auto-download Arch ISO if not found
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///session}"  # Use session mode by default

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

Create a virtual machine for testing the Gentoo automated installer.

OPTIONS:
    -n, --name NAME         VM name (default: gentoo-test)
    -m, --memory MB         Memory in MB (default: 4096)
    -c, --cpus COUNT        CPU count (default: 4)
    -d, --disk-size GB      Disk size in GB (default: 40)
    -i, --iso PATH          Path to installation ISO (optional with --download)
    -p, --disk-path PATH    Path for VM disk (default: ~/.local/share/libvirt/images/NAME.qcow2)
    --network NAME          Libvirt network (default: default)
    --graphics TYPE         Graphics type: spice, vnc, none (default: spice)
    --download              Auto-download latest Arch Linux ISO if not found
    --download-dir PATH     Directory for ISO download (default: ~/Downloads)
    --session               Use qemu:///session (user VMs, default)
    --system                Use qemu:///system (system VMs, requires permissions)
    --delete                Delete existing VM with same name
    -h, --help              Show this help message

ENVIRONMENT VARIABLES:
    VM_NAME, VM_MEMORY, VM_CPUS, VM_DISK_SIZE, ISO_PATH, ISO_DOWNLOAD_DIR, NETWORK, GRAPHICS, LIBVIRT_URI

EXAMPLES:
    # Auto-download Arch ISO and create VM
    $0 --download

    # Create VM with existing ISO
    $0 --iso ~/Downloads/archlinux.iso

    # Create VM with custom resources
    $0 -n gentoo-prod -m 8192 -c 8 -d 80 --download

    # Delete existing VM and recreate with download
    $0 --delete --download

REQUIREMENTS:
    - libvirt, virt-install, qemu-kvm installed
    - User in libvirt group or run with sudo
    - curl (for --download option)
    - Arch Linux ISO or similar live ISO with partitioning tools

EOF
}

check_requirements() {
    print_info "Checking requirements..."

    local missing=()

    for cmd in virt-install virsh qemu-img; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    # Check for curl if download is enabled
    if [ "$AUTO_DOWNLOAD" = true ] && ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required commands: ${missing[*]}"
        print_error "Install packages: libvirt qemu-kvm virt-install curl"
        exit 1
    fi

    # Check if libvirtd is running
    if ! systemctl is-active --quiet libvirtd; then
        print_error "libvirtd service is not running"
        print_error "Start it with: sudo systemctl start libvirtd"
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

download_arch_iso() {
    print_info "Downloading latest Arch Linux ISO..."

    # Create download directory if it doesn't exist
    mkdir -p "$ISO_DOWNLOAD_DIR"

    # Get the latest ISO URL from Arch Linux mirror
    local mirror_url="https://geo.mirror.pkgbuild.com/iso/latest"

    print_info "Fetching latest ISO information from Arch Linux mirrors..."

    # Get the ISO filename from the mirror
    local iso_name
    iso_name=$(curl -s "${mirror_url}/" | grep -oP 'archlinux-[0-9]{4}\.[0-9]{2}\.[0-9]{2}-x86_64\.iso(?!\.sig)' | head -1)

    if [ -z "$iso_name" ]; then
        print_error "Failed to determine latest Arch Linux ISO name"
        print_error "Please download manually from: https://archlinux.org/download/"
        exit 1
    fi

    local iso_url="${mirror_url}/${iso_name}"
    local iso_path="${ISO_DOWNLOAD_DIR}/${iso_name}"

    # Check if ISO already exists
    if [ -f "$iso_path" ]; then
        print_info "ISO already exists: $iso_path"

        # Verify it's not corrupted (basic size check)
        local size
        size=$(stat -f%z "$iso_path" 2>/dev/null || stat -c%s "$iso_path" 2>/dev/null || echo "0")

        if [ "$size" -gt 500000000 ]; then  # Should be > 500MB
            print_info "Using existing ISO"
            ISO_PATH="$iso_path"
            return 0
        else
            print_warn "Existing ISO appears corrupted (too small), re-downloading..."
            rm -f "$iso_path"
        fi
    fi

    print_info "Downloading: $iso_name"
    print_info "From: $iso_url"
    print_info "To: $iso_path"
    print_info "This may take several minutes..."

    # Download with progress bar
    if ! curl -L -o "$iso_path" --progress-bar "$iso_url"; then
        print_error "Failed to download ISO"
        print_error "Please download manually from: https://archlinux.org/download/"
        rm -f "$iso_path"
        exit 1
    fi

    # Verify download size
    local size
    size=$(stat -f%z "$iso_path" 2>/dev/null || stat -c%s "$iso_path" 2>/dev/null || echo "0")

    if [ "$size" -lt 500000000 ]; then
        print_error "Downloaded ISO appears corrupted (too small: $size bytes)"
        rm -f "$iso_path"
        exit 1
    fi

    print_info "Download complete: $iso_path"
    print_info "Size: $(du -h "$iso_path" | cut -f1)"

    ISO_PATH="$iso_path"
}

delete_vm() {
    local vm_name="$1"

    print_info "Checking for existing VM: $vm_name"

    if virsh --connect "$LIBVIRT_URI" list --all | grep -q "$vm_name"; then
        print_warn "VM $vm_name already exists"

        # Check if running
        if virsh --connect "$LIBVIRT_URI" list --state-running | grep -q "$vm_name"; then
            print_info "Destroying running VM..."
            virsh --connect "$LIBVIRT_URI" destroy "$vm_name"
        fi

        print_info "Undefining VM..."
        virsh --connect "$LIBVIRT_URI" undefine "$vm_name" --nvram || virsh --connect "$LIBVIRT_URI" undefine "$vm_name"

        print_info "VM deleted successfully"
    fi

    # Delete disk if exists
    if [ -f "$VM_DISK_PATH" ]; then
        print_warn "Removing existing disk: $VM_DISK_PATH"
        rm -f "$VM_DISK_PATH"
    fi
}

create_vm() {
    print_info "Creating VM: $VM_NAME"
    print_info "  Memory: ${VM_MEMORY}MB"
    print_info "  CPUs: $VM_CPUS"
    print_info "  Disk: ${VM_DISK_SIZE}GB"
    print_info "  ISO: $ISO_PATH"

    # Create directory for disk image if it doesn't exist
    local disk_dir
    disk_dir=$(dirname "$VM_DISK_PATH")
    if [ ! -d "$disk_dir" ]; then
        print_info "Creating disk directory: $disk_dir"
        mkdir -p "$disk_dir"
    fi

    # Create qcow2 disk
    print_info "Creating disk image: $VM_DISK_PATH"
    qemu-img create -f qcow2 "$VM_DISK_PATH" "${VM_DISK_SIZE}G"

    # Determine network configuration
    local network_arg
    if [ -n "$NETWORK" ]; then
        # Use specified network
        network_arg="network=$NETWORK,model=virtio"
    elif [ "$LIBVIRT_URI" = "qemu:///session" ]; then
        # Session mode: use user-mode networking (no network setup required)
        network_arg="user,model=virtio"
    else
        # System mode: use default network
        network_arg="network=default,model=virtio"
    fi

    # Build virt-install command
    local cmd=(
        virt-install
        --connect "$LIBVIRT_URI"
        --name "$VM_NAME"
        --memory "$VM_MEMORY"
        --vcpus "$VM_CPUS"
        --disk "path=$VM_DISK_PATH,format=qcow2,bus=virtio"
        --cdrom "$ISO_PATH"
        --network "$network_arg"
        --os-variant linux2022
        --boot uefi
        --graphics "$GRAPHICS"
        --video virtio
        --console pty,target_type=serial
        --noautoconsole
    )

    print_info "Creating VM with virt-install..."
    print_info "Using libvirt connection: $LIBVIRT_URI"
    "${cmd[@]}"

    print_info "VM created successfully!"
}

show_vm_info() {
    print_info "VM Information:"
    echo ""
    virsh --connect "$LIBVIRT_URI" dominfo "$VM_NAME"
    echo ""

    print_info "To connect to the VM console:"
    echo "  virt-manager (GUI):  virt-manager --connect $LIBVIRT_URI --show-domain-console $VM_NAME"
    echo "  virsh (CLI):         virsh --connect $LIBVIRT_URI console $VM_NAME"
    echo "  VNC viewer:          virt-viewer --connect $LIBVIRT_URI $VM_NAME"
    echo ""

    print_info "VM Management Commands:"
    echo "  Start VM:            virsh --connect $LIBVIRT_URI start $VM_NAME"
    echo "  Stop VM:             virsh --connect $LIBVIRT_URI shutdown $VM_NAME"
    echo "  Force stop:          virsh --connect $LIBVIRT_URI destroy $VM_NAME"
    echo "  Delete VM:           virsh --connect $LIBVIRT_URI undefine $VM_NAME --nvram"
    echo "  VM status:           virsh --connect $LIBVIRT_URI dominfo $VM_NAME"
    echo "  List all VMs:        virsh --connect $LIBVIRT_URI list --all"
    echo ""

    print_info "Snapshot Commands:"
    echo "  Create snapshot:     virsh --connect $LIBVIRT_URI snapshot-create-as $VM_NAME snapshot1 'Description'"
    echo "  List snapshots:      virsh --connect $LIBVIRT_URI snapshot-list $VM_NAME"
    echo "  Restore snapshot:    virsh --connect $LIBVIRT_URI snapshot-revert $VM_NAME snapshot1"
    echo "  Delete snapshot:     virsh --connect $LIBVIRT_URI snapshot-delete $VM_NAME snapshot1"
    echo ""

    print_info "Libvirt Connection:"
    echo "  URI:                 $LIBVIRT_URI"
    echo "  Note: Session mode runs VMs as your user (no permission issues)"
    echo ""

    print_info "Disk Location:"
    echo "  Disk image:          $VM_DISK_PATH"
    echo "  To delete manually:  rm \"$VM_DISK_PATH\""
    echo ""

    print_info "Next Steps:"
    echo "  1. Start the VM and boot from the ISO"
    echo "  2. Follow the VM_TEST_PLAN.md for testing the installer"
    echo "  3. Create snapshots at key points for easy rollback"
}

# Parse command line arguments
DELETE_EXISTING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            VM_NAME="$2"
            shift 2
            ;;
        -m|--memory)
            VM_MEMORY="$2"
            shift 2
            ;;
        -c|--cpus)
            VM_CPUS="$2"
            shift 2
            ;;
        -d|--disk-size)
            VM_DISK_SIZE="$2"
            shift 2
            ;;
        -i|--iso)
            ISO_PATH="$2"
            shift 2
            ;;
        -p|--disk-path)
            VM_DISK_PATH="$2"
            shift 2
            ;;
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --graphics)
            GRAPHICS="$2"
            shift 2
            ;;
        --download)
            AUTO_DOWNLOAD=true
            shift
            ;;
        --download-dir)
            ISO_DOWNLOAD_DIR="$2"
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
        --delete)
            DELETE_EXISTING=true
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

# Validate required parameters
if [ -z "$ISO_PATH" ] && [ "$AUTO_DOWNLOAD" != true ]; then
    print_error "ISO path is required (use --iso or --download)"
    echo ""
    usage
    exit 1
fi

# Update disk path if default and name changed
if [ "$VM_DISK_PATH" = "$HOME/.local/share/libvirt/images/gentoo-test.qcow2" ] && [ "$VM_NAME" != "gentoo-test" ]; then
    VM_DISK_PATH="$HOME/.local/share/libvirt/images/${VM_NAME}.qcow2"
fi

# Main execution
check_requirements

# Download ISO if requested or if ISO doesn't exist
if [ "$AUTO_DOWNLOAD" = true ]; then
    download_arch_iso
elif [ ! -f "$ISO_PATH" ]; then
    print_error "ISO file not found: $ISO_PATH"
    print_info "Use --download to automatically download the latest Arch Linux ISO"
    exit 1
fi

if [ "$DELETE_EXISTING" = true ]; then
    delete_vm "$VM_NAME"
else
    # Check for existing VM
    if virsh --connect "$LIBVIRT_URI" list --all | grep -q "$VM_NAME"; then
        print_error "VM $VM_NAME already exists"
        print_error "Use --delete flag to remove it first, or choose a different name"
        exit 1
    fi
fi

create_vm
show_vm_info

print_info "VM creation complete!"
