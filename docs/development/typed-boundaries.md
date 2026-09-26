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
- Kalender-Leseeffekte verwenden `Platform.query_calendar` und
  `resolve_calendar_event` über typisierte `AppleHost`-Callbacks bis zu
  `NativeServices`. Der Query enthält Kalender-IDs, UTC-Grenzen, Zeitzone,
  Auswahlrevision und eigene Terminreferenzen; die Antwort enthält Termine und
  nicht lesbare Kalender/Vorkommen. Die genaue Serieninstanz wird durch
  Kalenderkennung, externe Kennung, Vorkommenszeit und erwarteten Beginn
  aufgelöst. Die Auswahlprüfung vor und nach dem Lesen bleibt im Core.
- Agenda und Sprachantworten rufen `agenda_selection` und `query_calendar_events`
  als eigene UniFFI-Methoden auf. `AgendaQueryRequest` trägt UTC-Grenzen und einen
  optional erwarteten Scope (Kalender-IDs, Einstellungszeitzone, Auswahlrevision).
  `AgendaQueryResult` trägt den tatsächlich verwendeten Scope, die Grenzen und
  sämtliche Termine sowie Ausfallhinweise. Auswahl und Importzuordnungen kommen
  ausschließlich aus dem Core. `calendar_reads::query` liefert auch intern ein
  typisiertes Ergebnis; keine vollständige Leseantwort wird dafür zu JSON umgebaut.
- Die Agenda verlangt ihren erfassten Scope und prüft ihn vor der Veröffentlichung
  erneut. Der erste Read eines Gesprächsschritts erfasst die aktuelle Auswahl;
  alle weiteren Reads desselben Tokens, einschließlich eines separaten Referenztags,
  verlangen diese Revision. Ein Wechsel verwirft den Schritt samt Antwortcache.
  Die im Kalenderanliegen erfasste Zeitzone bestimmt weiterhin die Tagesgrenzen;
  die Einstellungszeitzone im Scope ersetzt sie nicht.
- Bereichsfehler sind typisierte Validierungsfehler, unzulässige Plattformantworten
  Speicherfehler. Ein Auswahlwechsel ist im Core `QueryError::SelectionChanged`
  und wird am nativen Eingang auf `StaleRevision` abgebildet; der Swift-Leseadapter
  zeigt eine kalenderbezogene Meldung. Native Fehlerarten bleiben unverändert.
  Die bisherigen `agendaSelection`-/`queryCalendarEvents`-Befehle delegieren an
  dieselbe Logik und behalten ihre JSON-Ergebnisform sowie Scope-Fehlertexte.
- Widgets verwenden denselben typisierten Query auf ihrer seriellen
  Kalenderqueue. Ihre Abfrage bindet sich synchron an den lokalen Auswahlstand
  (lokale Revision 0); die asynchrone App-Abfrage trägt die dauerhafte
  Auswahlrevision und verwirft überholte Antworten.

- Manuelle und gesprochene Terminänderungen teilen `EventSession` und
  `EventMutationClient`. Registrierung, Widerruf, Vorschau, Button-Bestätigung
  und Undo verwenden eigene UniFFI-Aufträge und Ergebnisse. `calendar_mutations`
  besitzt den gemeinsamen Core-Ablauf; `events::dispatch` bietet dafür nur noch
  den bisherigen Kompatibilitätseingang.
- `EventEditPatch` enthält ausschließlich editierbare Felder. Erinnerungen sind
  ausdrücklich `unchanged`, `disabled` oder `minutes`; eine leere Ortsangabe
  bleibt eine beabsichtigte Löschung. Die Bestätigung enthält ausschließlich
  den sichtbaren Button-Vertrag, Sitzung, Revision und Vorschlagstoken.
- Kalenderlisten und tatsächliche Änderungen verwenden `Platform.event_calendars`
  und `mutate_event`, die entsprechenden `AppleHost`-Callbacks und typisierte
  `NativeServices`-Methoden. Der EventKit-Worker liest die typisierten Felder
  direkt. `HostBridge.call` registriert diese beiden Stringeffekte nicht mehr.
  Auch Wiederanlauf verwendet den typisierten Mutationseffekt mit `recovery_only`.
