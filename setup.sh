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

# Enable console output
echo 'GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX console=ttyS0"' | sudo tee /etc/default/grub.d/console.cfg
sudo update-grub

# Install packages
sudo apt-get update && sudo apt-get -y install ${packages[@]}
sudo snap install canonical-livepatch

# OpenSSH server: Set 'PasswordAuthentication no' in
# /etc/ssh/sshd_config.d/PasswordAuthentication.conf. The installer adds this to
# /etc/ssh/sshd_config when importing keys, which is undesirable.
sudo apt-get -y purge openssh-server
sudo apt-get -y install openssh-server
echo 'PasswordAuthentication no' | sudo tee /etc/ssh/sshd_config.d/PasswordAuthentication.conf
sudo systemctl restart ssh.service

# Set shell to Zsh
if [ "$(awk -F ':' "/$USER/ { print \$7 }" /etc/passwd)" != '/bin/zsh' ]; then
	chsh -s /bin/zsh
fi

sudo systemctl enable --now {docker,znc}.service

# For convenience, e.g. when copying Neovim configuration from another machine
mkdir "$HOME"/.config/ 2> /dev/null
