include $(TOPDIR)/rules.mk

PKG_NAME:=ffgt-gluon-respondd
PKG_VERSION:=1

include ../gluon.mk

define Package/ffgt-gluon-respondd
  TITLE:=Provides node information to the legacy and modern network
  DEPENDS:=+gluon-core +gluon-respondd
endef

$(eval $(call BuildPackageGluon,ffgt-gluon-respondd))
