# Gentoo Automated Installer

A phase-based, resumable automation framework for installing and configuring Gentoo Linux on bare metal.

## Philosophy

This installer stays close to Gentoo's imperative philosophy while adding:
- **Idempotency**: Scripts can be safely re-run
- **Resumability**: Failed phases can be restarted without redoing completed work
- **Transparency**: All operations are visible shell scripts, no DSLs or abstractions
- **Validation**: State checks between phases ensure correctness
- **Declarative configuration**: Portage configs and package lists are version-controlled

## Directory Structure

```
.
├── README.md               # This file
├── INSTALL_GUIDE.md        # Detailed installation walkthrough
├── QUICKSTART_VM.md        # Quick start guide for VM testing
├── VM_TEST_PLAN.md         # Comprehensive VM testing plan
├── AUDIT.md                # Audit system documentation
├── install.sh              # Main orchestrator
├── audit.sh                # Standalone audit script
├── create-vm.sh            # Automated VM creation script
├── phases/                 # Installation phases (run in order)
│   ├── 01-partition.sh     # Disk partitioning (GPT + UEFI)
│   ├── 02-bootstrap.sh     # Stage3 auto-download and extraction
│   ├── 03-base-config.sh   # Locale, timezone, hostname
│   ├── 04-portage.sh       # Portage sync and configuration
│   ├── 05-kernel.sh        # Kernel installation (binary or genkernel)
│   ├── 06-bootloader.sh    # GRUB installation
│   ├── 07-system-pkgs.sh   # System packages from world.txt
│   ├── 08-users.sh         # User creation and sudo/doas
│   ├── 09-desktop.sh       # Hyprland desktop (optional, 1-3hr)
│   └── 10-audit.sh         # Comprehensive audit (optional)
├── lib/
│   ├── common.sh           # Logging, error handling, utilities
│   ├── validators.sh       # State validation functions
│   ├── preflight.sh        # Pre-installation checks
│   └── audit.sh            # Post-installation audit system
├── config/                 # Portage and system configuration
│   ├── make.conf           # Your USE flags, MAKEOPTS, etc.
│   ├── package.accept_keywords
│   ├── package.unmask
│   ├── package.mask
│   ├── package.use/
│   ├── world.txt           # System packages list
│   └── desktop-packages.txt # Desktop packages (~100 pkgs)
└── state/
    ├── .completed_phases   # Tracks completed phases
    └── install-*.log       # Detailed installation logs
```

## Quick Start

**For complete step-by-step instructions, see [INSTALL_GUIDE.md](INSTALL_GUIDE.md)**

### TL;DR Installation

```bash
# 1. Boot installation media with network
# 2. Clone repo
git clone https://github.com/henninb/gentoo-install.git
cd gentoo-install

# 3. Run pre-chroot phases (interactive prompts with smart defaults!)
sudo ./install.sh 01-partition  # Prompts for disk selection
sudo ./install.sh 02-bootstrap

# 4. Prepare and enter chroot
sudo mount -t proc none /mnt/gentoo/proc
sudo mount --rbind /dev /mnt/gentoo/dev
sudo mount --rbind /sys /mnt/gentoo/sys
sudo cp -L /etc/resolv.conf /mnt/gentoo/etc/
sudo cp -r $(pwd) /mnt/gentoo/root/gentoo-install
sudo chroot /mnt/gentoo /bin/bash
source /etc/profile
cd /root/gentoo-install

# 5. Run in-chroot phases
./install.sh  # Runs all remaining phases with defaults:
              # HOSTNAME="gentoo", PRIMARY_USER="henninb", KERNEL_METHOD="bin"

# 6. Reboot
exit && sudo reboot
```

**Defaults:**
- Hostname: `gentoo`
- User: `henninb`
- Kernel: Binary (fast)
- Disk: Interactive selection with confirmation

## Usage

### Run All Phases

```bash
./install.sh
```

This runs all incomplete phases in order (including final audit).

### Run Installation Audit

Verify installation completeness and correctness:

```bash
# Standalone audit
./audit.sh

# Or as part of installation
./install.sh 10-audit

# Or via flag
./install.sh --audit
```

See [AUDIT.md](AUDIT.md) for detailed audit documentation.

### Run Specific Phase

```bash
./install.sh 05-kernel
```

### List Phases and Status

```bash
./install.sh --list
```

Output:
```
Gentoo Installation Phases:

  [✓] 01-partition
  [✓] 02-bootstrap
  [✓] 03-base-config
  [ ] 04-portage
  [ ] 05-kernel
  [ ] 06-bootloader
  [ ] 07-system-pkgs
  [ ] 08-users
```

### Reset Installation State

If you need to start over:

```bash
./install.sh --reset
```

This clears the completion tracker but doesn't modify the system.

## Configuration

### Portage Configuration

All Portage configs are in `config/`:

