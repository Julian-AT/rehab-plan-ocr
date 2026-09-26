> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Planerkennung und Sprachassistenz – Entwicklungsvergleich

Stand: 26. September 2026. Ausgangscommit: `8c1dba1`.

## Ergebnis und Freigabestatus

Die Kalenderantworten verwenden einen gemeinsamen Aufbau aus aktuell abgefragten
Terminen. Eindeutige Textfragen umgehen das Sprachmodell. Komplexe Äußerungen
werden in einem Modellaufruf in Suchbedingungen oder einen Änderungsvorschlag
überführt. Kalenderwerte formuliert anschließend der Antwortaufbau. Änderungen
benötigen weiterhin die bestehende Bestätigung und Prüfung aktueller Daten.

Die OCR-Korrektur verbessert im vorhandenen Bestand einen Termin. Ein Modellwechsel
ist nicht freigegeben. Small, Einzelverarbeitung und die bisherige Reihenfolge beim
Nachlesen bleiben eingestellt. Breitenbündelung und priorisiertes Nachlesen sind
explizite Versuchsoptionen. Auch Sprachvokabular und Modellvorbereitung bleiben
Versuche. Kalendergestaltung, Datenbankschema und öffentliche Swift/Rust-Bindings
benötigen keine Änderung.

**Stand vom 26. September 2026, keine Freigabe zur iPhone-Installation:** Der Geschwindigkeitsnachweis auf dem
physischen Gerät, echte Spracheingaben und die Zustimmung zu Simulatorvorschau und
Hörproben fehlen. Der Mikrofonfehler gilt weiterhin als ungeprüft. Es gibt noch keine
Aussage zur Übertragbarkeit auf mindestens zehn bisher unbenutzte reale Pläne.

**Nachtrag vom 26. September 2026:** Die Freigabe der gezeigten Simulatorvorschau und
Hörproben ist inzwischen eingegangen. Speicherplatz, frische Sicherung, neuer
Gerätebuild und physische Tests stehen noch aus. Weitere Optimierung und die
konkreten nächsten Schritte: [Folgebericht](optimization-followup-2026-09-26-s16.md).

## Referenzen und Messverfahren

- Alle 20 vorhandenen Originalfotos wurden visuell nach Datum, Uhrzeit, Titel, Raum,
  Therapeut, Notizen, leeren Zellen und vollständigen sichtbaren Zeilen geprüft:
  **188 Zeilenvorkommen**, teilweise überlappende Seiten.
- Eine fehlende Notiz wurde gegenüber der älteren Transkription ergänzt. Unscharfe
  Namen wurden am Originalausschnitt geprüft. Abgeschnittene Angaben bleiben als
  abgeschnitten markiert; Nachbarseiten vervollständigen sie nicht.
- Vier Entwicklungsfolds halten gemeinsame Tage, Seiten und Aufnahmeserien zusammen.
  Dies ist ein bereits untersuchter Entwicklungsbestand, kein unabhängiger Test.
- Die Referenzfreigabe gilt für Feldwerte und Zeilenidentität. Die vorhandenen
  Polygone sind teilweise ungenaue Ausschnitte; **null separat freigegebene
  Erkenner-Trainingsausschnitte**. `crop-review.json` bindet jede spätere Freigabe
  an Quelle, Text, Zustand und Polygon. Änderungen sperren den Export wieder.
- Ausgangsprogramm, Modellmanifest, Konfiguration und Quellhashes wurden vor den
  Änderungen eingefroren. Alle Rohdaten, Einzelvorhersagen, Beschriftungen und
  Audits bleiben unter `artifacts/private/plan-voice-20260926-s15/` außerhalb von Git.
- Die Mac-Zeit beginnt vor dem Prozessstart und endet nach der vollständigen
  Serialisierung des Ergebnisses, einschließlich Bildvorbereitung und Nachlesen.
  Die Reihenfolge der Kandidaten rotiert je Foto. Jeder Lauf startet einen neuen
  Prozess. Dies sind weder warme Modellsitzungen noch iPhone-Messungen.
