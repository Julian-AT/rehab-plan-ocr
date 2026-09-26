> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Weitere Optimierung: Stand und nächste Schritte

## Ergebnis dieses Durchgangs

Die Sprachregeln wurden beschleunigt und die Vergleichsprüfung verschärft.
Die vorhandenen OCR-Ergebnisse wurden erneut auf konkrete Fehlerursachen untersucht.
Die Freigabe der bereits gezeigten Simulatorvorschau und Hörproben liegt seit
26. September 2026 vor. Ein Geräteupdate wurde noch nicht durchgeführt.

Der freie Speicherplatz lag zeitweise bei nur 143 MiB und blieb auch nach der
Bereinigung unter 0,6 GiB. Eine ältere, reproduzierbare Simulator-App-Kopie und alte Xcode-Testcaches
wurden entfernt. Der gewonnene Platz reicht für die kleinen Swift-Proben, aber
nicht für einen vollständigen Rust-/App-Neubau, Modelltraining und eine frische
iPhone-Sicherung. Originale, Sicherungen, Modellgewichte und Prüfnachweise bleiben erhalten.

## Sprachregeln: weniger wiederholte Arbeit

`VoiceRules` speichert bis zu 128 kompilierte Suchmuster. Ein kurzer Lock schützt
den Cache; die Suche selbst läuft außerhalb des Locks. Zahlwörter werden mit einem
gemeinsamen Muster in einem Durchlauf ersetzt. Originale UTF-16-Positionen bleiben
bei Umlauten und Emojis erhalten. Die Regeln für Zeit, Datum, Verneinung und
Kalenderänderungen sind unverändert.

Der Vergleich verwendet dieselben synthetischen Eingaben und dieselbe optimierte
Swift-6-Kompilierung vor und nach der Änderung. Sechs neue Prozesse pro Variante
wechseln ihre Reihenfolge ab. Pro Prozess werden 30 Blöcke mit jeweils 120 Fragen
gemessen. Die warme Messung enthält Regeln, Suchwörter und die Serialisierung einer
Vergleichssignatur; sie enthält weder Mikrofon noch Spracherkennung, Sprachmodell,
EventKit-Abfrage oder Sprachausgabe. Die erste Frage pro neuem Prozess wird separat
erfasst; das ist kein kalter iPhone-App-Start.

| Messung auf diesem Mac | Vorher | Nachher |
|---|---:|---:|
| Erste Frage, Median | 3,339 ms | 2,930 ms |
| Erste Frage, P95 / Maximum von sechs Prozessen | 8,266 ms | 7,714 ms |
| Warme Fragen, Median der Blockmittel | 0,240 ms | 0,065 ms |
| Warme Fragen, P95 der Blockmittel | 0,255 ms | 0,072 ms |

**175 Vergleichsfälle liefern identische strukturierte Ergebnisse.** Die warme
Ersparnis beträgt hier etwa 0,175 ms pro Frage. Sie ist eine kleine lokale
Verbesserung; daraus folgt keine entsprechend große Verkürzung der gesamten
Sprachinteraktion. Der Benchmark misst keine Qualität echter Spracheingaben.

Zusätzlich bestanden die nativen Regeltests mit Swift 6 und vollständiger
Nebenläufigkeitsprüfung: unter anderem österreichische Zeitangaben, Korrekturen,
Verneinungen, ungültige Daten, Wortgrenzen, Unicode und 256 parallele Aufrufe mit
mehr unterschiedlichen Mustern als Cacheplätzen. Swift-Format, ShellCheck und
Shell-Formatprüfung bestanden. Auch die isolierte Typprüfung der geänderten
Produktionsdatei gegen das iPhoneOS-26.4-SDK mit Ziel iOS 26.0 und Swift 6 bestand.
Ein vollständiger neuer App-Build steht noch aus.

Reproduzierbarer Benchmark: `experiments/voice-rules/RulesBenchmark.swift`.
Die private Vorher-Version stammt aus `00d7b9b`; Binär-, Benchmark- und Quellhashes
sowie alle Einzelmessungen stehen in
`artifacts/private/plan-voice-20260926-s16/rules-comparison.json` und den zugehörigen
`rules-before-*.json` / `rules-after-*.json`.

```sh
swiftc -swift-version 6 -strict-concurrency=complete -O \
  apps/ios/Features/Conversation/VoiceRules.swift \
  experiments/voice-rules/RulesBenchmark.swift \
  -o /tmp/reha-voice-rules-benchmark
/tmp/reha-voice-rules-benchmark > /tmp/reha-voice-rules-result.json
sh scripts/test-voice-rules.sh
```

## OCR: Fehler und Aufwand gezielt zuordnen

Diese Auswertung verwendet die bereits gemessenen 20 Entwicklungsfotos und deren
geprüfte Referenzen. Sie ist kein neuer Erkennungslauf und kein unabhängiger Test.

| Feld | Falsche / fehlende gedruckte Werte | Falsch gefüllte leere Zellen | Zusammen |
|---|---:|---:|---:|
| Therapeut | 55 | 3 | 58 |
| Notizen | 31 | 22 | 53 |
| Titel | 16 | 0 | 16 |
| Raum | 8 | 5 | 13 |
| Endzeit | 6 | 0 | 6 |
| Datum | 5 | 0 | 5 |
| Startzeit | 1 | 0 | 1 |
| **Gesamt** | **122** | **30** | **152** |

Der bereits gemessene Nachleseschritt beansprucht über alle 20 Fotos zusammen
44.488 ms, rund **55,8 %** der vollständigen Prozesszeit. Er ist damit der erste
Ansatzpunkt für eine größere Zeitersparnis.

### Unbelegte Werte aus benachbarten Feldern

