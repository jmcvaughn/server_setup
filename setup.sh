#!/bin/bash

packages=(
	aria2 certbot docker docker-compose ipmitool jq neovim smartmontools
	source-highlight tree zfsutils-linux znc zsh zsh-autosuggestions
	zsh-syntax-highlighting
	#exfat-utils genisoimage mailutils nfs-kernel-server unar zip zsh-completions
	#zsh-history-substring-search
)

# Set timezone
sudo timedatectl set-timezone Europe/London

# Install packages
sudo apt-get update && sudo apt-get -y install ${packages[@]}
sudo snap install canonical-livepatch

# Set shell to Zsh
if [ "$(awk -F ':' "/$USER/ { print \$7 }" /etc/passwd)" != '/bin/zsh' ]; then
	chsh -s /bin/zsh
fi

sudo systemctl enable --now {docker,znc}.service

# For convenience, e.g. when copying Neovim configuration from another machine
mkdir "$HOME"/.config/ 2> /dev/null