- Das 95. Perzentil verwendet den nächsten Rang: Bei fünf Fotos ist es das Maximum.
  Einzelne Desktop-Läufe liefern keine belastbare Aussage über thermisches Verhalten
  oder Gerätespeicher. Erforderliche manuelle Korrekturen werden gezählt, ihre
  tatsächliche Bearbeitungszeit wurde nicht gemessen.
- Kritische Fehler werden als Referenzzeile plus Feld gespeichert. Eine Verbesserung
  der Summe kann einen neuen Datumsfehler in einer anderen Zeile nicht verdecken.
  Eine Warnung zum Raum gilt nicht als Warnung vor einer falschen Uhrzeit.

## Vergleich auf allen 20 Fotos

Quelle: `full-20/summary.json`, eingefrorenes Programm `reha-validated`.

| Kennzahl | Ausgangsstand | Korrigierte Zuordnung |
|---|---:|---:|
| Nötige Feldkorrekturen | 153 | 152 |
| Vollständig richtige Termine | 75 / 188 | 76 / 188 |
| Kritische Datums-/Zeitfeldfehler | 13 | 12 |
| Kritische Fehler ohne passende Feldwarnung | 5 | 5 |
| Fehlende / zusätzliche Terminzeilen | 0 / 0 | 0 / 0 |
| Termine mit offenen Prüfpunkten | 103 | 103 |
| Pläne mit vollständig richtigen Feldwerten | 1 / 20 | 1 / 20 |
| Vollständig richtige, ohne Prüfung verwendbare Pläne | 0 / 20 | 0 / 20 |
| Median, vollständiger Prozess | 3.896 ms | 3.752 ms |
| 95. Perzentil | 5.935 ms | 5.939 ms |
| Maximum | 6.063 ms | 5.974 ms |

Es entstehen keine neuen kritischen Fehler, zusätzlichen Zeilen oder neuen
kritischen Fehler ohne Feldwarnung. Die einzige Qualitätsverbesserung betrifft
eine Endzeit. Das 95. Perzentil liegt ungerundet **3,591 ms höher**. Der strenge
Geschwindigkeitsvergleich ist damit nicht bestanden; dieser kleine Unterschied
belegt weder eine praktische Verlangsamung noch deren Abwesenheit.

## Fünfervergleich der ausführbaren Kandidaten

Die fünf Fotos decken mehrtägige, unscharfe, beschnittene, dichte und klare Pläne ab.
Sie wurden vor dem Vergleich festgelegt. Frühere Durchläufe wurden mit dem finalen
Evaluator erneut bewertet; ihre gemessenen Zeiten wurden nicht verändert.
Quelle: `reevaluated-canaries.json`, Originale in `canary-portable/` und `canary-apple/`.

| Portable Variante | Korrekturen | Kritische Fehler | Fehlend / zusätzlich | Median / P95 |
|---|---:|---:|---:|---:|
| Ausgangsstand Small | 58 | 9 | 0 / 0 | 4.250 / 6.224 ms |
| Korrigierte Zuordnung, Small | 57 | 8 | 0 / 0 | 4.245 / 6.210 ms |
| Small, gleiche Breiten bis Batch 4 | 57 | 8 | 0 / 0 | 4.362 / 6.060 ms |
| Small, gezieltes Nachlesen | 58 | 8 | 0 / 0 | 2.261 / 4.754 ms |
| Tiny | 92 | 28 | 1 / 0 | 1.950 / 3.233 ms |
| Medium | 58 | 17 | 0 / 1 | 17.092 / 28.027 ms |

- **Batch 4:** Alle 646 Beobachtungen einschließlich Nachlesungen haben identische
  Texte und Scores wie Einzelverarbeitung. Der Median wird langsamer; kein Standardwechsel.
