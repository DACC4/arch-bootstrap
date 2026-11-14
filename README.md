# arch-bootstrap

Automated installation of my Arch Linux computers (UEFI, btrfs, GNOME).

Installation happens in two stages:

1. **Base system**: a script run from the Arch live ISO partitions the disk and installs Arch.
2. **Configuration**: an Ansible playbook installs and configures everything else.

Inspired by [this guide](https://gist.github.com/mjkstra/96ce7a5689d753e7a6bdd92cdc169bae).

## 1. Base system

Boot the Arch ISO, connect to the network, then fetch this repo. Edit the config variables at the top of `install.sh` / `secure-install.sh` if needed (disk, locale, keymap, timezone, hostname, username), then run `setup.sh`. It asks whether to do a secure or non-secure install, then asks for the user password (and the disk encryption password for a secure install).

| Script              | Result                                                                                  |
| ------------------- | --------------------------------------------------------------------------------------- |
| `install.sh`        | btrfs root, GRUB, Timeshift                                                             |
| `secure-install.sh` | LUKS2 encrypted root unlocked by TPM2, encrypted swap, Secure Boot (sbctl) and a signed UKI |

```sh
pacman -Sy git
git clone https://github.com/DACC4/arch-bootstrap.git
cd arch-bootstrap
./setup.sh
```

> **Warning:** the scripts wipe the target disk (`/dev/nvme0n1` by default) without asking. The install scripts have a default password (`password`) that is only used if you run them directly instead of through `setup.sh`.

For `secure-install.sh`, put the firmware in Secure Boot **setup mode** first so the keys can be enrolled.

The machine reboots when done.

## 2. Configuration

Log in as your user and run:

```sh
cd ~/arch-bootstrap   # cloned automatically by secure-install.sh, otherwise clone it
./bootstrap.sh
```

`bootstrap.sh` installs `uv` and `yay`, asks which roles to apply (a `whiptail` checklist; your choice is saved in `ansible/enabled_roles.yaml` and preselected next time), sets up Ansible, then runs `ansible/localhost.yaml`. Skip the prompt with `ROLES=gnome,git,gaze ./bootstrap.sh`. Gaze is off by default.

The playbook applies these roles: base packages, NVIDIA drivers, GNOME settings, Gaze (face unlock), zsh, SSH key, Bluetooth, DisplayLink, git, Docker, apps and browsers. To add a role, list it in `ansible/localhost.yaml` (with its `when` condition) and in the checklist in `bootstrap.sh`.

### NVIDIA

The `nvidia` role detects an NVIDIA GPU with `lspci` and does nothing if there is none. Otherwise it installs `nvidia-open` and friends, sets `NVreg_PreserveVideoMemoryAllocations=1` in modprobe.d and enables `nvidia-suspend`, `nvidia-hibernate` and `nvidia-resume`. On hybrid laptops it also installs `nvidia-prime` and enables `nvidia-powerd`. Reboot afterwards. Note that `secure-install.sh` uses random-key swap, which cannot be used to resume from hibernation.

### Gaze (face unlock)

The `gaze` role installs Gaze and its GNOME extension, enables `gazed`, turns on GNOME keyring unlock and auto-detects the IR camera (override with `gaze_ir_camera`). The RGB camera stays on the package default (`primary`). Enrollment is TPM-bound and manual, so after the playbook run:

```sh
sudo gaze add-face
sudo gaze keyring   # enroll the GNOME keyring password
gaze doctor
```

## Development

```sh
uv sync
uv run pre-commit run --all-files   # yamllint + ansible-lint + syntax check
```
