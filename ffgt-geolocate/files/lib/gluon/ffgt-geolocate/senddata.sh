#!/bin/sh
# This script is supposed to be run every 5 minute via micron.d.
#
# Sent WiFi info once per boot.
# If is_mobile node, fetch location and fill in geoloc data, DO NOT commit.
# If is_mobile, do this every 5 Minutes. Otherwise, it can be manually requested in geoloc.
SETUPMODE="`/sbin/uci get gluon-setup-mode.@setup_mode[0].enabled 2>/dev/null`"
UPSECS=$(cut -d ' ' -f 1 /proc/uptime)
UPSECS=$(printf %.0f $UPSECS)
if [ $SETUPMODE -eq 0 -a $UPSECS -lt 300 ]; then exit 0 ; fi
# Need at least 5 mins (300 sec) of uptime for things to have settled outside config-mode.
CURMIN=`/bin/date +%M`
MODULO=`/usr/bin/expr ${CURMIN} % 5`
MOBILE="$(/sbin/uci get gluon-node-info.@location[0].is_mobile 2>/dev/null || echo 0)"
RUNNOW=1
ISCONFIGURED="`/sbin/uci get gluon-setup-mode.@setup_mode[0].configured 2>/dev/null`"
if [ "$ISCONFIGURED" != "1" ]; then
 ISCONFIGURED=0
fi
DIDENABLEWIFI=0

# Don't run if run already ...
if [ -e /tmp/geoloc.sh -o -e /tmp/run/wifi-data-sent ]; then
 RUNNOW=0
fi

