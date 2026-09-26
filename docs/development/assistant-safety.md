> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Assistent: aktuelle Anfrage und sichere Interpretation

Stand: 26. September 2026. Dies ist ein Entwicklungsnachweis, keine Modell- oder
Produktfreigabe.

## Vertrag

Die kompakte Rust-Schnittstelle prüft weiterhin Struktur, gültige Datums- und
Zeitwerte sowie bekannte Referenzen. Der gemeinsame Swift-Router prüft zusätzlich
die Bedeutung gegenüber der **aktuellen** Anfrage, bevor eine modellbasierte
Interpretation die Gesprächssteuerung erreicht:

- Eine Raumfrage ermächtigt keine Änderung. Änderungstyp und angefragte Felder
  müssen durch die aktuelle Äußerung gedeckt sein. Zusätzliche Dauer-, Datums- oder
  Zeitänderungen führen zur Klärung.
- Ungültige tatsächlich genannte Daten führen auch dann zur Klärung, wenn das
  Modell ein anderes, formal gültiges Datum liefert. ISO-Daten werden ebenso wie
  deutsche Schreibweisen geprüft.
- Korrigierte Tage und untere/obere Zeitgrenzen dürfen nicht vertauscht oder
  fallengelassen werden.
- Ein bekannter Referenzschlüssel allein genügt nicht. Eine genannte Position
  muss zur sichtbaren Seite passen; „den anderen“ bleibt ohne eindeutige Auswahl
  unaufgelöst. Ein ausdrücklich genannter anderer Titel darf nicht auf den
  einzigen sichtbaren Termin umgedeutet werden.
- Frühere Gesprächsbeiträge verleihen keine neue Änderungsbefugnis. Aussagen wie
  „Wie lösche ich …?“ werden auch vom vorgeschalteten Befehlsparser nicht mehr als
  Löschauftrag eingestuft.

Vollständig passende Regeln beantworten zusätzliche Raum-Rückfragen, korrigierte
Tagesfragen und zeitlich begrenzte Fragen nach dem nächsten Termin. Abbruch und
ungültige Daten benötigen keine verfügbaren Modellgewichte. Die Regelidentität
ist deshalb `calendar-3`; historische `calendar-2`-Berichte bleiben unverändert.
Unvollständige oder widersprüchliche Interpretationen werden nicht automatisch
repariert. Sichtbare Bestätigung und die erneute Kalenderabfrage bleiben
nachgelagerte Anforderungen.

## Prüfung

Die Swift-6-Probes `test-custom-assistant-provider`, `test-calendar-answers`,
`test-interpretation-provider` und `test-voice-rules` bestehen. Sie prüfen unter
anderem mehrteiligen Kontext mit einem früheren Löschwunsch, falsche existierende
Referenzen, zusätzliche Mutationseigenschaften, vertauschte Zeitgrenzen,
ungültige Kalenderdaten, unterbrochene Kontextvorbereitung und verspätete
Modellantworten. Die beiden Python-Evaluationssuites bestehen mit 8 bzw. 2 Tests.

Zusätzlich wurden gespeicherte Ausgaben der früheren nativen Entwicklungsläufe
mit dem aktuellen Router erneut geprüft. Gemeinsame Grundlage sind 40 erfundene
Fälle aus 10 Familien, **keine 40 unabhängigen Gespräche**. Der vorhandene
Abhängigkeitsgraph verbindet diese Fälle sogar zu einer einzigen Komponente:

| Variante | Früher exakt | Aktueller Replay exakt | Früher unsichere Vorschläge | Aktueller Replay unsichere Vorschläge |
|---|---:|---:|---:|---:|
| Trainiertes Modell | 17/40 | 33/40 | 11/40 | 0/40 |
| Untrainiertes Modell | 4/40 | 24/40 | 2/40 | 0/40 |
| Regeln | 4/40 | 24/40 | 0/40 | 0/40 |

24 Anfragen werden nun vollständig durch Regeln behandelt. Für die übrigen
16 Fälle wurden frühere strukturierte Ausgaben beziehungsweise Fehler verwendet.
Der untrainierte Replay hat 14 Fehler; der Regel-Replay hat außerhalb der 24
passenden Regeln 16 nicht interpretierbare Fälle. Das ist **keine neue Inferenz**,
kein Laufzeitvergleich und kein vollständiger Test des Gesprächs einschließlich
Terminauswahl, sichtbarer Bestätigung, Kalenderwirkung und Audio.

