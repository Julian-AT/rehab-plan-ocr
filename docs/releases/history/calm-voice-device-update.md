> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](retired-assets.json).

# Hotspot-Update vom 26. September 2026 – Build 2026092621

Nach ausdrücklicher Freigabe der [Simulatorvorschau und Victoria-Hörproben](previews/2026-09-26-s14-calm-voice.md) wurde **Laßnitzhöhe 0.3.0, Build 2026092621**, auf dem gekoppelten iPhone 17 mit iOS 26.6 installiert. Die Verbindung lief über den persönlichen Hotspot. Die Geräteabfrage bestätigt den Wechsel von Build 2026092620 auf 2026092621, ohne Deinstallation und mit unveränderten App-Kennungen und App-Gruppen.

Das Update enthält die gedämpften Terminfarben, die lokale Auswahl Du/Sie, die gemeinsame deutsche Antwortaufbereitung und die überarbeitete Mikrofonaufnahme mit unabhängiger Pegelmessung. Die einzelnen Implementierungen und Simulatorprüfungen sind in der Vorschau dokumentiert.

## Frische Sicherung und geprüftes Paket

Unmittelbar vor der Installation wurden die dauerhaften App-Daten und beide App-Gruppen frisch gesichert: **98 Dateien mit 649.637.483 Byte**. Die Datenbank ist integer und verwendet unverändert Schema 8. Alle Sicherungsdateien wurden vor der Installation und nach dem Datenvergleich gegen ihr SHA-256-Manifest geprüft. Frühere Sicherungen und signierte Pakete bleiben erhalten.

Der signierte Release-Archivbuild aus Commit `0f975a9` ist erfolgreich. Geprüft sind Signaturen, App-Kennungen, Buildnummern, App-Gruppen und die Freigabe dieses iPhones für alle vier Komponenten, außerdem vier Erkennungsdateien, 15 Sprachmodelldateien und die Lizenzprüfsummen. Alle 72 Dateien des Installationsbundles stimmen mit dem geprüften IPA überein. Die verwendeten Entwicklungsprofile sind bis zum 26. September 2026 gültig.

## Datenerhalt und Startprüfung

Der vollständige Vergleich unmittelbar nach der Installation besteht:

- SQLite-Integrität `ok`, Schema 8 und alle **15 Tabellen unverändert**.
- **90 dauerhafte Dateien bytegleich**, darunter sämtliche **18 Originaldateien**.
- Alle bisherigen App-Einstellungen unverändert, keine neuen Einstellungsschlüssel.
- Die frische Sicherung ist unverändert und erneut vollständig geprüft.

Die Startprüfung und ein erneuter Versuch wurden von iOS mit `Locked` abgelehnt. Das Update ist installiert; ein erfolgreicher App-Start dieses Builds auf dem Gerät ist noch nicht bestätigt. Der Nutzer wurde zum Entsperren aufgefordert.

## Ausstehende Sprachprüfung am Gerät

Der Mikrofonfehler gilt weiterhin als **nicht abschließend behoben bestätigt**. Dafür sind am eingebauten Mikrofon mindestens fünf Starts mit echter Sprache erforderlich: sichtbarer Pegel, erkanntes Transkript, passende Antwort und erneutes Zuhören. Zusätzlich müssen Du/Sie, fehlende Angaben, Frühstück I/II, Hineinsprechen, Stopp und Hintergrundwechsel geprüft werden. Eine synthetische Simulatorquelle ersetzt diese Prüfung nicht.

## Private Nachweise

Sicherungen, signiertes Paket, Gerätekennungen und technische Protokolle liegen ausschließlich unter `artifacts/private/calm-voice-device-20260926-s14/`. Maßgeblich sind `package-verification.json` sowie im Unterordner `delivery/` die Dateien `device-details.json`, `backup-manifest.json`, `before-state.json`, `preinstall-verification.json`, `install-result.json`, `installed-before.json`, `installed-after.json`, `retention-after-install.json`, `first-launch.json` und `launch-retry.json`.
