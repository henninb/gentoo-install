# Installation Audit System

The Gentoo installer includes a comprehensive audit system to verify that your installation is complete and correct.

## What Does the Audit Check?

The audit performs 50+ checks across 12 categories:

### 1. Disk Partitioning
- ✓ Boot and root partitions exist
- ✓ Correct filesystem types (FAT32 for boot, ext4 for root)
- ✓ Adequate partition sizes (512MB+ boot, 20GB+ root)

### 2. Mount Points
- ✓ Root filesystem mounted
- ✓ Boot partition mounted at /boot/efi
- ✓ /etc/fstab configured correctly

### 3. Base System
- ✓ Critical directories exist (/bin, /etc, /usr, /var, /home)
- ✓ Gentoo release files present
- ✓ System structure intact

### 4. Locale and Timezone
- ✓ Locale configured (en_US.UTF-8)
- ✓ Timezone set correctly
- ✓ Hostname configured
- ✓ /etc/hosts has correct entries

### 5. Portage Configuration
- ✓ Portage tree synced
- ✓ make.conf exists and configured
- ✓ USE flags set
- ✓ MAKEOPTS configured
- ✓ Profile selected

### 6. Kernel
- ✓ Kernel installed in /boot
- ✓ Initramfs present (if needed)
- ✓ Kernel sources configured (if present)
- ✓ Running kernel matches installed (if booted)

### 7. Bootloader
- ✓ GRUB installed
- ✓ grub.cfg exists
- ✓ Kernel entries in GRUB config
- ✓ EFI files present
- ✓ Boot entries configured

### 8. System Packages
- ✓ Critical packages installed (systemd, grub, sudo, dhcpcd, bash)
- ✓ Reasonable package count (100+ packages)

### 9. Users and Permissions
- ✓ Root user exists
- ✓ Root password set
- ✓ Regular user(s) created
- ✓ sudo or doas configured
- ✓ Wheel group permissions

### 10. Services (if booted)
- ✓ SSH daemon enabled
- ✓ DHCP client enabled
- ✓ Cron daemon enabled
- ✓ Services running

### 11. Network
- ✓ DNS configured (/etc/resolv.conf)
- ✓ Internet connectivity (if booted)
- ✓ DNS resolution working (if booted)

### 12. Desktop Environment (if installed)
- ✓ Hyprland installed
- ✓ Waybar, kitty, wofi present
- ✓ Wayland session file exists

## How to Run the Audit

### Method 1: Standalone Audit Script

Run the audit at any time:

```bash
# Basic audit
./audit.sh

# Specify disk
./audit.sh /dev/nvme0n1

# Custom report location
./audit.sh /dev/sda /tmp/my-audit-report.txt
```

### Method 2: As Part of Installation (Phase 10)

Include audit as the final installation phase:

```bash
# Run as part of install workflow
./install.sh 10-audit

# Or run all phases including audit
./install.sh  # Will run phases 1-10
```

### Method 3: Via Install Script Flag

```bash
./install.sh --audit
```

## When to Run the Audit

### During Installation (Recommended)

Run after completing all installation phases:

```bash
# After phases 1-9
./install.sh 10-audit
```

### After First Boot

Boot into your new system and verify:

```bash
cd /root/gentoo-install
./audit.sh
```

### Before Disaster Recovery Test

Audit your current system to establish a baseline:

```bash
./audit.sh
# Save the report for comparison after rebuild
```

### After Making Changes

Verify system integrity after:
- Major updates (`emerge -uDN @world`)
- Configuration changes
- Package installations
- System recovery

## Understanding Audit Results

### Result Types

- **[PASS]** - Check passed, no issues
- **[WARN]** - Check passed with warnings, may need attention
- **[FAIL]** - Check failed, requires action

### Exit Codes

```bash
./audit.sh
echo $?
```

- **0** - Audit passed (all checks passed or minor warnings)
- **1** - Audit failed (critical issues found)

### Example Output

```
==========================================
         Running Complete Installation Audit
==========================================

Environment: booted

==========================================
         Auditing Disk Partitioning
==========================================
✓ [PASS] Disk: Boot partition exists: /dev/sda1
✓ [PASS] Disk: Root partition exists: /dev/sda2
✓ [PASS] Disk: Boot partition is FAT32
✓ [PASS] Disk: Root partition is ext4
✓ [PASS] Disk: Boot partition size adequate: 1024MB
✓ [PASS] Disk: Root partition size adequate: 50GB

==========================================
         Auditing Mount Points
==========================================
✓ [PASS] Mounts: Root filesystem mounted at /
✓ [PASS] Mounts: Boot partition mounted at /boot/efi
✓ [PASS] Mounts: /etc/fstab contains boot entry
✓ [PASS] Mounts: /etc/fstab has root entry

... (continues for all categories)

==========================================
         Audit Report
==========================================

Date: 2025-01-15 12:34:56
Environment: booted
Hostname: gentoo

Summary:
  ✓ Passed:  47
  ⚠ Warnings: 3
  ✗ Failed:  0

======================================

✓ Audit PASSED - Installation appears complete and correct

Audit report saved to: state/audit-report-20250115-123456.txt
```

## Audit Reports

### Report Location

Reports are saved to:
```
state/audit-report-YYYYMMDD-HHMMSS.txt
```

### Report Format

