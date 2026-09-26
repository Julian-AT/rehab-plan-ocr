> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Integrierter experimenteller Voice-App-Test

Der getrennte Testaufbau verbindet den registrierten `assistant-development-002`-Anbieter (`tuned-v2`) mit dem tatsächlichen `VoiceModel`, den bestehenden Vorschlags- und Bestätigungsbuttons und `SpeechOutput`. Die fünf vorab festgelegten Fälle bleiben unverändert. Skriptierte Teil- und Endtranskripte ersetzen die Erkennung; vier Fälle verwenden einen Kalender-Fake, einer die vorhandenen eigenen EventKit-Vorschaukalender. Die normale UI-Suite bleibt unverändert.

Die unterstützten Einstiege sind getrennt:

```sh
make build-assistant-voice-trial
make test-assistant-voice-trial RUN=.local/runs/assistant-voice-NEW SIMULATOR=OWNED_FRESH_UUID SOURCE_COMMIT=EXACT_FINAL_FULL_COMMIT
```

Der Build ruft den kanonischen Builder mit `--model tuned-v2 --voice-ui-tests` auf und stellt anschließend das normale generierte Projekt wieder her. Der aktuelle native Assistant-Simulatorruntime und das unveränderte registrierte Modell müssen bereits vorhanden sein; dieses Ziel lädt keine Modelle. Der Test verwendet das bereits gebaute separate `AssistantVoiceTrial`-Produkt und startet keinen Build. Abweichende Werte von `ASSISTANT_TRIAL_MODEL` werden abgewiesen. `RUN`, `SIMULATOR` und `SOURCE_COMMIT` sind für den Test Pflicht; der Runner prüft den vollständigen aktuellen Commit, einen sauberen Arbeitsbaum sowie Quell-, Modell- und Testprodukthashes selbst.

Beide Ziele verlangen mindestens **44 GiB freien Platz**: 24 GiB erwarteten Spitzenbedarf zusätzlich zur bestehenden 20-GiB-Arbeitsreserve. Auch `PEAK_GIB=0` senkt diese zielgebundene Grenze nicht. Speicherbedarf vor dem gesamten Ablauf erneut prüfen; bestehende Modell-, Build- und Evidenzbestände werden nicht automatisch gelöscht. Nach Abschluss der aktiven OCR-Studie und erst wenn sämtliche Trainings-/Exportprozesse beendet sind, einen neuen ausschließlich eigenen `Termine-Native-Test-*`-Simulator erzeugen und seine UUID/Erzeugung dokumentieren. Keine parallelen Modell-/Simulatorläufe oder Wiederverwendung fremder Simulatordaten.

Build und Test seriell ausführen. Für die gemeinsame native Lease über beide Schritte den geprüften Ablauf mit `python3 tooling/build/product_generation.py lease -- sh -eu <reviewed-script>` starten; die beiden Make-Aufrufe stehen darin nacheinander. Beide zugrunde liegenden Python-Werkzeuge unterstützen dieselbe geerbte Lease und prüfen ihre Eigentümerschaft. Der finale Quellstand wird erst beim tatsächlichen Start ausgewählt und gebaut.

Der Runner bewahrt die signierten App-/XCTest-Kopien, die unveränderten begrenzten App-Beobachtungsbytes, das XCTest-Ergebnis und Quellen-/Modellidentitäten unter dem neuen `RUN`. Alle fünf exakten Tests müssen ausgeführt und erfolgreich sein. Titelverlust, Provider-Bypass, falsche Felder, Schreiben vor dem sichtbaren Button sowie fehlende oder abgebrochene Pflichtantworten scheitern separat im Grader. Jede vorgeschriebene Antwort einschließlich der Speicherbestätigung benötigt ihre konkrete `response_id`, vollständige vorbereitete Wörter, tatsächliche Audiopegel und den natürlichen Wiedergabeabschluss. Bereits erfolgreiches früheres Audio ersetzt keine spätere Antwort.

Die Ergebnisse bleiben Entwicklungsnachweise mit `qualified: false` und `full_voice_workflow: false`. Sie belegen weder echte Mikrofonerkennung noch menschliches Hören oder Geräteabnahme. Rohgenerierungsstrings werden in diesem Aufbau nicht beobachtet; erfasst werden die typisierte Anbieterantwort und die anschließenden tatsächlichen Zustände. Der Late-Cancel-Fall hält eine bereits abgeschlossene native Antwort vor der Auslieferung zurück; er behauptet keinen Abbruch eines laufenden nativen Rechenkernels. Die tatsächliche App-/XCTest-App-Group-Integration und alle Modellfälle müssen im späteren Lauf bestehen; vorbereitende Fake-Tests oder Typechecks zählen dafür nicht als Ergebnis.
