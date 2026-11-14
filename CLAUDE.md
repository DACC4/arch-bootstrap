# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal Arch Linux setup in two stages:

1. **Base install** — `install.sh` (plain, GRUB) or `secure-install.sh` (LUKS2 + TPM2 unlock, sbctl Secure Boot, signed UKI booted via efibootmgr, swap on random-key plain dm-crypt; also clones this repo into the new user's home for stage 2). Normally launched through `setup.sh`, a wrapper that prompts for secure vs non-secure, the user password (hashed with `openssl passwd -6`) and the FDE passphrase, and passes them via the `USER_PASSWORD_HASH` / `CRYPT_PASSWORD` env vars (the scripts fall back to a default `password` if unset). Run as root from the Arch live ISO; they wipe `target` (hardcoded `/dev/nvme0n1`), partition with sgdisk, create btrfs subvolumes `@` and `@home`, pacstrap, configure locale/users/bootloader, then reboot. Machine-specific config (disk, locale `fr_CH`, timezone, username, password hash/crypt password) lives in variables at the top of each script. These scripts are destructive — never run them.
2. **Post-install configuration** — `bootstrap.sh` installs `uv` and `yay`, shows a whiptail checklist of roles (or reads `ROLES=a,b`; writes the gitignored `ansible/enabled_roles.yaml`), runs `uv sync`, installs Ansible Galaxy collections (`kewlfft.aur` for AUR packages), then runs `ansible/localhost.yaml` against localhost.

`README.md` is a short usage overview of the two stages (not a manual install guide); keep it consistent with script and role changes.

## Commands

All tooling is managed with `uv` (Python ≥3.12, see `pyproject.toml`). Ansible commands must run from `ansible/` (that's where `ansible.cfg` and `roles_path=roles` live):

```sh
uv sync
cd ansible && uv run ansible-galaxy install -r requirements.yaml
cd ansible && uv run ansible-playbook localhost.yaml            # apply to this machine (uses sudo/become)
uv run ansible-playbook --syntax-check ansible/localhost.yaml   # from repo root, as pre-commit does
uv run pre-commit run --all-files                               # yamllint --strict, ansible-lint, syntax-check, whitespace
uv run python3 -m ansiblelint -c .ansible-lint                  # lint only
```

There is no test suite; validation is lint + syntax check.

## Ansible architecture

- `ansible/localhost.yaml` is the single playbook: `become: true`, connection local, and a fixed ordered list of roles (`base_packages`, `nvidia`, `gnome`, `gaze`, `zsh`, `ssh_keygen`, `bluetooth`, `displaylink`, `git`, `docker`, `apps`, `browsers`), each guarded by `when: "'<role>' in enabled_roles"`. `enabled_roles` defaults in the playbook (gaze excluded) and is overridden by `bootstrap.sh` via `-e @enabled_roles.yaml`. New roles must be added to the playbook (with the `when`) and to `ROLE_CATALOG` in `bootstrap.sh`.
- Because the playbook runs as root, AUR installs use `kewlfft.aur.aur` with `become_user: "{{ aur_user }}"` (`aur_user` = `$USER`, defined in the playbook vars). Official packages use `community.general.pacman`.
- `gnome` role keeps dconf settings as data in `roles/gnome/defaults/main.yaml` (`gnome_dconf_settings`, values are GVariant strings, so quoting like `"'Adwaita'"` is intentional).
- `git` role templates `~/.gitconfig` from `roles/git/templates/.gitconfig.j2`.
- Lint config: `.ansible-lint` skips `yaml`, `meta-no-info`, `ignore-errors`, `package-latest`; yamllint runs in `--strict` mode via `.yamllint`.

## Gotchas

- `ansible/roles/displaylink/` uses a directory named `task/` (not `tasks/`), so Ansible will not load it as written. Rename to `tasks/` if working on that role.
- `ansible/roles/apps/tasks/main.yaml` has inconsistent indentation in the AUR package list (the entries after `cork-rs-bin`); check YAML validity when editing.
- `library = ./library/ansible-aur` in `ansible.cfg` points at a path that doesn't exist in the repo; the AUR module actually comes from the `kewlfft.aur` collection.
