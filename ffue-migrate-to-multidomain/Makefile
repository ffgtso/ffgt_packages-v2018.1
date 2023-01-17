include $(TOPDIR)/rules.mk

PKG_NAME:=ffue-migrate-to-multidomain
PKG_VERSION:=2
PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/ffue-migrate-to-multidomain
  SECTION:=ffue
  CATEGORY:=Customization
  TITLE:=Unify multiple Firmwares into one Multidomain one
  DEPENDS:=+gluon-core +busybox
endef

define Package/ffue-migrate-to-multidomain/description
	Freifunk Uelzen moves to Multidomain
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/ffue-migrate-to-multidomain/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))