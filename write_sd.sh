#!/bin/env bash

device="$1"
build_dir="$PWD/out"

usage() { echo "usage: $0 <device> [<build_dir>]"; }

err_usage() {
  echo "$1"
  usage
  exit 2
}

[[ ! -z "$2" && -d "$2" ]] && build_dir="$2"

[[ -z "${device}" ]]   && err_usage "Error: No device specified"
[[ ! -b "${device}" ]] && err_usage "Error: ${device} is not a valid device"

removable=$(cat "/sys/block/${device/\/dev\//}/removable")
(( removable != 1 )) && err_usage "Error: ${device} is not removable"

echo "This script will destroy all data on the device you have selected (${device}) and create"
echo "a bootable Alpine installation for the Orange Pi Zero. Running fdisk from a script is"
echo "generally not recommended, you will not have an opportunity to inspect changes to the"
echo "partition table before they are written. You need to be confident that the device you"
echo "have specified (${device}) is the correct device."
echo
while true; do
  read -rp "Are you sure you want to continue? " confirmation
  case $(echo "$confirmation" | tr '[:upper:]' '[:lower:]') in
    y|yes ) break;;
    n|no ) echo "Discretion is the better part of valour. Exiting."; exit;;
    * ) echo "Please answer yes or no.";;
  esac
done
echo

printf "\nWiping signatures...\n"
wipefs --all --force "${device}1"
[[ -b "${device}2" ]] && wipefs --all --force "${device}2"

# from https://superuser.com/a/984637
# include comments so we can see what operations are taking place, but
# strip the comments with sed before sending arguments to fdisk
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk "${device}"
  o       # new empty MBR partition table
  n       # new partition
  p       # primary
  1       # numbered 1
  2048    # from sector 2048
  +500M   # +500M
  t       # of type
  c       # W95 FAT32 (LBA)
  a       # make it bootable
  n       # new partition
  p       # primary
  2       # numbered 2
          # from next available sector
  -0      # to the last sector
  w       # save changes
  q       # exit fdisk
EOF

printf "\nFormating partitions...\n"
mkfs.fat -n ALPINE "${device}1"
mkfs.ext4 -L ALPINE_VAR "${device}2"

printf "\nWriting u-boot...\n"
dd if=/dev/zero of="${device}" bs=1k count=1023 seek=1
dd if="${build_dir}/u-boot-sunxi-with-spl.bin" of="${device}" bs=1024 seek=8

cleanup() {
  mountpoint -q "${TEMP_MOUNT}" && umount "${TEMP_MOUNT}"
  [[ -d "${TEMP_MOUNT}" ]]      && rm -rf "${TEMP_MOUNT}"
}
TEMP_MOUNT=$(mktemp -d -t opi-zero-alpine-XXXXXXXX)
trap 'cleanup' EXIT

err_exit() {
  echo "$1"
  exit 1
}

printf "\nCopying files...\n"
mount "${device}1" "${TEMP_MOUNT}"               || err_exit "Error: failed to mount ${device}1"
cp -r "${build_dir}/"{apks,boot} "${TEMP_MOUNT}" || err_exit "Error: failed to copy files from ${build_dir}/{apks,boot}"
umount "${device}1"                              || err_exit "Error: failed to unmount ${device}1"

mount "${device}2" "${TEMP_MOUNT}"               || err_exit "Error: failed to mount ${device}2"
cp -r "${build_dir}/var" "${TEMP_MOUNT}"         || err_exit "Error: failed to copy files from ${build_dir}/var}"

printf "\nEjecting device...\n"
eject "${device}" || true

echo "Done!"
