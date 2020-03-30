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

## OpenStack script
All virtualisation requirements are met by OpenStack on LXD. `openstack.sh` automates the tasks detailed in the [OpenStack on LXD installation guide](https://docs.openstack.org/charm-guide/latest/openstack-on-lxd.html) up to and including "Deploy". After script completion, OpenStack will continue to install; progress can be monitored with `watch juju status`. Observe for any [actions](https://jaas.ai/docs/working-with-actions) that need to be run.

After running these actions and completing the installation, complete the setup of OpenStack by following the [Using the Cloud](https://docs.openstack.org/charm-guide/latest/openstack-on-lxd.html#using-the-cloud) section of the guide. However, note that by following the guide, the *admin_domain* domain, *admin* project and *admin* user will be used exclusively. This is poor practice. Instead, it is strongly recommended to add images, the external network, flavors and security group rules "as admin" for global availability, and create new domains, projects and users for regular use.

If taking this approach, remove the *admin* project's *provider-router* (created when running `neutron-ext-net-ksv3` as per the guide); routers will instead be created in user projects:
```
$ openstack router delete provider-router
```
