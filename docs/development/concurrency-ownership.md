> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Zuständigkeit, Abbruch und Lebensdauer nebenläufiger Arbeit

Quellprüfung vom 26. September 2026. Diese Bestandsaufnahme betrifft eigenen
Swift-, Rust- und nativen Adaptercode. Sie ist kein Geräte-, Energie- oder
Latenznachweis. Automatisch erzeugte UniFFI-Bindings und eingebundener Fremdcode
werden nicht durch manuelle Änderungen ihrer Sendable-Deklarationen qualifiziert.

## Prüfgrundlage

Die App verwendet Swift 6 mit vollständiger Nebenläufigkeitsprüfung
(`apps/ios/project.yml`); AppleServices, RehaCore und LocalAssistant verwenden
ebenfalls Sprachmodus 6. Eine projektweite MainActor-Standardisolation oder
Approachable-Concurrency-Option ist nicht gesetzt. UI-Zustand ist ausdrücklich
MainActor-isoliert. Rusts Runtime hat zwei asynchrone Arbeitsthreads;
Datei-, Datenbank-, Modell- und synchrone Hostoperationen wechseln auf
`spawn_blocking` beziehungsweise eigene serielle native Queues.

Die Inventarsuche erfasste 14 eigene `@unchecked Sendable`-Deklarationen und
25 `Task.detached`-Stellen: 12 beziehungsweise 19 gehören zu Produkt- oder
expliziten Diagnosepfaden, zwei beziehungsweise sechs zu Tests. Die Tabellen
benennen auch die nur bedingt erfüllten Verträge; die Annotation allein belegt
weder eine sichere Lebensdauer noch wirksamen Abbruch.

Reproduzierbare Suchgrenzen:

```sh
rg -n '@unchecked Sendable|Task\.detached|DispatchSemaphore|\.sync\b' \
  apps/ios packages/apple --glob '*.swift' --glob '!RehaCore.swift'
rg -n 'Task\s*\{|Task<|while |cancel\(|deinit' apps/ios packages/apple \
  --glob '*.swift' --glob '!RehaCore.swift'
rg -n 'spawn_blocking|thread::scope|\.spawn\(' packages/rust
```

## Eigene unchecked-Sendable-Typen

