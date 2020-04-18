#!/bin/bash

cd "$(dirname "$0")"

# Set and load sysctl parameters
cat << 'EOF' | sudo tee /etc/sysctl.d/openstack_lxd.conf
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_instances=1048576
fs.inotify.max_user_watches=1048576
vm.max_map_count=262144
vm.swappiness=1
EOF
sudo sysctl -p /etc/sysctl.d/openstack_lxd.conf

# Create network bridge
lxc network create lxdbr188 bridge.mtu=9000 ipv4.address=10.188.0.1/16 ipv4.dhcp.ranges=10.188.0.2-10.188.0.254 ipv6.address=none

# Create openstack model
juju add-model --config apt-http-proxy=http://10.188.0.1:8000 --config default-series=bionic openstack
juju switch openstack

# Update LXD profile
cat << 'EOF' | lxc profile edit juju-openstack
config:
  boot.autostart: True
  security.nesting: True
  security.privileged: True
  linux.kernel_modules: ip_tables,ip6_tables,nbd,openvswitch
devices:
  eth0:
    name: eth0
    nictype: bridged
    parent: lxdbr188
    type: nic
  eth1:
    name: eth1
    nictype: bridged
    parent: lxdbr188
    type: nic
  kvm:
    path: /dev/kvm
    type: unix-char
  mem:
    path: /dev/mem
    type: unix-char
  root:
    path: /
    pool: default
    type: disk
EOF

juju deploy ./openstack.yaml
