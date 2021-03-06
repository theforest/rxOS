################################################################################
#
# sdr-config
#
################################################################################

SDR_CONFIG_VERSION = 1.2
SDR_CONFIG_LICENSE = GPLv3+
SDR_CONFIG_SITE = $(BR2_EXTERNAL)/local/sdr-config/src
SDR_CONFIG_SITE_METHOD = local

SDR_CONFIG_SED_CMDS += s|%BINPATH%|$(call qstrip,$(BR2_SDR_BINARY_PATH))|;
SDR_CONFIG_SED_CMDS += s|%JSON_PATH%|$(call qstrip,$(BR2_LIBRARIAN_SETTINGS_FILE))|;

define SDR_CONFIG_INSTALL_TARGET_CMDS
	$(INSTALL) -Dm755 $(@D)/sdrargs $(TARGET_DIR)/usr/sbin/sdrargs
	$(INSTALL) -Dm755 $(@D)/ontimeout.sh $(TARGET_DIR)/usr/sbin/ontimeout
	$(INSTALL) -Dm755 $(@D)/sdr.sh $(TARGET_DIR)/usr/sbin/sdr
endef

define SDR_CONFIG_INSTALL_INIT_SYSV
	$(INSTALL) -Dm0755 $(BR2_EXTERNAL)/local/sdr-config/S90sdr \
		$(TARGET_DIR)/etc/init.d/S90sdr
	$(SED) '$(SDR_CONFIG_SED_CMDS)' $(TARGET_DIR)/etc/init.d/S90sdr
endef

$(eval $(generic-package))