- Die Schreibrückgabe unterscheidet `saved`, `failed`, `uncertain`, `conflict`
  und den bereits gespeicherten Prüfabschluss `acknowledged`. Dauerhafter
  Schreibstatus und nachgelagerte Erinnerungs-/Widgetwarnungen bleiben getrennt.

## Import, Überschneidungen und Agenda-Abgleich

`CalendarImportBridge` überträgt Snapshot, Importoperation und -ergebnis,
Überschneidungen, Agenda-Abgleich und lokales Vergessen direkt als `Sendable`-Werte
zu `NativeServices`. Schreibstatus, geschützte Identitäten und Wartungswarnungen
bleiben getrennt. Die älteren JSON-Eingänge delegieren an dieselben Operationen;
Kalenderjournal und Datenbank werden nicht umgeschrieben.

Die vorhandenen Schutzregeln bleiben im seriellen EventKit-Worker: Wiederanlauf
beobachtet nur, identische Wiederholung erzeugt keinen zweiten Termin, fremde
Änderungen und Alarmmetadaten verhindern überschreibende Änderungen. Nicht als
vorzeichenlose Minuten darstellbare externe Alarme erzeugen jetzt einen
Speicherfehler, statt beim FFI-Übergang in eine andere Erinnerung überzulaufen.

`make test-calendar-import-contracts`, 71 Agenda-/Wiederanlaufprüfungen und die
vollständige native Swift-6-Typprüfung mit Warnungen als Fehler sind bestanden.
Die Typprüfung umfasst den neuen EventKit-Regressionstest, beide bestehenden
Agenda-/Mitteilungstests und die Erweiterungen. Belege liegen unter
`.local/runs/import-contracts-20260926-s18-001/`. Der gemeinsame Appbuild besteht
an `a52d38b`. Die tatsächliche Simulatorausführung unter
`.local/runs/eventkit-20260926-s18-002/` besteht mit 18 Erfolgen, einem erwarteten
Dateischutz-Skip und null Fehlern, einschließlich der typisierten Importwiederaufnahme.

## Typisierte Importeffekte im Core

Vorschau, Bestätigung, Planannahme, Rücknahme und Wiederanlauf übergeben Snapshot
und Importauftrag direkt an `Platform.import_snapshot` und `apply_import`.
`HostBridge` projiziert die vorhandenen Domainwerte feldweise auf dieselben
UniFFI-Callbacks; die Stringeffekte `snapshot` und `apply` sind dort entfernt.
Bestätigte Texte, Uhrzeiten, Zeitzone, Notizen, Erinnerungen, Kalender-/Termin-
und Auftragsidentitäten sowie `recovery_only` bleiben erhalten. Schreibstatus
und Wartungswarnungen bleiben getrennt; DB-/Kalenderjournale ändern ihr Format nicht.

Nur die Standardadapter älterer `Platform`-Hosts serialisieren noch diese Aufträge.
Eine ausgelassene alte Schutzliste bedeutet weiterhin leer; eine vorhandene,
aber beschädigte Schutzliste scheitert nun ausdrücklich als Speicherfehler.
Sie kann nicht mehr stillschweigend den Schutz fremder/serieller Termine aufheben.
Unbekannte Operationen werden vor dem nativen Aufruf abgewiesen.

234 Core-/FFI-Tests, Clippy ohne Warnungen und die tatsächliche Swift-6-
Bindingsprobe bestehen. Die neue Routingprüfung erfasst sämtliche übergebenen
Felder, Recovery-Flag und separate Wartungswarnungen; ungültige Aufträge und die
entfernten Stringeffekte erreichen den Host nicht. Die bisherigen Import-, Undo-,
Wiederanlauf- und FFI-Prüfungen bestehen ebenfalls. Private Logs:
`.local/runs/typed-core-import-20260926-s18-002*.log`. Der gemeinsame iOS-Appbuild
und die vollständige Endabnahme bleiben separate Prüfungen.

## Kalenderstatus und Verlaufsverwaltung

