> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Dezente Grünflächen, Orb-Schatten und Audio-Wiederherstellung

Vorschau für **Laßnitzhöhe 0.3.0, Build 2026092623**.

Die fünf Greens-7-Grundfarben bleiben erhalten. Kalenderkarten und Tagesliste verwenden jetzt **18 % Deckkraft in Hell** und **22 % in Dunkel**; die native Fläche scheint durch. Die schmalen Akzente und die Legende behalten die ursprünglichen Grüntöne. Titel und Zusatztexte sind neutral. Der [Kontrastnachweis](contrast.json) berücksichtigt 25 Kombinationen aus Kategorie und normalem beziehungsweise erhöhtem Hintergrund; der kleinste Textkontrast beträgt **4,86:1**.

Der Orb erhält zwei dezente, schwarze Schlagschatten nach unten: einen weichen Umgebungsschatten und einen kleineren Kontaktschatten. Die bestehende Form, Größe und Bewegung bleiben erhalten.

## Simulatorvorschau

Die Aufnahmen stammen aus der nativen App und enthalten ausschließlich synthetische Termine.

| Ansicht | Hell | Dunkel |
| --- | --- | --- |
| Kalender, kurze und überlappende Termine | [Aufnahme](calm-cards-light.png) | [Aufnahme](calm-cards-dark.png) |
| Tagesliste, obere Kategorien | [Aufnahme](calm-list-light.png) | [Aufnahme](calm-list-dark.png) |
| Tagesliste, untere Kategorien | [Aufnahme](calm-list-lower-light.png) | [Aufnahme](calm-list-lower-dark.png) |
| Legende | [Aufnahme](calm-legend-light.png) | [Aufnahme](calm-legend-dark.png) |
| Orb mit Schatten | [Aufnahme](voice-start-light.png) | [Aufnahme](voice-start-dark.png) |
| Eingangswelle | [Aufnahme](voice-input-light.png) | [Aufnahme](voice-input-dark.png) |

Größte Schrift: [Kalender Hell](calm-large-light.png), [Kalender Dunkel](calm-large-dark.png), [Orb](voice-start-large.png), [Antwort](voice-answer-large.png). Die zusätzlichen `calm-large-…-0` bis `-4`-Aufnahmen dokumentieren alle Kategorien beim Scrollen.

## Ursache des Audiofehlers

Die vom iPhone gelesenen, inhaltsfreien Diagnosen zeigen sieben Startversuche mit erteilten Berechtigungen und eingebautem Mikrofon. In keinem dieser Versuche wurde ein gültiger Eingangspuffer protokolliert. Etwa 150 Millisekunden nach dem Start löste eine Audio-Konfigurationsmeldung einen vollständigen Neuaufbau aus; der zweite Aufbau wurde erneut unterbrochen. [Bereinigte Zeitfolgen](audio-before.json) enthalten ausschließlich relative Zeiten, technische Schritte und Zähler.

Der bisherige Pfad deaktivierte dabei die Audiositzung und erstellte Audioengine und Voice Processing neu. Zusammen mit dem wiederholten Startmuster spricht das für eine vom Neuaufbau erneut ausgelöste Konfigurationsänderung. Apple beschreibt, dass bei einer I/O-Konfigurationsänderung die Engine stoppt, ihre Knoten aber verbunden bleiben und bei Bedarf neu verbunden werden sollen. [Apple: AVAudioEngineConfigurationChangeNotification](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification)

Die Korrektur erhält die vorhandene Audioengine, den Wiedergabeknoten und die aktive Audiositzung. Nach einer kurzen Bündelung prüft sie zuerst, ob die Engine läuft und beide I/O-Formate stimmen. Eine Meldung bei gesunder Engine beendet weder Aufnahme noch Antwort. Bei einem tatsächlichen Ausfall werden Tap und Erkennungsanfrage mit dem aktuellen Format neu vorbereitet. Mikrofoneingang und Ausgang verwenden dasselbe Format für Voice Processing; Victorias 24-kHz-Ausgabe wird weiterhin vom Mixer angepasst.

Die Wiederherstellung bleibt begrenzt. Das Budget erneuert sich erst nach einer Sekunde fortlaufender Eingangspuffer. Stopp, Hintergrundwechsel und Systemunterbrechungen widerrufen ausstehende Arbeit. Die vorhandene Zwei-Sekunden-Prüfung auf ausbleibende Puffer bleibt erhalten; gültige Stille zählt weiterhin als ankommendes Audio. Eine unterbrochene Ausgabe wird vor dem Start des Players erkannt.

