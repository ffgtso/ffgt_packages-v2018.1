include $(TOPDIR)/rules.mk

PKG_NAME:=ffgt-autoupdater-wifi-fallback
PKG_VERSION:=6
PKG_RELEASE:=1
PKG_LICENSE:=BSD-2-Clause
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/ffgt-autoupdater-wifi-fallback
  TITLE:=Small IPv6 WiFi recovery updater for Gluon 2018.2
  DEPENDS:=+gluon-autoupdater +iw +batctl +libiwinfo-lua +luaposix +lua-jsonc +micrond
  CONFLICTS:=tecff-autoupdater-wifi-fallback ffho-autoupdater-wifi-fallback ffac-autoupdater-wifi-fallback
endef

define Package/ffgt-autoupdater-wifi-fallback/conffiles
/etc/config/autoupdater-wifi-fallback
endef

$(eval $(call BuildPackageGluon,ffgt-autoupdater-wifi-fallback))
