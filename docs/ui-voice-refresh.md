> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Oberfläche und lokale Stimme – Überarbeitung vom 26. September 2026

Build 2026092606 überarbeitet die native iPhone-Oberfläche nach der Geräte-Rückmeldung. Dieser Stand ersetzt die früheren Standardentscheidungen zu pauschal großen Schaltflächen und Apple-Systemstimmen.

## Bedienung und Darstellung

- Das Plus oben öffnet wieder die Aufnahme-/Importauswahl. Kamera, Fotos und Dateien werden von einem stabilen Präsentationsbesitzer in `NativeShell` geöffnet. Das kurzlebige Menü besitzt keine eigenen Dialoge mehr. Auch weitere Planseiten verwenden diesen Weg.
- Die Agenda trennt den nächsten beziehungsweise laufenden Termin, weitere heutige Termine und „Bereits vorbei“. Uhrzeit steht links, Behandlung und Ort rechts. Zusätzliche Tage werden mit „Weitere Tage anzeigen“ in Dreiergruppen eingeblendet. Die gesamte Breite dieser Schaltflächen ist antippbar.
- „Mehr“ verwendet einheitliche Icons, Textfarben und Zeilen. Die gemeinsame Akzentfarbe ist ein ruhiges Petrol; im Dunkelmodus wird sie für lesbaren Kontrast aufgehellt.
- Unter Einstellungen → Darstellung stehen normale, große und sehr große Schaltflächen sowie Schriftgrößen bereit. Die Änderung wirkt unmittelbar; größere iPhone-Bedienungshilfenschrift wird nicht verkleinert. Die normalen Hauptaktionen haben mindestens 44 Punkte Höhe.

## Behobene Fehler

1. `CaptureActions` enthielt Präsentationszustände und Dialogmodifikatoren innerhalb eines Menüs. Beim Schließen des Menüs verschwand deren Besitzer. Die Aktionen signalisieren nun dem langlebigen Scanner-/Shell-Zustand, welcher Systemdialog geöffnet werden soll.
2. Vorlesen, Wiederholen und Stopp standen mit automatischem Button-Stil in einer gemeinsamen List-/Form-Zeile. Explizite voneinander unabhängige Button-Stile verhindern, dass mehrere Aktionen ausgelöst werden.
3. Freie Flächen innerhalb von `HStack`-Beschriftungen waren mit schlichtem Button-Stil nicht automatisch Trefferflächen. Die Agenda-Nachlade- und Vergangenheitszeilen verwenden eine ausdrückliche rechteckige Trefferfläche.
4. Audiofehler wurden zuvor ignoriert. Der neue Player zeigt Vorbereitung, laufende Wiedergabe, Ende oder einen konkreten Fehler. Stopp beendet sofort den Player, invalidiert laufende Generierungen und verhindert verspätete Wiedergabe. Wiederholen beginnt von vorne. Hintergrundwechsel, Audio-Unterbrechungen und der Verlust eines Audiogeräts stoppen ebenfalls; es gibt kein automatisches Wiederanlaufen.

5. Beim Wiederverwenden eines bereits vorhandenen Fotos ersetzt die Navigation die Aufnahme-ID durch die gespeicherte Plan-ID. Die Planansicht erhält jetzt ebenfalls diese Identität, damit ihr gespeichertes Lademodell nicht mehr zur verlassenen Aufnahme gehört. Der Simulator-Import hat diesen vorherigen Leerzustand reproduziert und die Korrektur geprüft.

## Neue lokale Stimme

