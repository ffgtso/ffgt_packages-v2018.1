# ffgt-autoupdater-wifi-fallback

Kleiner WLAN-Rettungsupdater für **Gluon v2018.2.4**, speziell für Knoten mit
knappem Flash, die ihre einzige Mesh-Anbindung verloren haben. Einsatzbeispiele:
Wechsel von IBSS auf 802.11s, einer Batman-Version oder der Mesh-SSID.

Das Paket verwendet das vorhandene kleine **iw 4.14**. Es installiert weder
`iw-full` noch einen echten oder nachgebauten `wpa_supplicant`. IPv6 übernimmt
das in Gluon vorhandene netifd/odhcp6c. Der zusätzliche respondd-C-Baustein des
Vorgängers entfällt, um Platz zu sparen.

Dies ist ein vollständiges **Quellpaket**, kein fertiges IPK oder Firmware-Image.
Die Router-Kompatibilität und die Einhaltung des konkreten Flash-Limits müssen
mit dem eigenen Firmware-Build und einem Testgerät überprüft werden.

## Einbau

1. Den Ordner `ffgt-autoupdater-wifi-fallback` in den vorhandenen Site-Paketfeed
   übernehmen.
2. In `site.mk` das bisherige `tecff-autoupdater-wifi-fallback` durch
   `ffgt-autoupdater-wifi-fallback` ersetzen. Andere WLAN-Fallback-Pakete nicht
   gleichzeitig auswählen. Den übrigen Feed und die Mirror-Konfiguration behalten.
3. Den normalen Gluon-v2018.2.4-Build für das konkrete Zielgerät ausführen.
4. Vor einer Verteilung die tatsächliche Firmwaregröße und einen vollständigen
   Wiederherstellungslauf auf einem Testknoten prüfen.

Das Paket nutzt `gluon.mk` einschließlich LuaSrcDiet. Nur `files/` und `luasrc/`
werden installiert; Tests, Dokumentation und Prüfsummen kommen nicht auf den Router.
Alle Laufzeit-Abhängigkeiten sind bereits im entsprechenden Gluon/BATMAN-Aufbau
vorhanden: gluon-autoupdater/gluon-core, iw, batctl, libiwinfo-lua, luaposix,
lua-jsonc und micrond. Es wird keine neue native Hilfs-Binärdatei benötigt.

Für einen Wechsel von der alten Fassung ist ein reguläres Firmware-Upgrade der
vorgesehene Weg. Kein bloßes Kopieren über eine laufende Altinstallation: deren
`/usr/sbin/wpa_supplicant` und respondd-Modul würden dabei zurückbleiben.

## Konfiguration

Der bisherige UCI-Name und Programmname bleiben aus Kompatibilitätsgründen erhalten:

```text
config autoupdater-wifi-fallback 'settings'
        option enabled '1'
```

Konfigurationsdatei: `/etc/config/autoupdater-wifi-fallback`.

Beim ersten Gluon-Upgrade übernimmt das Paket den Aktivierungszustand des normalen
Autoupdaters. Ein vorhandenes `enabled` bleibt erhalten. Reguläre Läufe setzen
voraus, dass sowohl der Fallback als auch der normale Autoupdater aktiviert sind.

```sh
uci set autoupdater-wifi-fallback.settings.enabled='1'
uci commit autoupdater-wifi-fallback
```

Die Aufgabe läuft stündlich, zehn Minuten nach der Minutenposition des normalen
Autoupdater-Zeitplans. In der ersten Stunde nach dem Boot wird nichts verändert.
Anschließend wird ein monotoner Uptime-Zeitstempel im RAM gesetzt, wenn kein
BATMAN-Gateway per `batctl ping` erreichbar ist. Nach mindestens weiteren zwei
Stunden ohne erreichbares Gateway beginnt die erste Suchrunde. Der genaue Beginn
hängt vom stündlichen Zeitplan ab. Nach einer erfolglosen Runde wird stündlich
weiter versucht; eine wiederhergestellte Gateway-Verbindung löscht den Zähler.
Ein NTP-Zeitsprung verändert diese Wartefrist nicht.

Ein unmittelbarer Testlauf ist möglich:

```sh
/usr/sbin/autoupdater-wifi-fallback -f
# Optional einen bereits konfigurierten Autoupdater-Branch auswählen:
/usr/sbin/autoupdater-wifi-fallback -f -b stable
```