| Typ und Quelle | Besitzer und Zugriff | Lebensdauer, Abbruch und Grenze |
|---|---|---|
| `SpeechInput`, `Features/Conversation/LocalSpeech.swift` | Ein `NSLock` schützt Erkennungsrequest, Detektor, Fehlerzustand und kopierten Vorlauf. Der Audiotap verarbeitet seinen Buffer vollständig unter diesem Lock. | Vorlauf auf 0,4 Sekunden begrenzt. Über `SpeechInputChannel` gehen nur skalare Beobachtungen; Überlauf beendet die Eingabe ausdrücklich. `replace(nil)` beendet den Request. |
| `VoiceActivityDetector`, `Features/Conversation/InputAudio.swift` | Die Produktionsinstanz gehört ausschließlich `SpeechInput` unter dessen Lock; die Simulatorinstanz einem einzelnen MainActor-Task. Kein interner Lock. | C-VAD, Konverter und Samples gehören derselben Instanz; `deinit` gibt das Handle frei. Neue parallele Verbraucher müssten diesen externen Besitzvertrag erhalten. |
| `ConverterInput`, dieselbe Datei | Ein Lock erlaubt genau eine Entnahme des Audiobuffers durch den synchronen Konvertercallback. | Die lokale Instanz hält den Buffer bis zum Ende des Konvertierungsaufrufs. |
| `VoiceRegexCache`, `Features/Conversation/VoiceRules.swift` | Lock um die Map; Kompilierung und Suche außerhalb des Locks auf unveränderlichen Ausdrücken. Erneute Prüfung vor Einfügen. | Höchstens 128 Einträge. Prozessweiter Cache enthält keine Gesprächsdaten. |
| `LocalDiagnostics`, `AppleServices/LocalDiagnostics.swift` | Eine Utility-Queue besitzt Events, Ladezustand und geplanten Flush. | Höchstens 5.000 Events und 14 Tage, koaleszierter Flush nach 200 ms. Enqueued Writes dürfen bis zum Abschluss weiterlaufen. Der Flush hält den Besitzer nur schwach. |
| `NativeServices`, `AppleServices/NativeServices.swift` | Unveränderliche Servicebesitzer; Kalenderformatter und dedizierter Kalender nur auf `AgendaService.queue`; Präsentation auf MainActor, Bildarbeit auf Workerqueue. | Singleton. Requests behalten ihre Completion bis zur einmaligen Auflösung. Vision erhält ein eigenes abbrechbares Requestobjekt und Zeitbudget. |
| `AgendaService`, `AppleServices/agenda-service.swift` | Serielle Queue besitzt EventKit-Store, Journal, Reservations-, Benachrichtigungs- und Snapshotzustand. Callbacks wechseln zurück auf diese Queue. | Start ist ein gesonderter Initialisierungsvertrag: AppDelegate ruft ihn vor Veröffentlichung einmal auf; Tests initialisieren ihre Instanz vor paralleler Nutzung. Der historische C-Startentry ist keine Zusage für beliebige gleichzeitige Starts. |
| `BackgroundCompletion`, dieselbe Datei | Lock schützt optionalen BGTask bei Ablauf und regulärem Abschluss. | `finish` erledigt den Hintergrundtask höchstens einmal und gibt ihn frei. |
| `NotificationDeadline`, `AppleServices/NotificationDeadline.swift` | Ausschließlich Besitzerqueue, mit `dispatchPrecondition` abgesichert. | Höchstens vier ausstehende Operationen. Zeitüberschreitung cancelt den Task, behält aber seinen Platz bis zur tatsächlichen Rückkehr. Späte Antworten erhalten einen getrennten Reparaturpfad. |
| `EventEditingService`, `AppleServices/event-editing.swift` | Dieselbe Kalenderqueue und derselbe EventKit-Store wie AgendaService. | Systemeditor bekommt eine unveränderliche Vorkommensidentität und einen separaten MainActor-Store. Der synchrone Vordergrundtest ist unten dokumentiert. |
| `LocalAssistant`, `LocalAssistant/LocalAssistant.swift` | Serielle Queue besitzt Modellpointer; jede queued Operation hält den Besitzer stark. | Unload wird hinter vorhandener Arbeit eingereiht; Freigabe erfolgt nie während nativer Generierung. Frischer KV-/Samplerzustand je Aufruf; Gewichte dürfen wiederverwendet werden. |
| `Operation`, dieselbe Datei | Unveränderlicher C-Pointer; nur die atomare C-Abbruchflagge ist von beliebigen Threads veränderlich. | Operation wird von der queued Arbeit und dem Cancelhandler gehalten. Hashprüfung kontrolliert den Status je 4-MiB-Block, Laden/Generierung erhalten dieselbe Deadline; höchstens 120 Sekunden angefordert. |
| `ControlledNotifications`, `IntegrationTests/notification-race-tests.swift` | Lock schützt Testrequests, Halteflags und Continuations. | Tests geben gehaltene Continuations ausdrücklich frei. Callbackaufruf erfolgt außerhalb des Locks. |
| `RecognitionProbeHost`, `Tests/Support/RecognitionProviderScenario.swift` | Unveränderlicher NativeBridge; Lock schützt Zähler. | Simulatorprobe besitzt den Host bis zum Ende der unabhängigen Anwendung; Kalenderwirkungen werden abgewiesen. |

Pfadpräfixe der Tabelle: Appdateien liegen unter `apps/ios`, AppleServices unter
`packages/apple/AppleServices/Sources`, LocalAssistant unter
`packages/apple/LocalAssistant/Sources`.

`NativeBridge` ist zustandslos und compilergeprüft `Sendable`.
`RecognitionTraceHost` besitzt ausschließlich einen unveränderlichen `NativeBridge`
und verwendet nun ebenfalls eine reguläre `Sendable`-Konformität; die gemeinsame
App-Kompilierung prüft diesen Adapter. Kalenderwirkungen
bleiben dort gesperrt. `ServiceRequest`
ist ebenfalls compilergeprüft: unveränderliche Argumentbytes und ein
`OSAllocatedUnfairLock` besitzen die einmalige Completion. Sie wird unter dem
Lock entnommen und außerhalb ausgeführt, damit Wiedereintritt nicht blockiert.

