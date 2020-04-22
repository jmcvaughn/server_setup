#!/bin/bash

packages=(
	aria2
	bridge-utils  # LXD
	certbot
	docker
	docker-compose
	ipmitool
	jq
	neovim
	python3-openstackclient
	smartmontools
	source-highlight
	squid-deb-proxy  # Juju
	tree
	zfsutils-linux
	zip
	znc
	zsh
	zsh-autosuggestions
	zsh-syntax-highlighting
	#exfat-utils genisoimage mailutils nfs-kernel-server unar zsh-completions
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
sudo snap install juju --classic --edge
sudo snap refresh lxd --channel=4.0/stable

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

# Configure kernel and security limits for LXD
## https://github.com/lxc/lxd/blob/master/doc/production-setup.md
cat << 'EOF' | sudo tee /etc/security/limits.d/lxd.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF
cat << 'EOF' | sudo tee /etc/sysctl.d/lxd.conf
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=1048576
vm.max_map_count=262144
kernel.dmesg_restrict=1
net.core.bpf_jit_limit=3000000000
kernel.keys.maxbytes=200000
vm.swappiness=1
EOF
sudo sysctl -p /etc/sysctl.d/lxd.conf

# Initialise LXD
sudo zfs create zpssd/lxd 2> /dev/null && sleep 5
lxd init --auto --network-address 0.0.0.0 --network-port 8443 --storage-backend zfs --storage-pool zpssd/lxd

# Configure network; Juju doesn't support IPv6
lxc network set lxdbr0 ipv4.address=10.188.0.1/16 ipv4.dhcp.ranges=10.188.0.2-10.188.0.254 ipv6.address=none

# Bootstrap Juju controller
juju bootstrap --config apt-http-proxy=http://10.188.0.1:8000 localhost "$(hostnamectl | awk '/Static hostname:/ { for (i = 3; i <= NR; i++); print $i }')"

sudo systemctl enable --now {docker,znc}.service

# For convenience, e.g. when copying Neovim configuration from another machine
mkdir "$HOME"/.config/ 2> /dev/null