```
======================================
  Gentoo Installation Audit Report
======================================

Date: 2025-01-15 12:34:56
Environment: booted
Hostname: gentoo

Summary:
  ✓ Passed:  47
  ⚠ Warnings: 3
  ✗ Failed:  0

======================================

=== Disk ===
PASS - Disk - Boot partition exists: /dev/sda1
PASS - Disk - Root partition exists: /dev/sda2
PASS - Disk - Boot partition is FAT32
...

=== Mounts ===
PASS - Mounts - Root filesystem mounted at /
...

=== System ===
PASS - System - Critical directory exists: /bin
...

(grouped by category for easy review)
```

### Multiple Reports

The audit keeps all reports with timestamps:

```bash
ls -lh state/audit-report-*.txt

# Compare before/after
diff state/audit-report-20250115-120000.txt \
     state/audit-report-20250115-130000.txt
```

## Common Audit Failures and Fixes

### FAIL: Boot partition not mounted

**Fix:**
```bash
mount /dev/sda1 /boot/efi
# Update /etc/fstab if needed
```

### FAIL: No kernel found in /boot

**Fix:**
```bash
./install.sh 05-kernel
```

### FAIL: GRUB config missing kernel entries

**Fix:**
```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

### FAIL: Root password may not be set

**Fix:**
```bash
passwd root
```

### FAIL: No internet connectivity

**Fix:**
```bash
systemctl start dhcpcd
# or
systemctl start NetworkManager
```

### WARN: Low package count

**Cause:** Minimal installation or failed package installs

**Fix:**
```bash
# Review and install missing packages
./install.sh 07-system-pkgs
./install.sh 09-desktop
```

## Integration with Installation Workflow

### Automatic Audit (Recommended)

Run audit as part of installation:

```bash
# install.sh automatically includes phase 10 (audit)
./install.sh  # Runs phases 1-10 including audit
```

### Manual Audit

Skip audit during installation, run later:

```bash
# Install without audit
./install.sh 01-partition
./install.sh 02-bootstrap
# ... through 09-desktop

# Later, run audit manually
./audit.sh
```

### Audit on First Boot

Add to post-install checklist:

```bash
# After reboot into new system
cd /root/gentoo-install
./audit.sh

# Review report
cat state/audit-report-*.txt
```

## Advanced Usage

### Audit from Live System

Audit the installed system from live media:

```bash
# Boot live media
# Mount installed system
mount /dev/sda2 /mnt/gentoo
mount /dev/sda1 /mnt/gentoo/boot/efi

# Run audit
cd /path/to/gentoo-install
AUDIT_ENV=live ./audit.sh /dev/sda
```

### Audit Specific Categories

Modify `audit.sh` to run specific checks:

```bash
# In audit.sh, comment out categories you don't need
# audit_desktop    # Skip desktop audit
```

### Custom Audit Checks

Add your own checks to `lib/audit.sh`:

```bash
# Add custom audit function
audit_custom_apps() {
    section "Auditing Custom Applications"

    if [ -f "/usr/bin/myapp" ]; then
        audit_result PASS "Custom" "myapp installed"
    else
        audit_result FAIL "Custom" "myapp missing"
    fi
}

# Add to run_complete_audit()
run_complete_audit() {
    # ... existing checks ...
    audit_custom_apps
    # ...
}
```

### Scheduled Audits

Run audits on a schedule:

```bash
# Add to crontab
0 0 * * 0 /root/gentoo-install/audit.sh

# Or systemd timer
# /etc/systemd/system/gentoo-audit.timer
[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
```

## Audit in CI/CD

Use audit for automated testing:

```bash
#!/bin/bash
# ci-test.sh

# Run installation in VM
./install.sh

# Run audit
if ./audit.sh; then
    echo "Installation test PASSED"
    exit 0
else
    echo "Installation test FAILED"
    cat state/audit-report-*.txt
    exit 1
fi
```

## FAQ

### Q: Should I run the audit before or after reboot?

**A:** Run it both times:
- Before reboot (in chroot): Validates installation completeness
- After reboot: Validates boot process and running services

### Q: Can I skip the audit?

**A:** Yes, it's optional. Phase 10 can be skipped:
```bash
# Install without audit
./install.sh 01-partition
# ... through 09-desktop
# Skip 10-audit
```

### Q: What if the audit fails?

**A:** Review the report, fix issues, re-run:
```bash
# Fix the issue (e.g., re-run failed phase)
./install.sh 05-kernel

# Re-run audit
./audit.sh
```

### Q: Does audit modify the system?

**A:** No, the audit is read-only. It only checks and reports.

### Q: Can I run audit on a running system?

**A:** Yes! Audit works in three modes:
- **chroot**: During installation (before reboot)
- **booted**: After reboot into new system
- **live**: From live media examining installed system

### Q: How long does the audit take?

**A:** Very fast, typically 5-10 seconds. No compilation or network access.

### Q: Should I commit audit reports to git?

**A:** Optional. Reports are in `.gitignore` by default, but you can commit them:
```bash
git add -f state/audit-report-*.txt
git commit -m "Baseline audit report"
```

## Summary

The audit system provides:

✅ **Comprehensive verification** - 50+ checks across 12 categories
✅ **Multiple run modes** - Chroot, booted, or live media
✅ **Detailed reports** - Timestamped, categorized, saved
✅ **Actionable results** - Clear pass/warn/fail with explanations
✅ **Flexible integration** - Standalone, phase 10, or automated
✅ **No system changes** - Read-only verification

Run it regularly to ensure your Gentoo system stays healthy!
