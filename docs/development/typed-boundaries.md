> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Native Grenzen und noch offene Umstellungen

## Bereits typisierte aktive Grenzen

- `AppleHost` überträgt Import-Snapshots, Operationen, Schreibrückgaben,
  Überschneidungen und Fotobytes als UniFFI-Werte. `NativePhoto` übernimmt
  Fotobytes direkt; die native App verwendet dafür kein Base64-JSON mehr.
- `NativeServiceError` unterscheidet Berechtigung, Eingabe, Speicherung,
  Zeitüberschreitung, unklaren Schreibabschluss und Abbruch. `NativeBridge`
  bildet diese Varianten ohne Auswertung übersetzter Meldungen auf `AppError` ab.
  `ServiceError` erhält alle zehn nativen Fehlervarianten durch Rust-Dispatch
  und zurück nach Swift. Bestehende FFI-Varianten behalten ihre Ordnungswerte.
- Die synchrone FFI-Wartebrücke ist nur für Rust-Arbeitsthreads bestimmt.
  Lese- und Erkennungsfristen sind Zeitüberschreitungen; möglicherweise bereits
  ausgeführte Kalenderänderungen bleiben ausdrücklich unklar. Ein abgelaufener
  oder abgeschlossener Aufruf nimmt keine weiteren Ergebnisse an.
- `PreferencesSaveResult` trennt dauerhaft gespeicherte Einstellungen von
  nachgelagerten Wartungswarnungen. Agenda und Widgets erhalten dabei dieselbe
  explizite Kalenderauswahl; auch eine leere Auswahl bleibt leer.

## Wiederanlauf nach bestätigten Kalenderänderungen

Die SQLite-Transaktion für Import beziehungsweise Rücknahme legt zusammen mit
den Kalenderoperationen ein versioniertes lokales Nachbearbeitungsjournal an
(`calendar_bookkeeping:*`, Formatversion 1). Es hält nur Dokument-, Termin- und
Ereignisidentitäten sowie den freigegebenen Wertehash fest. Bestätigte Operationen
bleiben bei einem späteren Speicherfehler bestätigt; der Rückgabewert ergänzt
einen Wartungshinweis.

Beim Öffnen und beim Abgleich werden gespeicherte Markierungen atomar und ohne
weitere Kalenderwirkung repariert. Geänderte Werte, entfernte Zeilen und
abgelaufene Seiten werden nicht markiert oder wiederhergestellt. Offene lokale
Aufträge erscheinen getrennt von unklaren Kalenderoperationen im Kalenderstatus.
Ein fehlgeschlagener rein lokaler Abgleich liefert einen Speicherfehler und
behält das Journal für einen weiteren Versuch.

## Serialisierung mit dauerhaftem Zweck

- SQLite-Dokumente, Kalenderjournale, Herkunftsnachweise, Wiederanlaufdaten,
  ICS-/Diagnoseexporte und Modell-Schnittstellen behalten ihre bestehenden
  Formate. Ein interner Typwechsel schreibt diese Bestände nicht um.
- Wartungswarnungen und persistierte Diagnosen bleiben lesbare Strings. Diese
  Speicherprojektion wird nicht als Fehlertransport zwischen nativen Aufrufen
  verwendet.
- Der JSON-Fotoadapter bleibt für bestehende Plattformadapter und Test-Hosts
  erhalten. Er verwendet denselben Decoder und dieselben Grenzen wie der
  Binärpfad; die native App umgeht ihn.

## Weiterhin offen

`Platform.call`, `AppleHost.calendar_event_call`,
`NativeApplication.calendar_request` und Teile von `NativeServices.perform`
transportieren aktive Kalenderbefehle weiterhin als String/JSON. Dazu gehören
Abfrage, Einzelterminauflösung, manuelle Vorschau/Bestätigung, Reparatur,
Wiederherstellung und Agenda-Abgleich. Diese Pfade sind **noch keine vollständig
typisierten Produktgrenzen**. Ihre bestehenden Bereichs-, Revisions-,
Bestätigungs- und Journalprüfungen müssen bei einer Umstellung erhalten bleiben.

`ServiceError::Legacy` hält die bisherige Verarbeitung von Domain-Fehlertexten
kompatibel. Native Callback-Fehler dürfen diesen Adapter nicht benutzen. Die
noch vorhandene textbasierte Zuordnung von Domain-Fehlern ist gesondert zu
migrieren; dieses Dokument erklärt Architekturpaket D nicht für abgeschlossen.

## Prüfungen

- `make test-native-photo`: acht Orientierungen, Pixelzuordnung, HEIF-Primärbild,
  erneute Normalisierung sowie ungültige und übergroße Eingaben.
- `make test-service-request`: einmaliger Abschluss, Wiedereintritt,
  verspätete Antworten und getrennte Lese-/Schreibfristen.
- `make test-native-bindings`: tatsächliche Swift–Rust–Swift-Übertragung aller
  nativen Fehlerarten zusammen mit Kalender-, Journal- und Revisionsfällen.
- `make test-ordered-settings`: dauerhafte Werte und getrennte Wartungswarnungen
  neben Reihenfolge, Rücknahme fehlgeschlagener Eingaben und Wiederholung.
- Rust-Integrationstest `calendar_bookkeeping`: Speicherfehler nach bestätigten
  Effekten, echtes Schließen/Öffnen der Datenbank, atomare Anlage vor dem ersten
  Effekt, geänderte beziehungsweise abgelaufene Zeilen und partielles Undo.

Die Decoderprüfungen sind Host-Prüfungen. Sie belegen keine gemessene
Leistungsverbesserung und ersetzen weder Geräteprüfung noch OCR-Produktabnahme.