Status, lokaler Bookkeeping-Abgleich, Wiederanlauf unklarer Terminänderungen,
manueller Prüfabschluss sowie Terminverlauf und dessen Details verwenden eigene
UniFFI-Aufträge und Ergebnisse. Kalenderzugriff, beobachtete Kalender und letzte
Lesezeit kommen über `AppleHost.calendar_status` als native Werte; gespeicherte
Auswahl und offene Journale ergänzt der Core. Die UI dekodiert diese Antworten
nicht mehr aus JSON. Die bisherigen Befehle delegieren an dieselbe Core-Logik.

Ein manueller Abschluss verlangt weiterhin den sichtbaren Bestätigungsbutton.
Er markiert nur das Journal als `acknowledged`, verändert weder den gespeicherten
Vorschlag noch den Kalender und erlaubt danach kein App-Undo. Wiederanlauf liest
nur noch offene Vorschläge als Replay-Aufträge; abgeschlossene historische
Vorschläge müssen dafür nicht dem aktuellen Replay-Decoder entsprechen.

232 Core-/FFI-Tests, Clippy ohne Warnungen, offizieller Bindingsvergleich,
Swift–Rust–Swift-Roundtrip und vollständige VoiceModel-Probe sind bestanden.
Belege: `.local/runs/calendar-administration-20260926-s18/`. Die Integration der
neuen Verwaltungsansichten und des App-Adapters kompiliert im gemeinsamen
Appbuild an `a52d38b`; dies ist noch keine bestandene UI-Abnahme.

## Kalenderberechtigung und Mitteilungszustand

`NativeBridge.requestCalendarAccess` fordert ausschließlich die Berechtigung an.
Es erstellt keinen Kalender und verändert keine gespeicherte oder sichtbare Auswahl.
Speicherziel- und Kalenderauswahlansicht verwenden anschließend die vorhandene
typisierte Kalenderliste. Der Planeditor liest sie ebenfalls direkt.

`NativeAgendaStatus`, `NativeReminderStatus` und `NativeNotificationReceipt`
übertragen die Antworten als `Sendable`-Werte. Auch die serialisierten Arbeitsabläufe
in `AgendaService` geben diese Typen zurück. Eine erlaubte Mitteilungsberechtigung
aktiviert noch keine Erinnerungen; die gespeicherten Einstellungen bestimmen die
Aktivierung. Angenommene Aufträge, bestätigte Systemvormerkungen und tatsächlich
beobachtete Zustellungen bleiben getrennte Eigenschaften.

Die bisherigen `NativeServices.perform`-Eingänge verwenden explizite
Kompatibilitätsprojektionen mit unveränderten Schlüsseln, einschließlich `error: null`.
Private Alarmjournale, Wiederanlaufdaten und der eingeschränkte Widget-Snapshot
werden dadurch nicht migriert. Die bestehenden Konkurrenztests für verzögerte,
doppelte oder überholte Mitteilungsaufträge verwenden jetzt die typisierten Antworten.

Commit `662f84f` besteht 71 Agenda-/Vertragsprüfungen und die vollständige native
iOS-26-Typprüfung einschließlich beider geänderter Integrationstestdateien,
Widget und Mitteilungsansicht: Swift 6, vollständige Nebenläufigkeitsprüfung,
Warnungen als Fehler. Der gemeinsame Appbuild besteht an `a52d38b`; die
Mitteilungstests bestehen tatsächlich im Simulatorlauf `eventkit-20260926-s18-002`.
Rohlogs und Quellhashes der Vertragsprüfung liegen unter
`.local/runs/reminder-contracts-20260926-s18-001/`.

## Typisierter Agenda-Abgleich

Die interne Nachbearbeitung nach Kalenderänderungen, Speichern der Einstellungen
und der normale Agenda-Refresh verwenden `Platform.synchronize_agenda` und den
UniFFI-Auftrag `AgendaSyncRequest`. `AgendaOwnedRecord` erhält bestätigte Werte,
Kalender-/Ereignisidentität, Herkunft, Importzuordnung und Operationsidentität auch
für manuell erzeugte Termine. Diese Bestände bleiben unabhängig von den sichtbaren
Kalendern: Ein ausgeblendeter eigener Termin wird weiterhin abgeglichen; eine leere
sichtbare Auswahl bleibt leer.

