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

### Packages to pacstrap ##
pacstrappacs=(
        base
        base-devel
        linux
        linux-firmware
        git
        btrfs-progs
        grub
        efibootmgr
        grub-btrfs
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
    -n1:0:+512M  -t1:ef00 -c1:EFISYSTEM \
    -N2          -t2:8304 -c2:linux \
    "$target"
# Reload partition table
sleep 2
partprobe -s "$target"
sleep 2

# File systems
echo "Making File Systems..."
mkfs.fat -F 32 -n EFISYSTEM /dev/disk/by-partlabel/EFISYSTEM
mkfs.btrfs -L linux -f /dev/disk/by-partlabel/linux
# mount the root
echo "Mounting File Systems..."
mount /dev/disk/by-partlabel/linux "$rootmnt"
# btrfs subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
mount -o subvol=@ /dev/disk/by-partlabel/linux "$rootmnt"
# mount subvolumes
mkdir "$rootmnt"/home -p
mount -o subvol=@home /dev/disk/by-partlabel/linux "$rootmnt"/home
# create + mount the EFI directory
mkdir "$rootmnt"/efi -p
mount /dev/disk/by-partlabel/EFISYSTEM "$rootmnt"/efi

# Update pacman mirrors and then pacstrap base install
echo "Pacstrapping..."
reflector --country $pacman_country --age 24 --protocol http,https --sort rate --save /etc/pacman.d/mirrorlist
pacstrap -K $rootmnt "${pacstrappacs[@]}" 

# Fstab
genfstab -U "$rootmnt" >> "$rootmnt"/etc/fstab

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

# Grub
echo "Configuring grub..."
arch-chroot "$rootmnt" grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
arch-chroot "$rootmnt" grub-mkconfig -o /boot/grub/grub.cfg

#enable the services we will need on start up
echo "Enabling services..."
systemctl --root "$rootmnt" enable systemd-timesyncd NetworkManager

echo "-----------------------------------"
echo "- Install complete. Rebooting.... -"
echo "-----------------------------------"
sleep 10
sync
umount -R "$rootmnt"
reboot

