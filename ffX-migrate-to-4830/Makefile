include $(TOPDIR)/rules.mk

PKG_NAME:=ffX-migrate-to-4830
PKG_VERSION:=2
PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/ffX-migrate-to-4830
  SECTION:=ffgt
  CATEGORY:=Customization
  TITLE:=Unify multiple Firmwares into one Multidomain one
  DEPENDS:=+gluon-core +busybox
endef

define Package/ffX-migrate-to-4830/description
	Freifunk X moves to 4830.org
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/ffX-migrate-to-4830/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))