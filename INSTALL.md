# Base Arch Linux installation
The following instructions detail the process for a base installation of Arch
Linux prior to running ansible-arch. It should be suitable for most systems
without significant deviation. Familiarity with a typical installation process
as per the [ArchWiki Installation
Guide](https://wiki.archlinux.org/index.php/Installation_guide) is assumed. Your
particular setup may require additional steps (e.g. manual network configuration
or setup of Internet connection sharing on another system).

If you are already running Arch Linux, you can run the `create_arch_iso.sh`
script as root to create an installation image with the following changes:
- `sshd.socket` enabled to allow SSH access
- root user password set to `archiso`
- `termite-terminfo` installed to allow SSH via Termite terminal emulator to
  work correctly
- Current mirrorlist copied to `/root/mirrorlist` (see [Generate
  mirrorlist](#generate-mirrorlist))

## Optional: load keymap
If accessing the machine locally, set the relevant keymap, e.g. `loadkeys uk`
for a British keyboard. See the [ArchWiki page on console
keymaps](https://wiki.archlinux.org/index.php/Keyboard_configuration_in_console#Temporary_configuration)
for further details.

## Update the system clock
```
# timedatectl set-ntp true
```

## Disk setup
It is presumed that the system will be running in UEFI mode (and thus the
installation disk formatted with GPT rather than MBR) with a Btrfs file system
on top of either a raw partition or a dm-crypt LUKS device for full disk
encryption. The bootloader configuration steps are provided for either.

If dual booting, it is down to you to determine the correct partitioning scheme.
As Windows will typically be the other installed OS, see the [ArchWiki page on
dual booting with
Windows](https://wiki.archlinux.org/index.php/Dual_boot_with_Windows) for
further guidance. On an unrelated note, in such configurations the [Windows
clock will need to be configured to use UTC instead of
localtime](https://wiki.archlinux.org/index.php/Dual_boot_with_Windows#Time_standard).

The target devices and partitions may be different due to the above as well as
the order in which udev detects devices. Adjust accordingly while following the
instructions.

### Partitioning
Using parted or gdisk, create the following partitions:
- sda1: EFI System Partition (ESP), 512MiB, type `ef00` (EFI System)
- sda2: remaining space, type `8300` (Linux filesystem)

If mirroring is to be used, repeat these steps on the second drive.

### Optional: LUKS setup
Skip this step if you aren't using encryption.

Prior to creating the dm-crypt device, it is recommended you run `cryptsetup
benchmark`. Encryption may impede performance without any practical security
benefits, particularly for CPUs without AES instruction set extensions (AES-NI
on Intel). See the ArchWiki pages on [cryptsetup
usage](https://wiki.archlinux.org/index.php/Dm-crypt/Device_encryption#Cryptsetup_usage)
and [LUKS
options](https://wiki.archlinux.org/index.php/Dm-crypt/Device_encryption#Encryption_options_for_LUKS_mode)
for further details.

Setup the dm-crypt LUKS device in a similar manner to the following:
```
# cryptsetup --verbose --hash sha512 --cipher aes-xts-plain64 --use-random --key-size 512 --iter-time 5000 luksFormat /dev/sda2
```

Then open the dm-crypt LUKS device (where `archcrypt1` is the desired device mapper
name, represented by device file `/dev/mapper/archcrypt1` once unlocked):
```
# cryptsetup open --type luks /dev/sda2 archcrypt1
```

Repeat the above steps for any mirrored configurations, changing the device and
mapped name as appropriate (e.g. `archcrypt2`).

### Formatting
#### Boot partition
Format the ESP as FAT32. You can set the correct number of sectors per cluster
and logical sector size using switches `-s` and `-S` respectively; omit them if
you are unsure. For an SSD, the following is recommended and supported by FAT32
without issues:
```
# mkfs.fat -F 32 -s 1 -S 4096 /dev/sda1
```

Repeat on the second disk's ESP if mirroring. The mirroring is performed by
a script run by a custom pacman hook; see the bootsync hook and script in the
`boot` role.

#### Root file system (Btrfs)
Ideally, file system sector size should match the block/sector/page size of the
underlying block device. This is a complex subject, so to summarise:
- If you don't specify a file system sector size, the `mkfs` utilities will use
  the logical block size as specified in
  `/sys/block/sdX/queue/logical_block_size`. This may be suboptimal; refer to
  the physical block size.
- You can verify the *reported* physical block size by reading
  `/sys/block/sdX/queue/physical_block_size`. However, some disks (particularly
  SSDs) will not report this accurately. You may need to refer to the
  specifications of the disk or flash memory (for SSDs) to find the correct
  value.
- Most modern SSD controllers will have fairly decent emulation capabilities for
  smaller block sizes. If page/sector/block size of the device cannot be
  determined, a sector size of 4096 for all disk types is often an *acceptable*
  default.
 
If you're not using encryption, specify the partition instead of the mapped
device. Create the file system as follows (specifying the raw partition if
encryption isn't being used):
```
# mkfs.btrfs --sectorsize 4096 --force /dev/mapper/archcrypt1
```

The same applies for mirrors:
```
# mkfs.btrfs --data raid1 --metadata raid1 --sectorsize 4096 --force /dev/mapper/archcrypt1 /dev/mapper/archcrypt2
```

Create the subvolumes (specifying only one of the devices in the file system):
```
# mount -t btrfs -o compress=lzo /dev/mapper/archcrypt1 /mnt/ && for i in root var home; do btrfs subvolume create /mnt/$i/; done && umount /mnt/
```

### Mounting partitions
Mount the root subvolume:
```
# mount -t btrfs -o compress=lzo,subvol=root /dev/mapper/archcrypt1 /mnt/
```

Create the mount points:
```
# mkdir /mnt/{boot,var,home}/
```

Create the backup ESP mount point if required:
```
# mkdir /mnt/boot.bak/
```

Mount the partitions:
```
# mount /dev/sda1 /mnt/boot/; for i in var home; do mount -t btrfs -o compress=lzo,subvol=$i /dev/mapper/archcrypt1 /mnt/$i/ done
```

Mount the backup ESP if required:
```
# mount /dev/sdb1 /mnt/boot.bak/
```

### Other performance options
#### I/O schedulers
The default I/O scheduler, CFQ (Completely Fair Queueing) is recommended for
most use cases using the stock kernel, regardless of whether an SSD or
mechanical disk is in use. Its performance is generally competitive with the
`noop` and `deadline` schedulers on SSDs, while offering better performance for
mechanical disks and of course requiring no prior configuration.

This guide won't cover changing schedulers in any more detail unless the
configurations for my own systems are changed accordingly. However, it is
recommended that you **do not** set the I/O scheduler using the `elevator`
kernel parameter in the bootloader entry as this will be set globally for all
block devices. Instead, refer to the [Debian Wiki page on SSD
optimisation](https://wiki.debian.org/SSDOptimization#Low-Latency_IO-Scheduler)
to set the scheduler for individual drives or groups of drives using either
sysfsutils or udev rules. These I/O schedulers do not apply to NVMe SSDs and ZFS
file systems; the former uses blk-mq [(see the Thomas-Krenn Wiki for
details](https://www.thomas-krenn.com/en/wiki/Linux_Multi-Queue_Block_IO_Queueing_Mechanism_(blk-mq)),
while the latter uses its own scheduler, setting the kernel I/O scheduler for
zpool devices to `noop` (this can be verified by reading the value stored in
`/sys/block/sdX/queue/scheduler` for the member device).

#### Mount options
The default mount options used by Btrfs are recommended for most use cases.
Btrfs will automatically detect and set the correct options if being run on an
SSD.

There is little performance benefit specifying `noatime`. This will, however
introduce issues with applications that require access times (e.g. some mail
clients).

## Generate mirrorlist
If you used the `create_arch_iso.sh` script to create an installation image,
your mirrorlist will have been copied to `/root/mirrorlist`. You can copy this
to `/etc/pacman.d/mirrorlist`.

Otherwise, see the [ArchWiki page on
mirrors](https://wiki.archlinux.org/index.php/Mirrors) for instructions on
generating a mirrorlist.

## Install base operating system
```
# pacstrap /mnt/ base intel-ucode dosfstools btrfs-progs termite-terminfo openssh ansible
```

Of course, omit `intel-ucode` for non-Intel systems. For AMD systems, microcode
updates are provided by `linux-firmware`, installed as part of the default
`base` package group.

## Generate fstab
```
# genfstab -pU /mnt/ >> /mnt/etc/fstab
```

For mirrored setups, add the option `noauto` to the `/boot.bak` entry.

## Set up systemd-boot
### Install
```
# bootctl install --path /mnt/boot/
```

### Configure
It is recommended you configure systemd-boot with the following options in
`/mnt/boot/loader/loader.conf`:
```
default archlinux
editor 0
```
Add `timeout 3` if you are dual booting. systemd-boot will pick up the Windows
Boot Loader.

### Create the boot entry
Create the following boot entry in `/mnt/boot/loader/entries/archlinux.conf`:
```
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options DEVICES rw rootflags=subvol=root
```

#### Specifying devices
UUIDs for this section can be found by running `lsblk -o name,uuid`. This
section substitutes `DEVICES` in the `options` line.

If encryption is used, specify the UUID of the raw partition holding the
dm-crypt LUKS device and the desired mapped name, substituting `...`. Repeat
this for each drive:
```
rd.luks.name=UUID_OF_archcrypt1_RAW_PARTITION=archcrypt1
```

For all configurations, at the end of the `DEVICES` substitution specify the
UUID of the device on which the root file system resides. For encrypted setups
this will be the UUID of the unlocked dm-crypt LUKS device itself, otherwise
this will be the UUID of the partition itself:
```
root=UUID=UUID_OF_archcrypt1 
```

#### System-specific options
Append the following to the options line if applicable:
- For serial access: `console=ttyS0`
- For Nvidia systems: `nomodeset` (see [Blacklist
  nouveau](#for-nvidia-systems-blacklist-nouveau))
- For MacBooks: `acpi_osi=!Darwin`

## For Nvidia systems: blacklist nouveau
If specified, ansible-arch installs the proprietary Nvidia driver---my system
runs Maxwell cards, for which features and performance is currently poor for the
`nouveau` driver. `nouveau` causes `lspci`, and thus Ansible, to get
stuck while gathering facts. Run the following to blacklist `nouveau`:
```
# echo blacklist nouveau > /mnt/etc/modprobe.d/blacklist.conf
```

## Set the keymap for the installation
This will most likely match the keymap specified in [Load
keymap](#optional-load-keymap). See the [Arch Wiki page on console
keymaps](https://wiki.archlinux.org/index.php/Keyboard_configuration_in_console#Persistent_configuration)
for further details. Run the following to permanently set the keymap for the
installation:
```
# echo KEYMAP=uk > /mnt/etc/vconsole.conf
```

## Set mkinitcpio hooks
Comment out the `HOOKS` line in `/mnt/etc/mkinitcpio.conf` and add the follwing
`HOOKS` line for unencrypted installations:
```
HOOKS="base systemd autodetect modconf sd-vconsole keyboard block filesystems fsck"
```

Or the following `HOOKS` line for encrypted installations:
```
HOOKS="base systemd autodetect modconf sd-vconsole keyboard block filesystems fsck"
```

## Configuration while chrooted into the installation
Use the `arch-chroot` utility to chroot into your new installation:
```
# arch-chroot /mnt/
```

### Set root password, create user and set password
```
# passwd; useradd -mG wheel USER && passwd USER
```

### Generate initramfs
```
# mkinitcpio --preset linux
```

### Optional: enable services
You may wish to enable `sshd.socket` or `dhcpcd` for an Ethernet connection
(without using a network manager). Modify the following as appropriate:
```
# systemctl enable sshd.socket dhcpcd@eno1
```

## Optional: configure EFI boot entries
You may wish to configure these in the BIOS/UEFI interface on your system.
However, if you are running a system that doesn't offer this (e.g. Apple
hardware), or if running a mirrored setup and wish to add your ESP mirror as
a boot entry, you can modify some of the following commands to achieve your
desired configuration:
### List entries
```
# efibootmgr --verbose
```
### Create a new entry for systemd-boot
```
# efibootmgr --create --disk /dev/sdh --part 1 --label 'systemd-boot (SSD1)' --loader '\EFI\systemd\systemd-bootx64.efi'
```
### Delete
```
# efibootmgr --bootnum <BOOTNUM> --delete-bootnum
```
### Delete duplicates
```
# efibootmgr --remove-dups
```
### Boot order
```
# efibootmgr --bootorder BOOTNUM,BOOTNUM
```

## Reboot
Reboot into the installation to finish, and run ansible-arch as specified in the
[usage instructions](README.md#usage).