## Abgekoppelte Aufgaben und ihre Besitzer

| Stellen | Besitzer, Ergebnisübergabe und Ende |
|---|---|
| `App/TermineApp.swift`, ein Task | Appöffnung lässt Verzeichnisse und Ressourcenpfade auf einem Worker prüfen und übernimmt nur die fertigen Pfade. Anschließend öffnet die asynchrone FFI-Anwendung. Kein fortlaufender Worker. |
| `Features/Capture/CapturePreparation.swift`, ein Task | Kamera-Vorbereitung hält den Worker über den äußeren Task. Cancel wird weitergereicht, vor/nach dem Encoder geprüft und verspätete Auslieferung durch den Zustandsautomaten verworfen. Ein bereits laufender Systemcodec wird nicht hart unterbrochen. |
| `Features/Capture/ScanModel.swift`, 13 Tasks | Erasure-Gate lesen/beginnen/beenden; Foto-/Dateikopien, PDF-Erkennung, Seitenermittlung/-rendering, temporäre Sicherung und Share-Wiederaufnahme laufen außerhalb MainActor. Producer-Leases, Erasure-Tickets und Dokumentgenerationen besitzen diese Arbeit. Löschen wartet auf Producer, Jobs und `recognitionBusy`, bevor Arbeitsdateien entfernt werden. Dateiarbeit wird bewusst zu Ende geführt und anschließend verworfen, falls ihre Generation abgelaufen ist. |
| `Features/Conversation/SystemSpeech.swift`, ein Task | Nur kopierte Samples und unveränderliche Metadaten gehen in die Konvertierung. Der Renderaufruf wartet auf das Ergebnis, reicht Cancel weiter und kontrolliert den Zustand vor Veröffentlichung; die Schleife prüft Abbruch. |
| `Features/PlanReview/RecognitionTraceModel.swift`, ein Task | Quellenkopie in einen reservierten temporären Arbeitsbereich; danach Prüfung auf Abbruch/Schließen. `close` wartet auf den gehaltenen Trace-Task und das tatsächliche Ende des Rust-Workers, erst dann wird die Workspace-Lease freigegeben. |
| `Features/PlanReview/SourceView.swift`, zwei Tasks | Bildthumbnail und PDF-Erkennung nehmen lokale Quellenwerte entgegen. Der Besitzer reicht Abbruch an beide Worker weiter; sie prüfen davor und danach. Die Ansichten prüfen nach dem Await vor Bild-/Pfadveröffentlichung und zeigen Abbruch nicht als Fehler. Laufende Systemcodecs können weiterhin zu Ende arbeiten. Parser-/Formatprüfung liegt vor; integrierter Appbuild folgt auf dem gemeinsamen Stand. |
| `Tests/IntakeErasureProbe.swift`, zwei Tasks | Kontrollierter Writer und Eraser, explizite Semaphorefreigabe testet tatsächliches Warten auf Writer. |
| `Tests/IntakeReceiptProbe.swift`, zwei Tasks | Test wartet auf Recovery und Erasure; gemeinsame Datei-Gategeneration entscheidet den Gewinner. |
| `Tests/SpeechInputChannelProbe.swift`, ein Task | Begrenzter Testproducer; Verbraucher und Producer werden beide abgewartet. |
| `Tests/Support/RecognitionProviderScenario.swift`, ein Task | Prüft ausschließlich Dateien der Simulatorprobe; Rückkehr wird vor Modellinitialisierung abgewartet. |

Die 13 ScanModel-Stellen verwenden keinen gemeinsam beschreibbaren Buffer über
Aktorgrenzen. Dennoch ist Dateisystem-/Codecarbeit nicht zeitlich hart abbrechbar.
Aus dem sicheren Drain beim lokalen Löschen folgt keine garantierte kurze
Löschlatenz bei blockiertem Dateisystem.

## Unstrukturierte Tasks, Streams und Schleifen

