# Quick Start - VM Testing

Get a Gentoo test VM running in under 5 minutes!

## TL;DR - Fastest Method

```bash
# One command to download ISO and create VM
./create-vm.sh --download

# Start and connect
virsh start gentoo-test
virt-viewer gentoo-test
```

Done! You now have a VM ready for testing the Gentoo installer.

## What Just Happened?

The script automatically:
1. Downloaded the latest Arch Linux ISO (~900MB)
2. Created a 40GB QCOW2 disk image
3. Created a VM with 4GB RAM, 4 CPUs, UEFI firmware
4. Configured network and graphics
5. Attached the ISO as boot media

## Next Steps

### 1. Boot the VM

```bash
virsh start gentoo-test
virt-viewer gentoo-test
```

### 2. In the VM (Arch ISO boot menu)

- Select "Arch Linux install medium"
- Wait for boot to complete
- You'll get a root shell automatically

### 3. Set Up Network (Usually Automatic)

```bash
# Check if network is working
ping -c 3 gentoo.org

# If not working, start DHCP
dhcpcd
```

### 4. Clone the Installer

```bash
# Install git if needed
pacman -Sy git

# Clone this repo
git clone https://github.com/henninb/gentoo-install.git
cd gentoo-install
```

### 5. Create Your First Snapshot

```bash
# From your host (different terminal)
virsh snapshot-create-as gentoo-test fresh-boot "Clean boot before install"
```

### 6. Start Testing

Follow the comprehensive [VM_TEST_PLAN.md](VM_TEST_PLAN.md) for detailed testing scenarios.

Or jump straight in with a quick test:

```bash
# In the VM
export DISK="/dev/vda"  # or /dev/sda depending on your config
export HOSTNAME="gentoo-vm"
export PRIMARY_USER="testuser"
export KERNEL_METHOD="bin"

# Run pre-chroot phases
sudo ./install.sh 01-partition
sudo ./install.sh 02-bootstrap

# ... continue with the installation
```

## Common Commands

### VM Management

```bash
# Start VM
virsh start gentoo-test

# Stop VM gracefully
virsh shutdown gentoo-test

# Force stop
virsh destroy gentoo-test

# Check status
virsh list --all
virsh dominfo gentoo-test
```

### Snapshots

```bash
# Create snapshot
virsh snapshot-create-as gentoo-test <name> "<description>"

# List snapshots
virsh snapshot-list gentoo-test

# Restore snapshot
virsh snapshot-revert gentoo-test <name>

# Delete snapshot
virsh snapshot-delete gentoo-test <name>
```

### Console Access

```bash
# Graphical viewer
virt-viewer gentoo-test

# virt-manager GUI
virt-manager

# Text console (press Ctrl+] to exit)
virsh console gentoo-test
```

### Cleanup

```bash
# Delete VM and disk completely
virsh destroy gentoo-test
virsh undefine gentoo-test --nvram
rm ~/.local/share/libvirt/images/gentoo-test.qcow2

# Or use the script to recreate from scratch
./create-vm.sh --delete --download
```

## Customization Options

### Different Resources

```bash
# More powerful VM for desktop testing
./create-vm.sh --download -m 8192 -c 8 -d 80

# Minimal VM for quick iteration
./create-vm.sh --download -m 2048 -c 2 -d 20
```

### Multiple Test VMs

```bash
# Create multiple VMs for parallel testing
./create-vm.sh --download -n gentoo-test1
./create-vm.sh --download -n gentoo-test2
./create-vm.sh --download -n gentoo-test3
```

### Use Existing ISO

```bash
# If you already downloaded the ISO
./create-vm.sh --iso ~/Downloads/archlinux-2025.01.01-x86_64.iso
```

## Troubleshooting

### "Cannot connect to libvirt"

```bash
# Add yourself to libvirt group
sudo usermod -aG libvirt $USER
newgrp libvirt

# Start libvirtd if not running
sudo systemctl start libvirtd
sudo systemctl enable libvirtd
```

### "VM already exists"

```bash
# Delete and recreate
./create-vm.sh --delete --download
```

### "Download failed"

```bash
# Try again (script will resume/retry)
./create-vm.sh --download

# Or download manually from: https://archlinux.org/download/
./create-vm.sh --iso ~/Downloads/archlinux-*.iso
```

### VM won't boot

```bash
# Check VM details
virsh dumpxml gentoo-test | grep -A5 "<boot"

# Ensure firmware is UEFI
virsh dumpxml gentoo-test | grep -i uefi
```

## Advanced Usage

### Custom Download Directory

```bash
./create-vm.sh --download --download-dir /mnt/isos
```

### Headless VM (No Graphics)

```bash
./create-vm.sh --download --graphics none
# Access via serial console: virsh console gentoo-test
```

### Different Network

```bash
# List available networks
virsh net-list --all

# Use specific network
./create-vm.sh --download --network bridge0
```

## What's Next?

1. **Test the base installation** - Follow Test 1 in VM_TEST_PLAN.md
2. **Test the desktop installation** - Follow Test 2 in VM_TEST_PLAN.md
3. **Test error recovery** - Follow Tests 3-4 in VM_TEST_PLAN.md
4. **Full test suite** - Complete all 10 tests in VM_TEST_PLAN.md
5. **Bare metal** - Once VM tests pass, deploy to real hardware

## Tips for Effective Testing

1. **Take snapshots frequently** - Before each major phase
2. **Test failures** - Intentionally break things to test recovery
3. **Document issues** - Keep notes on what works and what doesn't
4. **Iterate quickly** - Use snapshots to rollback and retry
5. **Test variations** - Different configs, package sets, etc.

## ISO Auto-Download Details

The script downloads from: `https://geo.mirror.pkgbuild.com/iso/latest`

- Automatically finds the latest ISO
- Checks if already downloaded (won't re-download)
- Verifies download size
- Saves to `~/Downloads` by default
- Typical size: ~900MB
- Download time: 2-10 minutes depending on your connection

---

Happy testing! Report issues at: https://github.com/henninb/gentoo-install/issues
