#!/bin/sh

archisodir="/tmp/archiso$RANDOM"

# Create directory
mkdir "$archisodir"

# Copy archiso contents to directory
cp -r /usr/share/archiso/configs/releng/* "$archisodir"

# Add console device
sed -i '/^options/ s/$/ console=ttyS0/' "$archisodir"/efiboot/loader/entries/*

# Packages
## Add repositories
cat << 'EOF' >> "$archisodir"/pacman.conf
[archzfs]
Server = http://archzfs.com/$repo/x86_64
SigLevel = Optional TrustAll
EOF
## Add packages (comments need to be on their own lines)
cat << 'EOF' >> "$archisodir"/packages.x86_64
# Generates mirrorlists
reflector
tmux
tree
zfs-linux
EOF

# Customise root file system
cat << 'EOF' >> "$archisodir"/airootfs/root/customize_airootfs.sh
echo root:archiso | chpasswd  # Set root password
systemctl enable sshd.service
EOF

# Build image
mkdir "$archisodir"/out
cd "$archisodir"
sudo ./build.sh -v