Der trainierte Replay bleibt bei sieben Fällen falsch: vier kombinierte
Negation/Änderungswünsche werden konservativ zur Klärung zurückgegeben; drei
minimale Erstellungen behalten die frühere falsche `invalid_date`-Klärung.
Der direkte mehrstufige VoiceModel-Pfad benötigt weiterhin eine Geräte- und
Sprachabnahme. Die neue Grenze ist konservativ und muss mit weiteren sprachlich
geprüften Fällen auf unnötige Rückfragen untersucht werden.

Lokaler, nicht versionierter Beleg:
`.local/runs/assistant-safety-replay-20260926-s18-001/`. `summary.json` enthält
Input- und Ursprungsbericht-Hashes, Fallzahlen und Fehlerfamilien. Die drei
Ursprungsläufe `assistant-app-40-{custom,untuned,rules}-20260926-s18-001` wurden nicht
verändert. Der ausführbare Replay ist im bestehenden Custom-Provider-Probe über
die drei Argumente `input.json report.json neue-ausgabe.json` verfügbar und
überschreibt keine vorhandenen Ausgabedateien.

Neue ungesehene Daten, menschlich geprüfte Referenzen, tatsächliche native
Inferenz des endgültigen Kandidaten, vollständige Dialoge und Geräteprüfungen
bleiben Voraussetzung für eine Freigabe. Der Replay öffnet keinen abschließenden
Testsatz und verbessert keine Modellgewichte.

## Gesprächssteuerung mit ersetzten Geräteeffekten

`make test-voice-flow` kompiliert und prüft den tatsächlichen `VoiceModel`,
`VoiceRules`, `InterpretationRouter`, `CalendarConversation`, `ConversationState`
und `EventSession` gemeinsam mit Swift 6. Nur Zeit, Kalendertransport,
Interpretationsanbieter und Audioeffekte werden deterministisch vorgegeben.
Der iOS-Adapter benutzt weiterhin dieselben Kalenderdienste, denselben Recorder
und dieselbe Ausgabe. Die Darstellung bleibt erhalten.

Der Host-Ablauf prüft Kalenderfragen bei fehlendem Modell, Raum-/Danach-Folgefragen,
zwischenzeitlich ausgeblendete Termine, eine Erstellung über Titel/Datum/Zeit/Dauer,
ungültige Daten, ein ausgeblendetes Schreibziel, Auswahl des zweiten Termins,
Themenwechsel und bestätigungsfreie Ablehnung unsicherer Wünsche. Gesprochene
Zustimmung erzeugt keinen Schreibauftrag; erst `confirmProposal()` schickt über
den echten EventSession die Knopfbestätigung. Eine verzögerte Bestätigung und
ein zweiter Aufruf erzeugen genau einen Schreibauftrag. Erfolg bleibt auch bei
nachgelagerter Erinnerungs-/Widgetwarnung sichtbar.

Weitere Fälle prüfen Abbruch während Vorschau, Erkennung und Modellantwort,
bereits abgebrochene Aufnahme-Tasks, tatsächlich ausgelöste Barge-in-Callbacks,
nur bereits gehörte Wörter in der Historie sowie Wiederholung und Lesefehler.
Die Eintrittsprüfungen verhindern, dass ein zweiter Bestätigungsaufruf die laufende
Sitzung zurücksetzt oder ein bereits abgebrochener Audio-Task erneut aufnimmt.

Dieser Ablauf ist bestanden. Er misst weder reale Erkennungs-/Synthesequalität
noch Unterbrechungslatenz und ersetzt keine EventKit-, UI- oder Geräteabnahme.
Die freie sprachliche Abdeckung und tatsächliche deutsche Spracherkennung sind
davon getrennt zu prüfen.

## Ordinale Änderungsreferenzen

Der vorherige direkte Befehlspfad suchte „zweiten“ als Teil eines Termintitels.
Der neue Ablauf übernimmt etwa bei „Verschiebe den zweiten Termin auf morgen um
zehn Uhr“ die zweite Position der zuvor tatsächlich beantworteten Kalenderseite.
Der gleiche Auftrag ohne eine solche Seite führt zur Klärung. Vor der Vorschau
werden Sichtbarkeit und Werte dieses Termins erneut gelesen; zusätzliche Titel-,
Kalender-, Tages- und Uhrzeitangaben müssen dazu passen. Die Änderung bleibt auf
die angefragten Felder beschränkt und benötigt weiterhin die Schaltfläche.

Die Auflösung eines Änderungsziels erzeugt keine neue gesprochene Kalenderseite.
Ein abgelehnter Bezug darf insbesondere die ursprünglichen Positionen nicht
verschieben. Mehrere Positionen, ein unbestimmter „anderer“ Termin und ein
unklarer Bezug wie „die zweite Therapie“ führen zur Klärung. Eine spätere Auswahl
kann „Nicht den ersten, sondern den zweiten“ berichtigen; widersprüchliche
Titel oder zusätzliche Zeit-/Datumsangaben werden nicht stillschweigend verworfen.

