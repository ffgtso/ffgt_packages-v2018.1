# gluon-ssid-changer

Korrigierte Fassung des Pakets aus `FreiFunkMuenster/packages-ffms`, Branch
`v2018.1.x`, Commit `c6fe6cb169ac03114f7b34e47daa0dc8dd04553e`.

Das Paket wechselt bei schlechter Verbindung zum ausgewählten BATMAN_IV-Gateway
die Freifunk-Client-SSIDs auf `FF_OFFLINE_<Knotenname>` und bei ausreichender
Verbindung zurück auf die jeweiligen SSIDs aus UCI. Der Aufruf erfolgt einmal
pro Minute durch micrond. UCI wird dabei nicht verändert.

## Verhalten

| Gateway-TQ | Aktion |
| --- | --- |
| unter 45, einschließlich kein ausgewähltes Gateway | Offline-SSID setzen |
| 45 bis einschließlich 55 | aktuelle SSID beibehalten |
| über 55 | konfigurierte Online-SSID wiederherstellen |
| batctl-Aufruf fehlgeschlagen oder ausgewählte Zeile ungültig | keine SSID-Änderung; Fehler protokollieren |

Die Grenzen sind Rohwerte auf der TQ-Skala 0–255, keine Prozentwerte.
`LOWER_LIMIT`, `UPPER_LIMIT` und `OFFLINE_PREFIX` stehen oben im Skript.

Jedes `wireless.client_radioN` wird über sein UCI-`ifname` dem entsprechenden
`interface=`- oder `bss=`-Abschnitt in `/var/run/hostapd-phy*.conf` zugeordnet.
Es wird dessen eigene UCI-SSID verwendet. Private APs und andere Interfaces
bleiben unberührt, selbst wenn ihre SSID identisch ist. Sowohl `ssid=` als auch
hexadezimales `ssid2=` werden unterstützt; beim Umschalten wird `ssid=` geschrieben.
Es gibt keinen geratenen Ersatzwert für fehlende UCI-SSIDs.

Offline-SSIDs sind höchstens 32 Bytes lang. Bei langen Knotennamen bleiben Anfang
und Ende mit `...` dazwischen erhalten. SSIDs sind Bytefolgen; ein mehrbytekodierter
Knotenname kann beim Kürzen an einer Zeichengrenze getrennt werden.

Alle Funkgeräte werden vor einem gemeinsamen `HUP` bearbeitet. Ein fehlgeschlagener
Signalaufruf wird beim nächsten erfolgreichen Durchlauf erneut versucht, auch
innerhalb des Hysteresebands. Ein erfolgreicher Signalaufruf bestätigt nur die
Signalzustellung, nicht die erfolgreiche Verarbeitung durch hostapd.

## Verwendung im Firmware-Build

Den vollständigen Ordner `gluon-ssid-changer` anstelle des bisherigen Paketordners
im Feed verwenden. Die vorhandene Paketauswahl in `site.mk` beibehalten bzw.
`gluon-ssid-changer` aufnehmen und die Firmware im Gluon-2018.1-Buildsystem bauen.
Das Archiv ist Quellcode, kein vorgebautes `.ipk` und kein Firmware-Image.

Der Paketname und `PKG_VERSION=1` bleiben erhalten; `PKG_RELEASE=2` markiert die
Korrektur. `batctl` ist jetzt eine explizite Abhängigkeit. Das Installationsziel
kopiert wie bisher nur `files/`; Bericht und Tests werden nicht auf Router kopiert.

## Prüfungen

Auf einem Entwicklungsrechner mit Python 3 und POSIX-Shell:

```sh
python3 tests/test_ssid_changer.py
TEST_SHELL=/bin/bash python3 tests/test_ssid_changer.py
sh -n files/usr/lib/ssid-changer/ssid-changer.sh
```

Die Tests führen das echte Skript mit simuliertem `uci`, `batctl`, `uname`,
`logger` und `killall` aus. Sie verändern keine echten Routerkonfigurationen
und senden keine Signale an echte hostapd-Prozesse.

`SSID_CHANGER_RUN_DIR` verlegt für Tests das Laufzeitverzeichnis. Im normalen
Betrieb bleibt die Variable ungesetzt und `/var/run` wird verwendet.

## Betriebsgrenzen

- Ziel ist Gluon 2018.1 mit BATMAN_IV und dem damaligen hostapd-Konfigurationsformat.
  BATMAN_V-Durchsatzwerte sind keine TQ-Werte und werden nicht unterstützt.
- Keine Hardwareprüfung, kein vollständiger Firmware-Build und kein Test mit der
  originalen BusyBox-Version wurden hier ausgeführt. Vor Verteilung auf einem
  Testknoten mit der konkreten Firmware prüfen: Gateway-Verlust, Wiederkehr,
  beide Funkbänder, privates WLAN und tatsächliche hostapd-Neuladung.
- Das Skript verändert generierte Laufzeitdateien. Ein gleichzeitiges externes
  `wifi reload` wird durch seine eigene Sperre nicht serialisiert und kann die
  Dateien neu erzeugen. Der nächste Minutenlauf gleicht den Zustand erneut ab.
- Die Verzeichnissperre verhindert überlappende Skriptaufrufe. Nach `SIGKILL` kann
  `/var/run/ssid-changer.lock` zurückbleiben. Erst nach Prüfung, dass keine Instanz
  mehr läuft, mit `rmdir /var/run/ssid-changer.lock` entfernen; ein Neustart leert
  normalerweise `/var/run` ebenfalls.
- Gateway-TQ misst Mesh-Verbindungsqualität, nicht die Internet-Erreichbarkeit.

Details zu den ursprünglichen Fehlern: `REVIEW-DE.md`.
