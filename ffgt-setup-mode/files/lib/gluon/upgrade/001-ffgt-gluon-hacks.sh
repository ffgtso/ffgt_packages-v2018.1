#!/bin/sh
# Another big fat ugly hack ...
# Rationale: we don't want to change too much on Gluons core files,
# but we need to replace some for practical reasons. Thus we clone
# the original, stash them in the firmware as -ffgt versions and
# on first boot replace the Gluon ones with their FFGT counterparts.
# Yes, what we would need is some kind of overlay packages that may
# replace existig files during image creation.
#
# Hmm, looks like it's possible to have Gluon apply patches to itself?
# Anyone willing to explain that magic to me? -- wusel, 2018-07-19 FIXME!

# HACK, FIXME; if /bin/wget does not exists, create a symlink from /usr/bin/wget
if [ ! -e /bin/wget ]; then ln -s /usr/bin/wget /bin/wget ; fi

START=1

if [ -e /gluon/config-mode/model/gluon-config-mode/wizard-ffgt.lua ]; then
  mv /gluon/config-mode/model/gluon-config-mode/wizard-ffgt.lua /gluon/config-mode/model/gluon-config-mode/wizard.lua
fi

if [ -e /lib/gluon/config-mode/view/wizard/welcome-ffgt.html ]; then
  mv /lib/gluon/config-mode/view/wizard/welcome-ffgt.html /lib/gluon/config-mode/view/wizard/welcome.html
fi

if [ -e /lib/gluon/config-mode/wizard/0100-hostname-ffgt.lua ]; then
  mv /lib/gluon/config-mode/wizard/0100-hostname-ffgt.lua /lib/gluon/config-mode/wizard/0100-hostname.lua
fi

if [ -e /lib/gluon/config-mode/wizard/0200-domain-select-ffgt.lua ]; then
  mv /lib/gluon/config-mode/wizard/0200-domain-select-ffgt.lua /lib/gluon/config-mode/wizard/0200-domain-select.lua
fi

if [ -e /lib/gluon/config-mode/wizard/0400-geo-location-ffgt.lua ]; then
  mv /lib/gluon/config-mode/wizard/0400-geo-location-ffgt.lua /lib/gluon/config-mode/wizard/0400-geo-location.lua
fi

if [ -e /lib/gluon/config-mode/wizard/0500-contact-info-ffgt.lua ]; then
  mv /lib/gluon/config-mode/wizard/0500-contact-info-ffgt.lua /lib/gluon/config-mode/wizard/0500-contact-info.lua
fi

if [ -e /etc/crontabs/root ]; then
  mv /etc/crontabs /etc/crontabs_not_used_by_gluon
fi

if [ -e /lib/gluon/config-mode/controller/admin/privatewifi-ffgt.lua ]; then
  mv /lib/gluon/config-mode/controller/admin/privatewifi-ffgt.lua /lib/gluon/config-mode/controller/admin/privatewifi.lua
fi

if [ -e /lib/gluon/config-mode/controller/admin/wifi-config-ffgt.lua ]; then
  mv /lib/gluon/config-mode/controller/admin/wifi-config-ffgt.lua /lib/gluon/config-mode/controller/admin/wifi-config.lua
fi

if [ -e /lib/gluon/config-mode/view/admin/info-ffgt.html ]; then
  mv /lib/gluon/config-mode/view/admin/info-ffgt.html  /lib/gluon/config-mode/view/admin/info.html
fi

COMMIT_WIRELESS=0
EOS_CHECK=$(uci get wireless.dep_radio0.ifname >/dev/null 2>&1 ; echo $?)
if [ ${EOS_CHECK} -eq 0 ]; then
  uci delete wireless.dep_radio0
  COMMIT_WIRELESS=1
fi

LEGACY_CHECK=$(uci get wireless.legacy_radio0.ifname >/dev/null 2>&1 ; echo $?)
if [ ${LEGACY_CHECK} -eq 0 ]; then
  uci delete wireless.legacy_radio0
  COMMIT_WIRELESS=1
fi

LEGACY_CHECK=$(uci get wireless.legacy_radio1.ifname >/dev/null 2>&1 ; echo $?)
if [ ${LEGACY_CHECK} -eq 0 ]; then
  uci delete wireless.legacy_radio1
  COMMIT_WIRELESS=1
fi

if [ ${COMMIT_WIRELESS} -eq 1 ]; then
  uci commit wireless
fi

BRANCH=$(uci get autoupdater.settings.branch)
uci get autoupdater.${BRANCH}.name >/dev/null 2>&1 || uci set autoupdater.settings.branch='stable' && uci commit autoupdater
