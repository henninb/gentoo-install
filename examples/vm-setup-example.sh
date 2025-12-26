#!/bin/bash
# vm-setup-example.sh - Example workflow for setting up a test VM

# This example shows the complete workflow for creating a test VM
# and preparing it for testing the Gentoo installer

set -e

# Step 1 & 2: Auto-download ISO and create VM
echo "Creating test VM with auto-download..."

# Option A: Quick test with default settings (auto-download ISO)
./create-vm.sh --download

# Option B: Custom configuration for production-like testing
# ./create-vm.sh \
#   --name gentoo-prod-test \
#   --memory 8192 \
#   --cpus 8 \
#   --disk-size 80 \
#   --download

# Option C: Minimal resources for quick iteration
# ./create-vm.sh \
#   --name gentoo-minimal \
#   --memory 2048 \
#   --cpus 2 \
#   --disk-size 20 \
#   --download

# Option D: Use existing ISO
# ./create-vm.sh --iso ~/Downloads/archlinux-YYYY.MM.DD-x86_64.iso

# Step 3: Start the VM
echo "Starting VM..."
virsh start gentoo-test

# Step 4: Connect to the VM console
echo ""
echo "VM started successfully!"
echo ""
echo "Connect to the VM using one of these methods:"
echo "  1. virt-manager GUI: virt-manager"
echo "  2. virt-viewer:      virt-viewer gentoo-test"
echo "  3. virsh console:    virsh console gentoo-test"
echo ""
echo "Once booted into the Arch ISO, follow the test plan in VM_TEST_PLAN.md"
echo ""
echo "Recommended next steps:"
echo "  1. Boot from the ISO"
echo "  2. Set up network (usually automatic with dhcpcd)"
echo "  3. Clone this repo or mount shared folder"
echo "  4. Create initial snapshot: virsh snapshot-create-as gentoo-test fresh-boot 'Clean ISO boot'"
echo "  5. Follow VM_TEST_PLAN.md starting at Test 1"
