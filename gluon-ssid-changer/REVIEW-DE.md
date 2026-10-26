# Codeprüfung und Korrekturen

Prüfdatum: 26.10.2026. Umfang: vollständiges Paket `gluon-ssid-changer`, nicht
alle übrigen Pakete im Repository.

Quelle: https://github.com/FreiFunkMuenster/packages-ffms/tree/v2018.1.x/gluon-ssid-changer

Ausgecheckter Stand: `c6fe6cb169ac03114f7b34e47daa0dc8dd04553e`.
Alle fünf Originaldateien sind in der korrigierten Fassung enthalten; Lizenz
und micron-Zeitplan bleiben unverändert. Der Patch im Archiv dokumentiert die
Änderungen an Makefile und Laufzeitskript. README, Bericht und Tests ergänzen
Dokumentation und Nachprüfbarkeit.

## Befunde im Original

Zeilenangaben beziehen sich auf das ursprüngliche `ssid-changer.sh`.

| Schwere | Stelle | Fehler und Auswirkung | Korrektur |
| --- | --- | --- | --- |
| Hoch | 36–40, 59–63 | `break` beendet die gesamte Schleife am ersten bereits richtigen Funkgerät. Nachfolgende Geräte bleiben im falschen Zustand. `HUP_NEEDED=0` kann außerdem eine vorher gesetzte Änderungsmarkierung löschen. | Alle Konfigurationsdateien bearbeiten; persistente Reload-Markierung niemals wegen eines unveränderten Geräts zurücksetzen. |
| Hoch | 5, 34–74 | Die SSID von radio0 wird für sämtliche Funkgeräte verwendet. Bei unterschiedlichen Band-SSIDs wird das zweite Band nicht erkannt bzw. falsch zurückgestellt. | Online-SSID pro Client-UCI-Abschnitt und Zuordnung über dessen Interface. |
| Hoch | 35–46, 58–69 | Unquotierte Tests und Ersetzungen zerlegen SSIDs mit Leerzeichen; reguläre Ausdrücke interpretieren `.`, `*`, `[` usw. als Muster. `/`, `&` und Backslashes können sed-Ersetzungen zerstören oder verfälschen. | Wörtliche AWK-Zuweisung aus einer Datendatei statt dynamischer Regex-/sed-Ausdrücke; Variablen quotieren. |
| Hoch | 35, 42, 58, 65 | SSID-Suche ist nicht am Zeilenende verankert und berücksichtigt keine BSS-Grenzen. Ähnliche oder identische private SSIDs können versehentlich geändert werden. `cut -d= -f2` schneidet SSIDs mit `=` ab. | Exakte Parameternamen und Client-Interface-Zuordnung; volle SSID als Wert. |
| Mittel | 6 | Bei fehlender Konfiguration wird `Freifunk` geraten. Das kann eine falsche Online-SSID vorgeben. | Fehlende bzw. ungültige UCI-Werte überspringen. |
| Mittel | 18 | `${name:offset:length}` ist keine POSIX-sh-Syntax. Bei langen Namen scheitert das Skript unter z. B. dash; auf BusyBox ash kann es funktionieren. Auch die ursprünglichen `==`-Tests sind nicht POSIX-konform. | Bytebasiertes Kürzen mit `cut`; gesamte Offline-SSID maximal 32 Bytes. |
| Mittel | 24–31, 54, 77 | Keine Prüfung des batctl-Exitstatus; Fehler erscheinen als fehlendes Gateway. Ungültige oder mehrzeilige TQ-Werte führen zu fehlerhaften numerischen Tests. | Tabellenabruf separat prüfen; genau eine gültige ausgewählte TQ-Zeile im Bereich 0–255 oder kein ausgewähltes Gateway zulassen. |
| Mittel | 83 | `HUP_NEEDED` ist nicht grundsätzlich initialisiert. Wenn keine Datei passt, entsteht ein ungültiger Test. | Expliziter Zustand und persistente Reload-Markierung. |
| Mittel | 46, 69, 84 | Schreib- und Signalfehler werden nicht zuverlässig behandelt. Nach fehlgeschlagenem HUP kann die Datei bereits die Ziel-SSID enthalten; spätere Läufe versuchen dann keine Neuladung mehr. | Ersatzdatei mit erhaltenen Rechten, Statusprüfung und Wiederholung fehlgeschlagener Signalaufrufe. |
| Niedrig | 34, 57 | `$(ls ...)` zerlegt Dateinamen und behandelt leere Treffer schlecht. Das breite Muster kann nicht passende Laufzeitdateien erfassen. | Direktes quotiertes Verzeichnis-Glob `hostapd-phy*.conf` und Prüfung auf reguläre Dateien. |
| Niedrig | Makefile | `batctl` wird verwendet, aber nicht direkt als Paketabhängigkeit angegeben. | Explizites `+batctl`. |

Zusätzliche Absicherung: Sperre gegen gleichzeitige Minutenaufrufe; Behandlung
von `ssid2=`; Wiederherstellung nach geändertem Knotennamen anhand der
Client-Interface-Zuordnung. Diese Punkte sind Erweiterungen der Robustheit,
keine Behauptung, dass jeder entsprechende Fehler im Original bereits beobachtet wurde.

## Beibehaltene Semantik

Offline bei TQ < 45, online bei TQ > 55, keine Änderung bei 45–55 einschließlich.
Kein ausgewähltes Gateway entspricht TQ 0. Es wird weiterhin nur die Verbindung
zum ausgewählten Gateway bewertet. UCI bleibt die Quelle der Online-SSIDs und
wird nicht geschrieben. Die offline erzeugte SSID wird nicht dauerhaft gespeichert.

## Verifikation

22 automatisierte Testmethoden, erfolgreich unter `/bin/sh` (dash) und Bash:
44 erfolgreiche Testausführungen, teilweise mit mehreren Unterfällen.
Die Protokolle liegen unter `tests/results-sh.txt` und `tests/results-bash.txt`.
Zusätzlich POSIX-Shell-Syntaxprüfung mit `sh -n`.

Abgedeckt: beide Reihenfolgen teilweise bereits korrekter Dualband-Konfigurationen,
Neuladung erst nach allen Änderungen, Schwellwertgrenzen, kein Gateway, leere
Tabelle, batctl-Fehler, ungültige/mehrfache TQ-Zeilen, Sonderzeichen, private BSS,
Client als sekundäre BSS, hexadezimale SSID, wiederholte Ausführung ohne Änderung,
fehlende hostapd-Dateien, langer Knotenname, fehlende/ungültige UCI-SSID, leere
UCI-Zuordnung, HUP-Wiederholung, Sperre und UCI-Ausfall.

Die Zuordnung `wireless.client_radioN.ifname` wurde mit dem Gluon-v2018.1-Quelltext
abgeglichen:
https://github.com/freifunk-gluon/gluon/blob/v2018.1/package/gluon-client-bridge/luasrc/lib/gluon/upgrade/320-gluon-client-bridge-wireless

Es erfolgte kein Firmware-Build, kein tatsächlicher hostapd-/batctl-Lauf und kein
Hardwaretest. Die Tests belegen die Skriptlogik innerhalb der simulierten
Schnittstellen, keine uneingeschränkte Einsatzfreigabe. Weitere Betriebsgrenzen
stehen in README.md.