- **Gezieltes Nachlesen:** schneller, aber insgesamt keine geringere Korrekturzahl.
  Eine verbesserte Endzeit steht einer zusätzlich falschen leeren Raumzelle gegenüber.
  Die beiden älteren Versuche mit breiteren Zeilenausschnitten verfehlten das P95-Ziel.
- **Tiny:** zusätzliche kritische Fehler und eine fehlende Zeile; ausgeschlossen.
- **Medium:** zusätzliche kritische Fehler, ein zusätzlicher Termin und deutlich
  längere Laufzeit; ausgeschlossen.

| Apple-Variante, eigener Durchlauf | Korrekturen | Kritische Fehler | Zusätzliche Zeilen | Median / P95 |
|---|---:|---:|---:|---:|
| Eingefrorener Ausgangsstand | 58 | 9 | 0 | 3.863 / 5.539 ms |
| `RecognizeTextRequest` | 79 | 13 | 3 | 782 / 7.198 ms |
| `RecognizeDocumentsRequest` | 79 | 13 | 3 | 964 / 2.429 ms |

Beide Apple-Varianten scheiden wegen der Feldqualität aus. Der erste Apple-Textlauf
enthält hohe Initialisierungskosten. Die Dokumenterkennung liefert häufig nur die
Patientenkopfdaten als Tabelle, bei einem Foto keine Tabelle und bei einem weiteren
nur die letzten drei Terminzeilen. Ein kleiner fälschlich erkannter Tabellenbereich
ordnet einen Namen einem Essen zu. Die ausgegebene Zellgeometrie bleibt im privaten
Vergleichsergebnis erhalten; sie wird nicht ungeprüft in die App-Zuordnung übernommen.
Die Probe führt genau einen Apple-Dokument- oder Textdurchlauf aus. Apples
[Tabellenerkennung](https://developer.apple.com/documentation/vision/recognize-tables-within-a-document)
liefert die dafür untersuchten Zellinformationen.

## Weitere Kandidaten und offene Experimente

| Kandidat | Status und nächste notwendige Voraussetzung |
|---|---|
| GLM-OCR | Vorhandene lokale Regionsversuche einbezogen: Median 19.224 ms, P95 26.041 ms, 19 vollständige und ein begrenztes Ergebnis. Kein Nachweis eines schnelleren vollständigen Ersatzes. |
| PaddleOCR-VL | Vorhandene Regionsversuche: Median 34.719 ms, P95 55.195 ms, 20 vollständige Ergebnisse. Kein Nachweis eines schnelleren vollständigen Ersatzes. |
| Lateinischer Spezialerkenner | Noch nicht ausgeführt; passende Gewichte, Wörterbuch, Konvertierung und Laufzeit fehlen lokal. |
| Nachtrainiertes kleines OCR-Modell | Kein Training gestartet. Zuerst exakte Textausschnitte separat prüfen und exportieren, anschließend die bestehende Architektur je Entwicklungsfold trainieren. |
| Gelernte Zeilen-/Spaltenzuordnung, Table Transformer | Noch kein trainierter Vergleich. Zeilenreferenzen sind vorhanden; Trainingsumgebung und überprüfte Strukturbeispiele fehlen. |
| CoreML, feste Formen, reduzierte Genauigkeit | Kein qualifizierter iPhone-Vergleich. Alle hier berichteten ONNX-Ergebnisse verwenden CPU. |
| Granite-Docling 258M | Nicht lokal ausgeführt. Laufzeit/Gewichte fehlen; Deutsch muss separat geprüft werden. Die Modellkarte bezeichnet weitere Sprachen außerhalb Englisch als experimentell. |
| FunctionGemma 270M | Kein deutsches Absichtsmodell trainiert oder integriert. Trainings-/Laufzeitumgebung und geprüfte deutsche Absichtsbeispiele fehlen. Es bleibt ein möglicher Ersatz des Absichtsschrittes. |
| Apple-Adapter | Gemäß beauftragtem Plan ausgeschlossen; kein Versuch begonnen. |

Die vorhandenen VLM-Messungen betreffen jeweils **einen Ausschnitt pro Foto**, keine
vollständigen Seiten und keinen gemeinsamen Lauf mit dem hier eingefrorenen Programm.
Sie sind kein neuer Genauigkeitsvergleich. Details: `docs/simple-app-delivery.md` und
private Ergebnisse unter `artifacts/private/vlm-region-comparison/`.

Auf diesem Mac stehen 24 GB RAM und während der Arbeit weniger als 1,5 GiB freier
Plattenplatz zur Verfügung. PyTorch, Transformers, Paddle und die entsprechenden
Python-Trainingslaufzeiten sind nicht installiert. Reproduzierbare Build-Caches
wurden bereinigt; private Originale, Sicherungen und Modellgewichte blieben erhalten.
Nicht ausführbare Kandidaten sind **ungeprüft**, nicht aufgrund ihrer Qualität verworfen.

Primärquellen für die noch offenen Versuche:
[PaddleOCR Fine-Tuning](https://www.paddleocr.ai/main/en/version2.x/ppocr/model_train/finetune.html),
[Table Transformer](https://github.com/microsoft/table-transformer),
[ONNX Runtime CoreML](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html),
[Granite-Modellkarte](https://huggingface.co/ibm-granite/granite-docling-258M),
[FunctionGemma](https://ai.google.dev/gemma/docs/functiongemma).

## Umsetzung in Erkennung und Sprache

### Erkennung

- Extraktionsversion 8; gespeicherte OCR aus Version 5–7 kann bei eindeutiger
  Zeilenidentität neu zugeordnet werden. Bestätigte Werte, manuelle Änderungen und
  Kalenderbindungen bleiben erhalten. Strukturell abweichende Ergebnisse benötigen
  eine explizite Neuverarbeitung; keine Datenbankmigration.
- Nachgelesene Zeilen werden anhand ihrer Geometrie gegenseitig eindeutig den
  bestehenden Zeilen zugeordnet. Mehrere tatsächlich verschiedene Termine bleiben
  erhalten, auch wenn Uhrzeit und Titel übereinstimmen.
- Tatsächlich gelieferte OCR-Alternativen können mehrdeutige Zahlen vorbereiten.
  Datum und Wochentag müssen zusammenpassen. Abweichende plausible Lesarten bleiben
  widersprüchlich; aus einer Alternative übernommene Zahlen bleiben prüfpflichtig.
  Originalbeobachtungen werden nicht umgeschrieben; Wörterbücher ergänzen keine Namen.
- Derselbe entzerrte Bildausschnitt wird für direkt aufeinanderfolgende Nachlesevarianten
  wiederverwendet. Der Versuchsplan priorisiert mögliche Auslassungen, Datum, Uhrzeit,
  Titel und dann optionale Felder; identische Datumsbereiche und überlappende
  Zeilenbereiche werden innerhalb desselben Abschnitts zusammengelegt, maximal 24.
- Versuchsoptionen im bestehenden Konfigurations-JSON:
  `recognition_batch_size: 1..8`, Standard `1`;
  `prioritized_rereads: true|false`, Standard `false`.
  Wiederholungen desselben Erkenners gelten weiterhin nicht als unabhängige Bestätigung.

### Kalenderdialog und Sprache

- Direkte Fragen, Nachfragen zu Details, Wiederholen und Verneinungen laufen vor
  dem Sprachmodell. Zusätzliche Suchbedingungen werden nicht durch Teiltreffer
  der einfachen Regeln verschluckt. Ungültige Datumsangaben werden nicht zu „heute“.
- Strukturierte Modellantworten enthalten Suchbedingungen; Kalenderantworten
  verwenden ausschließlich die tatsächlichen Datensätze. Freie Antworten mit
  erkannten Kalenderbezügen werden abgefangen. Strukturierung garantiert keine
  korrekte Interpretation der Absicht; echte Modelltests bleiben erforderlich.
- Abfragen derselben Antwort teilen einen Snapshot. Jede neue Antwort prüft die
  Sichtbarkeit und aktuelle Werte erneut. Verweise auf gelöschte oder ausgeblendete
  Termine liefern keine früheren Kalenderwerte. Du/Sie, fehlende Angaben,
  Seiten mit fünf Terminen und mehrdeutige Bezüge sind berücksichtigt.
  „Weitere Termine“ setzt nach der tatsächlich ausgegebenen Anzahl fort; nach
  einem einzelnen nächsten Termin werden keine vier Termine übersprungen.
  Eine ausgeschöpfte Liste springt beim erneuten Weiterblättern nicht an den Anfang.
- Stabile Anweisungen und ein kleiner JSON-Gesprächszustand ersetzen den alten
  Modell-/Werkzeugkreislauf. Ab 26.4 wird das Tokenbudget einschließlich Schema und
  Ausgabereserve vorab geprüft. Ältere Systeme verwenden eine konservative Grenze
  auf Basis der UTF-8-Länge. Ganze ältere Beiträge entfallen zuerst; die aktuelle
  Frage wird nicht abgeschnitten. Gehörte und angezeigte Antworten bleiben getrennt.
- `--model-prewarm-trial` und `--speech-vocabulary-trial` aktivieren begrenzte
  Versuche. Das Vokabular enthält maximal 32 kurze allgemeine Begriffe und tatsächlich
  bekannte Termintitel. Kein zusätzlicher Modell-Kontrollaufruf pro Antwort.
- Die lokale Verfügbarkeitsprobe meldet `de-AT` und `de-DE` für `SpeechTranscriber`
  als unterstützt, auf diesem Mac jedoch nicht installiert. Kein Download und kein
  Mikrofonzugriff wurden durch die Probe ausgelöst. Die Offline-Eignung ist hier
  damit nicht gegeben. Apple Intelligence ist auf diesem Mac nicht aktiviert.

Die APIs wurden anhand aktueller Primärdokumentation geprüft:
[strukturierte Generierung](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation),
[Prewarming](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)),
[SpeechAnalyzer](https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio).

## Reproduktion und Abschlussprüfungen

Die Vergleichsdatei enthält für jeden Kandidaten `name`, `binary`, `models` und
`config`; die fünf vorab festgelegten Quellhashes stehen unter `canary_hashes`.

```sh
.venv/bin/python scripts/compare-recognition.py \
  --root artifacts/private/plan-voice-20260926-s15/references \
  --suite artifacts/private/plan-voice-20260926-s15/suite-final.json \
  --destination artifacts/private/plan-voice-20260926-s15/neuer-vergleich \
  --evaluator artifacts/private/plan-voice-20260926-s15/reha-validated
```

`--canary` begrenzt auf die fünf festgelegten Fotos; `--repeats 1..5` bezeichnet
vollständige neue Prozesse und darf nicht als warmer iPhone-Lauf ausgegeben werden.
Der Ergebnisordner muss neu sein. Binärdateien, Konfigurationen, Modellmanifeste,
Originale und Referenzen werden gegen Prüfsummen kontrolliert.

Für die spätere Gerätefreigabe sind pro Foto ein kalter und vier
warme Durchläufe sowie längere Serien für Wärmeentwicklung erforderlich. Vor einer
Installation: ausdrückliche Vorschau-/Hörprobenfreigabe, frische Sicherung,
Aktualisierung ohne Deinstallation, anschließender Vergleich dauerhafter Daten.

### Abgeschlossene Prüfungen

- Rust-Workspace, Python-Prüfungen und die nativen Swift-Proben für Dialogregeln,
  Antworten, Audioeingabe, Kalender, Einstellungen, Datenhaltung und Bindungen.
  Der letzte Bindungs-Linkschritt scheiterte zunächst an vollem Speicher und
  bestand nach Bereinigung reproduzierbarer Testprogramme separat.
- 69 Rust-Bibliotheksprüfungen mit `kokoro,onnx-download`; gezielte Prüfungen für
  Nachlesen, Erhalt manueller Werte, numerische Alternativen und Aktualisierung
  alter Extraktionsstände. Standard-Clippy sowie Clippy mit den Modellfunktionen
  bestehen mit `-D warnings`. Rust-, Python-, Shell- und Swift-Formatprüfungen bestanden.
- Der Vergleich der neu erzeugten Swift/Rust-Bindings zeigt keine Änderung.
- **Simulator-Testbuild 2026092625**: vollständige App und Tests mit Swift 6,
  strikter Nebenläufigkeitsprüfung und frisch gebauter Rust-Simulatorbibliothek.
- Drei Oberflächenfälle bestanden: Textfragen nach Anzahl und nächstem Termin,
  unbekannter Raum, Wiederholen und Weiterblättern; direkte EventKit-Integration
  mit zwölf synthetischen Terminen, Seitenende und ungültigen Verweisen; Verwerfen
  einer unbestätigten Änderung nach Verlassen der App.
- Bei einem Wiederholungslauf scheiterte der letzte Fall während der Bereinigung
  der Testdaten. Die aufgezeichnete Oberfläche meldet ausdrücklich, dass das Volume
  `Data` voll ist. Die automatische Diagnosesammlung wurde begrenzt. Nach weiterer
  Bereinigung reiner Buildprodukte bestand der Fall erneut ohne Codeänderung.
  Der fehlgeschlagene Lauf bleibt dokumentiert und wird nicht als Erfolg gezählt.
- Vier Hörproben aus echten Ausgaben des gemeinsamen Antwortaufbaus wurden durch
  die gebündelte lokale Victoria-Stimme gerendert: nächster Termin, Anzahl,
  unbekannter Raum und Sie-Rückfrage. WAV mit 24 kHz; die Längen betragen rund
  11,50 / 5,88 / 3,70 / 2,38 Sekunden. Dies ist keine Aufnahme echter Spracheingabe
  und keine Hörfreigabe durch den Nutzer.

Die Rohprotokolle liegen unter `artifacts/private/plan-voice-20260926-s15/validation/`.
Die lokalen Resultbundles `voice-ui.xcresult`, `voice-ui-final.xcresult` und
`voice-ui-confirmation.xcresult` halten Erfolg, Speicherfehler und erfolgreichen
Wiederholungslauf getrennt fest. Screenshots und Hörproben liegen im Unterordner
`preview/`, gemeinsam eingebettet in `preview/index.html`. Das temporäre Testgerät
enthielt ausschließlich synthetische Daten und wurde nach dem Export entfernt,
um Speicher freizugeben. Die gebaute Simulator-App bleibt unter `apps/ios/build/`.
Das echte iPhone wurde nicht aktualisiert.

### Noch erforderlich

1. Vorschau und Hörproben ausdrücklich freigeben, bevor ein Geräteupdate erfolgt.
2. Genügend lokalen Speicher für die verbleibenden Modell- und Trainingsversuche
   bereitstellen; Textausschnitte separat prüfen und Entwicklungsfolds beim Training einhalten.
3. Den offenen Geschwindigkeitsvergleich klären und die geeigneten Varianten auf dem
   iPhone kalt, warm und unter längerer Last messen. Keine Standardumschaltung allein
   aufgrund der hier gezeigten Mac-Zeiten.
4. Komplexe Absichten mit tatsächlich verfügbarem Apple-Sprachmodell und dieselben
   Fragen mit echten österreichisch-deutschen Spracheingaben prüfen. Vokabular,
   Prewarming und SpeechTranscriber bleiben bis dahin ausgeschaltet.
5. Mindestens zehn neue, bislang unbenutzte reale Pläne separat prüfen, bevor eine
   Aussage zur Übertragbarkeit oder ein abschließender Modellgewinn getroffen wird.