`-f` übergeht auch Aktivierung, Mindest-Uptime und Mesh-Prüfung. Es unterbricht
für die Suchrunde sämtliche WLAN-Interfaces und kann ein echtes Firmware-Update
mit Neustart auslösen. Es ist kein Trockenlauf.

## Ablauf einer Suchrunde

1. Alle über UCI und `gluon.util.find_phy` erkannten mac80211-Funkgeräte scannen.
   Ausgewählt werden offene Infrastruktur-APs, deren SSID die Zeichenfolge
   `freifunk` in beliebiger Groß-/Kleinschreibung enthält. Verschlüsselte WLANs,
   IBSS und Mesh-BSS werden ausgelassen.
2. Kandidaten nach Signalstärke sortieren und pro PHY/BSSID deduplizieren.
   Unterschiedliche BSSIDs mit derselben SSID bleiben getrennte Kandidaten.
3. `wifi down` aufrufen und auf das Verschwinden der WLAN-Interfaces warten.
   Die gespeicherten UCI-WLAN-Einstellungen werden währenddessen nicht verändert.
4. Mit `iw phy … interface add ffgtfallback type managed` die temporäre Station
   auf dem passenden Funkgerät anlegen. SSID und BSSID gehen als getrennte
   Argumente direkt an `execvp`; es findet keine Shell-Auswertung statt.
5. `iw connect` ohne `-w` starten und mit begrenzten Abfragen auf die Verbindung
   zur gewünschten BSSID warten. Bei Misserfolg folgt der nächste Kandidat.
6. Das eigene netifd-Interface `ffgt_fallback6` aktivieren. Es nutzt `dhcpv6`
   mit SLAAC-Unterstützung, ohne Präfixdelegation und ohne DHCPv4. Es wird auf
   IPv6-GUA oder ULA, eine IPv6-Default-Route sowie angekündigte DNS-Server geprüft.
7. Den vorhandenen Autoupdater mit `-f -b <Branch>` starten. Die bisherigen
   Mirrors, Schlüssel, Signaturprüfung, Geräteprüfung und Versionsprüfung gelten
   unverändert. Das Paket übernimmt keine Mirror-Adressen aus WLAN-Namen.
8. Falls der Aufruf ohne begonnenes sysupgrade zurückkehrt, den nächsten AP probieren. Auch Exitcode 0 kann
   beim historischen Autoupdater lediglich „keine neuere Firmware“ bedeuten.
   Ein Upgrade-Hook setzt vor sysupgrade eine RAM-Markierung. Solange sie vorhanden
   ist, erfolgen weder weitere AP-Wechsel noch eine WLAN-Wiederherstellung, auch
   wenn sysupgrade vor dem Neustart an procd übergibt und zurückkehrt. Der
   Abort-Hook löscht die Markierung bei einem vom Autoupdater erkannten Abbruch.
9. Am Ende IPv6-Fallback herunterfahren, die temporäre Station löschen und mit
   `wifi up` die bisherigen AP-/Mesh-Interfaces wieder aktivieren.

Die Firewall bindet die Zone `ffgtfb` ausdrücklich an `ffgtfallback`, damit
Router Advertisements und DHCPv6 schon vor einer Adresszuweisung zulässig sind.
Freigegeben werden die nötigen ICMPv6-Typen und DHCPv6-Antworten; kein Forwarding
und keine zusätzliche SSH-Freigabe. Die Konfiguration startet beim Boot nicht
automatisch. DNS-Daten und Routen werden von netifd beim Beenden wieder entfernt.

Die Erreichbarkeitsprüfung beschränkt sich auf die lokale IPv6-Konfiguration.
Ob die Mirrors tatsächlich erreichbar sind, prüft der Autoupdater selbst. Es
gibt keinen zusätzlichen Ping-/URL-Parser und keine IPv4-Fallback-Verbindung.
Mirrors müssen über das gewählte Netz per IPv6 erreichbar sein. Ein Netz ohne
angekündigten DNS-Server wird übersprungen, auch wenn ein rein numerischer
IPv6-Mirror theoretisch erreichbar wäre.

## Fristen und Fehlerbehandlung