# ... unless forced or ...
if [ $# -eq 1 ]; then
 FORCERUN=1
 RUNNOW=1
else
 FORCERUN=0
fi

# ... it's supposed to be a mobile device
if [ ${MOBILE} -eq 1 ]; then
 RUNNOW=1
fi

if [ ${RUNNOW} -eq 0 ]; then
 exit 0
fi

## RUNNOW == 1
IPVXPREFIX="`/lib/gluon/ffgt-geolocate/ipv5.sh`"
if [ "Y$IPVXPREFIX" == "Y" -o "$IPVXPREFIX" == "ipv5." ]; then
 logger "$0: IPv5 not implemented."
 exit 1
fi

# Delay run by a random number of seconds (1..10)
sleep $(/bin/grep -m1 -ao '[0-9]' /dev/urandom | /bin/sed s/0/10/  | /usr/bin/head -n1)

MAC=`/sbin/uci get network.bat0.macaddr`
# Fuuuu... iw might not be there. If so, let's fake it.
if [ -e /usr/sbin/iw ]; then
 SCANIF="`/usr/sbin/iw dev | /usr/bin/awk 'BEGIN{idx=1;} /Interface / {iface[idx]=$2; ifacemap[$2]=idx; idx++}; END{if(ifacemap["client0"]>0) {printf("client0\n");} else if(ifacemap["client1"]>0) {printf("client1\n");} else if(ifacemap["wlan0"]>0) {printf("wlan0\n");} else {printf("%s\n", iface[idx-1]);}}'`"
 /usr/sbin/iw ${SCANIF} scan 2>/dev/null >/dev/null
 if [ $? -ne 0 ]; then
  /sbin/ifconfig ${SCANIF} up
  DIDENABLEWIFI=1
  sleep 5
 fi
 wget -q -O /dev/null "`/usr/sbin/iw dev ${SCANIF} scan | /usr/bin/awk -v mac=${MAC} -v ipv4prefix=${IPVXPREFIX} -f /lib/gluon/ffgt-geolocate/preparse.awk`" && /bin/touch /tmp/run/wifi-data-sent
 if [ ${DIDENABLEWIFI} -eq 1 ]; then
   /sbin/ifconfig ${SCANIF} down
   DIDENABLEWIFI=0
 fi

 # On success only ...
 if [ -e /tmp/run/wifi-data-sent ]; then
  CURLAT="`/sbin/uci get gluon-node-info.@location[0].longitude 2>/dev/null`"
  if [ "X${CURLAT}" = "X" -o ${MOBILE} -eq 1 -o ${FORCERUN} -eq 1 ]; then
   /bin/cat /dev/null >/tmp/geoloc.sh
   sleep 2
   wget -q -O /tmp/geoloc.out "http://setup.${IPVXPREFIX}4830.org/geoloc.php?list=me&node=${MAC}"
   if [ -e /tmp/geoloc.out ]; then
    # Actually, we might want to sanity check the reply, as it could be empty or worse ... (FIXME)
    HASLOCATION="`/sbin/uci get gluon-node-info.@location[0] 2>/dev/null`"
    if [ "${HASLOCATION}" != "location" ]; then
     echo "/sbin/uci add gluon-node-info location" >>/tmp/geoloc.sh
    fi
    # Honour existing share_location setting; if missing, create & set to '1'
    HASSHARE="`/sbin/uci get gluon-node-info.@location[0].share_location >/dev/null 2>&1; echo $?`"
    if [ "${HASSHARE}" != "0" ]; then
     echo "/sbin/uci set gluon-node-info.@location[0].share_location=1" >>/tmp/geoloc.sh
    fi
    grep "LAT: 0" </tmp/geoloc.out >/dev/null 2>&1
    if [ $? -ne 0 ]; then
     /usr/bin/awk </tmp/geoloc.out '/^LAT:/ {printf("/sbin/uci set gluon-node-info.@location[0].latitude=%s\n", $2);} /^LON:/ {printf("/sbin/uci set gluon-node-info.@location[0].longitude=%s\n", $2);}' >>/tmp/geoloc.sh
     /usr/bin/awk </tmp/geoloc.out '/^ADR:/ {printf("/sbin/uci set gluon-node-info.@location[0].addr=%c%s%c\n", 39, substr($0, 6), 39);} /^CTY:/ {printf("/sbin/uci set gluon-node-info.@location[0].city=%c%s%c\n", 39, substr($0, 6), 39);}' >>/tmp/geoloc.sh
     /usr/bin/awk </tmp/geoloc.out '/^LOC:/ {printf("/sbin/uci set gluon-node-info.@location[0].locode=%s\n", $2)}; /^ZIP:/ {printf("/sbin/uci set gluon-node-info.@location[0].zip=%s\n", $2);}' >>/tmp/geoloc.sh
     if [ ${MOBILE} -ne 1 -o ${FORCERUN} -eq 1 ]; then
      echo "/sbin/uci commit gluon-node-info" >>/tmp/geoloc.sh
     fi
     if [ ${MOBILE} -eq 1 -o ${FORCERUN} -eq 1 ]; then
      /bin/sh /tmp/geoloc.sh
      if [ $ISCONFIGURED -ne 1 ]; then
       loc="`/sbin/uci get gluon-node-info.@location[0].locode 2>/dev/null`"
       adr="`/sbin/uci get gluon-node-info.@location[0].addr 2>/dev/null`"
       zip="`/sbin/uci get gluon-node-info.@location[0].zip 2>/dev/null`"
       if [ "x${zip}" != "x" -a "x${adr}" != "x" ]; then
        nodeid=`echo "util=require 'gluon.util' print(string.format('%s', string.sub(util.node_id(), 9)))" | /usr/bin/lua`
        suffix=`echo "util=require 'gluon.util' print(string.format('%s', string.sub(util.node_id(), 9)))" | /usr/bin/lua`
        hostname="${zip}-${adr}-${suffix}"
        /sbin/uci set system.@system[0].hostname="${hostname}"
        if [ ${MOBILE} -ne 1 ]; then
         /sbin/uci commit system
        fi
       fi
      fi
     fi
    fi
   fi
  fi
 fi
fi
