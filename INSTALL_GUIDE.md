# Gentoo Automated Installation Guide

This guide walks you through using the phase-based automated installer to set up a complete Gentoo Linux system with Hyprland desktop environment.

## Prerequisites

1. **Installation Media**: Boot from Arch Linux live USB or any Linux with:
   - parted, mkfs tools
   - curl, tar, sha256sum
   - chroot capability
   - Internet connection

2. **Hardware Requirements**:
   - Minimum 20GB disk space (100GB+ recommended)
   - Minimum 2GB RAM (4GB+ recommended)
   - UEFI firmware (BIOS may work with manual tweaks)
   - Network connectivity

## Installation Steps

### Step 1: Boot Installation Media

Boot your installation media and verify network connectivity:

```bash
ping -c 3 gentoo.org
```

### Step 2: Clone the Installer

```bash
git clone https://github.com/henninb/gentoo-install.git
cd gentoo-install
```

### Step 3: Configure Environment

Set your installation parameters:

```bash
# Required: Specify target disk (WARNING: Will be wiped!)
export DISK="/dev/sda"              # Change to your disk (e.g., /dev/nvme0n1)

# System configuration
export HOSTNAME="gentoo"            # Your desired hostname
export TIMEZONE="America/Chicago"   # Your timezone
export PRIMARY_USER="henninb"       # Your username

# Stage3 configuration
export STAGE3_PROFILE="desktop-systemd"  # or: systemd, openrc, desktop-openrc
# export STAGE3_URL="<url>"         # Optional: Manually specify stage3 URL

# Kernel configuration
export KERNEL_METHOD="bin"          # bin = binary kernel (fast), genkernel = compile

# Bootloader
export BOOTLOADER_ID="gentoo"       # GRUB EFI entry name
```

### Step 4: Review Your Configuration

**IMPORTANT**: Double-check your disk selection!

```bash
echo "Target disk: ${DISK}"
lsblk
```

### Step 5: Run Pre-Installation Phases (Outside Chroot)

Run phases 01-02 outside the chroot:

```bash
# Phase 01: Partition the disk
sudo ./install.sh 01-partition

# Phase 02: Download and extract stage3
sudo ./install.sh 02-bootstrap
```

At this point, your disk is partitioned and stage3 is extracted to `/mnt/gentoo`.

### Step 6: Prepare for Chroot

Mount necessary filesystems:

```bash
sudo mount -t proc none /mnt/gentoo/proc
sudo mount --rbind /dev /mnt/gentoo/dev
sudo mount --rbind /sys /mnt/gentoo/sys
sudo modprobe efivarfs
```

Copy DNS configuration:

```bash
sudo cp -L /etc/resolv.conf /mnt/gentoo/etc/
```

Copy the installer into the chroot:

```bash
sudo cp -r $(pwd) /mnt/gentoo/root/gentoo-install
```

### Step 7: Enter Chroot

```bash
sudo chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) $PS1"
cd /root/gentoo-install
```

### Step 8: Run In-Chroot Phases

Set environment variables again inside chroot:

```bash
export HOSTNAME="gentoo"
export TIMEZONE="America/Chicago"
export PRIMARY_USER="henninb"
export KERNEL_METHOD="bin"
```

Run the remaining phases:

```bash
# Phase 03: Configure locale, timezone, hostname
./install.sh 03-base-config

# Phase 04: Sync Portage and apply configurations
./install.sh 04-portage

# Phase 05: Install kernel (binary or compile)
# NOTE: Binary kernel is much faster!
./install.sh 05-kernel

# Phase 06: Install GRUB bootloader
./install.sh 06-bootloader

# Phase 07: Install system packages
./install.sh 07-system-pkgs

# Phase 08: Create user and configure sudo/doas
./install.sh 08-users
```

**Or run all at once:**

```bash
./install.sh  # Runs all incomplete phases
```

### Step 9: Install Desktop Environment (Optional)

If you want the full Hyprland desktop:

```bash
# Phase 09: Install Hyprland and desktop packages
# WARNING: This takes 1-3 hours!
./install.sh 09-desktop
```

This installs ~100 packages including Hyprland, Waybar, terminal, browser, and all supporting tools.

### Step 10: Exit and Reboot

```bash
exit              # Exit chroot
sudo umount -R /mnt/gentoo
sudo reboot
```

Remove the installation media and boot into your new Gentoo system!

## Post-Installation

### First Boot

1. Log in as your user
2. Start Hyprland (if installed):
   ```bash
   Hyprland
   ```

### Configure Dotfiles

Clone and symlink your dotfiles for Hyprland, Waybar, shell, etc.

### Install Additional Software

Add packages to `config/world.txt` or `config/desktop-packages.txt` and re-run:

