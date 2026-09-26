> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](retired-assets.json).

# Greens-7 auf dem iPhone – Build 2026092622

Nach ausdrücklicher Freigabe der [grünen Simulatorvorschau](previews/2026-09-26-s14-greens.md) wurde **Laßnitzhöhe 0.3.0, Build 2026092622**, am 26. September 2026 über den persönlichen Hotspot auf dem iPhone 17 mit iOS 26.6 installiert. Die Geräteabfrage bestätigt das Update von Build 2026092621 ohne Deinstallation. App-Kennung und beide App-Gruppen sind unverändert.

Die fünf gelieferten Greens-7-Farben gelten für Kalenderkarten, Tagesliste und Legende. Die SwiftUI-Ansichten sind für Hell/Dunkel, kurze und überlappende Termine sowie größte Schrift geprüft. Der minimale Textkontrast beträgt 4,85:1. Der signierte Release-Archivbuild stammt aus Commit `3fcc919`.

## Sicherung und Paketprüfung

Unmittelbar vor der Installation wurden die dauerhaften App-Daten und beide App-Gruppen frisch gesichert: **98 Dateien mit 649.686.462 Byte**. SQLite-Integrität und Schema 8 sind bestätigt. Vor der Installation und bei beiden anschließenden Datenvergleichen wurde die Sicherung vollständig gegen ihr SHA-256-Manifest geprüft. Frühere Sicherungen und signierte Pakete bleiben erhalten.

Die Prüfung umfasst Signaturen, App-Kennungen, Buildnummern, App-Gruppen und die Freigabe dieses iPhones für alle vier App-Komponenten sowie vier Erkennungsdateien, 15 Sprachmodelldateien und die Lizenzprüfsummen. Alle 72 Dateien des Installationsbundles stimmen mit dem geprüften IPA überein. Die verwendeten Entwicklungsprofile gelten bis zum 26. September 2026.

## Datenerhalt und erfolgreicher Start

Unmittelbar nach der Installation besteht der strikte Vergleich: **alle 15 Datenbanktabellen, sämtliche Einstellungen und 90 dauerhafte Dateien sind unverändert**, einschließlich aller **18 Originaldateien**.

Die App wurde anschließend erfolgreich gestartet. Auch der Vergleich nach diesem ersten Start besteht:

- SQLite-Integrität `ok`, Schema 8 und alle 15 Tabellen unverändert.
- Alle bisherigen Einstellungen erhalten; keine neuen Einstellungsschlüssel.
- 88 dauerhafte Dateien bytegleich, eine JSON-Datei inhaltlich gleich.
- Die Diagnose-Datei enthält ausschließlich 53 zusätzliche Betriebseinträge; alle 2.492 bisherigen Einträge sind unverändert erhalten.
- Alle 18 Originaldateien und die frische Sicherung sind unverändert.

Nach dem Vergleich wurde die App wieder erfolgreich geöffnet; die abschließende Geräteabfrage bestätigt ihren laufenden Prozess. Die zuvor beim älteren Build blockierte Startprüfung ist damit für Build 2026092622 bestanden. Eine Prüfung des Mikrofons mit echter Sprache wurde bei diesem Farbupdate nicht durchgeführt; die im [Sprachbericht](calm-voice-device-update.md) beschriebenen Gerätetests bleiben offen.

## Private Nachweise

Sicherungen, signiertes Paket und technische Geräteprotokolle liegen ausschließlich unter `artifacts/private/greens-device-20260926-s14/`. Maßgeblich sind `archive-build.log`, `package-verification.json` sowie im Unterordner `delivery/` die Dateien `device-details.json`, `backup-manifest.json`, `before-state.json`, `preinstall-verification.json`, `install-result.json`, `installed-before.json`, `installed-after.json`, `retention-after-install.json`, `first-launch.json`, `retention-after-launch.json`, `retention-after-launch-classified.json`, `final-launch.json`, `running-final.json` und `delivery-complete.json`.