- **Gespräch:** `VoiceModel` besitzt Turn- und Antworttask; Gesprächs-, Anfrage-
  und EventSession-Generationen verwerfen verspätete Antworten. Stop/Interrupt
  beendet Interpretation, Recorder und Wiedergabe. Bestätigte Kalenderaufträge
  werden über das Journal abgeschlossen und nicht durch bloßes Verschwinden
  der Ansicht zurückgenommen.
- **Interpretation:** `InterpretationRouter` wählt vor Generierung genau einen
  Anbieter. `InterpretationDeadline` besitzt Worker, Timer und Continuation,
  liefert genau einmal und entfernt den Lieferweg später Antworten. Cancel
  oder Deadline cancelt beide Tasks. Ein nicht kooperierender Anbieter kann
  trotzdem weiterarbeiten; diese Grenze ist kein harter nativer Arbeitsstopp.
- **Audioeingang:** `LocalSpeechRecorder` besitzt Streamconsumer und Watchdog.
  Mikrofon-, Segment- und Gesamtgeneration prüfen Recognitioncallbacks nach
  dem Hop auf MainActor. Cancel beendet Channel, Tap, Recognition, Watchdog
  und Simulatorproducer. Der geordnete Channel ist auf 64 Pakete begrenzt.
  `endTurn` wartet höchstens zwei Sekunden auf das tatsächliche Recognitionende.
- **Audioausgang:** `SpeechOutput` besitzt Ausgabetask, höchstens einen
  vorbereiteten Folgeabschnitt, Fortschritts- und Ausblendtask. Stop verändert
  die Generation, cancelt diese Aufgaben und ruft zusätzlich Renderer- und
  Graphstop auf. `SystemSpeechRenderer` besitzt aktive Synthesizer samt
  Delegate; 30-Sekunden-Renderdeadline und Generation begrenzen die Lieferung.
  `ConversationAudio` besitzt Graph, Player und einmalige Playbackcontinuation.
  Ein reines `Task.cancel()` ersetzt dort ausdrücklich nicht `stopPlayback()`.
- **Kalenderansicht:** `TodayModel` bindet Antworten an Anfrage, Epoche,
  Auswahlrevision und Zeitzone; Prefetch ist begrenzt. Ein separater
  Wartungstask wird koalesziert. Der Scroll-Koordinator prüft mit schwacher
  Referenz alle 50 ms auf Ende einer Geste; danach oder nach Besitzerfreigabe
  endet der Task.
- **Archiv:** `PlansModel` besitzt einen koaleszierten Refresh-Task, leitet
  Cancel weiter und veröffentlicht nur die aktuelle Generation. Paging
  verwirft Ergebnisse nach Refresh. Bestehende Zeilen bleiben sichtbar.
- **Planprüfung:** `PlanModel` und `PlanPagesModel` sammeln einen vollständigen
  Lesestand, prüfen nach jedem Await die Generation und veröffentlichen ohne
  weiteren Suspendierungspunkt. Alte Inhalte bleiben während Refresh sichtbar;
  ein bisheriger Bestätigungsvorschlag wird zu Beginn ungültig. Die Probe
  `test-plan-loading.sh` steuert jede verzögerbare Lesegrenze separat.
- **Kalenderersetzung:** `CalendarView` bindet Vergleich/Resolution an
  `ReplacementState` und aktuelle Eingaben. Bestätigtes Schreiben bleibt ein
  bis zum Journalergebnis zu bearbeitender Auftrag. Ein Export besitzt eine
  `TemporaryCalendarExport`-Lease; Close cancelt und wartet vor Dateifreigabe.
- **Bearbeitungssitzung:** `EventSessionRegistration` übernimmt einen spät
  registrierten Servertoken auch nach Cancel, um ihn anschließend explizit
  abzumelden. Cleanup läuft unabhängig vom abgebrochenen UI-Task. Der Core
  behält höchstens 32 aktive Sitzungen; bereits gestartete Worker halten eine
  widerrufbare Lease. Abmeldung entfernt den Registryeintrag, widerruft aber
  auch alle alten Leases. Es gibt keine wachsende Tombstone-Liste und keinen
  TTL, nach dessen Ablauf alte Vorschläge wieder zulässig würden.
