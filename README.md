# Orange Pi Zero Alpine
Alpine for the Orange Pi Zero

Running in RAM, using an SD card only for initial loading of the filesystem and configuration storage.

Pre-built files, ready to go, can be found in [`builds/`](./builds).
There is also a Makefile which allows easy customization and building using either files in [`config/`](./config) or defconfigs as a base to work from.

The built kernel images are intentionally quite minimal, and no modules are included to keep the size down.
The default build is intended to be a base to build from, it should be everything necessary to run all the hardware on the Orange Pi Zero, but nothing else.
Any other builds in this repo will generally be the bare minimum for a particular application of mine.
You'll probably need to build your own kernel to suit your application and/or support any devices you might attach,
unless your application happens to be quite similar to something I've already built for.

## Versions
```
U-Boot 2025.10

# uname -r
6.17.0

# cat /etc/alpine-release
3.22.2
```

## Current status
This is a work in progress. Not everything necessarily functions, not everything will necessarily be made to function.
(Although if you want to make something function that doesn't feel free to fork and pull request.)

## Install on SD card

### Automatic
The script [`write_sd.sh`](./write_sd.sh) will automatically configure an SD card with a bootable Alpine from a build folder (it expects to see `apks/`, `boot/`, `var/` and `u-boot-sunxi-with-spl.bin`).
If no `<path>` argument is specified it defaults to the `out` directory.
Be careful about specifying the correct device because the script will happily rewrite the partition table of any device you point it at.

Usage: `sudo ./write_sd.sh <device> <path>`

Example: `sudo ./write_sd.sh /dev/sdb builds/default/`

### Manual
A manual approach is safer, with less risk of accidentally aiming `dd` and `fdisk` at the wrong device.

1. zero the start of the SD card
    - `dd if=/dev/zero of=<device> bs=1k count=1023 seek=1`
2. write u-boot
    - `dd if=u-boot-sunxi-with-spl.bin of=<device> bs=1024 seek=8`
3. create partitions with fdisk (you can skip the second partition if you want, I'm doing this as I'm binding it to the `/var` directory after install)
```sh
    fdisk <device>
    o         # new empty MBR partition table
    n         # new partition
    p         # primary
    1         # numbered 1
    2048      # from sector 2048
    +500M     # +500M
    t         # of type
    c         # W95 FAT32 (LBA)
    a         # make it bootable
    n         # new partition
    p         # primary
    2         # numbered 2
    <enter>   # from the next available sector
    -0        # to the last sector
    w         # save changes
    q         # exit fdisk
```
4. format and label partitions
    - `mkfs.fat -n ALPINE <partition_1>`
    - `mkfs.ext4 -L ALPINE_VAR <partition_2>`
5. create directory (if necessary) and mount the SD card
    - `mkdir <mount_path>`
    - `sudo mount <partition_1> <mount_path>`
6. copy `apks` and `boot` directories
    - `cp -r apks <mount_path>`
    - `cp -r boot <mount_path>`
7. unmount the first partition and mount the other one
    - `sudo umount <partition_1>`
    - `sudo mount <partition_2> <mount_path>`
8. copy the `var` directory
    - `cp -r var <mount_path>`
9. unmount the SD card and remove the mount path (if desired)
    - `sudo umount <partition>`
    - `rm -rf <mount_path>`
10. eject the SD card before removing it
    - `eject <device>`

## Build
To build with the default configuration all that's required is:

```sh
make all
```

This has been tested on Fedora, however, it should function just fine on other distros.
The prerequisites for building can be installed with `apt` on distros that use it:

```sh
sudo apt get -y --no-install-recommends --fix-missing install \
    gcc automake make bison flex swig python-dev musl \
    u-boot-tools dosfstools device-tree-compiler \
    git wget pv
```

Or with `dnf` (in case of Fedora):
```sh
sudo dnf install \
    gcc automake make bison flex swig python3-devel \
    python3-pytest ncurses-devel dosfstools \
    git wget pv uboot-tools libfdt-devel
```

### make
The Makefile will fetch all necessary source files and build whatever needs to be built.
`make help` will give a list of options,
`make info` will show build parameters (which can be changed by editing variables defined at the top of the Makefile).
To build a complete set of files, ready to go onto an SD card, all you need to do is type `make all` and everything else should sort itself out.

Menuconfig will pop up for the builds of U-Boot and the linux kernel but the build process is otherwise non-interactive.
Completed build files will output into `out/`, builds of individual components (e.g. `make uboot`, `make linux`) will output into the respective source folders.

It wouldn't be hard to adapt the Makefile to work with other devices, it's just a matter of providing appropriate config files and device trees.

## Configuration

### Alpine
At the moment the Alpine filesystem that loads is taken directly from the generic ARM distro and not modified.

The default login is `root` with no password.

Initial configuration on first boot can be done with `alpine-setup`.

At some point I plan to customize the OS a bit more, integrating a rootfs builder that allows package selection into the build process in one way or another.

### DT Overlays

DT overlays can be applied at boot using the `boot/bootEnv.txt` file (which will be in `/media/mmcblk0p1/` from within the booted OS).
The environment variable `overlays` should be set to a space separated string of overlays to load. The overlay DTBO files themselves will be in `boot/dtbs/overlays` and prefixed with `sun8i-h2-plus-`.

The overlays created during the build process have generally not been individually tested,
they're just pulled directly from the [relevant Armbian repo](https://github.com/armbian/sunxi-DT-overlays) and renamed.

## What is different from the original project?

- Newer uboot, kernel and alpine version
- No Wi-Fi
- Less options in the [`Makefile`](./Makefile)

## Why fork this?

I've made many modifications to meet my needs and although this is very much incomplete, I thought it would be useful for someone as I struggled a lot to make this work.