Diese Fälle sind Teil desselben echten VoiceModel-Ablaufprobes. Die ursprüngliche
fehlende Auflösung wurde vor der Änderung durch dessen fehlschlagende Zusicherung
`Spoken ordinal must use the discussed page` reproduziert. Die Prüfhülle begrenzt
Cargo und Swift jeweils auf einen Compilerjob.

## Gepaarter Replay nach Korrektur des CLI-Prompts

Die am 26.09.2026 neu erzeugten 40 Antworten aus
`assistant-token-trace-20260926-s18-004` wurden unverändert durch denselben aktuellen
Swift-Router geschickt. Zwei Vergleichsvarianten verwenden die historischen
CLI-Texte beziehungsweise damaligen App-Interpretationen. Entfernt werden nur
äußere Leerzeichen und der abschließende CLI-Anzeigemarker; JSON wird vor dem
Router weder repariert noch neu serialisiert. Kontext, Ziele und Prompt-Hashes
sind gegen die ursprünglichen erfundenen Entwicklungsfälle geprüft.

Alle drei Varianten erreichen 33/40 exakte Antworten und 0/40 unsichere
Änderungsvorschläge. 24 Fälle beantwortet jeweils die vollständige Regel,
16 aufgezeichnete Modellantworten erreichen den Anbieter. Die korrigierte CLI
verursacht hinter dem Router weder neue unsichere Vorschläge noch neue falsche
Fälle. Die sieben bekannten Abweichungen bleiben erhalten. Dies ist ein Replay
frischer Inferenztexte, keine zusätzliche Modellinferenz, Laufzeitmessung oder
vollständige VoiceModel-/Audioabnahme. Die Fälle bilden weiterhin nur eine
verbundene Entwicklungsgruppe und keine unabhängigen realen Dialoge.

Beleg: `.local/runs/assistant-router-replay-20260926-s18-001/`, mit Quellen-/Inputhashes,
unveränderten Antworttexten, Swift-Log und gepaartem Ergebnis. Drei zusätzliche
Regressionen verhindern unter anderem das Verbergen einer neuen unsicheren
Änderung im Gesamtwert sowie die Annahme unvollständiger oder widersprüchlicher
Anbieterbelege. Die vorhandene vollständige Custom-Provider-Probe besteht ebenfalls.

Wiederholung in einem neuen privaten Verzeichnis:

```sh
make prepare-assistant-router-replay RUN=.local/runs/<neu> \
  APP_RUN=.local/runs/assistant-app-40-custom-20260926-s18-001 \
  DEPLOYMENT_RUN=.local/runs/assistant-development-001/deployment \
  NATIVE_RUN=.local/runs/assistant-token-trace-20260926-s18-004
make test-custom-assistant-provider \
  TEST_ARGS='.local/runs/<neu>/input.json .local/runs/<neu>/recorded.json .local/runs/<neu>/router.json'
make assess-assistant-router-replay RUN=.local/runs/<neu>
```

## Erneute Laufzeitprüfung am 26. September 2026

Die Herkunftsprüfung verwirft den alten nativen Cache nach Änderungen an Builder
und Assembly-Helfer. `make build-assistant-native` erstellt deshalb alle drei
bisher vorhandenen Ziele (Mac, Simulator, Gerät) mit den aktuellen Werkzeugen neu.
Alte Produkte und der Ablehnungsbeleg bleiben erhalten; keine Cacheprüfung wurde
umgangen. Der Swift-6-Hostlauf mit echter C-Grenze besteht Eingabe-/Assetprüfungen,
Abbruch, Deadline, Kontext-/Ausgabelimit, Isolation nach Abbruch und Wiederladen.

Zwei tatsächlich erneut erzeugte Entwicklungsantworten sind identisch zum
früheren Desktop-Ergebnis, aber **0/2 fachlich exakt**. Eine enthält den bereits
bekannten falschen Änderungsvorschlag bei einer Raum-Rückfrage. Diese Rohinferenz
enthält weder vorgeschaltete Regeln noch Router, Bestätigung oder Kalenderzugriff;
sie führt keine Änderung aus und ersetzt den getrennten Routerreplay nicht.
Modellparität und fachliche Qualifizierung bleiben offen beziehungsweise
fehlgeschlagen. Belege: `.local/runs/native-package-content-20260926-s20-001` und
`native-assistant-refresh-20260926-s20-001`; keine physische Installation.