Die technische Diagnose protokolliert jetzt die Formatwerte bereits beim Vorbereiten, die Engine-Erzeugung und Konfigurationsmeldungen. Der Konfigurationszähler ist eine Bitmaske: 1 = Engine läuft, 2 = Formate stimmen, 4 = der Eingangsempfänger muss ersetzt werden. Enginefehler enthalten nur den Betrag des technischen Fehlercodes; erfolgreiche Spracherkennung enthält die Zeichenanzahl. Gesprächsinhalte und Rohaufnahmen werden nicht in den Diagnosen gespeichert.

## Prüfung und Gerätestatus

Die Audio-Regressionsfälle prüfen die beobachtete Startfolge, doppelte Benachrichtigungen, gesunde und gestoppte Engines, Formatwechsel, ungültige Empfänger, fortlaufende gegenüber vereinzelten Puffern sowie Abbruch vor der verzögerten Wiederherstellung. PCM-Prüfungen mit 16/44,1/48 kHz, Mono/Stereo, Stille und Konvertierungsfehlern sowie die Datenschutz- und Begrenzungsprüfungen der Diagnosen bestehen.

| Prüfung | Ergebnis |
| --- | --- |
| `scripts/test-input-audio.sh` | Bestanden: PCM, Stille, Fehler, Watchdog und Konfigurationswiederherstellung |
| `scripts/test-diagnostics.sh` | Bestanden: Begrenzung, Aufbewahrung und bereinigter Export |
| `CalmCalendarTests` | 2 Tests bestanden: fünf Kategorien, Hell/Dunkel, Tagesliste, Legende und größte Schrift |
| `VoiceSurfaceTests` | 3 Tests bestanden: Eingangswelle, Stille, Stopp, Hintergrundwechsel, Wortanzeige und echte Victoria-Wiedergabe im Simulator |
| Abschließender Wiedergabetest nach zusätzlicher Engine-Prüfung | 1 Test bestanden, 0 Fehler |
| Swift-Formatierung, ShellCheck, shfmt und `git diff --check` | Bestanden |

Die lokalen Xcode-Ergebnisbündel heißen `/tmp/reha-soft-audio-preview.xcresult` und `/tmp/reha-soft-audio-playback.xcresult`. Die 32 PNG-Aufnahmen dieser Vorschau wurden aus dem ersten Ergebnisbündel exportiert; Kalender, Tagesliste, große Schrift und Orb wurden anhand repräsentativer Aufnahmen visuell kontrolliert. Der zweite Lauf prüft die abschließende Audioabsicherung; die visuellen Änderungen sind identisch. Die Codeänderungen sind getrennt als `c672945` (Darstellung) und `3c8c9e5` (Audio) committed.

Der Mikrofonfehler gilt erst nach fünf erfolgreichen Starts mit **echter Sprache am eingebauten iPhone-Mikrofon** als behoben. Dazu gehören sichtbarer Pegel, Transkript, Antwort und erneutes Zuhören sowie Stopp und Hintergrundwechsel. Simulator-Pegel und synthetische Testsignale ersetzen diesen Nachweis nicht.

Die Stimme und Ausspracheaufbereitung sind unverändert; die zugehörigen [Victoria-Hörproben](../2026-09-26-s14-calm-voice/README.md) bleiben verfügbar. Das Geräteupdate erfolgt nach ausdrücklicher Freigabe dieser Vorschau und mit frischer Sicherung sowie Datenvergleich.

Der signierte Release-Archivbuild von Commit `3c8c9e5` ist erfolgreich. Das private Installationspaket für Build **2026092623** ist vorbereitet: Signaturen aller vier App-Komponenten, Gerätefreigabe, beide App-Gruppen, vier Sprachmodell-Dateien, 15 Dateien der Sprachausgabe und Lizenzen sind geprüft. Paket-SHA-256: `4c2016adf8c1caa224b1ffb3501295ef5e54a75c16eddca15c0da86c366db38b`. Archiv, Paket und Prüfbericht bleiben privat unter `/tmp/reha-soft-audio-20260926-s14.xcarchive` beziehungsweise `artifacts/private/soft-audio-device-20260926-s14/`.

Nach ausdrücklicher Freigabe wurde **Build 2026092623 am 26. September 2026 über den Hotspot installiert**. Frische Sicherung, Update ohne Deinstallation, App-Start und Datenvergleich sind im [Gerätebericht](../../soft-audio-device-update.md) dokumentiert. Die Prüfung des Mikrofons mit echter Sprache bleibt offen.
