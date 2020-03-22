#!/bin/bash

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

disks=(  # Must be by-id. First is default for booting.
	/dev/disk/by-id/ata-Crucial_CT275MX300SSD1_163313A6BB6A
	/dev/disk/by-id/ata-Crucial_CT275MX300SSD1_16371415CD66
)
ashift=14
swap=16  # Integer, in GiB. Defaults to 8 if null or undefined.
users=(jamesvaughn)
locales=(
	en_GB.UTF-8  # First is default
	en_US.UTF-8  # Do not remove, must always be included regardless of position
)
timezone='Europe/London'
keymap='uk'
mirror_country='GB'
kernel_opts='console=ttyS0 apparmor=1 security=apparmor'


#-------------------------------------------------------------------------------
# Installation
#-------------------------------------------------------------------------------

# Determine CPU vendor
cpu=$(lscpu | awk '/Model name/ {print $3}')
cpu=$(echo "${cpu%(*}" | tr '[:upper:]' '[:lower:]')

# Determine if running on UEFI system
if [ ! -d /sys/firmware/efi/efivars ]; then
	echo 'Must be run on a UEFI system, exiting.'
	exit 1
fi

# Synchronise time
timedatectl set-ntp true

# Partition disks
for disk in ${disks[@]}; do
	# 1 = ESP, 2 = swap, 3 = zproot
	sgdisk \
		-n 1:+1M:+1G -t 1:ef00 "$disk" \
		-n 2:0:+"${swap:-8}"G -t 2:8200 "$disk" \
		-n 3:0:0 -t 3:8300 "$disk"
done
sleep 1  # Allow udev to create the device files

# Format disks
## Create root zpool
test "${#disks[@]}" -gt 1 && vdev_type='mirror'
zpool create zproot -fo ashift="$ashift" \
	-O canmount=off \
	-O compression=lz4 \
	-O dnodesize=auto \
	-O mountpoint=none \
	-O normalization=formD \
	-O relatime=on \
	-O xattr=sa \
	-R /mnt \
	$vdev_type "${disks[@]/%/-part3}"  # Append "-part3" to each disk

## Set up zfs-mount-generator (ZFS-systemd integration)
### Generated in the live environment, then copied to the chroot environment
mkdir /etc/zfs/zfs-list.cache/
touch /etc/zfs/zfs-list.cache/zproot
ln -sf /usr/lib/zfs-*/zfs/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d/
systemctl start zfs-zed.service

## Create datasets
### /
zfs create -o canmount=off zproot/ROOT
zfs create -o canmount=noauto -o mountpoint=/ zproot/ROOT/default
zfs mount zproot/ROOT/default
### /home/, /root/ and user directory
zfs create -o mountpoint=/home zproot/home
zfs create -o mountpoint=/root zproot/home/root
chmod 0750 /mnt/root/
for user in ${users[@]}; do
	zfs create zproot/home/"$user"
done
### /usr/
zfs create -o canmount=off -o mountpoint=/usr zproot/usr
zfs create zproot/usr/local
### /var/
zfs create -o canmount=off -o mountpoint=/var zproot/var
zfs create -o com.sun:auto-snapshot=false zproot/var/cache
zfs create zproot/var/cache/pacman
zfs create -o canmount=off zproot/var/lib
zfs create -o canmount=off zproot/var/lib/systemd
zfs create zproot/var/lib/systemd/coredump
zfs create zproot/var/log
zfs create -o acltype=posixacl zproot/var/log/journal

# Create and mount ESP (mirrored)
mkdir /mnt/esp/
if [ "${#disks[@]}" -eq 1 ]; then  # Single
	mkfs.fat -F 32 -s 1 -S 4096 "${disks[0]/%/-part1}"
	mount "${disks[0]/%/-part1}" /mnt/esp/
else  # Mirror
	mdadm --create /dev/md0 --level 1 --raid-devices "${#disks[@]}" --metadata 1.0 "${disks[@]/%/-part1}" --run
	sleep 1  # Allow udev to create the device files
	mkfs.fat -F 32 -s 1 -S 4096 /dev/md0
	mount /dev/md0 /mnt/esp/
fi
mkdir -p /mnt/esp/env/zedenv-default/ /mnt/boot/
mount --bind /mnt/esp/env/zedenv-default/ /mnt/boot/

# Generate mirrorlist
reflector -c "$mirror_country" -f 5 --ipv4 > /etc/pacman.d/mirrorlist

# Get repository keys
## arch-zfs
pacman-key --recv-keys 403BD972F75D9D76
pacman-key --lsign-key 403BD972F75D9D76

# Install essential packages (and some realistic extras)
pacstrap /mnt/ \
	apparmor base bash-completion "$cpu"-ucode dhcpcd dosfstools efibootmgr \
	gptfdisk linux-lts linux-firmware linux-lts-headers less man-db man-pages \
	openssh reflector sudo tmux vim zfs-dkms \
	$(test "${#disks[@]}" -gt 1 && printf 'mdadm')

