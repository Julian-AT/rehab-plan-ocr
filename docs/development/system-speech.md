> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Lokale Systemsprachausgabe

Die App bereitet Antworten weiterhin über `ConversationReply` auf. Die typisierte
Grenze `LocalSpeechRendering` liefert Stimme, PCM, Wortfortschritt und
Vorbereitungsdauer. `SpeechOutput` hält Antwortzustand, Wiederholung und Abbruch;
`ConversationAudio` spielt weiterhin im gemeinsamen Mikrofon-/Ausgabegraphen.
Ein Anbieterwechsel ersetzt weder die sichtbare Kalenderbestätigung noch den
belegten Antworttext.

## Verfügbarkeit und Einstellungen

Nur über `AVSpeechSynthesisVoice.speechVoices()` angebotene deutsche Stimmen
werden ausgewählt. Ohne Auswahl bevorzugt die technische Vorauswahl die normale
deutsche Systemstimmenfamilie, dann deren Qualitätsstufe und stabile Kennung.
Dies ist **keine menschlich qualifizierte Stimmenrangliste**. Die Einstellungen
zeigen die tatsächlich vorhandenen Namen; eine explizit gewählte fehlende Stimme
führt zu einer verständlichen Meldung. Die App lädt keine Stimme nach.

Die neue Auswahl liegt in `voice.system.id`. Bestehende `voice.neural.id`-Werte
bleiben erhalten; `voice.neural.rate` wird weiterverwendet. Vollständiges lokales
Löschen entfernt auch die neue Auswahl. Einrichtung/Downloads erfolgen in den
Systemeinstellungen. Flugmodus, Neustart, fehlende Assets und Routenwechsel
bleiben Bestandteile der Geräteabnahme.

## Fortschritt, Grenzen und Lebensdauer

Die Standardstimme Anna liefert beim Schreiben von PCM keine Marker-Callbacks,
wohl aber `willSpeakRangeOfSpeechString`. Deshalb wird der zugehörige UTF-16-Bereich
an der aktuellen PCM-Puffergrenze erfasst. Das ist Fortschritt auf Puffergrenzen,
keine behauptete phonemgenaue Ausrichtung. Wiederholte Bereiche werden unterdrückt;
gesprochener Verlauf wird erst an der nächsten Wortgrenze beziehungsweise nach
vollständiger Wiedergabe bestätigt. Bei fehlendem Fortschritt wird nicht blind
abgespielt.

Ein Synthesizer gehört genau einer begrenzten Anfrage. Generation, Task-Abbruch
und 30-Sekunden-Deadline verhindern verspätete Wiedergabe. Stoppen beendet alle
aktiven Synthesen sowie unmittelbar den vorhandenen Audio-Player. Die PCM-Sammlung
ist auf fünf Minuten, einzelne Puffer auf 192.000 Frames und vorbereiteten Text
auf 4.000 UTF-16-Einheiten begrenzt. Fremde Audio-Puffer werden im Callback kopiert;
nur unveränderliche Werte verlassen ihn. Die Konvertierung nach 24 kHz läuft
außerhalb des UI-Actors, wird vollständig bis Stream-Ende gelesen und prüft Abbruch.

## Nachweise und offene Abnahme

`make test-system-speech` prüft Konvertierung bei 16/22,05/24/44,1/48 kHz,
Signalenergie/Dauer, beschädigte Eingaben, UTF-16-Bereiche, doppelte Rückmeldungen,
fehlende Stimmen und Abbruch. `TEST_ARGS=--live` ergänzt echte lokale Synthese.
Am 26.09.2026: Anna, 14 Bereiche, 4,875 Sekunden Audio, Abbruch und anschließende
neue Synthese bestanden (macOS 26.5.2/Xcode 26.4; kein iPhone-Nachweis).

Der gemeinsame App-/UI-Test, aktuelle iPhone-Hörproben, menschliche Verständlichkeit,
Unterbrechungszeit und gepaarte Latenz-/Energieprüfung müssen gesondert bestehen.
Der öffentliche Releasepfad prüft den Ausschluss experimenteller Sprachressourcen
und eSpeak-Symbole. Die gesamte Veröffentlichungsfreigabe bleibt davon unabhängig
offen.

API-Vertrag: [Apple: Sprachsynthese](https://developer.apple.com/documentation/avfoundation/speech-synthesis)
und `AVSpeechSynthesis.h` des gepinnten Xcode-26.4-SDK; tatsächliche Callbackfolge
zusätzlich mit der installierten Stimme geprüft.
