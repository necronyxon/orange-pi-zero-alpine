#
# Build U-Boot, kernel and Alpine initramfs/modloop for Orange Pi Zero
#
#	https://github.com/moonbuggy/orange-pi-zero-alpine/
#
# Although the configs included from the GitHub repo are for the Orange Pi Zero it's
# possible to adapt for other devices without a lot of trouble. The variables defined
# below can be adjusted to suit alternative devices, if you have appropraite DTBs
# available and spend some time in menuconfig then Bob's your uncle.
#

# These can be modified as necessary:
#
UBOOT_BRANCH    ?= v2025.10
UBOOT_SOURCE    ?= github.com/u-boot/u-boot -b $(UBOOT_BRANCH)
LINUX_SOURCE    ?= github.com/linux-sunxi/linux-sunxi -b sunxi-next
LINUX_BRANCH    ?= v6.17
LINUX_SOURCE    ?= github.com/torvalds/linux -b $(LINUX_BRANCH)
ALPINE_VERSION  ?= 3.22.2
ALPINE_SERVER   ?= dl-cdn.alpinelinux.org
OVERLAYS_SOURCE ?= github.com/armbian/sunxi-DT-overlays
LINARO_VERSION  ?= 14.3.rel1
LINARO_SERVER   ?= developer.arm.com
# LINARO_VERSION  ?= 14.0-2023.06-1
# LINARO_VERSION2 ?= 14.0.0-2023.06
# LINARO_SERVER   ?= snapshots.linaro.org

UBOOT_DEFCONFIG ?= orangepi_zero_defconfig
LINUX_DEFCONFIG ?= sunxi_defconfig
DEVTREE_NAME    ?= sun8i-h2-plus-orangepi-zero

CROSS_COMPILE ?= $(ROOT_DIR)/$(LINARO_DIR)/bin/arm-none-linux-gnueabihf-
# CROSS_COMPILE ?= $(ROOT_DIR)/$(LINARO_DIR)/bin/arm-linux-gnueabihf-
ARCH          ?= arm
MENUCONFIG    ?= menuconfig

INITRAMFS_COMPRESSION ?= xz --check=crc32
MODLOOP_COMPRESSION   ?= xz


# These shouldn't need to be modified (although many of them can be if you want):
#
THIS_FILE      := $(lastword $(MAKEFILE_LIST))
ROOT_DIR       := $(shell pwd)
CURRENT_CONFIG := $(ROOT_DIR)/.make.conf

-include $(CURRENT_CONFIG)

SOURCE_DIR     ?= source
CONFIG_DIR     ?= config
OUTPUT_DIR     ?= out
UBOOT_DIR      ?= $(SOURCE_DIR)/u-boot
UBOOT_FILE     ?= $(UBOOT_DIR)/u-boot-sunxi-with-spl.bin
LINUX_DIR      ?= $(SOURCE_DIR)/linux
LINUX_OUT_DIR  ?= $(ROOT_DIR)/$(LINUX_DIR)/output
ZIMAGE_FILE    ?= $(LINUX_DIR)/arch/arm/boot/zImage
LINARO_NAME    ?= arm-gnu-toolchain-$(LINARO_VERSION)-x86_64-arm-none-linux-gnueabihf
# LINARO_NAME    ?= gcc-linaro-$(LINARO_VERSION2)-x86_64_arm-linux-gnueabihf
LINARO_DIR     ?= $(SOURCE_DIR)/$(LINARO_NAME)
LINARO_ARCHIVE ?= $(SOURCE_DIR)/$(LINARO_NAME).tar.xz
ALPINE_NAME    ?= alpine-uboot-$(ALPINE_VERSION)-armv7
ALPINE_DIR     ?= $(SOURCE_DIR)/$(ALPINE_NAME)
ALPINE_ARCHIVE ?= $(SOURCE_DIR)/$(ALPINE_NAME).tar.gz
DEVTREE_DIR    ?= $(UBOOT_DIR)/arch/arm/dts
DEVTREE_OUT    ?= $(OUTPUT_DIR)/boot/dtbs
OVERLAYS_DIR   ?= $(SOURCE_DIR)/overlays
OVERLAYS_OUT   ?= $(DEVTREE_OUT)/overlays

