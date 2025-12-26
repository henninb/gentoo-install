# VM Test Plan - Gentoo Automated Installer

This test plan validates the installer in a safe VM environment before using on bare metal.

## Test Environment Setup

This test plan supports both **virt-manager (KVM/QEMU)** and **VirtualBox**. virt-manager is recommended for Linux hosts as it provides better performance and easier automation.

### Option 1: virt-manager/KVM (Recommended for Linux)

**Automated VM Creation:**

Use the provided script to automatically create a test VM:

```bash
# Easiest: Auto-download Arch Linux ISO and create VM
./create-vm.sh --download

# Create VM with existing ISO
./create-vm.sh --iso ~/Downloads/archlinux-YYYY.MM.DD-x86_64.iso

# Create VM with custom resources and auto-download
./create-vm.sh \
  --name gentoo-test \
  --memory 8192 \
  --cpus 8 \
  --disk-size 80 \
  --download

# Recreate VM (delete existing first)
./create-vm.sh --delete --download

# Custom download directory
./create-vm.sh --download --download-dir /path/to/isos
```

**Manual VM Creation (if you prefer):**

```bash
# Install required packages (Arch Linux)
sudo pacman -S libvirt virt-manager qemu-kvm dnsmasq bridge-utils

# Install required packages (Debian/Ubuntu)
sudo apt install virt-manager qemu-kvm libvirt-daemon-system

# Start and enable libvirtd
sudo systemctl enable --now libvirtd

# Add your user to libvirt group
sudo usermod -aG libvirt $USER
newgrp libvirt
```

Then create VM using virt-manager GUI or CLI:

```bash
virt-install \
  --name gentoo-test \
  --memory 4096 \
  --vcpus 4 \
  --disk size=40,format=qcow2,bus=virtio \
  --cdrom ~/Downloads/archlinux.iso \
  --network network=default,model=virtio \
  --os-variant linux2022 \
  --boot uefi \
  --graphics spice \
  --video virtio
```

**Recommended VM Settings:**
```
Name: gentoo-test
Memory: 4096 MB (minimum 2048 MB)
CPUs: 4 (minimum 2)
Disk: 40 GB qcow2 (virtio bus)
  - Minimum: 20 GB
  - Recommended: 40+ GB for desktop

Firmware: UEFI (critical!)
Network: virtio (NAT or bridged)
  - Must have internet access
Graphics: Spice or VNC
Video: virtio (for Hyprland testing)
```

**Snapshot Management:**

Create snapshots at key points for testing recovery:

```bash
# Create snapshots
virsh snapshot-create-as gentoo-test fresh-boot "After ISO boot, before changes"
virsh snapshot-create-as gentoo-test post-partition "After phase 01 completes"
virsh snapshot-create-as gentoo-test stage3-extracted "After phase 02 completes"
virsh snapshot-create-as gentoo-test in-chroot "After entering chroot"
virsh snapshot-create-as gentoo-test base-system "After phases 1-8 complete"
virsh snapshot-create-as gentoo-test desktop-installed "After phase 09 completes"

# List snapshots
virsh snapshot-list gentoo-test

# Restore snapshot
virsh snapshot-revert gentoo-test fresh-boot

# Delete snapshot
virsh snapshot-delete gentoo-test fresh-boot
```

**VM Management Commands:**

```bash
# Start/Stop VM
virsh start gentoo-test
virsh shutdown gentoo-test
virsh destroy gentoo-test  # Force stop

# Connect to console
virsh console gentoo-test
virt-viewer gentoo-test
virt-manager --connect qemu:///system --show-domain-console gentoo-test

# VM info
virsh dominfo gentoo-test
virsh list --all

# Delete VM completely
virsh destroy gentoo-test
virsh undefine gentoo-test --nvram
rm ~/.local/share/libvirt/images/gentoo-test.qcow2
```

---

### Option 2: VirtualBox Configuration

**Recommended VM Settings:**
```
Name: gentoo-test
Type: Linux
Version: Gentoo (64-bit)

Memory: 4096 MB (minimum 2048 MB)
Processors: 4 CPUs (minimum 2)
Enable VT-x/AMD-V: Yes

Hard Disk: 40 GB VDI (dynamically allocated)
  - Minimum: 20 GB
  - Recommended: 40+ GB for desktop

Storage Controller: SATA
  - Enable EFI: YES (critical!)

Network: NAT or Bridged
  - Must have internet access

Display:
  - Video Memory: 128 MB
  - Graphics Controller: VMSVGA
  - Enable 3D Acceleration: Yes (for Hyprland testing)
```

