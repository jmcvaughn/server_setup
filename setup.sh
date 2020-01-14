#!/bin/bash

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

hostname='jvaughnserver'
packages=(
  # Archive utilities
  unarchiver unzip xz zip  # bzip2, gzip, tar already dependencies of base
  cpio  # Required by virt-install for --initrd-inject

  # Base utilities
  archiso htop ipmitool lsof
  ## Network diagnostic tools
  bind-tools mtr tcpdump

  # Build utilities
  base-devel git

  # Disk health/SMART
  smartmontools

  # Download utilities
  aria2 curl

  # File sharing
  nfs-utils

  # Filesystem/partitioning utilities
  cdrtools exfat-utils

  # Mail
  postfix s-nail

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
sudo pacman -Sy --noconfirm --needed "${packages[@]}" --overwrite '/etc/netctl/examples/*'

# Set shell to Zsh
test ! "$(awk -F ':' "/$USER/ {print \$7}" /etc/passwd)" = '/usr/bin/zsh' && chsh -s /usr/bin/zsh

# Set hostname
sudo hostnamectl set-hostname "$hostname"

# Configure pkgfile
systemctl --quiet is-enabled pkgfile-update.timer || sudo pkgfile --update

# Copy configuration file tree
sudo cp -r --dereference setup/. /

# Create mail spool file
touch /var/spool/mail/jamesvaughn
chmod 0600 /var/spool/mail/jamesvaughn

# Configure Postfix
sudo postalias /etc/postfix/aliases

# Configure Open vSwitch
sudo systemctl disable --now dhcpcd@eno1.service
sudo systemctl enable --now ovs-vswitchd.service
sudo ovs-vsctl add-br br0
sudo ovs-vsctl add-port br0 eno1
for profile in $(netctl list | grep br0 | cut -c 3-); do
  sudo netctl enable "$profile"
  sudo netctl start "$profile"
done

# Configure virtualisation
sudo usermod -aG libvirt jamesvaughn
sudo systemctl enable --now {libvirtd,libvirt-guests}.service 
if ! sudo virsh net-list --all | grep -q br0; then
  sudo virsh net-define br0.xml
  sudo virsh net-autostart br0
  sudo virsh net-start br0
fi

# Enable and start other miscellaneous services
## iptables: using default configuration, for forwarding
sudo systemctl enable --now {dnsmasq,docker,iptables,nfs-server,postfix,smartd,zfs-share}.service pkgfile-update.timer

# Make key directories
mkdir "$HOME"/{.config,git}/ 2> /dev/null
