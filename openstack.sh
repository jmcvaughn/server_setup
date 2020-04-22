#!/bin/bash

cd "$(dirname "$0")"

# Create openstack model
juju add-model --config default-series=bionic openstack
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
    parent: lxdbr0
    type: nic
  eth1:
    name: eth1
    nictype: bridged
    parent: lxdbr0
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