[Supertonic 3 von Supertone](https://huggingface.co/Supertone/supertonic-3) unterstützt Deutsch und lokale ONNX-Inferenz. Die beiden enthaltenen Stimmen F1 und M1 sind als weibliche und männliche Stimme auswählbar. Standard ist F1 mit Geschwindigkeit 0,95×; einstellbar sind 0,75–1,25×. Zehn Entrauschungsschritte werden verwendet.

Die neun benötigten Dateien (398.960.003 Byte) sind mit Modellrevision und SHA-256 in `models/supertonic.lock.json` festgehalten und im iPhone-Paket enthalten. `tooling/build/fetch-speech-model.py` lädt nur diese öffentlichen Dateien. Laufende Sprachwiedergabe hat keinen Netzwerkpfad. OpenRAIL-M-Modelllizenz und MIT-Lizenz der Referenzimplementierung werden mitgeliefert.

Der Rust-Renderer verwendet den bereits vorhandenen ONNX Runtime 1.22.0. Swift steuert Speicherpuffer, Audio-Session, Player und Abbruch. Texte und erzeugtes Audio werden nicht auf Datenträger geschrieben. Längere Texte werden in begrenzten Abschnitten vorgelesen; der nächste Abschnitt wird während der Wiedergabe vorbereitet. Bei VoiceOver wird konkurrierende App-Wiedergabe vermieden.

Apples `SpeechAnalyzer` bleibt für die lokale **Erkennung** von Sprache zuständig. Er ist von der neuen **Ausgabestimme** getrennt und kann weiterhin eine einmalige Einrichtung auf dem iPhone benötigen.

## Prüfungen

Die Tests prüfen Auswirkungen statt ausschließlich die Existenz von Knöpfen:

- Menü → Kamera/Fotos/Dateien tatsächlich öffnen und schließen, auch aus dem Archiv.
- Echtes öffentliches Planbild aus dem System-Fotowähler importieren und erkennen.
- Modell-Audio starten, Status „playing“ abwarten, stoppen und erneut starten.
- Größen ändern und tatsächliche Schaltflächenhöhe vergleichen.
- Zusätzliche Tage einblenden und sichtbare Termine prüfen; vergangene Termine ausklappen.
- Bestehende Plan-, Erkennungs-, Speicher-/Undo-, Original- und Großschrift-Abläufe weiter prüfen.

Die separate reale Modellprobe (`speech_probe`) erzeugte beide deutschen Beispielsätze erfolgreich: 1,27 s zum Laden, danach 1,15 s (F1) beziehungsweise 1,14 s (M1) Rechenzeit auf dem Mac. Das ist keine iPhone-Latenzmessung und keine subjektive Qualitätsabnahme. Dateien: `artifacts/private/ui-refresh-20260926-s12/audio/`.

Automatisierte Simulatorprüfungen können die physische Kamera, Hörhilfen oder echte iPhone-Spracherkennung nicht ersetzen. Der Simulator prüft dafür die Kamerapräsentation, den echten Fotoimport und die echte lokale Audioausgabe. Die technischen Ergebnisse und die Auslieferung sind nachfolgend dokumentiert.


## Technische Abnahme

- 119 Rust-Tests bestanden; Swift-6-/UniFFI-Integration und generierte Bindings geprüft.
- 23 deutsche Sprachregelprüfungen bestanden; Tauri-Kompatibilitätsbuild erfolgreich.
- Alle 13 unterschiedlichen Simulatorabläufe bestanden: zunächst zwölf im vollständigen Lauf, anschließend gezielte Wiederholungen nach den Foto- und Zustandskorrekturen. Die abschließenden Läufe prüfen sowohl das Wiederöffnen eines schon vorhandenen PNGs als auch die neue Erkennung eines JPEGs. Das neue Bild lieferte acht Termine und eine ausdrücklich offene Dauer.
- Vorlesen, Stopp und Wiederholen mit echter Modellinferenz sowie Beenden beim Hintergrundwechsel bestanden. Beide Stimmen erzeugten in der separaten Modellprobe gültiges Audio; keine synthetischen Erfolgsmeldungen oder Audio-Mocks.
- Sichtprüfung der exportierten Simulatorbilder: Mehr in Hell, Agenda mit weiteren Tagen und aufgeklappten vergangenen Terminen in Dunkel, große Bedienungshilfenschrift, Sprachsteuerung und erkannter neuer Plan. Bei der Prüfung gefundene Trefferflächen-, Kontrast- und Navigationsfehler wurden korrigiert und erneut geprüft.

Die einzelnen Ergebnisse stehen in `artifacts/private/ui-refresh-20260926-s12/ui-verification.json`, die Logs in `verification-logs/`. Screenshots liegen dort in `full-ui-evidence/`, `final-ui-evidence/`, `duplicate-photo-evidence/` und `new-photo-evidence/`. Die beiden deutschen Stimmproben liegen in `audio/`.

Die Bewertung des Stimmklangs durch den Nutzer sowie physische Kamera, iPhone-Spracherkennung, Flugmodus und Hörhilfen bleiben gesonderte Geräteprüfungen. Das frühere Latenzziel wurde auf dem iPhone noch nicht gemessen.


## Installiertes Update und Datenerhalt

**Laßnitzhöhe 0.3.0, Build 2026092606** wurde am 26. September 2026 ohne Deinstallation auf dem verbundenen iPhone 17 installiert und gestartet. Die App lief auch nach dem abschließenden Datenvergleich.

Vor dem Update wurden der vollständige App-Container und beide App-Groups gesichert: 103 Dateien, 534.350.496 Byte. Die Sicherung liegt unter `artifacts/private/ui-refresh-20260926-s12/backup/`. Die vorherige signierte Version bleibt in `artifacts/private/voice-release-20260926-s12/` erhalten.

Nach dem Update ist SQLite-Schema 7 weiterhin intakt. Alle 14 Datenbanktabellen stimmen vollständig mit der Sicherung überein, darunter 17 Pläne, 14 Scans und 36 Importdatensätze. 14 Originalbilder und 28 Quell-/Eingangsdateien sind bytegleich. Bestehende Einstellungen wurden erhalten; lediglich die neuen Schlüssel für Stimme und Vorlesegeschwindigkeit kamen hinzu. Der Agenda-Schnappschuss unterscheidet sich nur in der JSON-Serialisierung, nicht in seinem Inhalt. Es wurden keine Kalenderänderungen auf dem Gerät zum Testen ausgelöst.

Der Vergleich verwendet die dauerhaften App-Daten, Einstellungen und beide App-Groups. iOS verweigerte beim ersten vollständigen Rücklesen eine nicht benötigte SplashBoard-Cachedatei; die dauerhaften Verzeichnisse wurden daraufhin separat vollständig gelesen und geprüft. Nachweise: `backup-manifest.json`, `migration-verification.json`, `installed-after.json`, `processes-after.json`.

Das Paket `artifacts/private/ui-refresh-20260926-s12/Lassnitzhoehe-0.3.0-2026092606.ipa` umfasst 408.162.365 Byte. Alle vier Signaturen, vier OCR-Dateien, neun Sprachdateien und mitgelieferten Lizenzen sind geprüft. SHA-256: `774eef8149ba2a270a9898d2f7bb0cc71c63f84babb250263bd35f0d8dca5040`.
