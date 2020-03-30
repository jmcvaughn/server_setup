#!/bin/bash

# Based on https://docs.openstack.org/charm-guide/latest/openstack-on-lxd.html

#-------------------------------------------------------------------------------
# Host setup
#-------------------------------------------------------------------------------

sudo snap install juju --classic

sudo apt-get update && sudo apt-get -y install zfsutils-linux squid-deb-proxy \
	bridge-utils python3-novaclient python3-keystoneclient python3-glanceclient \
	python3-neutronclient python3-openstackclient

git clone https://github.com/openstack-charmers/openstack-on-lxd "$HOME"/git/openstack-on-lxd/


#-------------------------------------------------------------------------------
# LXD
#-------------------------------------------------------------------------------

cat << 'EOF' | sudo tee /etc/sysctl.d/openstack_lxd.conf
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=1048576
vm.max_map_count=262144
vm.swappiness=1
EOF
sudo sysctl -p /etc/sysctl.d/openstack_lxd.conf

# Use LXD 3.0 LTS
sudo snap refresh lxd --channel=3.0/stable

sudo zfs create zpssd/lxd 2> /dev/null
lxd init --auto --network-address 0.0.0.0 --network-port 8443 --storage-backend zfs --storage-pool zpssd/lxd

lxc profile device set default eth0 mtu 9000  # For OpenStack

# Additional tweaks
## Disable IPv6 as Juju doesn't support it
lxc network set lxdbr0 ipv6.address none
## Limit the DHCP range as LXD makes scattered assignments
lxdbr0_ipv4=$(lxc network get lxdbr0 ipv4.address)
lxc network set lxdbr0 ipv4.dhcp.ranges "${lxdbr0_ipv4%1/24}"2-"${lxdbr0_ipv4%1/24}"50


#-------------------------------------------------------------------------------
# Juju
#-------------------------------------------------------------------------------

# Bootstrap the Juju Controller
## Uses name $HOSTNAME-lxd
juju bootstrap --config default-series=bionic --config apt-http-proxy=http://${lxdbr0_ipv4%/24}:8000 --no-gui localhost "$(hostnamectl | awk '/Static hostname:/ { for (i = 3; i <= NR; i++); print $i }')"-lxd

# Juju Profile Update
cat "$HOME"/git/openstack-on-lxd/lxd-profile.yaml | lxc profile edit juju-default


#-------------------------------------------------------------------------------
# OpenStack
#-------------------------------------------------------------------------------

# Deploy
juju deploy "$HOME"/git/openstack-on-lxd/bundle-bionic-train.yaml
