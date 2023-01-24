#!/bin/sh

if [ -e /tmp/fbwanspeed.txt ]; then
  exit 0
fi

wandefaultgw="$(ip -4 route show | grep br-wan | awk '/^default/ {ip=$0; gsub(" dev.*$", "", ip); gsub("^default via ", "", ip); printf("%s", ip);}')"
if [ "$wandefaultgw" != "" ]; then
 sleep $(expr $(echo $(hexdump -n 4 -e '"%u"' </dev/urandom) % 120))
 fbwanspeed="$(/usr/bin/get-wan-speed-fb.sh $wandefaultgw)"
 if [ "$fbwanspeed" != "" ]; then
  echo "<tr><th>Line</th><td>$fbwanspeed</td></tr>" >/tmp/fbwanspeed.txt
 fi
 t1="$(/bin/date +%s)"
 bytes="$(/bin/uclient-fetch -O /dev/null -4 --timeout=60 http://spd-tst.4830.org/100M.dat 2>&1 | awk '/^Download completed/ {bytes=$3; gsub("\(", "", bytes); printf("%d", bytes);}')"
 t2="$(/bin/date +%s)"
 echo ${bytes} ${t1} ${t2} | awk '{dt=$3-$2; if(dt==0) dt=1; printf("<tr><th>wget 100MB</th><td>%.1f MBit/sec</td></tr>\n", ($1*8)/dt/1000000);}' >>/tmp/fbwanspeed.txt
fi