Einzelne Status-/iw-Aufrufe werden nach höchstens 5 Sekunden beendet;
`ifup`/`ifdown` nach 15 und `wifi` nach 30 Sekunden. Assoziation und WLAN-Abbau
werden höchstens 30-mal, IPv6-Bereitschaft höchstens 60-mal geprüft, mit jeweils
zusätzlicher Sekunde Pause. Dies sind begrenzte Abfragezahlen, keine garantierten
30-/60-Sekunden-Gesamtfristen. Bei normal schneller Befehlsausführung endet ein
Versuch deutlich früher als bei ausgeschöpften Einzel-Timeouts.

Der Autoupdater hat **keinen äußeren Kill-Timeout**. Er besitzt eigene
Download-Timeouts; ein bereits gestartetes sysupgrade darf keinesfalls vom
Fallback-Skript abgebrochen werden. SIGTERM/INT/HUP beendet die Suchrunde nach
Bereinigung; während eines laufenden Autoupdaters wird dessen Rückkehr abgewartet.
Eine fcntl-Sperre verhindert überlappende Fallback-Instanzen. Ein begonnenes Upgrade
wird auch von späteren Fallback-Aufrufen respektiert. Falls sysupgrade selbst
nach dem Upgrade-Hook fehlschlägt, bleibt die RAM-Markierung vorsichtshalber
erhalten; ein Administrator muss dann den Flash-Zustand prüfen. Erst wenn
sicher kein Upgrade mehr läuft, darf `/tmp/ffgt-wifi-fallback.upgrading` entfernt
und der WLAN-Betrieb wiederhergestellt werden. Ein Neustart leert die Markierung.

Normale Fehler und Lua-Ausnahmen innerhalb einer Runde führen zu einem
Bereinigungsversuch. Bei SIGKILL, Stromausfall, einem hängenden Kernel/Driver oder
parallelen administrativen `wifi`-/Netzwerkänderungen ist das nicht garantiert.
Nach einem abgebrochenen Test können `ifdown ffgt_fallback6`, das Löschen einer
noch vorhandenen Station mittels `iw dev ffgtfallback del` und `wifi up` nötig sein.

## Prüfung und Grenzen

Die Entwicklung wurde gegen folgende Quellen abgeglichen:

- Ausgangspaket tecff: Commit `31dd4090bc361a9ef1f61078356eb9697b44b371`
  in https://github.com/ffgtso/ffgt_packages-v2018.1
- Gluon v2018.2.4: Commit `992e72f207b7185b7e456b5480df206a3aa09bc7`
- Dessen OpenWrt: `83ce31d3d88429b094f3436446294a17fa7041d4`
- Dessen Gluon-Packages: `a0ab6d6e712f9cc736e834ef3a8a5d2b4fc2a708`
- luaposix v33.2.1, netifd/odhcp6c- und firewall3-Schnittstellen dieser Version.

Das kleine iw 4.14 wurde auf dem Entwicklungsrechner mit den zugehörigen
OpenWrt-Patches gebaut; `connect` bleibt enthalten. Es wurde keine Funkverbindung
mit diesem Host-Build hergestellt.

Die 40 Regressionstests unter Lua 5.1 prüfen Auswahl, IPv6-Kriterien, Prozess-
und Argumentbehandlung, begrenzte Wartephasen, Ablauf nach Fehlern, Aufräumen,
Uptime-Wartefrist, Sperre, Konfiguration und Cron-Erzeugung. Betriebssystem- und
Router-Schnittstellen sind dabei simuliert. Ausführen im Paketordner:

```sh
lua5.1 tests/test.lua
find luasrc -type f -exec luac5.1 -p '{}' \;
```

Ergebnisse: `tests/RESULTS.txt`. Die Tests ersetzen weder einen vollständigen
Gluon-Firmware-Build noch einen Test von Treiber, Scan, Assoziation, IPv6/DNS,
Flash-Vorgang und Wiederherstellung auf dem Zielgerät. Genau diese Integration
ist vor einer Verteilung zu prüfen. Andere Gluon-Versionen und Routing-Protokolle
als BATMAN mit `bat0` sind nicht zugesichert.

Für 4-MB-Geräte ist die Größe des fertigen Images entscheidend, nicht die Größe
des ZIPs. Bootloader, Firmware-Partition, Kernel, SquashFS und Overlay müssen
zum jeweiligen Gerät passen; dieses Archiv allein kann das nicht garantieren.