- **Einstellungen:** `OrderedSettings` besitzt einen einzelnen Drain-Task;
  geordnete Speicherabsichten laufen bis zum Ende. Reset wartet darauf und
  verwendet eine neue Ladegeneration. Ein UI-Cancel verwirft keine bereits
  bestätigte dauerhafte Einstellung.
- **Temporäre Daten:** `AppTemporaryStore` ist ein Actor mit Besitzer-Leases und
  Erasuregeneration. Erasure schließt die Aufnahme neuer Besitzer, beendet und
  drainiert vorhandene Arbeit und entfernt danach erst Dateien.
- **Share-Erweiterung:** Ein MainActor-Task übernimmt höchstens zwölf Provider
  nacheinander. Kopieren findet innerhalb des Dateiprovidercallbacks statt,
  bevor dessen URL ungültig wird; das gemeinsame Erasureticket bleibt wirksam.
  Die sichtbare Abbruchtaste und eine 30-Sekunden-Frist je Provider beenden
  die eigene Continuation unabhängig vom Anbieter. `IntakeProviderRequest`
  besitzt einen abbrechbaren Timer-Task und nimmt höchstens einen Callback an.
  Beide neuen Zustände sind compilergeprüft Sendable; Locks schützen Resultat
  und Schreibzulassung. `IntakeWritePermit` serialisiert Widerruf und finale
  Veröffentlichung. Progress-Cancel läuft außerhalb der UI, da sein fremder
  Handler ebenfalls hängen kann. Alte Ansichtsantworten haben eine abgelaufene
  Generation. Abgebrochene Kopien entfernen nur ihren eigenen unveröffentlichten
  Ordner; veröffentlichte Receipts bleiben erhalten. Neue Providerkopien tragen
  bis zum Commit einen Marker, damit Recovery nach Prozessende keine abgebrochene
  Kopie veröffentlicht. Markierte Reste bleiben als offener Nachweis erhalten.
  Laufende Systemdateioperationen sind weiterhin nicht hart unterbrechbar.

## Synchrone Übergänge und native Lebensdauer

`NativeServiceCall.waitValue` darf nur vom synchronen Rust-Worker verwendet
werden. Es weist den Hauptthread per Vorbedingung ab und wartet mit endlicher
Frist, standardmäßig 60 Sekunden. Ein Lock entscheidet einmalig zwischen
Resultat und Ablauf; späte Antworten werden verworfen. Eine Frist beendet
keinen möglicherweise bereits ausgeführten Kalenderwrite: die typisierte
Rückgabe ist in diesem Fall `uncertainWrite`, nicht ein behaupteter Fehlschlag.
SwiftUI benutzt `NativeBridge.request` mit Continuation statt dieser Wartebrücke.

Der einzige eigene synchrone Mainqueue-Hop im Produkt ist der Vordergrundtest
von `EventEditingService`. Er läuft innerhalb der seriellen Kalenderqueue.
Die überprüften MainActor-Aufrufer warten asynchron auf diese Queue, sodass
kein zyklisches Mainqueue-Warten gefunden wurde. Der Hop bleibt potenziell
von Hauptthreadlast abhängig; daraus folgt keine gemessene Latenzgarantie.

Im Core laufen synchrone Hostcallbacks aus Agenda, Events, typisierten
Kalenderlesevorgängen und lokaler Löschung auf `spawn_blocking`. Die FFI hält
Application/Host-Referenzen für ihre gestarteten Tasks. Bereits bestätigte
Writes dürfen über das Ende des UniFFI-Aufrufers hinaus weiterlaufen; Journal
und Abgleich bestimmen anschließend ihren dauerhaften Zustand.

OCR besitzt eine aktive Workerzulassung. `service/scan.rs` setzt bei Ablauf
oder Abbruch die Flagge, behält die aktive Belegung jedoch bis zum tatsächlichen
Workerende. Die ONNX-Watchdogarbeit liegt in einem `std::thread::scope`, prüft
die Abbruchflagge und terminiert RunOptions; Scope-Ende wartet auf den Watchdog.
Neuere bestätigte Benutzerwerte werden nach der Rechenphase erneut gelesen,
bevor ein Ergebnis gespeichert wird. Der Forschungs-Sprachpfad bleibt separat
featuregesteuert und gehört nicht zum öffentlichen App-Release.

