#!/bin/bash

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

hostname='jvaughnserver'
packages=(
  # Archive utilities
  unarchiver unzip xz zip  # bzip2, gzip, tar already dependencies of base

  # Base utilities
  archiso htop ipmitool lm_sensors lsof
  ## Network diagnostic tools
  bind-tools mtr

  # Build utilities
  base-devel git

  # Disk health/SMART
  smartmontools
  postfix  # To send messages

  # Download utilities
  aria2 curl

  # File sharing
  nfs-utils

  # Filesystem/partitioning utilities
  cdrtools exfat-utils

  # Networking
  netctl

  # pacman
  pacman-contrib pkgfile

  # Shell utilities
  tree tmux
  ## Zsh
  zsh zsh-autosuggestions zsh-completions zsh-history-substring-search
  zsh-syntax-highlighting

  # Text editors/pager utilities
  neovim
  source-highlight  # For syntax highlighting in less

  # Virtualisation/containerisation
  docker
  ## libvirt and its optional dependencies
  libvirt bridge-utils dnsmasq ebtables openbsd-netcat qemu-headless
  dmidecode  # Required to suppress errors
  ### To create virtual machines
  vagrant virt-install
  ### Open vSwitch
  openvswitch

  # Other utilities
  jq
)


#-------------------------------------------------------------------------------
# Setup machine
#-------------------------------------------------------------------------------

cd "$(dirname "$0")"

# Import zpools
sudo zpool import -af

# Install packages
sudo pacman -Rsn --noconfirm vim 2> /dev/null
sudo pacman -Sy --noconfirm --needed "${packages[@]}"

# Set shell to Zsh
test ! "$(awk -F ':' "/$USER/ {print \$7}" /etc/passwd)" = '/usr/bin/zsh' && chsh -s /usr/bin/zsh

# Set hostname
sudo hostnamectl set-hostname "$hostname"

# Configure pkgfile
systemctl --quiet is-enabled pkgfile-update.timer || sudo pkgfile --update

# Copy configuration file tree
sudo cp -r --dereference setup/. /

# Configure Postfix
sudo postalias /etc/postfix/aliases

# Configure Open vSwitch
sudo systemctl disable --now dhcpcd@eno1.service
sudo systemctl enable --now ovs-vswitchd.service
sudo ovs-vsctl add-br br0
sudo ovs-vsctl add-port br0 eno1
sudo netctl enable br0
sudo netctl start br0

# Configure virtualisation
sudo usermod -aG libvirt jamesvaughn
sudo systemctl enable --now {libvirtd,libvirt-guests}.service 
if ! sudo virsh net-list --all | grep -q br0; then
  sudo virsh net-define br0.xml
  sudo virsh net-autostart br0
  sudo virsh net-start br0
fi

# Enable and start other miscellaneous services
sudo systemctl enable --now {docker,nfs-server,postfix,smartd,zfs-share}.service pkgfile-update.timer

# Make key directories
mkdir "$HOME"/{.config,git}/ 2> /dev/null