-include $(CURRENT_CONFIG)

.PHONY: help info list-configs all get-all clean mrproper distclean \
	uboot-clean uboot-mrproper uboot uboot-defconfig .build-uboot get-uboot \
	linux-clean linux-mrproper linux linux-defconfig .build-linux .build-modules get-linux \
	get-firmware install-clean install initramfs modloop get-alpine apks overlays get-overlays

.DEFAULT_TARGET: help

##@ Information

help: ## display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_%-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo
	@echo "There's no need to manually download source or build individual components (unless you want to modify"
	@echo "them before they're incorporated into the rest of the build), all targets will prepare prerequisites as"
	@echo "necessary (i.e. 'make all' alone is sufficient for a complete build)."
	@echo
	@echo "Files ready for installation will be put in the output folder, other generated files remain within their"
	@echo "individual project folder. The output folder is:"
	@echo
	@echo "	$(ROOT_DIR)/$(OUTPUT_DIR)"
	@echo

info: ## display build parameters
	@echo "   U-Boot source:  $(UBOOT_SOURCE)"
	@echo "U-Boot defconfig:  $(UBOOT_DEFCONFIG)"
	@echo
	@echo "    Linux source:  $(LINUX_SOURCE)"
	@echo " Linux defconfig:  $(LINUX_DEFCONFIG)"
	@echo
	@echo "  Alpine version:  $(ALPINE_VERSION)"
	@echo "   Alpine server:  $(ALPINE_SERVER)"
	@echo
	@echo "   make defaults:  ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) MENUCONFIG=$(MENUCONFIG)"
	@echo "   Output folder:  $(OUTPUT_DIR)"

##@ Global

all: uboot linux install  ## build U-Boot, linux, Alpine RAM filesystem and prepare files for install

get-all: ## get latest source for U-Boot, linux and xradio and the specified Alpine version
	@$(MAKE) -f $(THIS_FILE) --no-print-directory get-uboot
	@$(MAKE) -f $(THIS_FILE) --no-print-directory get-linux
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(ALPINE_DIR)
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(LINARO_DIR)

clean: uboot-clean linux-clean          ## remove most generated files in source folders

mrproper: uboot-mrproper linux-mrproper ## remove all generated files in source folders

distclean:                              ## remove all source files, leave only files in the output folder
	@test ! -d $(SOURCE_DIR) || rm -rf $(SOURCE_DIR)

##@ U-Boot