## Konkrete Befunde und verbleibende Nachweise

| Priorität | Reproduzierbarer Auslöser | Bewertung / weiterer Nachweis |
|---|---|---|
| P2 | Zwei Planseiten-Ladevorgänge überlappen; der ältere `loadScan` antwortet nach dem neueren Seitenverzeichnis. | Behoben durch `PlanPagesModel`: IDs und Reviews werden gemeinsam veröffentlicht. Die kontrollierte Probe hält beide Lesegrenzen einzeln an. |
| P2 | Ein altes `PlanModel.load` wartet in `planCalendar`, während ein neueres Laden einschließlich Vorschlag fertig wird. | Behoben: nach jedem Await Generationsprüfung und vollständige lokale Snapshotbildung. Die Probe prüft zusätzlich alte Fehler, Cancel und Inhaltserhalt. |
| P2 | In der geprüften FFI-Version wird ein Import vor der ersten oder zweiten Cancelprüfung abgebrochen oder scheitert vor der abschließenden Cleanupzeile. | Behoben in `f8a3191` durch registrierte `RecognitionJob`-Versuche mit eigener atomarer Abbruchflagge und Worker-Lease; kein Tombstone und kein TTL. `c9412b4` hält die Swift-Leases bis zum tatsächlichen Ende von Vorbereitung und Worker. Frühe Fehler, unbekannte IDs und verworfene Futures werden gezielt geprüft. |
| Offen, kein zusätzlicher bestätigter Fehler | Ein Interpretationsanbieter ignoriert Cancel auch nach Ablauf. | Ergebnislieferung ist gesperrt; der Router besitzt keine globale Zulassungsgrenze für solche Restarbeit. LocalAssistant prüft nativ Deadline/Cancel. Apples tatsächlicher Arbeitsstopp und Ressourcenverbrauch benötigen Gerätemessung. |
| P2 | Fremder Share-Dateiprovider antwortet dauerhaft nicht; zuvor blieb die einzige Schaltfläche deaktiviert. | Behoben durch sichtbaren Abbruch und eigene Deadline. Kontrollierte Probe prüft fehlende, späte, doppelte und synchrone Antworten, blockierte fremde Cancelhandler, atomaren Widerruf/Commit, Copy-Abbruch, erhaltene Originale und Erasure. |

Fokussierte Hostproben prüfen Zustandsautomaten und kontrollierte Rennen; sie
ersetzen keine Gerätetests bei Audio-Routenwechsel, Hintergrund, Sperren,
Widerruf von Berechtigungen oder längeren Sitzungen. Insbesondere sind die
Ziele 150 ms Mikrofonrückmeldung und 250 ms Wiedergabestopp hiermit nicht
als erreicht erklärt.

Der Ladefix ist in `f7b5e91` enthalten. `sh tooling/checks/test-plan-loading.sh`
bestand mit Swift 6 und `-strict-concurrency=complete`: acht kontrollierte
Detail-Ladegrenzen, zwei Seitenlisten-Grenzen, verspätete Fehler, Abbruch und
Erhalt des vorherigen Inhalts. Swift-Formatprüfung, ShellCheck, shfmt und
Diffprüfung bestanden ebenfalls. Die Sitzungs-Lifecycle-Korrektur liegt in
`6fd38ec`; die Gesamt-App- und Geräteabnahme erfolgt auf dem gemeinsamen Stand.

Für den Share-Fix bestehen `test-intake-provider.sh`, `test-intake-erasure.sh`
und `test-intake-size.sh` mit synthetischen temporären Dateien. Bestehende
Legacy-Receipt-Wiederherstellung, Kollisionen, Größenlimits und geschützte
beschädigte Zwischenstände bleiben durch die bisherigen Proben abgedeckt.
Der tatsächliche ShareController samt Intakequellen besteht außerdem den
Swift-6-Typecheck mit vollständiger Nebenläufigkeitsprüfung,
`-application-extension` und iOS-26-Simulator-SDK. Ein Appbuild oder eine
Geräteinstallation wurde für diesen Slice nicht vorgenommen.
