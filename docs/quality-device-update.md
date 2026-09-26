> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Geräteupdate vom 26. September 2026 – Build 2026092613

**Laßnitzhöhe 0.3.0, Build 2026092613, ist auf dem angeschlossenen iPhone 17 installiert.**
Die ausdrückliche Installationsaufforderung vom 26. September 2026 gibt die
[neue Simulatorvorschau und Victoria-Hörproben](preview/2026-09-26-s12-quality/README.md)
frei. Die vorhandene App wurde von Build 2026092612 ohne Deinstallation aktualisiert.

## Sicherung und Paketprüfung

Vor der Installation wurde die App regulär beendet. Die frische Sicherung enthält
**92 Dateien, 604.276.876 Byte** aus den dauerhaften App-Bereichen und beiden
App-Gruppen. SQLite-Integrität und Schema 7 sind geprüft. Documents, Application
Support, Preferences, Cookies, LanguageModeling und WebKit wurden vollständig
kopiert; erzeugbare Caches, gespeicherter UI-Zustand, SplashBoard und tmp gehören
nicht zur Sicherung dauerhafter Daten. Alle Sicherungsdateien wurden vor und nach
der Installation erneut gegen das SHA-256-Manifest geprüft.

Der signierte Release-Build wurde wegen störender Finder-Metadaten im Projektordner
in einem separaten temporären Buildordner erfolgreich archiviert. App und alle drei
Erweiterungen bestehen die strenge Signaturprüfung; sämtliche Profile autorisieren
das angeschlossene Gerät. 19 Modell- und 28 Lizenzdateien sind geprüft. Alle
**72 Dateien** des zur Installation verwendeten App-Bundles stimmen mit dem
geprüften IPA überein. Die vorherige signierte Version 2026092612 ist ebenfalls
gegen ihre Prüfsumme geprüft und bleibt zusammen mit den früheren Sicherungen erhalten.

IPA-SHA-256: `cd38d850dc068fd86df797225ea1b185a6a58e43ca6d80b8bfddc1dea8200d63`.
Die aktuellen Entwicklungsprofile sind bis zum 26. September 2026 gültig.

## Datenvergleich nach Installation

Die Geräteabfrage bestätigt Version 0.3.0 und Build 2026092613. Der Vergleich vor
dem ersten Start ist bestanden:

- Alle **14 bestehenden Tabellen** sind unverändert, einschließlich Einstellungen,
  **21 Plänen, 36 Importdatensätzen und 18 Scans**.
- **83 dauerhafte Dateien** sind bytegleich; eine weitere JSON-Datei ist inhaltlich identisch.
- Alle **17 gespeicherten Originaldateien** sind erhalten.
- Schema 7, Schema-Definition, SQLite-Integrität und sämtliche bisherigen
  App-UserDefaults sind unverändert; es wurden keine Einstellungsschlüssel ergänzt.

Der erste Start wurde von iOS wegen des gesperrten Geräts verweigert. Deshalb sind
Start, sichtbare App-Oberfläche und Migration auf Schema 8 noch nicht als bestanden
ausgewiesen. Das Entsperren wurde angefragt. Danach folgen erneuter Start und Vergleich
aller bisherigen Datensätze sowie der additiv angelegten gemeinsamen Terminzuordnungen.

## Nachweise und offene Abnahme

Sicherung, signiertes IPA, Bildschirmaufnahme und technische Nachweise bleiben
ausschließlich unter dem ausgeschlossenen Verzeichnis
`artifacts/private/quality-device-20260926-s13/`. Die wesentlichen Belege sind
`package-verification.json`, `delivery/backup-manifest.json`, `delivery/before-state.json`,
`delivery/preinstall-verification.json`, `delivery/install-result.json`,
`delivery/installed-after.json` und `delivery/retention-after-install.json`.

Die Installation ersetzt keine erweiterte Geräteabnahme von Mitteilungszustellung,
Mikrofon, Hineinsprechen, Audio-Unterbrechungen oder VoiceOver. Auch die im
[Qualitätsbericht](quality-overhaul.md) dokumentierte Prioritätswarnung bei Sprachtests
bleibt für die Geräteprofilierung offen. Private Originale, Datenbanken, Gerätekennungen,
Modelle und Sicherungen werden nicht versioniert.