**Installation Media:**
- Download Arch Linux live ISO (has all necessary tools)
- Or any Linux live ISO with: parted, curl, tar, chroot
- Attach to VM optical drive

**VirtualBox Snapshots:**

Create snapshots at key points for testing recovery (via GUI or VBoxManage):
```
Snapshot 1: "Fresh Boot"          - After ISO boot, before any changes
Snapshot 2: "Post-Partition"      - After phase 01 completes
Snapshot 3: "Stage3 Extracted"    - After phase 02 completes
Snapshot 4: "In-Chroot"           - After entering chroot
Snapshot 5: "Base System"         - After phases 1-8 complete
Snapshot 6: "Desktop Installed"   - After phase 09 completes
```

---

## Test Suite

### Test 1: Normal Installation (Base System)

**Objective**: Verify complete base system installation without errors.

**Steps:**

1. Boot VM from Arch Linux ISO
2. Verify network connectivity:
   ```bash
   ping -c 3 gentoo.org
   ```

3. Clone installer (or mount shared folder):
   ```bash
   git clone https://github.com/henninb/gentoo-install.git
   cd gentoo-install
   ```

4. Configure environment:
   ```bash
   export DISK="/dev/sda"
   export HOSTNAME="gentoo-vm"
   export TIMEZONE="America/Chicago"
   export PRIMARY_USER="testuser"
   export KERNEL_METHOD="bin"  # Fast binary kernel
   ```

5. Run pre-chroot phases:
   ```bash
   sudo ./install.sh --list
   sudo ./install.sh 01-partition
   sudo ./install.sh 02-bootstrap
   ```

6. **Checkpoint 1**: Verify partitions
   ```bash
   lsblk
   # Should show /dev/sda1 (vfat) and /dev/sda2 (ext4)

   ls /mnt/gentoo
   # Should show extracted stage3 directories
   ```

7. Prepare chroot:
   ```bash
   sudo mount -t proc none /mnt/gentoo/proc
   sudo mount --rbind /dev /mnt/gentoo/dev
   sudo mount --rbind /sys /mnt/gentoo/sys
   sudo cp -L /etc/resolv.conf /mnt/gentoo/etc/
   sudo cp -r $(pwd) /mnt/gentoo/root/gentoo-install
   ```

8. Enter chroot:
   ```bash
   sudo chroot /mnt/gentoo /bin/bash
   source /etc/profile
   export PS1="(chroot) $PS1"
   cd /root/gentoo-install
   ```

9. **Checkpoint 2**: Verify chroot environment
   ```bash
   ping -c 3 gentoo.org  # Network should work
   pwd                    # Should be /root/gentoo-install
   ls /usr/portage || ls /var/db/repos/gentoo  # Portage tree exists
   ```

10. Configure and run in-chroot phases:
    ```bash
    export HOSTNAME="gentoo-vm"
    export TIMEZONE="America/Chicago"
    export PRIMARY_USER="testuser"
    export KERNEL_METHOD="bin"

    ./install.sh --list  # Check what's pending
    ./install.sh         # Run all remaining phases
    ```

11. **Checkpoint 3**: Verify each phase completion
    ```bash
    # After phase 03
    cat /etc/hostname  # Should be "gentoo-vm"
    cat /etc/locale.gen | grep en_US.UTF-8

    # After phase 04
    emerge --info  # Should show your make.conf settings

    # After phase 05
    ls /boot/vmlinuz*  # Kernel should exist

    # After phase 06
    ls /boot/grub/grub.cfg  # GRUB config should exist
    cat /boot/grub/grub.cfg | grep vmlinuz  # Should have kernel entry

    # After phase 07
    which sudo  # Should find sudo
    which doas  # Should find doas

    # After phase 08
    id testuser  # User should exist
    groups testuser | grep wheel  # Should be in wheel group
    ```

12. Exit chroot and reboot:
    ```bash
    exit
    sudo umount -R /mnt/gentoo
    sudo reboot
    ```

13. **Checkpoint 4**: First boot verification
    - VM should boot to login prompt
    - Login as testuser
    - Verify network: `ping gentoo.org`
    - Verify sudo: `sudo whoami` (should return "root")
    - Check services: `systemctl status sshd dhcpcd cronie`

