# Pass build hook arguments

BR2_ROOTFS_POST_SCRIPT_ARGS = $(BR2_LINUX_KERNEL_VERSION) \
							  $(RXOS_INITRAMFS_COMPRESSION)
