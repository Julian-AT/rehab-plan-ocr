> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Transparente Kalenderflächen und Audio-Wiederherstellung auf dem iPhone

Nach Freigabe der [neuen Vorschau](preview/2026-09-26-s14-soft-greens-audio/README.md) wurde **Laßnitzhöhe 0.3.0, Build 2026092623**, am 26. September 2026 über den persönlichen Hotspot auf dem iPhone 17 mit iOS 26.6 installiert. Die Geräteabfrage bestätigt das Update von Build 2026092622 ohne Deinstallation. App-Kennung und beide App-Gruppen bleiben unverändert.

Die Kalenderflächen verwenden die Greens-7-Farben mit 18 % Deckkraft in Hell und 22 % in Dunkel. Der Orb erhält einen weichen, neutralen Schatten. Die Audio-Wiederherstellung erhält die bestehende Engine und bündelt Konfigurationsmeldungen, bevor sie einen nötigen Neustart ausführt. Änderungen an Darstellung und Audio sind getrennt als `c672945` und `3c8c9e5` committed; aus letzterem stammt das signierte Release-Archiv.

## Frische Sicherung und Paketprüfung

Unmittelbar vor der Installation wurden die dauerhaften App-Daten und beide App-Gruppen frisch gesichert: **98 Dateien mit 649.703.381 Byte**. SQLite-Integrität `ok` und Schema 8 sind bestätigt. Alle Sicherungsdateien wurden vor Installation und beim anschließenden Vergleich erneut gegen das SHA-256-Manifest geprüft. Frühere Sicherungen und Pakete bleiben erhalten.

Alle 72 Dateien des Installationsbundles stimmen mit dem geprüften IPA überein. Die Prüfung umfasst Signaturen, Buildnummern, App-Kennungen, App-Gruppen und Gerätefreigabe für alle vier App-Komponenten sowie Modell- und Lizenzprüfsummen. Paket-SHA-256: `4c2016adf8c1caa224b1ffb3501295ef5e54a75c16eddca15c0da86c366db38b`.

## Datenerhalt und Start

Unmittelbar nach der Installation besteht der strikte Datenvergleich: **alle 15 Datenbanktabellen, sämtliche Einstellungen und 90 dauerhafte Dateien sind unverändert**, einschließlich aller **18 Originaldateien**. Die App wurde anschließend über den Gerätedienst erfolgreich gestartet.

Auch der Vergleich nach dem ersten Start besteht: Schema 8, SQLite-Integrität, alle 15 Tabellen und sämtliche bisherigen Einstellungen sind unverändert. 88 dauerhafte Dateien sind bytegleich, eine JSON-Datei ist inhaltlich gleich. Die Diagnose-Datei enthält ausschließlich 64 neue Betriebseinträge; alle 2.590 vorhandenen Einträge sind erhalten. Alle 18 Originaldateien sowie die frische Sicherung sind unverändert. Nach dem Vergleich wurde die App wieder geöffnet.

Die abschließende Geräteabfrage bestätigt, dass der erneut gestartete App-Prozess weiterläuft.

Der Mikrofonfehler ist mit dieser Installation noch nicht als behoben nachgewiesen. Die Prüfung mit fünf Starts und echter Sprache am eingebauten iPhone-Mikrofon, sichtbarem Pegel, Transkript, Antwort und erneutem Zuhören sowie Stopp und Hintergrundwechsel bleibt offen. Die bestandenen Simulator- und Audio-Regressionsprüfungen sind in der Vorschau dokumentiert.

## Private Nachweise

Sicherung, signiertes Paket, Archivprotokoll und Geräteprüfungen liegen ausschließlich unter `artifacts/private/soft-audio-device-20260926-s14/`. Im Unterordner `delivery/` dokumentieren `authorization.json`, `device-details.json`, `installed-before.json`, `backup-manifest.json`, `before-state.json`, `preinstall-verification.json`, `install-result.json`, `installed-after.json`, `retention-after-install.json`, `first-launch.json`, `retention-after-launch.json`, `retention-after-launch-classified.json`, `final-launch.json`, `running-final.json` und `delivery-complete.json` die Freigabe, Sicherung, Installation, Datenprüfung und den erfolgreichen Start.