**Expected Results:**
- ✅ All phases complete without errors
- ✅ System boots successfully
- ✅ User can login and use sudo
- ✅ Network connectivity works
- ✅ All services running

**Time Estimate**: 30-60 minutes (mostly stage3 download + kernel install)

---

### Test 2: Normal Installation (Full Desktop)

**Objective**: Verify complete desktop environment installation.

**Prerequisites**: Complete Test 1 first, or restore to "Base System" snapshot.

**Steps:**

1. Boot into installed Gentoo VM
2. Login as testuser
3. Navigate to installer:
   ```bash
   cd /root/gentoo-install
   ```

4. Run desktop phase:
   ```bash
   sudo ./install.sh 09-desktop
   ```

5. **Monitor installation**:
   - Should enable GURU repository
   - Should install ~100 packages
   - Will take 1-3 hours depending on VM resources
   - Watch for failures (some packages may be skipped)

6. **Checkpoint**: Verify desktop packages
   ```bash
   # Check key packages
   which Hyprland
   which waybar
   which kitty
   ls /usr/share/wayland-sessions/  # Should have hyprland.desktop

   # Check fonts
   fc-list | grep -i nerd
   ```

7. Start Hyprland:
   ```bash
   # From TTY (Ctrl+Alt+F1 if needed)
   Hyprland
   ```

8. **Checkpoint**: Verify Hyprland functionality
   - Hyprland should start
   - Waybar should appear
   - Super+Return should open kitty terminal
   - Super+Q should close windows
   - Super+D should open wofi launcher

**Expected Results:**
- ✅ GURU overlay enabled
- ✅ Most packages install (some may fail - check summary)
- ✅ Hyprland starts successfully
- ✅ Basic keybindings work
- ✅ Terminal, launcher functional

**Time Estimate**: 1-3 hours

**Note**: Some packages may fail due to missing overlays or keywords. Check the installation summary at the end.

---

### Test 3: Resume After Interruption

**Objective**: Verify installation can resume after interruption.

**Setup**: Restore VM to "Fresh Boot" snapshot.

**Steps:**

1. Start installation as in Test 1
2. During phase 05 (kernel install), press **Ctrl+C**
3. **Checkpoint**: Verify graceful interrupt
   ```
   WARN: Installation interrupted by user
   INFO: You can resume by running the installer again
   INFO: Completed phases will be skipped automatically
   ```

4. Check phase status:
   ```bash
   ./install.sh --list
   ```
   Expected output:
   ```
   [✓] 01-partition
   [✓] 02-bootstrap
   [✓] 03-base-config
   [✓] 04-portage
   [ ] 05-kernel        # Not completed
   [ ] 06-bootloader
   [ ] 07-system-pkgs
   [ ] 08-users
   ```

5. Resume installation:
   ```bash
   ./install.sh
   ```

6. **Checkpoint**: Verify resume behavior
   - Phases 01-04 should be skipped (logged but not re-run)
   - Phase 05 should run from the beginning
   - Subsequent phases should run normally

**Expected Results:**
- ✅ Interrupt handled gracefully
- ✅ Completed phases are skipped
- ✅ Failed phase re-runs completely
- ✅ Installation continues to completion

**Time Estimate**: 45 minutes

---

### Test 4: Resume After Phase Failure

**Objective**: Verify recovery from a failed phase.

**Setup**: Restore VM to "In-Chroot" snapshot.

**Steps:**

1. Simulate a failure by breaking network:
   ```bash
   # From host, disable VM network adapter
   # Or in VM: sudo systemctl stop NetworkManager dhcpcd
   ```

2. Try to run phase 04 (needs network):
   ```bash
   ./install.sh 04-portage
   ```

3. **Checkpoint**: Verify failure handling
   - Should fail with clear error message
   - Should show log file location
   - Should NOT mark phase as completed

4. Fix the issue:
   ```bash
   # Re-enable network
   sudo systemctl start dhcpcd
   ping -c 3 gentoo.org
   ```

5. Re-run failed phase:
   ```bash
   ./install.sh 04-portage
   ```

6. **Checkpoint**: Verify recovery
   - Phase should complete successfully
   - Should be marked as completed
   - Next phases should run normally