`AgendaSyncResult` führt Wartungswarnungen als getrennte Werte zurück. Bereits
bestätigte Kalenderwrites und gespeicherte Einstellungen bleiben erfolgreich,
wenn dieser nachgelagerte Abgleich scheitert. Fehlende ältere Erinnerungswerte
behalten die bisherigen Vorgaben; `null` bleibt ausgeschaltet. Ungültige
Minutenwerte werden vor dem Effekt zurückgewiesen, ohne die gespeicherten
Einstellungen umzuschreiben.

Die native Ansicht verwendet `NativeApplication.refreshAgenda`. Der alte
`calendarRequest("refreshAgenda")` bleibt ein ausdrücklich abgegrenzter
Kompatibilitätseingang: Er liefert weiterhin die vollständige bisherige JSON-
Antwort mit Snapshot, Präsentation und Erinnerungsstatus. Nur dieser Eingang
und ältere `Platform`-Hosts verwenden dafür noch den Stringcallback `agenda`.
Die App und ihre interne Nachbearbeitung verwenden diesen Callback nicht mehr.
Journale und Widgetdateien behalten ihre bestehenden Formate.

237 Core-/FFI-Tests, Clippy ohne Warnungen und der tatsächliche Swift–Rust–Swift-
Rundweg bestehen. Neue Regressionen prüfen ausgeblendete bestätigte Datensätze,
fehlende Terminidentitäten, leere Anzeigeauswahl, ausgeschaltete Erinnerungen,
Fehleridentität und unveränderte Legacyantworten. Der native Rundweg prüft zudem
sämtliche Felder eines bestätigten Imports und mehrere Wartungswarnungen.
Belege: `.local/runs/typed-agenda-effect-20260926-s19-001*.log`. Der gemeinsame
Appbuild und die vollständige Simulatorabnahme des neuen Standes folgen separat.

## Sichtbare Bearbeitung im Systemkalender

Der aktive Aufruf überträgt Kalenderkennung, externe Terminidentität,
Serienvorkommen und erwarteten Beginn als `NativeCalendarReference` an
`NativeServices.editSystemEvent`. Der serielle EventKit-Besitzer löst exakt
dieses Vorkommen auf; der Systemeditor prüft es anschließend mit seinem eigenen
MainActor-Store erneut. Es gehen keine EventKit-Objekte über die Queuegrenze.
Der sichtbare Systemeditor bleibt für Bestätigung und tatsächliche Änderungen
zuständig. Das Öffnen übernimmt weder fremde Termine noch verändert es ihre
Metadaten oder die App-Journale.

`NativeSystemEventEditAction` unterscheidet Abbruch, Speichern und Löschen. Der
Legacy-Eingang projiziert die drei bekannten Abschlüsse weiterhin auf
`{"reload": true}`. Fehler behalten ihre native Kategorie. Die Completion ist
an die konkrete Editorinstanz gebunden und wird vor Auslieferung entnommen;
doppelte oder verspätete Delegate-Aufrufe können keine spätere Sitzung abschließen.
Die neue Integration prüft ein konkretes Serienvorkommen, alle drei Antworten,
Legacyform, fehlende Identität, Fehlerart und unveränderte Kalenderdaten.
Strenge Swift-6-Typprüfung einschließlich Integrationstests und Erweiterungen
sowie die Kalenderlesevertragsprobe bestehen. Die tatsächliche EventKit-Ausführung
`system-editor-20260926-s19-001` besteht mit 20 Erfolgen, einem erwarteten
Simulator-Dateischutz-Skip und null Fehlern. Der neue Serienvorkommens-Test
ist darin enthalten; vollständiges Resultat, Quellpatch und ausführbare Produkte
bleiben privat erhalten. Der anschließende gemeinsame App-/UI-Testbuild und die
Paketprüfung über zwölf Mach-O-Dateien bestehen in
`visual-capture-control-20260926-s19-004`; dessen drei Aufnahmetests bestehen ebenfalls.
Der vollständige Endlauf und das reale Bedienen des Systemeditors bleiben separat.

## Prüfung lokaler Kalenderzuordnungen

`Platform.inspect_calendar_links` überträgt bestätigte Datensätze über den
typisierten `AppleHost`-Callback an `NativeServices.inspectCalendarLinks`.
Die Antwort enthält lesbare Kalenderkennungen und getrennte Fälle für gefunden,
gelöscht und nicht erreichbar. Bei einem Treffer werden nur Kalenderkennung,
externe Kennung und der exakte Besitzmarker übertragen. Weder ein vollständiger
Terminsnapshot noch Metadaten-JSON ist für diesen aktiven Effekt nötig.