# Generate fstab for ESP and boot partitions
genfstab -U /mnt/ | awk '/[[:space:]]\/esp[[:space:]]+vfat/ {
	gsub("[[:space:]]+", " ")
	print
	print "/esp/env/zedenv-default /boot none "$4",bind "$5" "$6
}' >> /mnt/etc/fstab

# Create and set up swap device, add to fstab
if [ "${#disks[@]}" -eq 1 ]; then  # Single
	mkswap "${disks[0]/%/-part2}"
	echo "UUID=$(lsblk "${disks[0]/%/-part2}" --noheadings --output uuid) none swap defaults 0 0" >> /mnt/etc/fstab
else
	mdadm --create /dev/md1 --level 1 --raid-devices "${#disks[@]}" "${disks[@]/%/-part2}" --run
	mkswap /dev/md1
	# Not using UUID as it is somehow changed once booted into the installation
	echo "/dev/md1 none swap defaults 0 0" >> /mnt/etc/fstab
fi

# Set timezone and synchronise hardware clock
arch-chroot /mnt ln -s /usr/share/zoneinfo/"$timezone" /etc/localtime
arch-chroot /mnt hwclock --systohc

# Generate/configure locales and configure keymap
for locale in ${locales[@]}; do
	sed -i "s/^#$locale/$locale/" /mnt/etc/locale.gen
done
arch-chroot /mnt locale-gen
echo "LANG=${locales[0]}" > /mnt/etc/locale.conf
echo "KEYMAP=$keymap" > /mnt/etc/vconsole.conf

# ZFS setup
## Set up host ID
zgenhostid
cp /etc/hostid /mnt/etc/

## Set up zfs-mount-generator (ZFS-systemd integration)
### Copied from live environment
mkdir /mnt/etc/zfs/zfs-list.cache/
cp {,/mnt}/etc/zfs/zfs-list.cache/zproot
arch-chroot /mnt ln -s /usr/lib/zfs-*/zfs/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d/

## Setup cachefile and enable services/targets
arch-chroot /mnt zpool set cachefile=/etc/zfs/zpool.cache zproot
arch-chroot /mnt systemctl enable {zfs,zfs-import}.target {zfs-import-cache,zfs-mount,zfs-zed}.service

# Enable AppArmor, dhcpcd and SSH
arch-chroot /mnt systemctl enable {apparmor,dhcpcd@"$(ip r | awk '/default/ {print $5}')",sshd}.service

# Disable systemd journal compression
sed -i 's/^#Compress=yes$/Compress=no/' /mnt/etc/systemd/journald.conf

# Set up users
echo '%wheel ALL=(ALL) ALL' > /mnt/etc/sudoers.d/wheel
chmod 0440 /mnt/etc/sudoers.d/wheel
echo "Setting up user root..."
arch-chroot /mnt passwd
for user in ${users[@]}; do
	echo "Setting up user $user..."
	arch-chroot /mnt useradd -G wheel "$user"
	shopt -s dotglob
	cp /mnt/etc/skel/* /mnt/home/"$user"/
	shopt -u dotglob
	arch-chroot /mnt chown -R "$user:$user" /home/"$user"/
	arch-chroot /mnt chmod 0700 /home/"$user"/
	arch-chroot /mnt passwd "$user"
done

# Update mdadm configuration file
mdadm --detail --scan >> /mnt/etc/mdadm.conf

# Generate initramfs
sed -i 's/^HOOKS=.*$/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

# systemd-boot
## Install
mkdir -p /mnt/esp/EFI/systemd/ /mnt/esp/loader/entries/
cp /mnt/usr/lib/systemd/boot/efi/systemd-bootx64.efi /mnt/esp/EFI/systemd/
## Add loader
cat << EOF > /mnt/esp/loader/entries/zedenv-default.conf
title    Arch Linux
linux    /env/zedenv-default/vmlinuz-linux-lts
initrd   /env/zedenv-default/intel-ucode.img
initrd   /env/zedenv-default/initramfs-linux-lts.img
options  zfs_force=1 zfs=zproot/ROOT/default rw $kernel_opts
EOF
## Add loader.conf
echo 'default zedenv-default' > /mnt/esp/loader/loader.conf
## Add pacman update hook
mkdir /mnt/etc/pacman.d/hooks/
cat << 'EOF' > /mnt/etc/pacman.d/hooks/100-systemd-boot.hook
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi /esp/EFI/systemd/
EOF

# ZFS repository
## Add archzfs repository
cat << 'EOF' >> /mnt/etc/pacman.conf

[archzfs]
Server = http://archzfs.com/$repo/x86_64
EOF
## Add repository keys
arch-chroot /mnt pacman-key --recv-keys 403BD972F75D9D76
arch-chroot /mnt pacman-key --lsign-key 403BD972F75D9D76

# Unmount filesystems
umount /mnt/{boot,esp}/
zpool export zproot

# Add boot entries
for ((disk="${#disks[@]}"; disk>0; disk--)); do
	efibootmgr --create \
		--disk "${disks[$((disk-1))]}" \
		--part 1 \
		--label "systemd-boot (SSD $disk)" \
		--loader '\EFI\systemd\systemd-bootx64.efi'
done
