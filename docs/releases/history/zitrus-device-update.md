> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](retired-assets.json).

# Zitrus & Olive auf dem iPhone – Build 2026092624

Nach Freigabe der [Simulatorvorschau](../../product/visual-baseline/README.md) wurde **Laßnitzhöhe 0.3.0, Build 2026092624**, am 26. September 2026 über den persönlichen Hotspot auf dem iPhone 17 mit iOS 26.6 installiert. Die Geräteabfrage bestätigt das Update von Build 2026092623 ohne Deinstallation.

Kalenderkarten, Tagesliste und Legende verwenden die gewählte Palette **Zitrus & Olive** mit 32 % Deckkraft in Hell und 36 % in Dunkel. „Vergangene Termine anzeigen“ erscheint grün. Der signierte Release-Build stammt aus Commit `bebe77e`; Stimme und Audioverarbeitung sind unverändert.

## Sicherung und Paketprüfung

Unmittelbar vor der Installation wurden die dauerhaften App-Daten und beide App-Gruppen frisch gesichert: **98 Dateien mit 649.749.633 Byte**. Die SQLite-Integrität ist `ok`, das Schema bleibt auf Version 8. Die Sicherung wurde vor Installation und beim Datenvergleich vollständig gegen ihr SHA-256-Manifest geprüft.

Signaturen, App-Kennungen, App-Gruppen, Buildnummern und die Gerätefreigabe aller vier App-Komponenten sind geprüft. Alle 72 Dateien des Installationsbundles stimmen mit dem verifizierten IPA überein; Modell- und Lizenzprüfsummen bestehen. Paket-SHA-256: `26de1a51680ff436e956d758a93290cea695cd949083d6f211b0e57e30f9ceaa`.

## Datenerhalt und Start

Der unmittelbare Vergleich nach der Installation besteht: **alle 15 Datenbanktabellen, sämtliche bisherigen Einstellungen und 90 dauerhafte Dateien sind unverändert**, darunter alle **18 Originaldateien**. Die App wurde anschließend erfolgreich gestartet.

Auch der Vergleich nach dem ersten Start besteht: Alle 15 Tabellen, bisherigen Einstellungen und 18 Originaldateien sind erhalten. 88 dauerhafte Dateien sind bytegleich, eine JSON-Datei ist inhaltlich gleich. Die Diagnosehistorie enthält lediglich 31 zusätzliche technische Einträge; alle 2.855 bisherigen Einträge sind unverändert. Die ursprüngliche Sicherung wurde erneut vollständig geprüft.

Für diesen Vergleich wurde die App regulär beendet. Beim anschließenden erneuten Öffnen meldete CoreDevice das iPhone über den Hotspot als nicht erreichbar. Installation, erster Start und beide Datenvergleiche sind bestätigt; die App muss auf dem iPhone manuell wieder geöffnet werden.

Die Prüfung des Mikrofons mit fünf echten gesprochenen Fragen bleibt separat offen; dieses Farbupdate liefert dafür keinen zusätzlichen Nachweis.

## Private Nachweise

Signiertes IPA, frische Sicherung und technische Protokolle liegen ausschließlich unter `artifacts/private/zitrus-device-20260926-s14/`. Das temporäre Build-Archiv wurde nach der erfolgreichen Installation entfernt; das verifizierte IPA, das Archivprotokoll und sämtliche Sicherungen bleiben erhalten.

Die technischen Nachweise umfassen Paketprüfung, Freigabe, Geräte- und Buildabfragen, Sicherungsmanifest, Prüfung vor der Installation, Installationsergebnis, ersten Start und beide Datenvergleiche. `delivery/retention-after-launch-classified.json` dokumentiert die ausschließlich ergänzte Diagnosehistorie; `delivery/delivery-complete.json` fasst den Abschluss einschließlich der später unterbrochenen Geräteverbindung zusammen.