Der EventKit-Besitzer führt die bisherige Suche auf seiner seriellen Queue aus;
EventKit-Objekte verlassen diese Queue nicht. Typisierter und älterer Eingang
verwenden dieselbe Suche. Der ältere `inspectCalendarLinks`-Eingang behält seinen
vollständigen Snapshot samt Kalenderprojektion. Der Core prüft weiterhin jede
angeforderte Identität, Vollständigkeit, Duplikate, lesbaren Zielkalender und
Besitzmarker. Ein passender Titel oder Zeitpunkt berechtigt nicht zur Übernahme.
Bestätigte Werte, Herkunft, Importhistorie, lokale Fingerprints, ausdrückliche
Auswahl und atomare Bereinigung bleiben erhalten. Nachgelagerte Wartungswarnungen
werden weiterhin getrennt vom bereits dauerhaften Abschluss gemeldet.

Die neun Reparaturregressionen verwenden einen Host, der jeden Stringeffekt
zurückweist. Zusammen mit allen anderen Core-/FFI-Fällen bestehen 239 Rusttests,
Workspace-Clippy ohne Warnungen, offizielle Bindings samt Konsistenzprüfung und
der echte Swift–Rust–Swift-Rundweg. Dieser prüft vollständige bestätigte Datensätze
und alle zehn Fehleridentitäten auch für die neue Prüfung. Strenge Swift-6-
Typprüfung einschließlich nativer Integration und Erweiterungen besteht ebenfalls.
Beleg: `typed-calendar-links-20260926-s19-001`, Prüfserie `checks2`. Die tatsächliche
EventKit-Ausführung `typed-calendar-links-20260926-s19-002` besteht mit 20 Erfolgen,
einem erwarteten Dateischutz-Skip und null Fehlern. Sie vergleicht beide Eingänge
für eindeutige Marker, fehlende Kalender und mehrdeutige Treffer; Notizen, Alarme
und fremde Termine bleiben erhalten. Gemeinsamer App-/UI-Testbuild und der echte
Reparaturdialog bestehen in `calendar-links-ui-20260926-s19-001` mit einem Erfolg ohne
Skip. Der Dialogfall prüft den Hinweis auf nicht erreichbare Kalender; er ersetzt
keine vollständige Bestätigungs-/Geräteabnahme. Quellen, Resultate und ausführbare
Produkte sind separat erhalten. Der erste
Simulatorstart wurde vor Kompilierung beendet, um den fehlenden expliziten
Dateieintrag im Integrationstestprojekt zu ergänzen; er ist kein bestandener Test.

Auch Anzeige und Bestätigung des Reparaturberichts verwenden jetzt eigene
UniFFI-Methoden: `inspectCalendarRepair` und `confirmCalendarRepair`. Bericht,
Probleme und ausgewählte Identitäten samt Fingerprint werden direkt übertragen.
Die sichtbare Auswahl und der bestehende Bestätigungsdialog bleiben erhalten;
`Confirmation::MissingVisibleButton` kann keine Bereinigung autorisieren.
Die bisherigen JSON-Befehle delegieren an denselben typisierten Core-Ablauf und
behalten ihre Ergebnisform. Bestätigte Werte, Importhistorie und Journale werden
nicht migriert. Leere, doppelte und veraltete Auswahl wird vor der Änderung
abgewiesen; spätere Wartungsfehler bleiben vom dauerhaften Ergebnis getrennt.

240 Core-/FFI-Tests einschließlich zehn Reparaturregressionen, Workspace-Clippy,
offizieller Bindingsvergleich und der echte Swift–Rust–Swift-Rundweg bestehen
in `typed-repair-report-20260926-s19-002`. Die native Probe bestätigt die Auswahl,
öffnet den Bestand erneut und prüft erhaltene Importhistorie und Wartungswarnungen.
Der erste Compilerlauf fehlte wegen einer unbehandelten ungültigen Bestätigungsart;
dieser Fall ist ergänzt und wird ausdrücklich zurückgewiesen. Der gemeinsame
App-/UI-Testbuild und der Reparaturdialog für nicht erreichbare Kalender bestehen
in `repair-report-ui-20260926-s19-001`: ein Test, null Fehler und null Skips. Das
aufbewahrte Simulatorpaket besteht die Prüfung sämtlicher zwölf Mach-O-Dateien,
Modelle, Notices und Datenschutzmanifeste. Quellen, vollständiges Resultat und
Produkte bleiben erhalten; der UI-Fall ersetzt keine Bestätigungs-/Geräteabnahme.

