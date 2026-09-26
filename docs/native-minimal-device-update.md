> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Native Oberfläche auf dem iPhone 17

Am 26. September 2026 wurde **Laßnitzhöhe 0.3.0, Build 2026092608**, auf dem verbundenen iPhone 17 mit iOS 26.6 installiert und geöffnet. Die Freigabe nach Bereitstellung der [Simulatorvorschau und Hörproben](preview/2026-09-26-s12-native/README.md) lautete: „spiele es auf das iphone“. Das Update erfolgte ohne Deinstallation unter der unveränderten App-Kennung `at.rehakalender.personal`.

Die installierte Oberfläche wurde über eine direkte Bildschirmaufnahme vom iPhone geprüft. Diese Aufnahme enthält persönliche Kalenderdaten und bleibt ausschließlich im privaten Auslieferungsverzeichnis. Mikrofoneingabe, Hörbewertung und Telefonunterbrechungen wurden bei dieser technischen Installation nicht erneut getestet.

## Sicherung und Datenerhalt

Vor der Installation wurde die bisherige App regulär beendet. Die frische Sicherung umfasst den App-Container und beide App-Gruppen: **101 Dateien, 534.515.889 Byte**, jeweils mit SHA-256 erfasst. Nach Installation und erstem Start wurde die App erneut beendet, der Datenstand ausgelesen und mit der Sicherung verglichen. Danach wurde die neue App wieder geöffnet.

| Vergleich | Ergebnis |
| --- | --- |
| SQLite-Integrität und Schema | `ok`, Schema 7 unverändert |
| Datenbanktabellen | Alle 14 Tabellen vollständig unverändert |
| Pläne / Scans / Importdatensätze | 17 / 14 / 36 erhalten |
| Originalbilder | Alle 14 bytegleich erhalten |
| Dauerhafte Dateien | 68 bytegleich; ein Agenda-JSON semantisch identisch |
| Einstellungen | Sämtliche vorhandenen Schlüssel und Werte unverändert |
| Kalender- und Wiederherstellungsdaten | Import-, Operations-, Annahme- und Mutationsdaten unverändert |
| Sicherung nach Abschluss | Erneut vollständig gegen das SHA-256-Manifest geprüft |

Es wurden während der Installation keine Kalenderänderungen ausgelöst. Die beiden App-Gruppen enthielten keine Dateien. Die Nutzdaten liegen weiterhin im App-Container.

## Paket und Nachweise

Der Release-Archivbuild und die Paketprüfung waren erfolgreich. App und drei Erweiterungen sind für das verbundene iPhone signiert. Geprüft wurden außerdem App-Kennung, Version, App-Gruppen, vier Erkennungsdateien, 15 Martin/Kokoro-Dateien und die Lizenzprüfsummen.

- Umsetzung: `2ab2f7b`; geprüfte Simulatorvorschau und Tests: `b528e8c`.
- IPA-SHA-256: `917b7fbf4f924412b9b78cc62d6ec7e813f09b96bab685f31c479d14b95158d4`.
- Paketgröße: 339.917.417 Byte.
- Frühester Profilablauf: 26. September 2026, 11:56:33 UTC.

Sicherung, signiertes Paket, Bildschirmaufnahme und technische Protokolle liegen ausschließlich lokal unter `artifacts/private/native-minimal-device-20260926-s12/`. Die Nachweise umfassen `backup-manifest.json`, `before-state.json`, `retention-after-launch.json`, `device-signing-check.json`, `package-verification.json`, `installed-after.json`, `install-result.json` und `final-launch.json`. Die bisherige signierte Version 2026092607 wurde vor dem Update ebenfalls gegen ihre Prüfsumme geprüft und bleibt privat erhalten.

Zum Freigeben von Build-Speicher wurden ausschließlich erzeugte Builddateien und der eigene temporäre Vorschausimulator entfernt. Die versionierten Vorschauartefakte und sämtliche privaten Sicherungen bleiben erhalten.
