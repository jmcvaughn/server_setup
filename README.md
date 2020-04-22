# server_setup
Configuration scripts for my server.

Note that I have switched to Ubuntu Focal. The last commit supporting Arch Linux was [c5a79fc1564c44b02dc848609cd046b1f7d0b4b9](https://github.com/jmcvaughn/server_setup/tree/c5a79fc1564c44b02dc848609cd046b1f7d0b4b9).

## Cloning
```
$ git clone https://github.com/v0rn/server_setup.git
```

## Installation
Use the Subiquity/live installer. This doesn't appears to have problems with refreshing partition tables; the old installer seems to.

For my configuration, most working data is stored in separate ZFS filesystems. As a result, the boot disk partitioning scheme doesn't matter too much; an ESP partition and a root partition is sufficient. If a disaster occurs, the installation can be rebuilt with minimal effort.

If RAID-1 is desired for the ESP, you will need to use a v1.0 superblock (metadata at the end of the partition). The Subiquity installer doesn't allow this to be specified so for now, do the following:
- Select "Custom storage layout"
- Clear any existing partitions for your chosen disks
- Select "Make Boot Device" under one of the disks
- On the other disk, create an unformatted partition 512MiB in size
- On both disks, create an unformatted partition spanning the rest of the disk space
- Create a RAID-1 array using the large unformatted partition of your selected disks
- Select "Format" under the RAID array and create the root partition (ext4 recommended as it allows both growing and shrinking unlike XFS, and doesn't suffer from performance issues under certain workloads unlike Btrfs)

At the "SSH Setup" screen, remember to select "Install OpenSSH server".

There is no requirement to install any snaps at the "Featured Server Snaps" screen; those required are installed by the scripts in this repository.

## Post-installation setup
### Set up RAID-1 ESP
1) Backup the existing ESP contents:
```
$ sudo cp -a /boot/efi{,.bak}/
```

2) Unmount the existing ESP:
```
$ sudo umount /boot/efi/
```

3) Create the new array, substituting the last argument with your own drives:
```
$ sudo mdadm --create /dev/md1 --level 1 --raid-devices 2 --metadata 1.0 --run /dev/disk/by-id/ata-Crucial_CT275MX300SSD1*part1
```

4) Add the new array to the `mdadm` configuration:
```
$ sudo mdadm --detail --scan | grep '/dev/md1 ' | sudo tee -a /etc/mdadm/mdadm.conf
```

5) Create a new FAT32 file system on the array:
```
$ sudo mkfs.fat -F 32 -s 1 -S 4096 /dev/md1
```

6) Modify fstab to use the new RAID-1 ESP, using the same mount options as the existing ESP and remembering to comment the existing ESP entry out:
```
$ EDITOR=vim sudo -e /etc/fstab
```
To obtain the new array device path, run:
```
$ sudo mdadm --detail --scan | awk -F '=' '/\/dev\/md1 / { print "/dev/disk/by-id/md-uuid-"$NF }'
```

7) Mount the new ESP:
```
$ sudo mount /boot/efi/
```

8) Copy the contents of the ESP back over and delete the backup:
```
$ sudo mv /boot/efi{.bak/*,} && sudo rm -r /boot/efi.bak/
```

9) Create a new boot entry using `efibootmgr` for disk that was not the ESP on install:
```
$ sudo efibootmgr --create --disk /dev/sdh --part 1 --label ubuntu --loader '\EFI\ubuntu\shimx64.efi'
```

## System setup
Prior to running `setup.sh`:
- Install the ZFS utilities:
```
$ sudo apt-get update && sudo apt-get -y install zfsutils-linux
```

- Manually import and mount/create ZFS pools and datasets as required.

After running `setup.sh`, enable [Canonical Livepatch](https://ubuntu.com/livepatch).

## OpenStack
All virtualisation requirements are met by OpenStack, running on LXD. `setup.sh` configures LXD and Juju as required, while `openstack.sh` adds the model, configures its profile, and deploys the openstack.yaml bundle.

Note that glance-simplestreams-sync is used to manage Ubuntu images; these do not need to be added manually.

### Post-deployment setup
The commands in this section are examples; modify as appropriate.

#### Obtain the admin OpenStack RC file
Obtain the admin user's password:
```
$ juju run --unit keystone/0 leader-get admin_passwd
```

Obtain the OpenStack Dashboard IP address:
```
$ juju status | grep openstack-dashboard
```

Log in to the OpenStack Dashboard at http://<DASHBOARD_IP>/horizon/ using the "admin_domain" domain, the "admin" user and the password obtained above. Once logged in, download the OpenStack RC file from the top-right menu.

#### Create provider network and subnet
```
$ openstack network create --share --external --provider-network-type flat --provider-physical-network physnet1 provider
$ openstack subnet create --network provider --allocation-pool start=10.188.1.1,end=10.188.1.254 --dns-nameserver 10.188.0.1 --gateway 10.188.0.1 --subnet-range 10.188.0.0/16 provider-subnet
```

#### Create flavours
```
$ openstack flavor create --public --ram 512 --disk 1 --ephemeral 0 --vcpus 1 m1.tiny
$ openstack flavor create --public --ram 1024 --disk 20 --ephemeral 40 --vcpus 1 m1.small
$ openstack flavor create --public --ram 2048 --disk 40 --ephemeral 40 --vcpus 2 m1.medium
$ openstack flavor create --public --ram 8192 --disk 40 --ephemeral 40 --vcpus 4 m1.large
$ openstack flavor create --public --ram 16384 --disk 80 --ephemeral 40 --vcpus 8 m1.xlarge
```

#### Set up users and domains
Much like you wouldn't use the "root" user for day-to-day work on a personal machine, don't use the "admin" user and the "admin_domain" domain for your workloads.

As from the command line the following tasks at minimum require changing domain/project contexts or using IDs, these tasks are most quickly performed in the OpenStack Dashboard.

Log in to the OpenStack Dashboard as "admin" as detailed in [Obtain the admin OpenStack RC file](#obtain-the-admin-openstack-rc-file). Under the Identity tab, repeat the following tasks for each required domain:
- Create a domain, then click "Set Domain Context" to manage it
- Create users
- Create projects
- Set users as domain Admins/Members
- Assign memberships and primary projects to users
- Set project quotas

As a user:
- Import an SSH public key (per user)
- Add ingress rules for ICMP and SSH to the default security group (per project)
- Create a network and subnet, and a router to connect to the provider network (per project)
- Download the OpenStack RC file

### Juju
To use the OpenStack installation as a Juju cloud itself, the following is recommended:

- Create a new "juju" project to your preferred domain
- Create a "juju" user to the domain, defaulting to the "juju" project and being a Member of it
- Set your own user as an Admin for the project
- Create a network and subnet, and a router to connect to the provider network

There is no need to modify security groups or rules.

Then copy and modify `juju_template.yaml` as required, and create the new cloud and credential:
```
$ juju add-cloud --controller "$(hostnamectl | awk '/Static hostname:/ { for (i = 3; i <= NR; i++); print $i }')" --client openstack /tmp/juju.yaml
$ juju add-credential --controller "$(hostnamectl | awk '/Static hostname:/ { for (i = 3; i <= NR; i++); print $i }')" --client -f /tmp/juju.yaml openstack
```

Finally, set the default region and model defaults:
```
$ juju default-region openstack RegionOne
$ juju model-defaults openstack network=default use-floating-ip=true  # Replace with network created previously
```
