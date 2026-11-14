#!/bin/bash
# Wrapper around install.sh / secure-install.sh: asks which install to do and
# for the passwords, then runs the chosen script with them.
set -euo pipefail

if [[ "$UID" -ne 0 ]]; then
    echo "This script needs to be run as root!" >&2
    exit 3
fi

cd "$(dirname "$(realpath "$0")")"

ask_password() { # ask_password <prompt> -> sets $REPLY_PASSWORD
    local p1 p2
    while true; do
        read -rsp "$1: " p1; echo
        read -rsp "$1 (confirm): " p2; echo
        if [[ -z "$p1" ]]; then
            echo "Password cannot be empty." >&2
        elif [[ "$p1" != "$p2" ]]; then
            echo "Passwords do not match." >&2
        else
            REPLY_PASSWORD="$p1"
            return
        fi
    done
}

echo "Install type:"
echo "  1) Secure     (LUKS2 + TPM2, Secure Boot, UKI)  -> secure-install.sh"
echo "  2) Non-secure (plain btrfs, GRUB)               -> install.sh"
while true; do
    read -rp "Choice [1/2]: " choice
    case "$choice" in
        1) script=./secure-install.sh; secure=1; break ;;
        2) script=./install.sh; secure=0; break ;;
        *) echo "Please answer 1 or 2." >&2 ;;
    esac
done

ask_password "User password"
USER_PASSWORD_HASH="$(printf '%s' "$REPLY_PASSWORD" | openssl passwd -6 -stdin)"
export USER_PASSWORD_HASH

if [[ "$secure" -eq 1 ]]; then
    ask_password "Disk encryption (FDE) password"
    CRYPT_PASSWORD="$REPLY_PASSWORD"
    export CRYPT_PASSWORD
fi
unset REPLY_PASSWORD

target="$(grep -m1 '^target=' "$script" | cut -d'"' -f2)"
echo
echo "About to run $script. This will WIPE $target."
read -rp "Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }

exec "$script"
