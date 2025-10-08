#!/bin/bash
set -xeuo pipefail

#check if we're root
if [[ "$UID" -ne 0 ]]; then
    echo "This script needs to be run as root!" >&2
    exit 3
fi

### Config options
target="/dev/nvme0n1"
rootmnt="/mnt"
locale="fr_CH.UTF-8"
locale_messages="en_US.UTF-8"
keymap="fr_CH"
pacman_country="CH"
timezone="Europe/Zurich"
hostname="arch"
username="christophe"
#SHA512 hash of password. To generate, run 'mkpasswd -m sha-512', don't forget to prefix any $ symbols with \ . The entry below is the hash of 'password'
user_password="\$6\$/VBa6GuBiFiBmi6Q\$yNALrCViVtDDNjyGBsDG7IbnNR0Y/Tda5Uz8ToyxXXpw86XuCVAlhXlIvzy1M8O.DWFB6TRCia0hMuAJiXOZy/"
crypt_password="password"

### Packages to pacstrap ##
pacstrappacs=(
        base
        base-devel
        linux
        linux-firmware
        sbctl
        git
        btrfs-progs
        efibootmgr
        inotify-tools
        timeshift
        vim
        networkmanager
        pipewire
        pipewire-alsa
        pipewire-pulse
        pipewire-jack
        wireplumber
        reflector
        zsh
        openssh
        man
        sudo
        )

# Partition
echo "Creating partitions..."
sgdisk -Z "$target"
sgdisk \
    --clear \
    --new=1:0:+512M --typecode=1:ef00 --change-name=1:EFISYSTEM \
    --new=2:0:+16G --typecode=2:8200 --change-name=2:cryptswap \
    --new=3:0:0 --typecode=3:8300 --change-name=3:cryptsystem \
    "$target"
# Reload partition table
sleep 2
partprobe -s "$target"
sleep 2

# Setup luks partitions
echo -n "$crypt_password" | cryptsetup luksFormat --type luks2 --batch-mode /dev/disk/by-partlabel/cryptsystem -
echo -n "$crypt_password" | cryptsetup open --batch-mode /dev/disk/by-partlabel/cryptsystem system -
# swap
cryptsetup open --batch-mode --type plain --key-file /dev/urandom /dev/disk/by-partlabel/cryptswap swap
mkswap -L swap /dev/mapper/swap
swapon -L swap

# File systems
echo "Making File Systems..."
mkfs.fat -F 32 -n EFISYSTEM /dev/disk/by-partlabel/EFISYSTEM
mkfs.btrfs -L linux -f /dev/mapper/system
# mount the root
echo "Mounting File Systems..."
mount /dev/mapper/system "$rootmnt"
# btrfs subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
mount -o subvol=@ /dev/mapper/system "$rootmnt"
# mount subvolumes
mkdir "$rootmnt"/home -p
mount -o subvol=@home /dev/mapper/system "$rootmnt"/home
# create + mount the EFI directory
mkdir "$rootmnt"/efi -p
mount /dev/disk/by-partlabel/EFISYSTEM "$rootmnt"/efi

# Update pacman mirrors and then pacstrap base install
echo "Pacstrapping..."
reflector --country $pacman_country --age 24 --protocol http,https --sort rate --save /etc/pacman.d/mirrorlist
pacstrap -K $rootmnt "${pacstrappacs[@]}" 

# Fstab
genfstab -U "$rootmnt" >> "$rootmnt"/etc/fstab

# Crypttab
echo "swap /dev/disk/by-partlabel/cryptswap /dev/urandom swap" > "$rootmnt"/etc/crypttab
echo "system /dev/disk/by-partlabel/cryptsystem none x-systemd.device-timeout=0,timeout=0,no-read-workqueue,no-write-workqueue,discard,tpm2-device=auto" > "$rootmnt"/etc/crypttab.initramfs

# UKI
sed -i -e 's/^HOOKS=(.*)/HOOKS=(base systemd keyboard autodetect modconf kms block sd-encrypt filesystems fsck)/' "$rootmnt"/etc/mkinitcpio.conf
echo "root=/dev/mapper/system rootfstype=btrfs rootflags=subvol=/@ rw loglevel=3 quiet" > "$rootmnt"/etc/kernel/cmdline
echo "root=/dev/mapper/system rootfstype=btrfs rootflags=subvol=/@ rw loglevel=3 quiet" > "$rootmnt"/etc/kernel/cmdline_fallback
cat > "$rootmnt"/etc/mkinitcpio.d/linux.preset << EOF
# mkinitcpio preset file for the 'linux' package

#ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

#default_config="/etc/mkinitcpio.conf"
#default_image="/boot/initramfs-linux.img"
default_uki="/efi/EFI/Linux/ArchLinux-linux.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"

#fallback_config="/etc/mkinitcpio.conf"
#fallback_image="/boot/initramfs-linux-fallback.img"
fallback_uki="/efi/EFI/Linux/ArchLinux-linux-fallback.efi"
fallback_options="-S autodetect --cmdline /etc/kernel/cmdline_fallback"
EOF
arch-chroot "$rootmnt" mkdir -p /efi/EFI/Linux
arch-chroot "$rootmnt" mkinitcpio -P

# Secure boot
chattr -i /sys/firmware/efi/efivars/PK*     || true
chattr -i /sys/firmware/efi/efivars/KEK*    || true
chattr -i /sys/firmware/efi/efivars/db*     || true
arch-chroot "$rootmnt" sbctl create-keys
arch-chroot "$rootmnt" sbctl enroll-keys --microsoft
arch-chroot "$rootmnt" sbctl sign --save /efi/EFI/Linux/ArchLinux-linux.efi
arch-chroot "$rootmnt" sbctl sign --save /efi/EFI/Linux/ArchLinux-linux-fallback.efi
arch-chroot "$rootmnt" efibootmgr --create --disk "$target" --part 1 --label "ArchLinux-linux-fallback" --loader 'EFI\Linux\ArchLinux-linux-fallback.efi' --unicode
arch-chroot "$rootmnt" efibootmgr --create --disk "$target" --part 1 --label "ArchLinux-linux" --loader 'EFI\Linux\ArchLinux-linux.efi' --unicode

# TPM2
# 0: System firmware executable code (so fwupd could cause TPM failures)
# 1: System configuration
# 4: Firmware boot order (so booting an external disk won’t allow unlocking with the TPM)
# 5: Boot configuration, including GPT
# 7: Secure Boot state (on/off)
# 8: Kernel command line (so editing the boot list in GRUB won’t allow unlocking with the TPM)
# 9: Kernel boot state including initrd contents and kernel itself (so system updates could cause TPM failures)
arch-chroot "$rootmnt" systemd-cryptenroll --wipe-slot tpm2 --tpm2-device=auto --tpm2-pcrs=0+1+4+5+7+8+9 /dev/disk/by-partlabel/cryptsystem

# Locale / Env
echo "Setting up environment..."
#add our locale to locale.gen
sed -i -e "/^#"$locale"/s/^#//" "$rootmnt"/etc/locale.gen
sed -i -e "/^#"$locale_messages"/s/^#//" "$rootmnt"/etc/locale.gen
#remove any existing config files that may have been pacstrapped, systemd-firstboot will then regenerate them
rm "$rootmnt"/etc/{machine-id,localtime,hostname,shadow,locale.conf} ||
systemd-firstboot --root "$rootmnt" \
	--keymap="$keymap" --locale="$locale" \
	--locale-messages="$locale_messages" --timezone="$timezone" \
	--hostname="$hostname" --setup-machine-id \
	--welcome=false
arch-chroot "$rootmnt" locale-gen

# Users
echo "Configuring users..."
#add the local user
arch-chroot "$rootmnt" useradd -G wheel -m -p "$user_password" "$username" 
#uncomment the wheel group in the sudoers file
sed -i -e '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' "$rootmnt"/etc/sudoers

# Enable the services we will need on start up
echo "Enabling services..."
systemctl --root "$rootmnt" enable systemd-timesyncd NetworkManager

# Prepare ansible code
arch-chroot "$rootmnt" sudo -u "$username" git clone --recurse-submodules https://github.com/DACC4/arch-bootstrap.git ~/arch-bootstrap

echo "-----------------------------------"
echo "- Install complete. Rebooting.... -"
echo "-----------------------------------"
sleep 10
sync
umount -R "$rootmnt"
reboot

