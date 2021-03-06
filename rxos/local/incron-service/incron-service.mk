################################################################################
#
# incron-service
#
################################################################################

INCRON_SERVICE_VERSION = 1.2
INCRON_SERVICE_LICENSE = GPLv3+
INCRON_SERVICE_SITE = $(BR2_EXTERNAL)/local/incron-service/src
INCRON_SERVICE_SITE_METHOD = local


define INCRON_SERVICE_INSTALL_INIT_SYSV
	$(INSTALL) -Dm0755 $(@D)/S99incrond   $(TARGET_DIR)/etc/init.d/S99incrond
    $(INSTALL) -m755 -d $(TARGET_DIR)$(call qstrip,$(BR2_INCRON_SERVICE_CONFDIR))
endef

$(eval $(generic-package))