## Weitere Seiten eines vorhandenen Plans

Fotoeingang und PDF-Eingang rufen `NativeApplication.appendPages` mit typisierter
Plan-/Seitenidentität auf. Der aktive Swift-Wrapper mit Stringbefehl und
JSON-Zähler entfällt. Die neue Methode verwendet denselben Core-Ablauf wie der
bisherige `appendPlanPages`-Kompatibilitätseingang. Lebenszyklussperre, atomare
Zuordnung, Seitenreihenfolge, Zwölf-Seiten-Grenze und Verwerfen betroffener
Vorschläge bleiben dort erhalten; Speicherformate ändern sich nicht.

Neue Regressionen prüfen Anhängen über eine Unterseite, wiederholte Seiten,
erhaltene Geschwister und unveränderte Prüfdaten nach erneutem Öffnen. Fehlende,
gelöschte und bereits anders gruppierte Seiten sowie Anhängen während einer
laufenden Datenlöschung werden ohne Teiländerung zurückgewiesen. 242 Core-/FFI-
Tests, Workspace-Clippy, offizielle Bindings und der tatsächliche native Rundweg
bestehen in `typed-plan-pages-20260926-s19-002`. Die Swift-Probe hängt echte lokal
gespeicherte Eingänge an, vergleicht den Legacy-Zähler und prüft nach erneutem
Öffnen die Seitenfolge sowie unveränderte Termine und Prüfrevision. Gemeinsamer
App-/UI-Testbuild, zwei bestehende Simulatorfälle für Mehrseitenansicht und
Originalzugriff sowie die Paketprüfung über zwölf Mach-O-Dateien, Ressourcen und
Notices bestehen in `plan-pages-ui-20260926-s19-001`. Die UI-Fälle prüfen die Ansichten;
das Anhängen selbst ist im echten FFI-Rundweg geprüft. Quellen, vollständiges
Resultat und ausführbare Produkte bleiben separat erhalten.

## Ausstehende Mitteilungslinks

Die App liest und quittiert ausstehende Terminidentitäten über
`NativeBridge.pendingEventOpen` und den typisierten `NativeServices`-Callback.
Der serielle Journalbesitzer liefert einen optionalen String; ausschließlich der
Kompatibilitätseingang `perform("pendingEventOpen")` projiziert ihn auf das
bisherige JSON mit `id: null` beziehungsweise einer Zeichenkette. Das Journalformat
bleibt unverändert. Eine fehlgeschlagene Speicherung stellt die ausstehende
Identität im Arbeitsspeicher wieder her; eine fremde Quittierung verändert nichts.

Interne Mitteilungsidentitäten werden vor der Navigation als UUID geprüft und
als `AgendaLink.event` weitergegeben. Externe URLs behalten den strengen
`AgendaLink`-Decoder; intern ist keine URL-Konstruktion mit erzwungenem Unwrap mehr
nötig. Die gemeinsame Auflösung und Quittierung benutzen denselben Ablauf.
Die Integrationsregression prüft den typisierten Eingang und den Legacy-Eingang
bei Schreibfehler, Wiederholung und erneutem Öffnen. Der tatsächliche Lauf
`pending-link-20260926-s19-001` besteht 19 EventKit-Tests mit einem erwarteten
Simulator-Dateischutz-Skip und null Fehlern. Der gemeinsame App- und UI-Testbuild
ist ebenfalls erfolgreich; die vollständige UI-Ausführung läuft gesondert.
Quellhashes, vollständiges Result-Bundle und ausführbare Produkte bleiben erhalten.

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

## Lebensdauer von Erkennungsaufträgen

