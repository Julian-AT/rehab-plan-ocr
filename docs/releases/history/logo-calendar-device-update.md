> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](retired-assets.json).

# Geräteupdate vom 26. September 2026 – Build 2026092616

Nach ausdrücklicher Nutzerfreigabe wurde **Laßnitzhöhe 0.3.0, Build 2026092616**
auf dem verbundenen iPhone 17 mit iOS 26.6 installiert. Das Update ersetzt
Build 2026092613 ohne Deinstallation. App-Kennung und beide App-Gruppen bleiben
unverändert. Die [Simulatorvorschau](previews/2026-09-26-s13-logo-calendar.md)
dokumentiert Logogrün, gleichmäßige Kalendergrößen und die bestandenen UI-Prüfungen.

## Sicherung und Paketprüfung

Vor der Installation wurde die App regulär beendet. Die frische Sicherung umfasst
**93 Dateien mit 604.404.084 Byte**: Documents, Application Support, Preferences,
Cookies, LanguageModeling, WebKit sowie beide App-Gruppen. Erzeugbare Caches und
temporäre Dateien sind ausgenommen. Die Sicherung wurde vor der Installation und
nach dem Datenvergleich vollständig gegen ihr SHA-256-Manifest geprüft.

Der Releasebuild aus Commit `602fc07` ist erfolgreich archiviert. Signaturen,
App-Kennungen, App-Gruppen, Buildnummern und Profile aller vier Komponenten sind
geprüft. Die Profile autorisieren das angeschlossene iPhone. 19 Modell- und
28 Lizenzdateien entsprechen ihren Prüfsummen. Das installierte App-Bundle stimmt
mit dem geprüften IPA überein. Das vorherige signierte Paket wurde ebenfalls gegen
seine gespeicherte Prüfsumme geprüft und bleibt erhalten.

## Datenerhalt und Start

Die Geräteabfrage bestätigt Build **2026092616**. Der erste Start war erfolgreich;
eine private Bildschirmaufnahme zeigt die geladene Kalenderansicht mit Logogrün
und gleichmäßiger Stundenachse. Für den anschließenden Datenvergleich wurde die App
erneut regulär beendet und ihr dauerhafter Datenstand vollständig zurückgelesen.

- SQLite-Integrität ist `ok`; Schema 8 und alle **15 Datenbanktabellen** sind
  unverändert, darunter 21 Pläne, 18 Scans, 36 Importdatensätze und 36 Terminzuordnungen.
- **83 dauerhafte Dateien** sind bytegleich; eine JSON-Datei hat bei anderer
  Serialisierung denselben Inhalt. Alle **17 Originaldateien** sind erhalten.
- Sämtliche bisherigen App-Einstellungen sind unverändert; keine neuen Schlüssel.
- Die Diagnose enthält ausschließlich zusätzliche Betriebsereignisse:
  765 statt 730 Einträge. Alle bisherigen Einträge sind unverändert enthalten.

Der strikte Dateivergleich meldet die ergänzte Diagnosedatei zunächst als Änderung.
Der gesonderte Vergleich bestätigt ausschließlich angehängte Diagnoseeinträge und
den unveränderten übrigen Datenstand. Beide Berichte bleiben erhalten.

Beim abschließenden erneuten Öffnen war das iPhone inzwischen gesperrt; iOS lehnte
diesen Start deshalb ab. Der zuvor erfolgreiche Start und die geladene Oberfläche
sind dokumentiert. Die installierte App lässt sich nach dem Entsperren normal öffnen.

## Private Nachweise

Sicherung, signiertes Paket, Gerätekennungen und Gerätebild bleiben ausschließlich
unter `artifacts/private/logo-calendar-device-20260926-s13/`. Dazu gehören
`package-verification.json`, `delivery/backup-manifest.json`, `delivery/before-state.json`,
`delivery/preinstall-verification.json`, `delivery/install-result.json`,
`delivery/installed-after.json`, `delivery/first-launch-retry.json`,
`delivery/retention-after-launch.json` und
`delivery/retention-after-launch-classified.json`.

Es wurden keine Kalenderänderungen zum Testen ausgelöst und keine Inhalte aus
einer älteren Sicherung zurückgeschrieben. Sprachverarbeitung und Datenbankschema
wurden durch dieses Update nicht geändert.
