#!/bin/bash

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

hostname='jvaughnserver'
packages=(
	# Archive utilities
	unarchiver unzip xz zip  # bzip2, gzip, tar already dependencies of base

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

	# Containerisation
	docker docker-compose
	lxc

	# Other utilities
	certbot jq python znc
)


#-------------------------------------------------------------------------------
# Setup machine
#-------------------------------------------------------------------------------

cd "$(dirname "$0")"

# Import zpools
sudo zpool import -af

# Copy /etc/pacman.conf
sudo cp {setup,}/etc/pacman.conf

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

# Create mail spool file
touch /var/spool/mail/jamesvaughn
chmod 0600 /var/spool/mail/jamesvaughn

# Configure Postfix
sudo postalias /etc/postfix/aliases

# Enable and start services
sudo systemctl enable --now {docker,nfs-server,postfix,smartd,zfs-share,znc}.service {certbot,pkgfile-update}.timer

# Make key directories
mkdir "$HOME"/{.config,git}/ 2> /dev/null
