> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Geräteupdate vom 26. September 2026 – Build 2026092612

**Laßnitzhöhe 0.3.0, Build 2026092612, ist auf dem iPhone 17 installiert und gestartet.** Der Nutzer hat die bereitgestellte Vorschau und die Hörproben durch seine anschließende ausdrückliche Installationsaufforderung freigegeben. Die vorhandene App wurde von Build 2026092611 ohne Deinstallation aktualisiert.

## Frische Sicherung

Vor der Installation wurde die App regulär beendet. Die dauerhaften App-Daten und beide App-Gruppen wurden frisch ausgelesen: **87 Dateien, 570.969.678 Bytes**, Datenbankschema 7 und fehlerfreie SQLite-Integrität. Das Dateimanifest wurde vor der Installation und beim anschließenden Vergleich erneut vollständig geprüft.

Eine anfängliche Kopie des gesamten Containers scheiterte an einer von iOS geschützten SplashBoard-Vorschaudatei. Die vollständige Sicherung der dauerhaften Bereiche umfasst Documents, Library/Application Support, Preferences, Cookies, LanguageModeling, WebKit und beide App-Gruppen. Erzeugbare Caches, gespeicherter UI-Zustand, SplashBoard und tmp sind ausgenommen. Der unvollständige erste Versuch bleibt getrennt erhalten und wurde nicht als vollständige Sicherung gewertet.

## Paket und Installation

Das außerhalb des Finder-verwalteten Projektordners erzeugte signierte Release-Archiv besteht die strenge Signaturprüfung für App und alle drei Erweiterungen. Sämtliche Profile autorisieren das angeschlossene Gerät. Modelle und Lizenzdateien sind geprüft; auch die neuen libfvad-Hinweise sind enthalten. Alle **72 Dateien** des installierten App-Bundles stimmen mit dem geprüften privaten IPA überein.

IPA-SHA-256: `b0e39a508a90e17a28fc2d023f0ffcf4dbd01ece2ee41fcbb3dbff74b175e635`.

Die Geräteabfrage bestätigt Version 0.3.0 und Build 2026092612. Erfolgreicher Start, laufender App-Prozess und geladene Kalenderansicht sind auf dem iPhone geprüft. Das Mikrofon wurde für diese Installationskontrolle nicht gestartet.

## Datenvergleich nach dem ersten Start

Die App wurde nach dem Start regulär beendet und dieselben Datenbereiche erneut gelesen. Der strenge Vergleich ist bestanden:

- Alle **14 Tabellen** einschließlich Einstellungen sind unverändert: unter anderem **20 Pläne, 36 Importdatensätze und 17 Scans**.
- **78 dauerhafte Dateien** sind bytegleich; eine weitere JSON-Datei ist inhaltlich identisch. Alle **16 gespeicherten Originaldateien** sind erhalten.
- Schema 7, Schema-Definition und Datenbankintegrität sind unverändert.
- App-UserDefaults enthalten weder geänderte noch hinzugefügte Schlüssel; die drei gespeicherten Einstellungseinträge sind vollständig identisch.

Die App wurde anschließend wieder gestartet. Sicherungen, signiertes IPA, Gerätebild und vollständige Prüfberichte liegen ausschließlich unter dem ausgeschlossenen Verzeichnis `artifacts/private/continuous-voice-device-20260926-s12/`.

Die Installation ersetzt keine akustische Abnahme: reale Mikrofontranskription, lokale Modellfolgefragen, automatische Gesprächsrunden, Hineinsprechen, Echo-Unterdrückung sowie Kopfhörer- und Systemunterbrechungen bleiben im persönlichen Gebrauch zu prüfen. [Umsetzung und Simulatornachweise](continuous-calendar-voice.md) · [Vorschau und Hörproben](preview/2026-09-26-s12-continuous/README.md).