**Expected Results:**
- ✅ Failure detected and reported
- ✅ Phase NOT marked as completed on failure
- ✅ Can recover by fixing issue and re-running
- ✅ No corruption of installation state

**Time Estimate**: 20 minutes

---

### Test 5: Pre-flight Check Validation

**Objective**: Verify pre-flight checks catch issues before installation.

**Setup**: Restore VM to "Fresh Boot" snapshot.

**Tests to run:**

#### 5a. Insufficient Disk Space

1. Create VM with 10GB disk (below 20GB minimum)
2. Run installer:
   ```bash
   sudo ./install.sh
   ```

3. **Expected**: Pre-flight check should fail with:
   ```
   ERROR: Disk is too small (10GB < 20GB minimum)
   ```

#### 5b. No Network Connectivity

1. Disable VM network adapter
2. Run installer:
   ```bash
   sudo ./install.sh
   ```

3. **Expected**: Pre-flight check should fail with:
   ```
   ERROR: No network connectivity detected
   ERROR: Please configure network before running the installer
   ```

#### 5c. Not Running as Root

1. Try to run without sudo:
   ```bash
   ./install.sh
   ```

3. **Expected**:
   ```
   ERROR: This installer must be run as root
   ```

#### 5d. Missing Required Commands

1. Uninstall parted:
   ```bash
   # On Arch live ISO
   sudo pacman -R parted
   ```

2. Run installer:
   ```bash
   sudo ./install.sh
   ```

3. **Expected**:
   ```
   ERROR: Missing required commands: parted
   ERROR: Please install these tools before running the installer
   ```

**Expected Results:**
- ✅ All pre-flight checks catch their respective issues
- ✅ Clear error messages explain what's wrong
- ✅ Installation does not proceed with failed checks

**Time Estimate**: 30 minutes

---

### Test 6: Different Configurations

**Objective**: Test various configuration options.

#### 6a. Different Stage3 Profiles

Test with different profiles:

```bash
# Test 1: Minimal systemd
export STAGE3_PROFILE="systemd"
sudo ./install.sh 02-bootstrap

# Test 2: OpenRC
export STAGE3_PROFILE="openrc"
sudo ./install.sh 02-bootstrap

# Test 3: Manual URL
export STAGE3_URL="https://mirror.bytemark.co.uk/gentoo/releases/amd64/autobuilds/20230115T170214Z/stage3-amd64-systemd-20230115T170214Z.tar.xz"
sudo ./install.sh 02-bootstrap
```

**Expected**: Each should download/use the specified stage3.

#### 6b. Different Kernel Methods

```bash
# Test with genkernel (slow, but tests compilation)
export KERNEL_METHOD="genkernel"
./install.sh 05-kernel
```

**Expected**: Should compile kernel from source (takes 20-40 minutes in VM).

#### 6c. Different Disk Devices

Test with NVMe-style naming:

```bash
# Create VM with NVMe disk
export DISK="/dev/nvme0n1"
sudo ./install.sh 01-partition
```

**Expected**: Should handle different device naming.

**Time Estimate**: 1-2 hours (depending on tests selected)

---

### Test 7: Custom Package Lists

**Objective**: Verify package list customization works.

**Steps:**

1. Edit package lists:
   ```bash
   # Add custom packages
   echo "app-editors/vim" >> config/world.txt
   echo "app-editors/neovim" >> config/desktop-packages.txt
   ```

2. Run package installation:
   ```bash
   ./install.sh 07-system-pkgs
   ./install.sh 09-desktop
   ```

3. **Checkpoint**: Verify custom packages installed
   ```bash
   which vim
   which nvim
   ```

4. Test package removal:
   ```bash
   # Remove a package from list
   sed -i '/vim/d' config/world.txt

   # Add it back
   echo "app-editors/vim" >> config/world.txt

   # Re-run (should be idempotent)
   ./install.sh 07-system-pkgs
   ```

**Expected Results:**
- ✅ Custom packages are installed
- ✅ Re-running phases is idempotent
- ✅ Changes to lists are respected

**Time Estimate**: 20 minutes

---

### Test 8: Log File Verification

**Objective**: Verify logging works correctly.

**Steps:**

1. Run any phase:
   ```bash
   ./install.sh 01-partition
   ```

2. Check log files:
   ```bash
   ls state/
   # Should show: install-YYYYMMDD-HHMMSS.log

   cat state/install-*.log | head -20
   # Should show detailed command output with timestamps
   ```

