include $(TOPDIR)/rules.mk

PKG_NAME:=ffgt-config-mode-domain-select
PKG_VERSION:=1

include $(TOPDIR)/../package/gluon.mk

define Package/ffgt-config-mode-domain-select
  TITLE:=UI for changing the node-config
  DEPENDS:=+config-mode-core @GLUON_MULTIDOMAIN
endef

$(eval $(call BuildPackageGluon,ffgt-config-mode-domain-select))
