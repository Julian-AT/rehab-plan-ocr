> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# WLAN-Update vom 26. September 2026 – Build 2026092620

Nach ausdrücklicher Nutzerfreigabe wurde **Laßnitzhöhe 0.3.0, Build 2026092620**, über die Verbindung zum persönlichen Hotspot auf dem gekoppelten iPhone 17 mit iOS 26.6 installiert. Die Geräteabfrage bestätigt die neue Version. Sie ersetzt Build 2026092616 ohne Deinstallation; App-Kennung und App-Gruppen bleiben unverändert.

Das Update enthält die geprüften Änderungen an [Bedienelementen und Bild-Tracing](preview/2026-09-26-s13-interface-tracing/README.md), [vereinfachten Einstellungen](preview/2026-09-26-s13-simplified-controls/README.md), [Mikrofonwelle und Antwortposition](preview/2026-09-26-s13-voice-waveform/README.md) sowie dem [Kalendercache](preview/2026-09-26-s13-calendar-cache/README.md).

## Sicherung und Paket

Vor dem Update wurde die App regulär beendet und ihr aktueller dauerhafter Datenstand einschließlich beider App-Gruppen gesichert: **93 Dateien mit 604.647.988 Byte**. Sämtliche Sicherungsdateien wurden vor der Installation und nach dem Datenvergleich erneut gegen ihr SHA-256-Manifest geprüft.

Der Release-Archivbuild aus Commit `cf0e6f6` ist erfolgreich. Signaturen, App-Kennungen, Buildnummern, App-Gruppen und die Gerätefreigabe aller vier Komponenten sind geprüft, ebenso vier Erkennungsdateien, 15 Sprachmodelldateien und die Lizenzprüfsummen. Die 72 Dateien des Installationsbundles stimmen mit dem geprüften IPA überein. Das vorherige signierte Paket bleibt erhalten.

## Datenerhalt und Start

Nach der Installation wurde der dauerhafte Datenstand vollständig zurückgelesen. Der strikte Vergleich besteht:

- SQLite-Integrität `ok`, Schema 8 und alle **15 Datenbanktabellen unverändert**.
- **85 dauerhafte Dateien bytegleich**, darunter alle **17 Originaldateien**.
- Sämtliche bisherigen App-Einstellungen unverändert; keine neuen Einstellungsschlüssel.
- Die frische Sicherung ist weiterhin unverändert.

Die Installation ist abgeschlossen. Die anschließende Startprüfung wurde auch bei der erneuten Prüfung über den bestätigten Hotspot von iOS mit dem Grund `Locked` abgelehnt, weil das iPhone inzwischen wieder gesperrt war. Der Nutzer wurde zum Entsperren aufgefordert. Ein erfolgreicher Start dieses Builds auf dem Gerät ist daher noch nicht bestätigt; der Datenvergleich belegt den Stand unmittelbar nach der Installation.

## Private Nachweise

Sicherung, signiertes Paket, Gerätekennungen und technische Protokolle liegen ausschließlich unter `artifacts/private/calendar-cache-device-20260926-s13/`. Die wesentlichen Berichte sind `package-verification.json`, `delivery/backup-manifest.json`, `delivery/before-state.json`, `delivery/preinstall-verification.json`, `delivery/install-result.json`, `delivery/installed-after.json`, `delivery/retention-after-install.json`, `delivery/first-launch.json`, `delivery/first-launch-retry.json` und `delivery/hotspot-launch.json`.