3. Verify log contents:
   ```bash
   grep "ERROR" state/install-*.log    # Should show any errors
   grep "SUCCESS" state/install-*.log  # Should show successes
   grep "Executing:" state/install-*.log  # Should show commands run
   ```

**Expected Results:**
- ✅ Log files created with timestamps
- ✅ All commands logged
- ✅ Errors clearly marked
- ✅ Log includes both stdout and stderr

**Time Estimate**: 10 minutes

---

### Test 9: State Management

**Objective**: Verify phase tracking works correctly.

**Steps:**

1. Check initial state:
   ```bash
   cat state/.completed_phases
   # Should be empty or not exist
   ```

2. Run a phase:
   ```bash
   sudo ./install.sh 01-partition
   ```

3. Check state:
   ```bash
   cat state/.completed_phases
   # Should contain: 01-partition
   ```

4. Try to run same phase again:
   ```bash
   sudo ./install.sh 01-partition
   ```

5. **Checkpoint**: Should see:
   ```
   INFO: Phase 01-partition already completed, skipping
   ```

6. Reset state:
   ```bash
   ./install.sh --reset
   # Confirm with: yes
   ```

7. Check state:
   ```bash
   cat state/.completed_phases
   # Should not exist or be empty
   ```

**Expected Results:**
- ✅ Completed phases tracked correctly
- ✅ Completed phases are skipped
- ✅ Reset clears state
- ✅ Can re-run after reset

**Time Estimate**: 15 minutes

---

### Test 10: Full End-to-End (Production Simulation)

**Objective**: Simulate a real bare-metal installation from start to finish.

**Setup**: Fresh VM, no snapshots.

**Steps:**

1. Boot Arch Linux ISO
2. Complete installation in one go:
   ```bash
   git clone https://github.com/henninb/gentoo-install.git
   cd gentoo-install

   export DISK="/dev/sda"
   export HOSTNAME="production-vm"
   export PRIMARY_USER="henninb"
   export KERNEL_METHOD="bin"

   # Pre-chroot
   sudo ./install.sh 01-partition
   sudo ./install.sh 02-bootstrap

   # Chroot
   sudo mount -t proc none /mnt/gentoo/proc
   sudo mount --rbind /dev /mnt/gentoo/dev
   sudo mount --rbind /sys /mnt/gentoo/sys
   sudo cp -L /etc/resolv.conf /mnt/gentoo/etc/
   sudo cp -r $(pwd) /mnt/gentoo/root/gentoo-install
   sudo chroot /mnt/gentoo /bin/bash
   source /etc/profile
   cd /root/gentoo-install

   # In-chroot - all phases at once
   export HOSTNAME="production-vm"
   export PRIMARY_USER="henninb"
   export KERNEL_METHOD="bin"
   ./install.sh  # Runs 03-09 automatically

   # Exit and reboot
   exit
   sudo umount -R /mnt/gentoo
   sudo reboot
   ```

3. **Post-boot verification**:
   ```bash
   # Login as henninb
   # Verify everything
   sudo emerge --info
   systemctl status
   Hyprland  # Should start desktop
   ```

**Expected Results:**
- ✅ Complete installation without manual intervention
- ✅ All phases complete successfully
- ✅ System boots to working desktop
- ✅ No errors in logs

**Time Estimate**: 2-4 hours (mostly compilation)

---

## Test Results Template

Use this template to track test results:

```markdown
## Test Results - [Date]

### Environment
- VM Software: virt-manager/KVM / VirtualBox / QEMU / VMware
- Host OS: [OS]
- VM Resources: [CPU/RAM/Disk]
- Installation Media: Arch Linux [version]
- Installer Version: [git commit hash]

### Test 1: Normal Installation (Base System)
- Status: ✅ PASS / ❌ FAIL
- Time: ____ minutes
- Issues: [None / describe issues]
- Notes:

### Test 2: Normal Installation (Full Desktop)
- Status: ✅ PASS / ❌ FAIL
- Time: ____ minutes
- Packages failed: [list any]
- Desktop functional: ✅ YES / ❌ NO
- Notes:

### Test 3: Resume After Interruption
- Status: ✅ PASS / ❌ FAIL
- Interrupted at: Phase ___
- Resumed correctly: ✅ YES / ❌ NO
- Notes:

[Continue for all tests...]

### Overall Assessment
- Ready for bare metal: ✅ YES / ❌ NO / ⚠️  WITH CAVEATS
- Critical issues: [list]
- Minor issues: [list]
- Recommendations:
```