`registerJob(scanID)` erzeugt einen `RecognitionJob` mit einer eigenen
Versuch-ID. Import, Tracing und Wiederholung benötigen diese Registrierung.
Die Aufnahme-ID und alle gespeicherten Originale bleiben unverändert; ein
erneuter Versuch erhält eine neue Versuch-ID.

Swift registriert vor dem Einrichten des Abbruchhandlers und ruft in `defer`
`close()` auf. Abbruch vor dem Import bleibt wirksam. Ein ungestarteter Auftrag
wird beim Schließen beziehungsweise beim Freigeben seines Handles entfernt.
Nach dem Start besitzt der innere Rust-Worker den Auftrags-Lease. Ein verworfenes
äußeres Future signalisiert Abbruch; der Worker gibt die Registrierung auch bei
Dateifehlern, ungültiger Eingabe, regulärem Abschluss und Unwinding frei.

Native Vorbereitung und Core-Erkennung teilen dieselbe atomare Abbruchflagge.
Ein alter Handle kann deshalb keinen neuen Versuch derselben Aufnahme
abbrechen. `cancelJob(id:)` erwartet die Versuch-ID; unbekannte und bereits
abgeschlossene IDs erzeugen keinen Eintrag. Die Verwaltung benötigt weder
Abbruch-Tombstones noch Ablaufzeiten. `recognitionBusy()` berücksichtigt auch
die gestartete Vorbereitung vor der eigentlichen Inferenz; ein nach einem
Zeitlimit noch arbeitender Core-Worker bleibt weiterhin als beschäftigt sichtbar.

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
- JSON-Lesecallbacks bleiben nur als Standardadapter für ältere `Platform`-Hosts
  sowie als Kompatibilitätseingang von `NativeServices.perform`. Der native
  `HostBridge` registriert `queryEvents`/`getEvent` nicht mehr als Stringeffekte.
  Komplexe EventKit-Metadaten und ihr vorhandener Fingerprint behalten das
  Journalformat: Alarme, Serien, Teilnehmer und Notizen werden nicht neu
  interpretiert. In der typisierten Leseantwort bleibt nur dieses opake
  Metadatenfeld als JSON erhalten.

- `EventProposalView` bleibt eine lesende Anzeige-/Verlaufsprojektion im bisherigen
  Codable-Format. Der Sprachplaner kann minimale Felder weiterhin als Wörterbuch
  bilden; ein strenger Adapter überführt nur erlaubte Felder in `EventEditPatch`.
  Weder diese Projektion noch das Wörterbuch transportieren aktive Kalenderwrites.
- SQLite-`event_mutations` und native `event-receipts` bleiben JSON-Journale mit
  denselben Schlüsseln. `before`-Metadaten und Fingerprints werden weiterhin zum
  Schutz fremder Änderungen und zum Wiederherstellen von Alarmen/Notizen benutzt.
  Neue Typen ersetzen keine Journalversion und schreiben historische Belege nicht um.
- `calendar_reads::resolve` nimmt nun einen typisierten Termin entgegen und
  gibt einen optionalen typisierten Termin zurück. Sowohl der Bearbeitungsablauf
  als auch die vorhandenen Lese-Regressionen verwenden diese gemeinsame Grenze.
  Der bisherige `Reference::from_legacy`-Decoder ist dadurch ersetzt; Identität,
  Vorkommenszeit, erwarteter Beginn und Fehleridentität bleiben geprüft.
  `Reference::legacy` bleibt für den älteren Platform-Hostadapter erhalten.
  Die alten JSON-Hostadapter bleiben für Integrationstests und kompatible Hosts.

## Weiterhin offen