Die Erstlesung wurde aus den gespeicherten Originalbeobachtungen und ausschließlich
ihren ursprünglichen Text-/Unsicherheitsregionen erneut geparst. Nachleseregionen
und abgeleitete Layoutregionen wurden vorher entfernt, damit sie die Ausrichtung
der Erstlesung nicht nachträglich verändern. Alle Termin-IDs bleiben dabei gleich.
Der eingefrorene Evaluator bewertet vor und nach dem Nachlesen dieselben Referenzen.

- Die isolierte Erstlesung benötigt **147**, das fertige Ergebnis **152** Feldkorrekturen.
- Das Nachlesen verändert elf leere Felder: fünf Räume, fünf Therapeuteneinträge
  und eine Endzeit.
- Die Endzeit wird richtig ergänzt. Fünf vorher korrekt leere Räume und ein vorher
  korrekt leerer Therapeuteneintrag werden falsch gefüllt. Vier weitere ergänzte
  Therapeuteneinträge bleiben falsch.
- Beispiele sind abgeschnittene Reste aus der Nachbarspalte sowie ein Vorbereitungshinweis,
  der als Raum übernommen wird. Die privaten Einzelbelege stehen in
  `reread-value-analysis-corrected.json`.

Dies begründet einen Versuch mit strengerer räumlicher Prüfung und gezielterem
Nachlesen. Es rechtfertigt noch kein pauschales Abschalten: Eine Endzeit profitiert,
und die Wirkung auf andere Fotos sowie fehlende Zeilen ist unbekannt. Die Probe
rekonstruiert außerdem nicht die vollständige Warnungsaufbereitung der Bildpipeline;
sie darf keine automatische Freigabe oder vollständige Laufzeitverbesserung belegen.
Die frühere Probe mit allen gespeicherten Regionen ist als ungültiger Vorversuch
markiert und wird nicht als Erstlesungsreferenz verwendet.

### Übersprungene Tagesüberschrift

Bei einem mehrtägigen Plan erkennt die OCR eine vollständige Sonntagsüberschrift,
verwendet zwischen Tag und Monat aber ein Komma. Der aktuelle Parser übersieht
diesen Abschnitt und ordnet zwei folgende Termine dem Samstag zu. Die Erkennung
des Abschnitts muss auch bei einem unleserlichen oder ungültigen Datum erhalten
bleiben: Ein vorheriges Datum darf nicht weitergetragen werden. Ein späterer Versuch
mit tolerierter Datumstrennung muss Kalenderdatum und Wochentag prüfen und den
Originaltext bewahren. Diese OCR-Korrektur ist noch nicht implementiert oder vermessen.

## Vergleichsprüfung verbessert

`compare-recognition.py` lehnt jetzt leere, doppelte oder unvollständige Vergleiche,
abweichende Fotos, ausgelassene Wiederholungen, geänderte Referenzanzahlen und
ungültige Laufzeiten ab. Jede Wiederholungsrunde muss die Qualitätsverbesserung
zeigen; ein guter erster Lauf kann eine spätere Verschlechterung nicht verdecken.
Zusätzliche fehlende Zeilen werden separat berichtet und verhindern die Aufnahme
in den iPhone-Vergleich.

Neun gezielte Tests bestehen. Die neue Prüfung wurde außerdem auf die vorhandenen
vollständigen, portablen und Apple-Vergleichsberichte angewandt: Ihre bisherigen
Freigabeentscheidungen ändern sich nicht. Nachweis:
`artifacts/private/plan-voice-20260926-s16/comparison-gates.json`.

## Nächste Schritte in Reihenfolge

1. **Arbeitsraum bereitstellen:** etwa 10 GB für Builds und weitere Versuche oder ein
   lokales beschreibbares externes Laufwerk. Den zusätzlichen Platzbedarf einer
   frischen iPhone-Sicherung separat prüfen.
2. **Datum und Nachlesefehler korrigieren:** unleserliche Tagesüberschriften als
   Abschnittsgrenze erhalten, das Überlaufen des Datums stoppen und Nachbartext an
   Ausschnitträndern nicht als Raum oder Therapeut übernehmen. Originalwerte,
   Unsicherheit, manuelle Korrekturen und Bestätigungen erhalten.
3. **Einzeln messen:** erst fünf, dann alle 20 geprüften Fotos, mit wiederholten
   Läufen. Kritische Fehler und falsch sichere Werte zuerst; danach vollständig
   richtige Termine, Korrekturen, Median und P95. Erst bei erfüllten Kriterien den
   Standard für das Nachlesen ändern. Gesamte App neu bauen und Simulatorfälle prüfen.
4. **Am iPhone prüfen:** Die bisherige Vorschau-/Hörprobenfreigabe ist vorhanden.
   Frisch sichern, ohne Deinstallation aktualisieren, dauerhafte Daten vergleichen.
   Österreichisches Deutsch und Kalenderdialoge über das echte Mikrofon testen;
   pro Foto einen kalten und vier warme Läufe sowie längere Wärmeserien messen.
5. **Gezielt trainieren und unabhängig prüfen:** exakte Trainingsausschnitte separat
   freigeben, besonders Namen und Notizen; kleine Modelle und Strukturzuordnung in
   getrennten Entwicklungsgruppen vergleichen. Mindestens zehn bisher unbenutzte
   reale Pläne bleiben für eine Aussage zur Übertragbarkeit erforderlich.

Weitere Modellversuche und echte Mikrofontests bleiben offen. Der Mikrofonfehler
wird weiterhin nicht als behoben bezeichnet.

Code-Commits: `883c685` (Sprachregeln), `590e2e9` (Vergleichsprüfung).
