#!/usr/bin/bash

if [ $UID != 0 ]; then
    echo "$0 must be run as root"
    exit 1
fi

archisodir="/tmp/archiso$RANDOM"

bootentrydir="$archisodir/efiboot/loader/entries/"

bootentrycd="$bootentrydir/archiso-x86_64-cd.conf"
bootentryusb="$bootentrydir/archiso-x86_64-usb.conf"

# Create directory
mkdir $archisodir

# Copy archiso contents to directory
cp -r /usr/share/archiso/configs/releng/* $archisodir

# Add packages
echo "termite-terminfo" >> $archisodir/packages.x86_64

# Add console device
for i in {$bootentrycd,$bootentryusb}; do
    sed -i '/^options/ s/$/ console=ttyS0/' $i
done

# Set root password
echo 'echo "root:archiso" | chpasswd' \
  >> $archisodir/airootfs/root/customize_airootfs.sh

# Enable sshd.socket
echo 'systemctl enable sshd.socket' \
  >> $archisodir/airootfs/root/customize_airootfs.sh

# Copy mirrorlist to /root
cp /etc/pacman.d/mirrorlist $archisodir/airootfs/root/

# Build image
mkdir $archisodir/out
cd $archisodir
./build.sh -v

echo "Arch installation ISO created in $archisodir/out/"