`Platform.call`, `AppleHost.calendar_event_call`,
`NativeApplication.calendar_request` und Teile von `NativeServices.perform`
transportieren weitere aktive Kalenderbefehle weiterhin als String/JSON. Dazu
gehören gemischte Archivseiten und deren Aufnahme-/Importdetails. Status,
Terminverlauf, Wiederanlauf, Kalenderlink-Reparatur und manuelle Klärung ungewisser
Terminänderungen sind bereits typisiert.
Weitere Plattformeffekte bleiben offen; Systemeditor und Besitzmarkerprüfung
verwenden die oben beschriebenen typisierten Grenzen.
Die Core-Import-/Undo-Abläufe verwenden inzwischen die typisierten
`Platform.import_snapshot`-/`apply_import`-Methoden. Der aktive
Core-Agenda-Abgleich verwendet ebenfalls typisierte Aufträge und Ergebnisse;
`calendar_event_call("agenda", ...)` bleibt ausschließlich für den ausdrücklichen
Legacy-Refresh erhalten. Die übrigen internen Grenzen müssen einschließlich
Wartungswarnungen und bestehender Legacy-Ergebnisformen separat umgestellt werden.
Diese verbleibenden Pfade sind **noch keine vollständig typisierten Produktgrenzen**. Ihre bestehenden Bereichs-, Revisions-,
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
- `make test-calendar-read-contracts` und Rust `calendar_reads`: Metadaten- und
  Identitätserhalt, typisierte Abwesenheit/Fehler, Auswahlrevision, leere Auswahl
  und Zurückweisung von Antworten außerhalb der aktuellen Auswahl.
- `make test-calendar-answers` prüft zusätzlich einen Auswahlwechsel zwischen
  Ziel- und Referenztag, A→B→A, einen widersprüchlichen Fake und Wiederanlauf mit
  einem neuen Gesprächstoken. `test-calendar-timezone` erhält Sommerzeit-,
  Tagesgrenzen- und Fortsetzungsfälle. `test-agenda-cache` verwirft auch einen
  nicht zur Anfrage passenden Antwortscope.
- Rust `recognition_jobs`/`recognition_job_tests` und `make test-native-bindings`:
  Registrierung, Vorstart-Abbruch, eigene Versuch-ID bei Wiederholung,
  unbekannte/abgeschlossene IDs, frühe Dateifehler und verworfenes Aufruf-Future.

- `make test-calendar-mutation-contracts`: Erinnerungs-Tristate, ungültige
  Felder und historische Ergebnisformen einschließlich `acknowledged`.
- Rust `event_mutations`: gleicher Sitzungsschutz, Bestätigungs- und Undoablauf
  hinter beiden Eingängen, Journal-Replay und typisierter Host ohne Stringeffekte.
- `make test-voice-flow`: echter Gesprächsautomat mit typisiertem Kalender-Fake,
  minimale Änderungen, sichtbare Bestätigung, Unterbrechung und verspätete Antworten.

Die Decoderprüfungen sind Host-Prüfungen. Sie belegen keine gemessene
Leistungsverbesserung und ersetzen weder Geräteprüfung noch OCR-Produktabnahme.

Stand 26. September 2026: Die Mutationsumstellung besteht 224 Tests aus
`reha-core` und `reha-ffi`, `cargo clippy --all-targets -- -D warnings`, den
offiziellen Bindingsgenerator mit anschließendem Konsistenzvergleich,
`test-calendar-mutation-contracts`, den echten Swift–Rust–Swift-Roundtrip
`test-native-bindings` und `test-voice-flow`. Der Roundtrip prüft zusätzlich
Vorschau, Button-Bestätigung und Journal-Replay über die neuen Callbacks.
Die Gesprächsprobe behält die bisherigen Auswahl-, Ordinal-, Bestätigungs-,
Abbruch- und Wartungsassertionen. Gemeinsamer Appbuild, EventKit-Integration
und Geräteabnahme bleiben nachgelagerte Prüfungen auf dem endgültigen Stand.

Der anschließende Query-Slice besteht 228 Core-/FFI-Tests, Clippy mit
`--all-targets -- -D warnings`, den offiziellen Bindingsgenerator samt
`check-bindings`, `test-native-bindings`, `test-agenda-cache`,
`test-agenda-projection`, `test-calendar-answers`, `test-calendar-timezone` und
`test-voice-flow`. Der native Roundtrip prüft den neuen App-Eingang neben dem
Legacy-Eingang, Scope und Bereich, opake Metadaten, Ausfallhinweise, leere Auswahl
ohne Plattformzugriff, A→B→A und sämtliche zehn nativen Fehleridentitäten.
Die neue Gesprächsregression prüft einen Auswahlwechsel zwischen Ziel- und
Referenztag, die Sperre des alten Antwortcaches und den anschließenden Neustart
mit einem neuen Token. Diese Host-Nachweise ersetzen den gemeinsamen Appbuild
und die Geräteabnahme nicht.
