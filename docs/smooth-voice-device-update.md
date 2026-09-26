> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Geräteupdate vom 26. September 2026

**Laßnitzhöhe 0.3.0, Build 2026092611, ist auf dem iPhone 17 installiert und gestartet.** Der Nutzer hat nach der neuen Simulatorvorschau ausdrücklich um die Installation gebeten. Die bestehende App wurde ohne Deinstallation von Build 2026092609 aktualisiert.

## Sicherung und Installation

Vor der Installation wurden App-Container und beide App-Gruppen frisch gesichert: 103 Dateien, 534.520.095 Bytes. Die SQLite-Integritätsprüfung besteht. Die Sicherung, Gerätebilder und vollständigen Vergleichsberichte liegen ausschließlich unter dem ausgeschlossenen Verzeichnis `artifacts/private/smooth-voice-device-20260926-s12/delivery/`.

Alle 69 Dateien des installierten App-Archivs stimmen mit dem zuvor geprüften privaten IPA überein. App und drei Erweiterungen bestehen die strenge Signaturprüfung; die Profile waren beim Update gültig. Das IPA hat SHA-256 `4718df3ef461dd2daa18bda83547ef8dcb311ce0518165b790dc6f394e5a87e0`.

Die Geräteabfrage bestätigt Version 0.3.0 und Build 2026092611. App-Start, laufender Prozess nach erneutem Start und die geladene Kalenderansicht sind auf dem Gerät geprüft.

## Datenvergleich

Nach dem ersten Start wurde die App regulär beendet und alle drei Container erneut gelesen. Die ursprüngliche Sicherung wurde dabei nochmals vollständig gegen ihr Dateimanifest geprüft.

- Alle 13 Tabellen mit Inhalts- und Verlaufsdaten sind unverändert, einschließlich 17 Plänen, 36 Importdatensätzen und 14 Scans.
- 68 dauerhafte Dateien sind bytegleich, eine weitere JSON-Datei ist inhaltlich gleich. Alle 14 Originaldateien sind erhalten.
- Datenbankschema 7 und Integrität sind unverändert; die App-UserDefaults sind identisch.
- Alle drei Einstellungseinträge sind erhalten. Einziger geänderter Wert: `preferences.appearance`, von `dark` auf `light`. Die Zuordnung dieser Änderung zu einer Bedienhandlung wurde beim Nutzer nachgefragt und ist noch offen. Der ursprüngliche strenge Vergleich bleibt deshalb als fehlgeschlagen dokumentiert; er wurde nicht nachträglich als vollständig identisch ausgegeben.

Die App wurde anschließend wieder gestartet. Mikrofontranskription, freie Modellantworten und Audioausgabe über die gewünschten iPhone-Ausgänge sind weiterhin im persönlichen Gebrauch zu prüfen. Die fünf bestandenen Simulatorprüfungen einschließlich Victoria-Wiedergabe stehen in der [Vorschau](preview/2026-09-26-s12-smooth-voice/README.md).
