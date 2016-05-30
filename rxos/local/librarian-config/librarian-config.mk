################################################################################
#
# librarian-config
#
################################################################################

LIBRARIAN_CONFIG_VERSION = 1.0
LIBRARIAN_CONFIG_LICENSE = GPL
LIBRARIAN_CONFIG_SITE = $(BR2_EXTERNAL)/local/librarian-config/src
LIBRARIAN_CONFIG_SITE_METHOD = local

LISTIFY = $(BR2_EXTERNAL)/scripts/listify.sh
BLACKLIST = $(foreach rxp,$(call qstrip,$(BR2_PATH_BLACKLIST)),'$(rxp)')

LIBRARIAN_SED_COMMANDS += s|%ADDR%|$(call qstrip,$(BR2_LIBRARIAN_ADDR))|g;
LIBRARIAN_SED_COMMANDS += s|%PORT%|$(call qstrip,$(BR2_LIBRARIAN_PORT))|g;
LIBRARIAN_SED_COMMANDS += s|%DEFROUTE%|$(call qstrip,$(BR2_LIBRARIAN_DEFROUTE))|g;
LIBRARIAN_SED_COMMANDS += s|%LOGPATH%|$(call qstrip,$(BR2_LIBRARIAN_LOGPATH))|g;
LIBRARIAN_SED_COMMANDS += s|%LOGSIZE%|$(call qstrip,$(BR2_LIBRARIAN_LOGSIZE))|g;
LIBRARIAN_SED_COMMANDS += s|%LOGBACKUPS%|$(call qstrip,$(BR2_LIBRARIAN_LOGBACKUPS))|g;
LIBRARIAN_SED_COMMANDS += s|%SETTINGS_FILE%|$(call qstrip,$(BR2_LIBRARIAN_SETTINGS_FILE))|g;
LIBRARIAN_SED_COMMANDS += s|%FSAL_SOCKET%|$(call qstrip,$(BR2_FSAL_SOCKETPATH))|g;
LIBRARIAN_SED_COMMANDS += s|%FSAL_LOGPATH%|$(call qstrip,$(BR2_FSAL_LOGPATH))|g;
LIBRARIAN_SED_COMMANDS += s|%DHCP_START%|$(call qstrip,$(BR2_NETWORK_CONFIG_DHCP_START))|g;
LIBRARIAN_SED_COMMANDS += s|%DHCP_END%|$(call qstrip,$(BR2_NETWORK_CONFIG_DHCP_END))|g;
LIBRARIAN_SED_COMMANDS += s|%PRIMARY%|$(call qstrip,$(BR2_STORAGE_PRIMARY))|g;
LIBRARIAN_SED_COMMANDS += s|%SECONDARY%|$(call qstrip,$(BR2_STORAGE_SECONDARY))|g;
LIBRARIAN_SED_COMMANDS += s|%BLACKLIST%|$(shell $(LISTIFY) $(BLACKLIST))|g;

define LIBRARIAN_CONFIG_INSTALL_TARGET_CMDS
	$(INSTALL) -Dm644 $(@D)/librarian.ini $(TARGET_DIR)/etc/librarian.ini
endef

$(eval $(generic-package))

# We patch the config last thing during the build because we need to wait for 
# any components that may provide additional $LIBRARIAN_SED_COMMANDS for the 
# configuration patch.
define PATCH_LIBRARIAN_CONFIG
	$(SED) '$(LIBRARIAN_SED_COMMANDS)' $(TARGET_DIR)/etc/librarian.ini
	$(SED) 's|%COMPONENTS%|$(shell $(LISTIFY) $(LIBRARIAN_COMPONENTS))|' \
		$(TARGET_DIR)/etc/librarian.ini
	$(SED) 's|%MENU%|$(shell $(LISTIFY) $(LIBRARIAN_MENU))|' \
		$(TARGET_DIR)/etc/librarian.ini
endef

TARGET_FINALIZE_HOOKS += PATCH_LIBRARIAN_CONFIG

print-librarian-sed-commands:
	@echo '$(LIBRARIAN_SED_COMMANDS)'

print-librarian-components:
	@echo $(call qstrip,$(LIBRARIAN_COMPONENTS))
