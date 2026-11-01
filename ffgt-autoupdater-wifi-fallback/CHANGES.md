# Änderungen in Version 6-3

- Mindestens 15 Minuten Uptime vor Gateway-/WLAN-/WAN-Aktionen, auch mit -f.
- Mindestens eine Stunde Offline-Beobachtungen aus dem minütlichen SSID-Changer.
- Neuer RAM-Status mit Boot-ID, Beobachtungszeit und Beginn der Gateway-Abwesenheit.
- Veraltete/unbekannte Statusdaten verhindern Updates; aktuelle Gateways ebenfalls.
- Gepatchter gluon-ssid-changer ist erforderlich, auch auf Geräten ohne WLAN.
- 54 simulierte Tests unter Lua 5.1; SSID-Changer zusätzlich separat getestet.

# Änderungen in Version 6-2

- Manuell angelegte WLAN-Station explizit als externes netifd-Gerät anmelden.
- Gezieltes ubus-up statt ifup mit globalem Netzwerk-Reload.
- Offline-Kriterium ausschließlich leere BATMAN-Gateway-Liste, ohne Ping.
- Keine Boot-/Ausfallwartefrist; auch -f respektiert vorhandene Gateways.
- WLAN-Hardware und aktive Interfaces vor Scan unterscheiden.
- Ohne WLAN: Default-Routen auf br-wan prüfen, offline4 und offline6 versuchen.
- WAN-Kindprozesse mit libpacketmark für Gluons IPv6-WAN-Routing starten.
- 50 simulierte Tests unter Lua 5.1; kein Firmware-Build oder Offloader-Hardwaretest.

# Änderungen gegenüber tecff Version 5

- Paketname `ffgt-autoupdater-wifi-fallback`, Version `6-1`.
- Kein `/usr/sbin/wpa_supplicant`-Ersatz; Station direkt über vorhandenes `iw`.
- Kein zusätzliches respondd-Modul und keine neue native Hilfs-Binärdatei.
- IPv6-only über netifd/odhcp6c, SLAAC, DNS und eigene Firewall-Zone.
- BSS-Auswahl auf offene Infrastruktur-WLANs mit Freifunk in jeder Schreibweise begrenzt.
- Je PHY/BSSID ein Versuch; gleiche SSID mit verschiedenen BSSIDs bleibt erhalten.
- Keine Shell-Interpolation von WLAN-Namen oder Branch-Namen.
- Begrenzte Systembefehle und Verbindungs-/IPv6-Abfragen.
- Keine Laufzeitänderung oder pauschales Revert der UCI-WLAN-Konfiguration.
- Aufräumen nach normalen Fehlern, Ausnahmen und TERM/INT/HUP.
- Upgrade-/Abort-Hooks verhindern Netzwerkänderungen nach Beginn von sysupgrade.
- Kein äußerer Kill-Timeout um den Autoupdater oder sysupgrade.
- Monotone Uptime im RAM statt Unix-Zeit/UCI-Zustand für die Ausfallfrist.
- Kein fehlerhafter Mirror-Parser oder vorgeschalteter Mirror-Ping.
- Exitcode 0 ohne begonnenes sysupgrade beendet die AP-Suchrunde nicht vorzeitig.
- Aktivierungszustand und etablierter UCI-/Programmname bleiben erhalten.
- 40 simulierte Regressionstests unter Lua 5.1; keine Hardware-Freigabe.

Betriebsdetails, Einbau und Grenzen stehen in README.md. Das Paket ist für den
beschriebenen BATMAN-/Gluon-2018.2.4-Fall ausgelegt; es ist kein allgemeiner
WLAN-Uplink-Manager und keine zugesicherte Portierung auf spätere Gluon-Versionen.