---

## Common Issues and Troubleshooting

### Issue: Stage3 download fails

**Symptoms**: Phase 02 fails with curl error

**Diagnosis**:
```bash
curl -I https://mirror.bytemark.co.uk/gentoo/
# Check if mirror is accessible
```

**Solutions**:
- Try different mirror: `export MIRROR_BASE="https://mirrors.rit.edu/gentoo"`
- Check VM network settings
- Retry with: `./install.sh 02-bootstrap` (automatic retry built-in)

---

### Issue: Kernel doesn't boot

**Symptoms**: VM boots to GRUB but kernel panic

**Diagnosis**:
```bash
# From live ISO, mount and chroot
mount /dev/sda2 /mnt/gentoo
mount /dev/sda1 /mnt/gentoo/boot/efi
chroot /mnt/gentoo /bin/bash

# Check kernel files
ls /boot/
cat /boot/grub/grub.cfg
```

**Solutions**:
- Regenerate GRUB config: `grub-mkconfig -o /boot/grub/grub.cfg`
- Try binary kernel: `export KERNEL_METHOD="bin"` and re-run phase 05
- Check VM is in EFI mode (not BIOS)

---

### Issue: Network doesn't work in chroot

**Symptoms**: Cannot ping or download in chroot

**Solutions**:
```bash
# Copy resolv.conf
cp -L /etc/resolv.conf /mnt/gentoo/etc/

# Verify from chroot
ping -c 3 gentoo.org
cat /etc/resolv.conf  # Should have nameservers
```

---

### Issue: emerge fails with "blocked packages"

**Symptoms**: Phase 07 or 09 fails with dependency conflicts

**Solutions**:
```bash
# Try with --autounmask-write
emerge --autounmask-write [package]
etc-update --automode -5

# Or manually resolve
emerge --depclean
emerge --update --deep --newuse @world
```

---

### Issue: Desktop doesn't start

**Symptoms**: Hyprland fails to launch

**Diagnosis**:
```bash
# Check logs
cat /tmp/hypr/$(ls -t /tmp/hypr/ | head -1)/hyprland.log

# Check if packages installed
which Hyprland
which waybar
```

**Solutions**:
- Install missing packages manually
- Check config/desktop-packages.txt for errors
- Try minimal start: `Hyprland --config /dev/null`

---

## Success Criteria

The installer is ready for bare metal when:

- ✅ All 10 tests pass
- ✅ Base system boots reliably (Test 1)
- ✅ Desktop is functional (Test 2)
- ✅ Resume works correctly (Tests 3, 4)
- ✅ Pre-flight catches issues (Test 5)
- ✅ Logs are complete and helpful
- ✅ No critical bugs found
- ✅ Recovery from common failures works
- ✅ End-to-end test completes successfully (Test 10)

---

## Next Steps After Successful Testing

1. **Document any issues found** and their workarounds
2. **Update package lists** based on failures
3. **Commit final version** to git
4. **Backup the repository**
5. **Create bootable USB** with installer pre-loaded
6. **Test on bare metal** in non-critical system first
7. **Keep VM for regression testing** future changes

---

## Automation Script (Optional)

Quick test runner:

```bash
#!/bin/bash
# quick-test.sh - Run basic validation

export DISK="/dev/sda"
export HOSTNAME="gentoo-test"
export PRIMARY_USER="testuser"
export KERNEL_METHOD="bin"

echo "=== Pre-chroot Tests ==="
sudo ./install.sh 01-partition || exit 1
sudo ./install.sh 02-bootstrap || exit 1

echo "=== Preparing chroot ==="
sudo mount -t proc none /mnt/gentoo/proc
sudo mount --rbind /dev /mnt/gentoo/dev
sudo mount --rbind /sys /mnt/gentoo/sys
sudo cp -L /etc/resolv.conf /mnt/gentoo/etc/
sudo cp -r $(pwd) /mnt/gentoo/root/gentoo-install

echo "=== Enter chroot and run: ==="
echo "cd /root/gentoo-install && export HOSTNAME=gentoo-test PRIMARY_USER=testuser && ./install.sh"
```

Good luck with testing! 🚀