- **make.conf**: USE flags, MAKEOPTS, compiler flags
- **package.accept_keywords**: Unmask testing packages
- **package.unmask**: Unmask specific versions
- **package.mask**: Mask specific versions
- **package.use/**: Per-package USE flags
- **world.txt**: Declarative package list

These are automatically applied during phase 04.

### Package Management

Edit `config/world.txt` to add packages:

```
# System utilities
app-editors/vim
app-shells/zsh
dev-vcs/git

# Development tools
dev-lang/rust-bin
dev-lang/go
```

Phase 07 will install all listed packages.

### Kernel Configuration

Set `KERNEL_METHOD` environment variable:

- **bin** (default): Uses `gentoo-kernel-bin` (fast, pre-compiled)
- **genkernel**: Builds kernel from source with genkernel
- **manual**: Expects you to build kernel yourself

For custom kernel config, place `.config` at `config/kernel.config`.

## Customization

### Adding New Phases

1. Create `phases/XX-myfeature.sh`
2. Follow existing phase structure (source libs, validate, etc.)
3. Add phase name to `PHASES` array in `install.sh`

### Modifying Existing Phases

Each phase is a standalone script. Edit directly and re-run.

### Adding Validation

Add validation functions to `lib/validators.sh` and call them at the end of phases.

## Post-Installation

After the base system is installed, you may want to:

1. **Install Hyprland and Desktop**:
   ```bash
   ~/scripts/hyprland-install.sh
   ```

2. **Configure Dotfiles**: Clone and symlink your dotfiles

3. **Set up Development Environment**: Install IDEs, languages, tools

4. **Configure Services**: Enable NetworkManager, configure firewall, etc.

## Disaster Recovery

To rebuild your system:

1. Boot installation media
2. Clone this repo
3. Run `./install.sh` (with appropriate DISK variable set)
4. All configs are applied automatically from `config/`
5. Packages are installed from `world.txt`
6. System is bootable in ~2 hours (mostly compile time)

## Troubleshooting

### Phase Failed - How to Resume?

1. Fix the issue (network, disk space, etc.)
2. Re-run the failed phase: `./install.sh 05-kernel`
3. Phases are idempotent and can be safely re-run

### Logs

All output is logged to `state/install-YYYYMMDD-HHMMSS.log`

### Network Issues in Chroot

Ensure `/etc/resolv.conf` is copied into chroot:
```bash
cp -L /etc/resolv.conf /mnt/gentoo/etc/
```

### Validation Failures

Each phase validates its work. If validation fails:
1. Check the error message
2. Manually verify system state
3. Fix the issue
4. Re-run the phase

### Kernel Doesn't Boot

- Verify `/boot/grub/grub.cfg` has correct kernel path
- Check if initramfs is required for your hardware
- Consider switching to `KERNEL_METHOD=bin` for binary kernel

## Advanced Usage

### Running Phases in Parallel

Phases are sequential by design. Don't run them in parallel.

### Testing in VM

This installer is designed to be tested in a VM before bare metal deployment.

**Quick VM Setup (virt-manager/KVM):**

```bash
# Auto-download Arch Linux ISO and create test VM (easiest!)
./create-vm.sh --download

# Or use existing ISO
./create-vm.sh --iso ~/Downloads/archlinux-YYYY.MM.DD-x86_64.iso

# Start the VM
virsh start gentoo-test

# Connect and test
virt-viewer gentoo-test
```

**Manual VM Setup:**

Works great with virt-manager, VirtualBox, or QEMU:

```bash
export DISK="/dev/vda"  # or /dev/sda depending on VM config
./install.sh
```

**Comprehensive Testing:**

- **Quick Start**: See [QUICKSTART_VM.md](QUICKSTART_VM.md) for fastest path to testing
- **Full Test Plan**: See [VM_TEST_PLAN.md](VM_TEST_PLAN.md) for:
  - Automated VM creation with `create-vm.sh`
  - 10 comprehensive test scenarios
  - Snapshot strategies for rollback testing
  - Validation of all installation phases
  - Recovery and resume testing

### Dry Run

There's no built-in dry-run, but you can:
1. Read through the phase scripts (they're transparent!)
2. Test in a VM first
3. Use `set -x` in scripts to see every command

## Comparison to Alternatives

| Tool | Pros | Cons |
|------|------|------|
| **This Framework** | Transparent, Gentoo-native, resumable | Manual initial setup |
| **Ansible** | Mature, declarative | Python dependency, abstraction overhead |
| **NixOS** | Fully declarative, atomic | Not Gentoo, steep learning curve |
| **Terraform** | ❌ Wrong tool for local system config | ❌ Requires API providers |

## Contributing

This is a personal automation framework. Fork and adapt to your needs!

## License

MIT - Use however you want.

## Credits

Based on manual Gentoo installation experience documented in `~/documents/gentoo-systemd-gpt-install.md`.