```bash
sudo ./install.sh 07-system-pkgs
# or
sudo ./install.sh 09-desktop
```

## Troubleshooting

### Phase Failed - How to Resume?

The installer is resumable! Simply fix the issue and re-run:

```bash
./install.sh 05-kernel  # Re-run specific failed phase
# or
./install.sh            # Continue from where you left off
```

Completed phases are automatically skipped.

### Network Issues in Chroot

If you can't reach the internet from chroot:

```bash
# Copy resolv.conf
cp -L /etc/resolv.conf /mnt/gentoo/etc/

# Verify in chroot
ping gentoo.org
```

### Kernel Doesn't Boot

If the system won't boot:

1. Boot installation media again
2. Mount your partitions:
   ```bash
   mount /dev/sda2 /mnt/gentoo
   mount /dev/sda1 /mnt/gentoo/boot/efi
   ```
3. Chroot and check GRUB:
   ```bash
   chroot /mnt/gentoo /bin/bash
   ls /boot/
   cat /boot/grub/grub.cfg
   grub-mkconfig -o /boot/grub/grub.cfg
   ```

### Slow Compilation

If compilation is very slow:

- Use `KERNEL_METHOD="bin"` for binary kernel
- Adjust `MAKEOPTS` in `config/make.conf`:
  ```bash
  MAKEOPTS="-j4"  # Number of parallel jobs (usually CPU cores + 1)
  ```

### Disk Space Issues

Check available space:

```bash
df -h /mnt/gentoo
```

If running low:
- Delete stage3 tarball: `rm /mnt/gentoo/stage3-*.tar.xz`
- Clean Portage distfiles: `emerge --depclean`

### Package Installation Failures

Some packages in `desktop-packages.txt` may fail due to:
- Missing overlays (enable GURU, etc.)
- Keyword requirements (add to `package.accept_keywords`)
- USE flag conflicts (check emerge output)

The installer will continue and report failures at the end.

## Advanced Usage

### Skip Desktop Installation

If you only want base system:

```bash
./install.sh 01-partition
./install.sh 02-bootstrap
# ... through 08-users
# Skip 09-desktop
```

### Custom Kernel Config

Place your `.config` at `config/kernel.config` and set:

```bash
export KERNEL_METHOD="genkernel"
./install.sh 05-kernel
```

### Different Stage3 Profile

```bash
export STAGE3_PROFILE="systemd"  # Minimal systemd
# or
export STAGE3_PROFILE="openrc"   # OpenRC init
```

### Manual Stage3 URL

```bash
export STAGE3_URL="https://mirror.bytemark.co.uk/gentoo/releases/amd64/autobuilds/20250101T000000Z/stage3-amd64-desktop-systemd-20250101T000000Z.tar.xz"
./install.sh 02-bootstrap
```

### Reset Installation

To start over from scratch:

```bash
./install.sh --reset  # Clears phase completion tracking
```

Then re-run phases as needed.

## What Gets Installed

### Base System (Phases 1-8)

- Partitioned disk with GPT + UEFI
- Gentoo stage3 (desktop-systemd profile)
- Configured locale, timezone, hostname
- Synced Portage tree with your custom configs
- Linux kernel (binary or compiled)
- GRUB bootloader
- Essential system packages (sudo, doas, cronie, dhcpcd, etc.)
- Primary user with sudo access

### Desktop Environment (Phase 9)

- Hyprland Wayland compositor
- Waybar status bar
- Kitty terminal
- Complete Wayland tooling (grim, slurp, swappy, wl-clipboard)
- Notification daemon (swaync/mako)
- Application launcher (wofi)
- Lock screen (swaylock, hyprlock)
- File manager (thunar)
- Networking (NetworkManager, Mullvad VPN)
- Media (mpd, pavucontrol, playerctl)
- Fonts (Nerd Fonts, emoji support)
- ~100 supporting packages

## Files and Logs

- **Installation logs**: `state/install-YYYYMMDD-HHMMSS.log`
- **Phase tracking**: `state/.completed_phases`
- **Portage configs**: `config/make.conf`, `config/package.*`
- **Package lists**: `config/world.txt`, `config/desktop-packages.txt`

## Getting Help

Check logs for detailed error messages:

```bash
tail -f state/install-*.log
```

For Gentoo-specific issues, consult:
- [Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
- [Gentoo Forums](https://forums.gentoo.org/)

## Disaster Recovery

To rebuild your system from scratch:

1. Boot installation media
2. Clone this repo (or use your backed-up copy)
3. Set `DISK` variable
4. Run `./install.sh`

All your configurations are in `config/`, so the system will be rebuilt identically (except for per-run generated files).

**Recommendation**: Keep this repo in version control and back it up!
