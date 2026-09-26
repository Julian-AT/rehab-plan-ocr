> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Rückwechsel auf Build 2026092613

Am 26. September 2026 wurde das angeschlossene iPhone 17 zunächst auf ausdrückliche
Aufforderung auf **Laßnitzhöhe 0.3.0, Build 2026092614**, aktualisiert. Der Nutzer
bewertete den neuen Stand anschließend als insgesamt schlechter und verlangte den
Rückwechsel. **Auf dem iPhone ist wieder Build 2026092613 installiert und gestartet.**
Die [Kalender- und Gesprächsüberarbeitung](uniform-calendar-conversation.md) ist nicht
abgenommen. Auch der Quellcode wurde anschließend auf den Stand von Build 2026092613
zurückgesetzt; der verworfene Versuch bleibt in der Git-Historie nachvollziehbar.

Beide Installationen erfolgten ohne Deinstallation. App-Kennung und App-Gruppen bleiben
gleich. Die signierten Pakete und Profile wurden geprüft; App und alle drei
Erweiterungen autorisieren das angeschlossene Gerät. Das frühere Paket wurde vor dem
Rückwechsel erneut gegen seine gespeicherte SHA-256-Prüfsumme geprüft. Beide Builds
verwenden Schema 8; eine Datenbankwiederherstellung oder Rückmigration war nicht nötig.

## Frische Sicherungen und Vergleich

Vor dem ersten Update wurden 93 Dateien mit 604.364.079 Byte gesichert. Nach dem ersten
Start und vor dem Rückwechsel wurde die App regulär beendet und ihr aktueller dauerhafter
Datenstand erneut vollständig ausgelesen: 93 Dateien mit 604.367.576 Byte. Dieser Stand
bildet die frische Rückwechselsicherung. Alle Sicherungsdateien wurden über SHA-256
erneut geprüft. Gesichert wurden Documents, Application Support, Preferences, Cookies,
LanguageModeling, WebKit und beide App-Gruppen; erzeugbare Caches und temporäre Dateien
sind ausgenommen.

Der Vergleich nach dem ersten Start des wiederhergestellten Builds ist bestanden:

- Alle **15 Datenbanktabellen** sind unverändert, darunter 21 Pläne, 18 Scans,
  36 Importdatensätze und 36 gemeinsame Terminzuordnungen.
- SQLite-Integrität und Schema 8 sind unverändert.
- **83 dauerhafte Dateien** sind bytegleich; eine JSON-Datei hat denselben Inhalt
  bei anderer Serialisierung. Alle **17 Originaldateien** sind erhalten.
- Sämtliche bisherigen App-Einstellungen sind unverändert; keine neuen Schlüssel.
- Die Diagnosedatei enthält ausschließlich zusätzliche Betriebsereignisse:
  548 statt 521 Einträge. Alle bisherigen Einträge sind unverändert enthalten.

Der strikte Dateivergleich weist die erwartete Ergänzung der Diagnose zunächst als
Änderung aus. Ein separater geprüfter Vergleich bestätigt ausschließlich angehängte
Diagnoseeinträge sowie den unveränderten übrigen Datenstand. Diese Unterscheidung bleibt
in den lokalen Nachweisen erhalten. Anschließend wurde Build 2026092613 erneut geöffnet
und der laufende App-Prozess bestätigt.

## Lokale Nachweise

Sicherungen, signierte Pakete, Gerätekennungen und Bildschirmaufnahmen bleiben privat:

- `artifacts/private/fluid-device-20260926-s13/`: neues Paket und ursprüngliche Auslieferung.
- `artifacts/private/fluid-rollback-20260926-s13/`: frische Sicherung, Paketprüfung,
  Installationsnachweis, bestätigte Buildnummer, beide Vergleichsberichte und App-Start.
- `artifacts/private/quality-device-20260926-s13/Laßnitzhöhe.ipa`: wieder installierter Build.

Es wurden keine Kalenderaktionen zum Testen ausgelöst und keine gespeicherten Inhalte
aus einer älteren Sicherung überschrieben.

## Quellcode zurückgesetzt

Die drei Implementierungscommits `606565f`, `b94d43f` und `ad9d5c4` wurden durch einen
neuen Rücknahmecommit aufgehoben. Sämtliche versionierten Dateien außerhalb der README
und Dokumentation stimmen wieder exakt mit `97b2e5c` überein, einschließlich Quellcode,
Tests, Buildkonfiguration und Buildnummer 2026092613. Die Dokumentation hält den Versuch
und den erfolgten Rückwechsel fest. Das erzeugte Xcode-Projekt wurde neu generiert.
Die Kalenderprojektions- und Gesprächsregel-Prüfprogramme sowie die Rust-Formatprüfung
sind auf dem wiederhergestellten Stand erfolgreich.
