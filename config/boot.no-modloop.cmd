setenv fdt_high ffffffff
setenv load_addr "0x44000000"
setenv overlay_prefix "sun8i-h2-plus-"
setenv machid 1029

setenv bootargs earlyprintk /boot/zImage modules=loop,squashfs,sd-mod,usb-storage rootwait console=${console}
load mmc 0:1 ${fdt_addr_r} /boot/dtbs/sun8i-h2-plus-orangepi-zero.dtb
load mmc 0:1 0x41000000 /boot/zImage

fdt addr ${fdt_addr_r}
fdt resize 65536

if test -e mmc 0:1 /boot/bootEnv.txt; then
  load mmc 0:1 ${load_addr} /boot/bootEnv.txt
  env import -t ${load_addr} ${filesize}
fi

load mmc 0:1 0x51000000 /boot/initramfs-sunxi

bootz 0x41000000 0x51000000 0x43000000
