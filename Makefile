BOARD:=rxos
BOARD_DIR=$(BOARD)
DEFCONFIG=$(BOARD)_defconfig

# Board-agnostic settings
BUILDROOT = ./buildroot
CONFIG = $(OUTPUT)/.config
BOARD_DIR = ./$(BOARD)
PLATFORM_FILE = platform
VERSION_FILE = version
VERSION = $(shell cat $(BOARD_DIR)/$(VERSION_FILE))
PLATFORM = $(shell cat $(BOARD_DIR)/$(PLATFORM_FILE))

# Build target
TARGET_NAME = rxos
RELEASE_NAME=$(TARGET_NAME)-$(VERSION)

# Build output files
OUTPUT = build/$(BOARD)
OUTPUT_DIR = ../$(OUTPUT)
IMAGES_DIR = $(OUTPUT)/images
KERNEL_IMAGE = $(IMAGES_DIR)/zImage
BUILD_STAMP = $(OUTPUT)/.stamp_built
IMG_FILE = $(IMAGES_DIR)/sdcard.img
PKG_FILE = $(IMAGES_DIR)/rxos.pkg

# External dir
EXTERNAL = .$(BOARD_DIR)
export BR2_EXTERNAL=$(EXTERNAL)

.PHONY: \
	default \
	version \
	build \
	rebuild \
	flash \
	update \
	menuconfig \
	linuxconfig \
	busyboxconfig \
	saveconfig \
	clean-build \
	clean

default: build

version:
	@echo v$(VERSION)

build: $(BUILD_STAMP)

menuconfig: $(CONFIG)
	@make -C $(BUILDROOT) O=$(OUTPUT_DIR) menuconfig

linuxconfig: $(CONFIG)
	@make -C $(BUILDROOT) O=$(OUTPUT_DIR) linux-menuconfig

busyboxconfig: $(CONFIG)
	@make -C $(BUILDROOT) O=$(OUTPUT_DIR) busybox-menuconfig

saveconfig: $(CONFIG)
	@make -C $(BUILDROOT) O=$(OUTPUT_DIR) savedefconfig
	@make -C $(BUILDROOT) O=$(OUTPUT_DIR) linux-update-defconfig
	@make -C $(BUILDROOT) O=$(OUTPUT_DIR) busybox-update-config

config: $(CONFIG)

rebuild: clean-build build

clean-build:
	@-rm $(BUILD_STAMP)
	@-rm $(KERNEL_IMAGE)
	@-rm $(IMAGES_DIR)/rootfs*
	@-rm $(IMAGES_DIR)/*.pkg
	@-rm $(IMAGES_DIR)/*.img
	@-rm $(IMAGES_DIR)/*.md5

clean:
	-rm -rf $(OUTPUT)

$(BUILD_STAMP): $(CONFIG)
	@VERSION_FILE=$(VERSION_FILE) PLATFORM_FILE=$(PLATFORM_FILE) make \
		-C $(BUILDROOT) O=$(OUTPUT_DIR)
	touch $@

$(CONFIG):
	@make -C $(BUILDROOT) O=$(OUTPUT_DIR) $(DEFCONFIG)

.DEFAULT:
	@make -C $(BUILDROOT) O=$(OUTPUT_DIR) $@