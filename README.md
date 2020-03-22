# server_setup
Configuration scripts for my server. Contains a highly assumptive Arch on ZFS root script.

## Cloning
```
$ git clone https://github.com/v0rn/server_setup.git
```

## Pre-installation
### Clear old configuration
`install.sh` makes no attempt to clean chosen disks for use, nor does it attempt to perform any validation.

To remove old EFI boot entries:
```
# efibootmgr -Bb C  # Would remove Boot000C
```

To destroy an old RAID array:
```
# mdadm --stop md0
# mdadm --zero-superblock /dev/sdg1
```

To then wipe any remaining filesystem or partition table signatures:
```
# wipefs -a /dev/sdg
```

### Configure `install.sh`
Modify the `Configuration` section of the script to match your requirements.

## Installation
Run `install.sh`. If run with multiple drives specified, the script will create an mdadm RAID-1 ESP and mirrored ZFS root. For all installations, the following dataset structure will be created:
```
$ zfs list zproot -ro name,canmount,mountpoint
NAME                             CANMOUNT  MOUNTPOINT
zproot                                off  none
zproot/ROOT                           off  none
zproot/ROOT/default                noauto  /
zproot/home                            on  /home
zproot/home/jamesvaughn                on  /home/jamesvaughn
zproot/home/root                       on  /root
zproot/usr                            off  /usr
zproot/usr/local                       on  /usr/local
zproot/var                            off  /var
zproot/var/cache                       on  /var/cache
zproot/var/cache/pacman                on  /var/cache/pacman
zproot/var/lib                        off  /var/lib
zproot/var/lib/systemd                off  /var/lib/systemd
zproot/var/lib/systemd/coredump        on  /var/lib/systemd/coredump
zproot/var/log                         on  /var/log
zproot/var/log/journal                 on  /var/log/journal
```

The following boot partition configuration will be created:
```
$ cat /etc/fstab
# Static information about the filesystems.
# See fstab(5) for details.

# <file system> <dir> <type> <options> <dump> <pass>
UUID=<UUID> /esp vfat rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro 0 2
/esp/env/zedenv-default /boot none rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro,bind 0 2
```

systemd-boot is used. While this scheme is compatible with [zedenv](https://github.com/johnramsden/zedenv), ZFS currently doesn't allow the `bootfs` property to be set on pools that don't adhere to its feature restrictions for GRUB. This means that for now, zedenv cannot be used in this configuration. A pull request is open to remove these restrictions (https://github.com/openzfs/zfs/pull/8627); once merged, zedenv can be used.

On completion, all installed partitions will be unmounted and the ZFS pool will be exported. For an unknown reason, `zproot/home` will not be mounted on first boot. Reboot the system immediately on first boot and the dataset will proceed to mount.

## System setup
Prior to running `setup.sh`, migrate any data between pools as required.

The setup script will import any other existing ZFS pools. For my system, important working data (Docker containers, virtual machines) is stored on an external ZFS pool, and will theoretically start back up when this script is first run. The script will copy the file structure in the `setup/` directory, install packages, perform any required configuration steps and enable and start required services.

## OpenStack script
All virtualisation requirements are now met by OpenStack on LXD. `openstack.sh` performs the work up to and including installing OpenStack, but leaves the configuration of OpenStack to the user.

Prior to running `openstack.sh`:
- [Install Snap from the AUR](https://aur.archlinux.org/packages/snapd/). As automating the installation of AUR packages is a potential security risk, this step is not automated.
- Add the lxd system group and add the existing user to it, then log back in for the new group membership to take effect: `sudo groupadd --system lxd && sudo usermod -aG lxd $USER`

`openstack.sh` will:
- Enable and (re)start the required Snap and AppArmor services
- Install the LXD and Juju snaps
- Initialise LXD with a ZFS backing store
- Bootstrap a Juju controller under the name "HOSTNAME-lxd"
- Configure LXC networking and profiles for Juju and OpenStack on LXD
- Add some sysctl configuration for OpenStack on LXD
- Create a Python venv at ~/venv/openstackclient/
- Clone the OpenStack on LXD repository to ~/git/openstack-on-lxd/
- Install OpenStack on LXD

After script completion OpenStack will continue to install; this can be monitored with `watch juju status`. Observe for any [actions](https://jaas.ai/docs/working-with-actions) that need to be run, then complete the setup of OpenStack from the [Using the Cloud section of the OpenStack on LXD documentation](https://docs.openstack.org/charm-guide/latest/openstack-on-lxd.html#deploy). Activate the openstackclient virtual environment to access the OpenStack client.
