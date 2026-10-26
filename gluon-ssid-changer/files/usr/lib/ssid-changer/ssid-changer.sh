#!/bin/sh

# Gluon 2018.1 / BATMAN_IV. All SSID lengths below are byte lengths.
LC_ALL=C
export LC_ALL
OFFLINE_PREFIX='FF_OFFLINE_'
UPPER_LIMIT=55
LOWER_LIMIT=45
RUN_DIR=${SSID_CHANGER_RUN_DIR:-/var/run}
LOCK="$RUN_DIR/ssid-changer.lock"
PENDING="$RUN_DIR/ssid-changer.reload"

log() {
	logger -t gluon-offline-ssid -- "$*"
}

# micron may start another instance while this one is still running.
mkdir "$LOCK" 2>/dev/null || exit 0
WORK=
cleanup() {
	[ -z "$WORK" ] || rm -rf "$WORK"
	rmdir "$LOCK"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM
WORK=$(mktemp -d "$RUN_DIR/ssid-changer.XXXXXX") || exit 1

NODENAME=$(uname -n) || exit 1
OFFLINE_SSID="$OFFLINE_PREFIX$NODENAME"
if [ "${#OFFLINE_SSID}" -gt 32 ]; then
	SPACE=$((32 - ${#OFFLINE_PREFIX} - 3))
	FIRST=$((SPACE / 2))
	LAST=$((SPACE - FIRST))
	HEAD=$(printf '%s' "$NODENAME" | cut -b "1-$FIRST")
	TAIL=$(printf '%s' "$NODENAME" | cut -b "$((${#NODENAME} - LAST + 1))-")
	OFFLINE_SSID="$OFFLINE_PREFIX$HEAD...$TAIL"
fi

# Command errors or an unsupported selected-row format are not an offline
# measurement. An empty, successfully read gateway table *is* offline.
if ! batctl gwl > "$WORK/gateways"; then
	log 'Cannot read gateway table; keeping current SSIDs'
	exit 1
fi
GATEWAY_TQ=$(awk '
	/^[[:space:]]*(=>|\*)/ {
		count++
		if (!match($0, /\([[:space:]]*[0-9]+[[:space:]]*\)/)) {
			bad = 1
			next
		}
		tq = substr($0, RSTART + 1, RLENGTH - 2) + 0
		if (tq > 255) bad = 1
	}
	END {
		if (bad || count > 1) exit 1
		print count ? tq : 0
	}' "$WORK/gateways") || {
	log 'Invalid gateway TQ; keeping current SSIDs'
	exit 1
}

MODE=keep
if [ "$GATEWAY_TQ" -gt "$UPPER_LIMIT" ]; then
	MODE=online
elif [ "$GATEWAY_TQ" -lt "$LOWER_LIMIT" ]; then
	MODE=offline
fi

STATUS=0
if [ "$MODE" != keep ]; then
	# Associate each client BSS with its own UCI SSID, not radio0's SSID.
	# Alternating lines preserve spaces, tabs, '=' and regex metacharacters.
	uci -q show wireless > "$WORK/wireless" || exit 1
	awk -F= '$1 ~ /^wireless\.client_radio[0-9]+$/ && $2 == "wifi-iface" {print $1}' \
		"$WORK/wireless" > "$WORK/sections"
	: > "$WORK/ssids"
	while IFS= read -r SECTION; do
		IFNAME=$(uci -q get "$SECTION.ifname") || continue
		ONLINE_SSID=$(uci -q get "$SECTION.ssid") || continue
		case "$IFNAME" in ''|*[!a-zA-Z0-9_.-]*) continue ;; esac
		case "$ONLINE_SSID" in
			''|*'
'*) log "Invalid SSID for $SECTION; skipping"; continue ;;
		esac
		if [ "${#ONLINE_SSID}" -gt 32 ]; then
			log "SSID exceeds 32 bytes for $SECTION; skipping"
			continue
		fi
		if [ "$MODE" = online ]; then
			SSID=$ONLINE_SSID
		else
			SSID=$OFFLINE_SSID
		fi
		printf '%s\n%s\n' "$IFNAME" "$SSID" >> "$WORK/ssids"
	done < "$WORK/sections"

	for HOSTAPD in "$RUN_DIR"/hostapd-phy*.conf; do
		[ -f "$HOSTAPD" ] || continue
		# Match BSS names and whole parameter names literally. Do not touch
		# private APs, mesh SSIDs, or other fields containing similar text.
		if ! awk '
			FILENAME == ARGV[1] {
				iface = $0
				if ((getline value) > 0) ssid[iface] = value
				next
			}
			/^interface=/ {iface = substr($0, 11)}
			/^bss=/ {iface = substr($0, 5)}
			/^(ssid|ssid2)=/ {
				if (iface in ssid) $0 = "ssid=" ssid[iface]
			}
			{print}
		' "$WORK/ssids" "$HOSTAPD" > "$WORK/new.conf"; then
			STATUS=1
			continue
		fi
		if cmp -s "$HOSTAPD" "$WORK/new.conf"; then
			continue
		fi
		# Preserve permissions (configs may contain private AP credentials).
		if cp -p "$HOSTAPD" "$WORK/replacement" &&
			cat "$WORK/new.conf" > "$WORK/replacement" &&
			: > "$PENDING" && mv -f "$WORK/replacement" "$HOSTAPD"; then
			log "TQ $GATEWAY_TQ: set client SSID(s) $MODE in $HOSTAPD"
		else
			log "Failed to update $HOSTAPD"
			STATUS=1
		fi
	done
fi

# Reload once, after *all* radios. Retry on later invocations if HUP failed,
# including when the next reading is inside the hysteresis band.
if [ -f "$PENDING" ]; then
	if killall -HUP hostapd; then
		rm -f "$PENDING"
	else
		log 'hostapd reload failed; will retry'
		STATUS=1
	fi
fi
exit "$STATUS"