uboot: $(UBOOT_DIR) $(LINARO_DIR)/ ## build U-Boot using existing .config if it exists, otherwise using default
	@if [[ -f $(CONFIG_DIR)/uboot.config ]]; then \
		cp $(CONFIG_DIR)/uboot.config $(UBOOT_DIR)/.config; \
	else \
		$(MAKE) -C $(UBOOT_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(UBOOT_DEFCONFIG); \
	fi
	@$(MAKE) -f $(THIS_FILE) --no-print-directory .build-uboot

uboot-defconfig: $(UBOOT_DIR) ## build U-Boot with the defconfig (discards any existing .config)
	$(MAKE) -C $(UBOOT_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(UBOOT_DEFCONFIG)
	@$(MAKE) -f $(THIS_FILE) --no-print-directory .build-uboot

uboot-clean: ## remove most generated files in U-Boot folder
	@test ! -d $(UBOOT_DIR) || $(MAKE) -C $(UBOOT_DIR) clean

uboot-mrproper: ## remove all generated files in U-Boot folder
	@test ! -d $(UBOOT_DIR) || $(MAKE) -C $(UBOOT_DIR) mrproper

.build-uboot: $(UBOOT_DIR) $(UBOOT_CONFIG)
	$(MAKE) -C $(UBOOT_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(MENUCONFIG)
	$(MAKE) -j$(shell nproc) -C $(UBOOT_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE)

##@ Linux

linux: $(LINUX_DIR)/ $(LINARO_DIR)/ ## build linux using existing .config if present, otherwise using default
	@if [[ -f $(CONFIG_DIR)/linux.config ]]; then \
		cp $(CONFIG_DIR)/linux.config $(LINUX_DIR)/.config; \
	else \
		$(MAKE) -C $(LINUX_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(LINUX_DEFCONFIG); \
	fi
	@$(MAKE) -f $(THIS_FILE) --no-print-directory .build-linux

linux-defconfig: $(LINUX_DIR)/ $(LINARO_DIR) ## build linux with the defconfig (discards any existing .config)
	@rm -f $(CURRENT_CONFIG) 2>/dev/null
	$(MAKE) -C $(LINUX_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(LINUX_DEFCONFIG)
	@$(MAKE) -f $(THIS_FILE) --no-print-directory .build-linux

linux-clean: ## remove most generated files in linux folder
	@test ! -d $(LINUX_DIR) || $(MAKE) -C $(LINUX_DIR) clean
	@rm -f $(ZIMAGE_FILE) 2>/dev/null

linux-mrproper: ## remove all generated files in linux folder
	@test ! -d $(LINUX_DIR) || $(MAKE) -C $(LINUX_DIR) mrproper
	@rm -f $(ZIMAGE_FILE) 2>/dev/null

.build-linux: $(LINUX_DIR)/ $(LINUX_CONFIG)
	$(MAKE) -C $(LINUX_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(MENUCONFIG)
	$(MAKE) -j$(shell nproc) -C $(LINUX_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) zImage
ifndef NO_MODULES
	$(MAKE) -j$(shell nproc) -f $(THIS_FILE) --no-print-director .build-modules
endif

.build-modules: $(ZIMAGE_FILE)
	$(MAKE) -C $(LINUX_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	$(MAKE) -C $(LINUX_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH=$(LINUX_OUT_DIR) modules_install

##@ Installation Files

$(OUTPUT_DIR)/ $(OUTPUT_DIR)/apks/armv7/:
	@mkdir -p $@

$(OUTPUT_DIR)%/:
	@mkdir -p $@

# copy apks to output folder
#
$(OUTPUT_DIR)/apks/%: $(ALPINE_DIR)/apks/% | $(OUTPUT_DIR)/apks/armv7/
	@cp -f $< $@

apks: $(ALPINE_DIR)/apks/ | $(OUTPUT_DIR)/apks/armv7/
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/apks/.boot_repository
	@$(foreach file, $(notdir $(wildcard $(ALPINE_DIR)/apks/armv7/*)), $(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/apks/armv7/$(file);)

# copy overlays to output folder
#
$(OVERLAYS_OUT)/%.dts: $(OVERLAYS_DIR)/ | $(OVERLAYS_OUT)/
	@cp -f $(OVERLAYS_DIR)/sun8i-h3/$(subst sun8i-h2-plus-,sun8i-h3-,$(@F)) $@

$(OVERLAYS_OUT)/%.dtbo: $(OVERLAYS_DIR)/ | $(OVERLAYS_OUT)/
	@echo "Making overlay $(@F)"
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OVERLAYS_OUT)/$(basename $(@F)).dts
	@dtc -@ -I dts -O dtb -W no-unit_address_vs_reg $(OVERLAYS_OUT)/$(basename $(@F)).dts > $(@) 2>/dev/null

$(OVERLAYS_OUT)/sun8i-h2-plus-fixup.scr: $(OVERLAYS_DIR)/sun8i-h3/sun8i-h3-fixup.scr-cmd
	@mkimage -C none -A $(ARCH) -T script -d $(OVERLAYS_DIR)/sun8i-h3/sun8i-h3-fixup.scr-cmd $(OVERLAYS_OUT)/sun8i-h2-plus-fixup.scr

overlays: $(OVERLAYS_DIR)/ | $(OVERLAYS_OUT)/
	@$(foreach file, $(notdir $(wildcard $(OVERLAYS_DIR)/sun8i-h3/*.dts)), $(eval dts_list+=$(subst sun8i-h3-,, $(basename $(file)))))
	@$(foreach file, $(sort $(dts_list)), $(MAKE) -f $(THIS_FILE) --no-print-directory $(OVERLAYS_OUT)/sun8i-h2-plus-$(file).dtbo;)
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OVERLAYS_OUT)/sun8i-h2-plus-fixup.scr


# copy device tree to output folder
#
$(DEVTREE_OUT)/$(DEVTREE_NAME).dts: $(DEVTREE_DIR)/$(DEVTREE_NAME).dts | $(DEVTREE_OUT)/
	@cpp -Wp,-MD,.$(DEVTREE_NAME).dtb.d.pre.tmp -nostdinc -Iinclude -I$(LINUX_DIR)/include -Itestcase-data -undef -D__DTS__ -x assembler-with-cpp -o $(DEVTREE_OUT)/$(DEVTREE_NAME).dts $(DEVTREE_DIR)/$(DEVTREE_NAME).dts
	@rm -f .$(DEVTREE_NAME).dtb.d.pre.tmp

$(DEVTREE_OUT)/$(DEVTREE_NAME).dtb: $(DEVTREE_OUT)/$(DEVTREE_NAME).dts | $(DEVTREE_OUT)/
	@echo "Making device tree $(@F)"
ifdef NO_OVERLAYS
	@dtc -I dts -O dtb -W no-unit_address_vs_reg $(DEVTREE_OUT)/$(DEVTREE_NAME).dts > $(DEVTREE_OUT)/$(DEVTREE_NAME).dtb
else
	@dtc -@ -I dts -O dtb -W no-unit_address_vs_reg $(DEVTREE_OUT)/$(DEVTREE_NAME).dts > $(DEVTREE_OUT)/$(DEVTREE_NAME).dtb
endif
	@echo

# copy miscellaneous to output folder
#
$(OUTPUT_DIR)/u-boot-sunxi-with-spl.bin: $(UBOOT_FILE) | $(OUTPUT_DIR)/

$(OUTPUT_DIR)/boot/boot.cmd: $(CONFIG_DIR)/boot.cmd | $(OUTPUT_DIR)/boot/
$(OUTPUT_DIR)/boot/boot.scr: $(OUTPUT_DIR)/boot/boot.cmd
	@echo; echo Making boot.scr..
	@mkimage -C none -A $(ARCH) -T script -d $(OUTPUT_DIR)/boot/boot.cmd $(OUTPUT_DIR)/boot/boot.scr
	@echo

$(OUTPUT_DIR)/boot/bootEnv.txt: $(CONFIG_DIR)/bootEnv.txt | $(OUTPUT_DIR)/boot/
$(OUTPUT_DIR)/boot/zImage: $(ZIMAGE_FILE) | $(OUTPUT_DIR)/boot/
$(OUTPUT_DIR)/kernel.config: $(LINUX_DIR)/.config | $(OUTPUT_DIR)/
$(OUTPUT_DIR)/uboot.config: $(UBOOT_DIR)/.config | $(OUTPUT_DIR)/

$(OUTPUT_DIR)/%: | $(OUTPUT_DIR)/
	@cp -f $< $@

install: $(LINARO_DIR)/ $(OUTPUT_DIR)/ $(LINUX_DIR)/ ## prepare all files for installation
	@echo Checking files..
	@$(MAKE) -f $(THIS_FILE) --no-print-directory apks
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/u-boot-sunxi-with-spl.bin
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/boot/zImage
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/uboot.config
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/boot/boot.scr
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/boot/bootEnv.txt
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(DEVTREE_OUT)/$(DEVTREE_NAME).dtb
ifndef NO_OVERLAYS
	@$(MAKE) -f $(THIS_FILE) --no-print-directory overlays
endif
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/kernel.config
ifndef NO_MODULES
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/boot/modloop-sunxi
endif
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(OUTPUT_DIR)/boot/initramfs-sunxi
	@echo Done.

initramfs: $(OUTPUT_DIR)/boot/initramfs-sunxi ## create Alpine initramfs file only

$(OUTPUT_DIR)/boot/initramfs-sunxi: modules_dir = $(LINUX_OUT_DIR)/lib/modules/$(shell make -s -C $(LINUX_DIR) kernelrelease)
	initramfs_temp ?= $(ROOT_DIR)/$(OUTPUT_DIR)/initramfs-temp
	initramfs_tempfile ?= $(ROOT_DIR)/$(OUTPUT_DIR)/initramfs-sunxi-temp
$(OUTPUT_DIR)/boot/initramfs-sunxi: $(ALPINE_DIR) $(LINUX_OUT_DIR) $(modules_dir) | $(OUTPUT_DIR)/
ifndef NO_MODULES
	@test -d $(modules_dir) || $(MAKE) -f $(THIS_FILE) --no-print-directory .build-modules
endif
	@echo Making initramfs..
	@mkdir -p $(initramfs_temp)
	@gunzip -c $(shell find $(ALPINE_DIR) -name 'initramfs*') | cpio -i --quiet -D $(initramfs_temp)
	@cp -r $(initramfs_temp)/var $(OUTPUT_DIR)/var
	@rm -rf $(initramfs_temp)/var
	@rm -rf $(initramfs_temp)/lib/modules/*
	@rm -rf $(initramfs_temp)/lib/firmware/*
ifndef NO_MODULES
	@cp -rP $(modules_dir) $(initramfs_temp)/lib/modules/ && find $(initramfs_temp)/lib/modules/ -type l -delete
endif
	@cd $(initramfs_temp)/; find . | cpio --quiet -H newc -o | $(INITRAMFS_COMPRESSION) $(INITRAMFS_COMPRESSION_ARGS) > $(initramfs_tempfile)
	@mkimage -n initramfs-sunxi -A $(ARCH) -O linux -T ramdisk -C none -d $(initramfs_tempfile) $(OUTPUT_DIR)/boot/initramfs-sunxi
	@rm -rf $(initramfs_temp) $(initramfs_tempfile)
	@echo

ifndef NO_MODULES
modloop: $(OUTPUT_DIR)/boot/modloop-sunxi ## create Alpine modloop file only
else
modloop:
	@echo No modloop is required for this build.
endif

$(OUTPUT_DIR)/boot/modloop-sunxi: modules_dir = $(LINUX_OUT_DIR)/lib/modules/$(shell make -s -C $(LINUX_DIR) kernelrelease)
	modloop_temp ?= $(OUTPUT_DIR)/modloop-temp
$(OUTPUT_DIR)/boot/modloop-sunxi: $(ALPINE_DIR) $(LINUX_OUT_DIR) $(modules_dir) | $(OUTPUT_DIR)/
	@test -d $(modules_dir) || $(MAKE) -f $(THIS_FILE) --no-print-directory .build-modules
	@echo Making modloop..
	@rm -rf $(modloop_temp)
	@mkdir -p $(modloop_temp)/modules/firmware
	@cp -rP $(modules_dir) $(modloop_temp)/modules/ && find $(modloop_temp)/modules/ -type l -delete
	@mksquashfs $(modloop_temp) $(OUTPUT_DIR)/boot/modloop-sunxi -b 1048576 -comp $(MODLOOP_COMPRESSION) -Xdict-size 100% -noappend
	@rm -rf $(modloop_temp)
	@echo

install-clean: ## remove previously generated installation files
	@echo Cleaning old installation files..
	@test ! -d $(OUTPUT_DIR) || rm -rf $(OUTPUT_DIR)/*

##@	Source Files

get-all: get-linaro get-uboot get-linux get-alpine get-overlays ## get/update all sources

get-uboot: $(SOURCE_DIR)/                                       ## clone or update U-Boot from repo
	$(call git,U-Boot,$(UBOOT_SOURCE),$(UBOOT_DIR),--depth 1)

get-linux: $(SOURCE_DIR)/                                       ## clone or update linux from repo
	$(call git,linux,$(LINUX_SOURCE),$(LINUX_DIR),--depth 1)

get-overlays: $(SOURCE_DIR)/                                    ## clone or update overlays from repo
	$(call git,overlays,$(OVERLAYS_SOURCE),$(OVERLAYS_DIR),--depth 1)

get-alpine: $(SOURCE_DIR)/                                      # download Alpine from repo and untar (if necessary)
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(ALPINE_DIR)/

get-linaro: $(SOURCE_DIR)/                                      # download Linaro from repo and untar (if necessary)
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(LINARO_DIR)/

define git
	@echo Checking ${1}..
	@test ! -d ${3} \
	  && git clone https://${2} ${4} ${3} \
	  || git -C ${3} pull ${4}
	@echo
endef

$(SOURCE_DIR)/:
	@mkdir -p $(SOURCE_DIR)

$(UBOOT_DIR):
	@$(MAKE) -f $(THIS_FILE) --no-print-directory get-uboot

$(UBOOT_FILE): | $(UBOOT_DIR)
	@$(MAKE) -f $(THIS_FILE) --no-print-directory .build-uboot

$(LINUX_DIR)/:
	@$(MAKE) -f $(THIS_FILE) --no-print-directory get-linux

$(LINUX_OUT_DIR): | $(LINUX_DIR)/
	@$(MAKE) -f $(THIS_FILE) --no-print-directory .build-modules

$(ZIMAGE_FILE): | $(LINUX_DIR)/
	@$(MAKE) -f $(THIS_FILE) --no-print-directory .build-linux

$(LINARO_DIR)%/:
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(LINARO_DIR)/

$(LINARO_DIR)/: $(LINARO_ARCHIVE)
	@if [[ ! -d $(LINARO_DIR) ]]; then \
		echo Untarring Linaro...; \
		mkdir -p $(LINARO_DIR); \
		tar -C $(SOURCE_DIR) -xf $(LINARO_ARCHIVE); \
	fi

$(LINARO_ARCHIVE):
	@echo Downloading Linaro...
	@wget --show-progress --progress=bar:force -q -P $(SOURCE_DIR)/ https://$(LINARO_SERVER)/-/media/Files/downloads/gnu/$(LINARO_VERSION)/binrel/$(LINARO_NAME).tar.xz

# $(LINARO_ARCHIVE):
# 	@echo Downloading Linaro...
# 	@wget --show-progress --progress=bar:force -q -P $(SOURCE_DIR)/ https://$(LINARO_SERVER)/gnu-toolchain/$(LINARO_VERSION)/arm-linux-gnueabihf/$(LINARO_NAME).tar.xz

$(ALPINE_DIR)%/:
	@$(MAKE) -f $(THIS_FILE) --no-print-directory $(ALPINE_DIR)/

$(ALPINE_DIR)/: $(ALPINE_ARCHIVE)
	@echo Untarring Alpine...
	@mkdir -p $(ALPINE_DIR)
	@tar -C $(ALPINE_DIR) -zxf $(ALPINE_ARCHIVE)

$(ALPINE_ARCHIVE):
	@echo Downloading Alpine...
	@wget --show-progress --progress=bar:force -q -P $(SOURCE_DIR)/ http://$(ALPINE_SERVER)/alpine/v$(shell echo $(ALPINE_VERSION) | cut -f1,2 -d".")/releases/armv7/$(ALPINE_NAME).tar.gz

$(OVERLAYS_DIR)/:
	@$(MAKE) -f $(THIS_FILE) --no-print-directory get-overlays
