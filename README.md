# Personal Arch linux installation guide and bootstrap
The main inspiration and source for this guide can be found [here](https://gist.github.com/mjkstra/96ce7a5689d753e7a6bdd92cdc169bae)

# Table of contents

- [Introduction](#introduction)
- [Preliminary Steps](#preliminary-steps)
- [Main installation](#main-installation)
  - [Disk partitioning](#disk-partitioning)
  - [Disk formatting](#disk-formatting)
  - [Disk mounting](#disk-mounting)
  - [Packages installation](#packages-installation)
  - [Fstab](#fstab)
  - [Context switch to our new system](#context-switch-to-our-new-system)
  - [Set up the time zone](#set-up-the-time-zone)
  - [Set up the language and tty keyboard map](#set-up-the-language-and-tty-keyboard-map)
  - [Hostname and Host configuration](#hostname-and-host-configuration)
  - [Root and users](#root-and-users)
  - [Grub configuration](#grub-configuration)
  - [Unmount everything and reboot](#unmount-everything-and-reboot)
  - [Automatic snapshot boot entries update](#automatic-snapshot-boot-entries-update)
  - [Virtualbox support](#virtualbox-support)
  - [Aur helper and additional packages installation](#aur-helper-and-additional-packages-installation)
  - [Finalization](#finalization)
- [Video drivers](#video-drivers)
  - [Amd](#amd)
    - [32 Bit support](#32-bit-support)
  - [Nvidia](#nvidia)
  - [Intel](#intel)
- [Setting up a graphical environment](#setting-up-a-graphical-environment)
  - [Option 1: KDE Plasma](#option-1-kde-plasma)
  - [Option 2: Hyprland \[WIP\]](#option-2-hyprland-wip)
- [Adding a display manager](#adding-a-display-manager)
- [Gaming](#gaming)
  - [Gaming clients](#gaming-clients)
  - [Windows compatibility layers](#windows-compatibility-layers)
  - [Generic optimizations](#generic-optimizations)
  - [Overclocking and monitoring](#overclocking-and-monitoring)
- [Additional notes](#additional-notes)
- [Things to add](#things-to-add)

# Introduction

The goal of this guide is to help new users set up a modern and minimal installation of **Arch Linux** with **BTRFS** on an **UEFI system**. I'll start from the basic terminal installation and then set up **video drivers and a desktop environment**. 

Then using ansible, we'll setup the system to the 

### Note that:

- I **won't** prepare the system for **secure boot** because the procedure of custom key enrollment in the BIOS is dangerous and [can lead to a bricked system](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Creating_and_enrolling_keys). If you are wondering why not using the default OEM keys in the BIOS, it's because they will make secure boot useless by being most likely [not enough secure](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Implementing_Secure_Boot).

- I **won't** encrypt the system because I don't need it and because encryption always adds a little bit of overhead in the boot phase leading to a **slower to varying degrees** start\-up, depending on your configuration. However it may be important for you so if you really wanna go this way I recommend reading [the wiki page in this regards](https://wiki.archlinux.org/title/Dm-crypt) and **must** perform the documented steps **IMMEDIATELY AFTER** [disk partitioning](#disk-partitioning). Also note that you must set the type of partition to a LUKS partition instead of a standard Linux partition when partitioning with `fdisk`.

- I'll **skip** the Arch ISO installation media preparation.

- I'll use a **wired** connection, so no wireless configuration steps will be shown. If you want to connect to wifi, you can either launch `wifi-menu` from the terminal which is a **TGUI** or use [`iwctl`](https://wiki.archlinux.org/title/Iwd#iwctl).

<br>

# Preliminary steps  

First set up your keyboard layout  

```sh
# List all the available keyboard maps and filter them through grep, in this case i am looking for an Swiss French keyboard, which usually starts with "fr_CH", for english filter with "en"
ls /usr/share/kbd/keymaps/**/*.map.gz | grep fr_CH

# If you prefer you can scroll the whole list like this
ls /usr/share/kbd/keymaps/**/*.map.gz | less

# Or like this
localectl list-keymaps

# Now get the name without the path and the extension ( localectl returns just the name ) and load the layout. In my case it is simply "fr_CH"
loadkeys fr_CH
```

<br>

Check that we are in UEFI mode  

```sh
# If this command prints 64 or 32 then you are in UEFI
cat /sys/firmware/efi/fw_platform_size
```

<br>

Check the internet connection  

```sh
ping -c 5 archlinux.org
```

<br>

Check the system clock

```sh
# Check if ntp is active and if the time is right
timedatectl

# In case it's not active you can do
timedatectl set-ntp true

# Or this
systemctl enable systemd-timesyncd.service
```

<br>

# Main installation

## Disk partitioning

I will make 2 partitions:  

| Number | Type | Size |
| --- | --- | --- |
| 1 | EFI | 512 Mb |
| 2 | Linux Filesystem | 99.5Gb \(all of the remaining space \) |  

<br>

```sh
# Check the drive name. Mine is /dev/nvme0n1
# If you have an hdd is something like sdax
fdisk -l

# Now you can either go and partition your disk with fdisk and follow the steps below,
# or if you want to do things yourself and make it easier, use cfdisk ( an fdisk TUI wrapper ) which is
# much more user friendly. A reddit user suggested me this and it's indeed very intuitive to use.
# If you choose cfdisk you will have to invoke it the same way as I did with fdisk below, but
# you don't need to follow my commands blindly as with fdisk below, just navigate the UI with the arrows
# and press enter to get inside menus, remember to write changes before quitting.

# Invoke fdisk to partition
fdisk /dev/nvme0n1

# Now press the following commands, when i write ENTER press enter
g
ENTER
n
ENTER
ENTER
+512M
ENTER
t
ENTER
1
ENTER
n
ENTER
ENTER
ENTER # If you don't want to use all the space then select the size by writing +XG ( eg: to make a 10GB partition +10G )
p
ENTER # Now check if you got the partitions right

# If so write the changes
w
ENTER

# If not you can quit without saving and redo from the beginning
q
ENTER
```

<br>

## Disk formatting  

For the file system I've chosen [**BTRFS**](https://wiki.archlinux.org/title/Btrfs) which has evolved quite a lot in the recent years. It is most known for its **Copy on Write** feature which enables it to make system snapshots in a blink of a an eye and to save a lot of disk space, which can be even saved to a greater extent by enabling built\-in **compression**. Also it lets the user create **subvolumes** which can be individually snapshotted.

```sh
# Find the efi partition with fdisk -l or lsblk. For me it's /dev/nvme0n1p1 and format it.
mkfs.fat -F 32 /dev/nvme0n1p1

# Find the root partition. For me it's /dev/nvme0n1p2 and format it. I will use BTRFS.
mkfs.btrfs /dev/nvme0n1p2

# Mount the root fs to make it accessible
mount /dev/nvme0n1p2 /mnt
```

<br>

## Disk mounting

I will lay down the subvolumes on a **flat** layout, which is overall superior in my opinion and less constrained than a **nested** one. What's the difference ? If you're interested [this section of the old sysadmin guide](https://archive.kernel.org/oldwiki/btrfs.wiki.kernel.org/index.php/SysadminGuide.html#Layout) explains it.

```sh
# Create the subvolume, in my case I choose to only make a subvolume for /. Subvolumes are identified by prepending @
btrfs subvolume create /mnt/@

# Unmount the root fs
umount /mnt

# Mount the root subvolume.
mount -o subvol=@ /dev/nvme0n1p2 /mnt
```

<br>

Now we have to mount the efi partition. In general there are 2 main mountpoints to use: `/efi` or `/boot` but in this configuration i am **forced** to use `/efi`, because by choosing `/boot` we could experience a **system crash** when trying to restore `@` _\( the root subvolume \)_ to a previous state after kernel updates. This happens because `/boot` files such as the kernel won't reside on `@` but on the efi partition and hence they can't be saved when snapshotting `@`. Also this choice grants separation of concerns and also is good if one wants to encrypt `/boot`, since you can't encrypt efi files. Learn more [here](https://wiki.archlinux.org/title/EFI_system_partition#Typical_mount_points)

```sh
mkdir -p /mnt/efi
mount /dev/nvme0n1p1 /mnt/efi
```

<br>

## Packages installation  

```sh
# This will install some packages to "bootstrap" methaphorically our system. Feel free to add the ones you want
# "base, linux, linux-firmware" are needed. If you want a more stable kernel, then swap linux with linux-lts
# "base-devel" base development packages
# "git" to install the git vcs
# "btrfs-progs" are user-space utilities for file system management ( needed to harness the potential of btrfs )
# "grub" the bootloader
# "efibootmgr" needed to install grub
# "grub-btrfs" adds btrfs support for the grub bootloader and enables the user to directly boot from snapshots
# "inotify-tools" used by grub btrfsd deamon to automatically spot new snapshots and update grub entries
# "timeshift" a GUI app to easily create,plan and restore snapshots using BTRFS capabilities
# "amd-ucode" microcode updates for the cpu. If you have an intel one use "intel-ucode"
# "vim" my goto editor, if unfamiliar use nano
# "networkmanager" to manage Internet connections both wired and wireless ( it also has an applet package network-manager-applet )
# "pipewire pipewire-alsa pipewire-pulse pipewire-jack" for the new audio framework replacing pulse and jack. 
# "wireplumber" the pipewire session manager.
# "reflector" to manage mirrors for pacman
# "zsh" my favourite shell
# "openssh" to use ssh and manage keys
# "man" for manual pages
# "sudo" to run commands as other users
pacstrap -K /mnt base base-devel linux linux-firmware git btrfs-progs grub efibootmgr grub-btrfs inotify-tools timeshift vim networkmanager pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber reflector zsh openssh man sudo
```

<br>

## Fstab  

```sh
# Fetch the disk mounting points as they are now ( we mounted everything before ) and generate instructions to let the system know how to mount the various disks automatically
genfstab -U /mnt >> /mnt/etc/fstab

# Check if fstab is fine ( it is if you've faithfully followed the previous steps )
cat /mnt/etc/fstab
```

<br>

## Context switch to our new system  

```sh
# To access our new system we chroot into it
arch-chroot /mnt
```

<br>

## Set up the time zone

```sh
# In our new system we have to set up the local time zone, find your one in /usr/share/zoneinfo mine is /usr/share/zoneinfo/Europe/Zurich and create a symbolic link to /etc/localtime
ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime

# Now sync the system time to the hardware clock
hwclock --systohc
```

<br>

## Set up the language and tty keyboard map

Edit `/etc/locale.gen` and uncomment the entries for your locales. Each entry represent a language and its formats for time, date, currency and other country related settings. By uncommenting we will mark the entry to be generated when the generate command will be issued, but note that it won't still be active. In my case I will uncomment _\( ie: remove the # \)_ `en_US.UTF-8 UTF-8` and `fr_CH.UTF-8 UTF-8` because I use English as a display language and Swiss French for date, time and other formats.  

```sh
# To edit I will use vim, feel free to use nano instead.
vim /etc/locale.gen

# Now issue the generation of the locales
locale-gen
```

<br>

Since the locale is generated but still not active, we will create the configuration file `/etc/locale.conf` and set the locale to the desired one, by setting the `LANG` variable accordingly. In my case I'll write `LANG=fr_CH.UTF-8` to apply Italian settings to everything and then override only the display language to English by setting \( on a new line \) `LC_MESSAGES=en_US.UTF-8`. _\( if you want formats and language to stay the same **DON'T** set `LC_MESSAGES`  \)_. More on this [here](https://wiki.archlinux.org/title/Locale#Variables)

```sh
touch /etc/locale.conf
vim /etc/locale.conf
```

<br>

Now to make the current keyboard layout permanent for tty sessions , create `/etc/vconsole.conf` and write `KEYMAP=your_key_map` substituting the keymap with the one previously set [here](#preliminary-steps). In my case `KEYMAP=fr_CH`

```sh
vim /etc/vconsole.conf
```

<br>

## Hostname and Host configuration

```sh
# Create /etc/hostname then choose and write the name of your pc in the first line. In my case I'll use Arch
touch /etc/hostname
vim /etc/hostname

# Create the /etc/hosts file. This is very important because it will resolve the listed hostnames locally and not over Internet DNS.
touch /etc/hosts
```

Write the following ip, hostname pairs inside /etc/hosts, replacing `Arch` with **YOUR** hostname:

```
127.0.0.1 localhost
::1 localhost
127.0.1.1 Arch
```

```sh
# Edit the file with the information above
vim /etc/hosts
```

<br>

## Root and users  

```sh
# Add a new user, in my case cc4.
# -m creates the home dir automatically
# -G adds the user to an initial list of groups, in this case wheel, the administration group.
useradd -mG wheel cc4
passwd cc4

# The command below is a one line command that will open the /etc/sudoers file with your favourite editor.
# You can choose a different editor than vim by changing the EDITOR variable
# Once opened, you have to look for a line which says something like "Uncomment to let members of group wheel execute any action"
# and uncomment exactly the line BELOW it, by removing the #. This will grant superuser priviledges to your user.
# Why are we issuing this command instead of a simple vim /etc/sudoers ? 
# Because visudo does more than opening the editor, for example it locks the file from being edited simultaneously and
# runs syntax checks to avoid committing an unreadable file.
EDITOR=vim visudo
```

<br>

## Grub configuration  

Now I'll [deploy grub](https://wiki.archlinux.org/title/GRUB#Installation)  

```sh
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB  
```

<br>

Generate the grub configuration ( it will include the microcode installed with pacstrap earlier )  

```sh
grub-mkconfig -o /boot/grub/grub.cfg
```

<br>

## Unmount everything and reboot 

```sh
# Enable newtork manager before rebooting otherwise, you won't be able to connect
systemctl enable NetworkManager

# Exit from chroot
exit

# Unmount everything to check if the drive is busy
umount -R /mnt

# Reboot the system and unplug the installation media
reboot

# Now you'll be presented at the terminal. Log in with your user account, for me its "cc4".

# Enable and start the time synchronization service
sudo timedatectl set-ntp true
```

<br>

## Boostrap

```sh
git clone --recurse-submodules https://github.com/DACC4/arch-bootstrap.git && cd arch-bootstrap && chmod +x bootrstrap.sh && ./bootstrap.sh
```

<br>

## Finalization

```sh
# To complete the main/basic installation reboot the system
reboot
```

After these steps you **should** be able to boot on your newly installed Arch Linux, if so congrats !  

<br>

# Video drivers

In order to have the smoothest experience on a graphical environment, **Gaming included**, we first need to install video drivers. To help you choose which one you want or need, read [this section](https://wiki.archlinux.org/title/Xorg#Driver_installation) of the arch wiki.  

<br>

## Amd  

For this guide I'll install the [**AMDGPU** driver](https://wiki.archlinux.org/title/AMDGPU) which is the open source one and the recommended, but be aware that this works starting from the **GCN 3** architecture, which means that cards **before** RX 400 series are not supported. _\( I have an RX 5700 XT \)_  

```sh

# What are we installing ?
# mesa: DRI driver for 3D acceleration.
# xf86-video-amdgpu: DDX driver for 2D acceleration in Xorg. I won't install this, because I prefer the default kernel modesetting driver.
# vulkan-radeon: vulkan support.
# libva-mesa-driver: VA-API h/w video decoding support.
# mesa-vdpau: VDPAU h/w accelerated video decoding support.

sudo pacman -S mesa vulkan-radeon libva-mesa-driver mesa-vdpau
```

### 32 Bit support

If you want to add **32-bit** support, we need to enable the `multilib` repository on pacman: edit `/etc/pacman.conf` and uncomment the `[multilib]` section _\( ie: remove the hashtag from each line of the section. Should be 2 lines \)_. Now we can install the additional packages.

```sh
# Refresh and upgrade the system
yay

# Install 32bit support for mesa, vulkan, VA-API and VDPAU
sudo pacman -S lib32-mesa lib32-vulkan-radeon lib32-libva-mesa-driver lib32-mesa-vdpau
```

<br>

## Nvidia  

In summary if you have an Nvidia card you have 2 options:  

1. [**NVIDIA** proprietary driver](https://wiki.archlinux.org/title/NVIDIA)
2. [**Nouveau** open source driver](https://wiki.archlinux.org/title/Nouveau)

The recommended is the proprietary one, however I won't explain further because I don't have an Nvidia card and the process for such cards is tricky unlike for AMD or Intel cards. Moreover for reason said before, I can't even test it.

<br>

## Intel

Installation looks almost identical to the AMD one, but every time a package contains the `radeon` word substitute it with `intel`. However this does not stand for [h/w accelerated decoding](https://wiki.archlinux.org/title/Hardware_video_acceleration), and to be fair I would recommend reading [the wiki](https://wiki.archlinux.org/title/Intel_graphics#Installation) before doing anything.

<br>

# Gaming

Gaming on linux has become a very fluid experience, so I'll give some tips on how to setup your arch distro for gaming.  
Before going further I'll assume that you have installed the video drivers, also make sure to install with pacman, if you haven't done it already: `lib32-mesa`, `lib32-vulkan-radeon` and additionally `lib32-pipewire` \( Note that the `multilib` repository must be enabled, [here](#32-bit-support) I've explained how to do it ).

Let's break down what is needed to game:  

1. **Gaming client** ( eg: Steam, Lutris, Bottles, etc..)
2. **Windows compatibility layers** ( eg: Proton, Wine, DXVK, VKD3D )

Optionally we can have:  

1. **Generic optimization** ( eg: gamemode )
2. **Overclocking and monitoring software** ( eg: CoreCtrl, Mangohud )
3. **Custom kernels**

<br>

## Gaming clients  

I'll install **Steam** and to access games from other launchers I'll use **Bottles**, which should be installed through **flatpak**.

```sh
# Install steam and flatpak
sudo pacman -S steam flatpak

# Install bottles through flatpak
flatpak install flathub com.usebottles.bottles
```

<br>

## Windows compatibility layers

Proton is the compatibility layer developed by Valve, which includes **DXVK**( DirectX 9-10-11 to Vulkan), **VKD3D** ( DirectX 12 to Vulkan ) and a custom version of **Wine**. It is embedded in Steam and can be enabled for **non** native games direclty in Steam: `Steam > Settings > Compatibility > Enable Steam Play for all other titles`. A custom version of proton, **Proton GE** exists and can be used as an alternative if something is broken or doesn't perform as expected. Can be either [downloaded manually](https://github.com/GloriousEggroll/proton-ge-custom#installation) or through yay as below.  

```sh
# Installation through yay
yay -S proton-ge-custom-bin
```

<br>

## Generic optimizations

We can use gamemode to gain extra performance. To enable it read [here](https://github.com/FeralInteractive/gamemode#requesting-gamemode)

```sh
# Install gamemode
sudo pacman -S gamemode
```

<br>
