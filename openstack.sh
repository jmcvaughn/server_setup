#!/bin/sh

# Services
sudo systemctl enable snapd.apparmor.service snapd.socket
## Restart to ensure rules are loaded correctly
sudo systemctl restart {apparmor,snapd.apparmor}.service

sudo ln -s /var/lib/snapd/snap/ /snap 2> /dev/null  # For classic snaps

# LXD
sudo snap install lxd --channel=3.0/stable && hash -r
sudo zfs create zpssd/lxd 2> /dev/null
lxd init --auto --network-address 0.0.0.0 --network-port 8443 --storage-backend zfs --storage-pool zpssd/lxd

# LXD tweaks
lxc network set lxdbr0 ipv6.address none  # Juju doesn't support IPv6
lxc profile device set default eth0 mtu 9000  # For OpenStack
## LXC assigns a hugely scattered range of addresses, so we limit the pool
lxdbr0_ipv4=$(lxc network get lxdbr0 ipv4.address)
lxc network set lxdbr0 ipv4.dhcp.ranges "${lxdbr0_ipv4%1/24}"2-"${lxdbr0_ipv4%1/24}"50

# Clone the OpenStack on LXD repository
git clone https://github.com/openstack-charmers/openstack-on-lxd "$HOME"/git/openstack-on-lxd/

# Juju
sudo snap install juju --classic && hash -r
juju bootstrap --config default-series=bionic --no-gui localhost "$(hostnamectl | awk '/Static hostname:/ { for (i = 3; i <= NR; i++); print $i }')"-lxd
cat "$HOME"/git/openstack-on-lxd/lxd-profile.yaml | lxc profile edit juju-default

# sysctl tweaks for OpenStack on LXD
cat << 'EOF' | sudo tee /etc/sysctl.d/openstack_lxd.conf
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=1048576
vm.max_map_count=262144
vm.swappiness=1
EOF
sudo sysctl -p /etc/sysctl.d/openstack_lxd.conf

# Deploy OpenStack on LXD
juju deploy "$HOME"/git/openstack-on-lxd/bundle-bionic-train.yaml

# Create OpenStack client venv
python3 -m venv "$HOME"/venv/openstackclient/
source "$HOME"/venv/openstackclient/bin/activate
pip install python-openstackclient python-neutronclient
