> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Kokoro-Update auf dem iPhone 17

Am 26. September 2026 hat der Nutzer das Geräteupdate ausdrücklich freigegeben: „Ja mach alles was du brauchst.“ **Laßnitzhöhe 0.3.0, Build 2026092607**, wurde anschließend auf dem verbundenen iPhone 17 mit iOS 26.6 ohne Deinstallation installiert und erfolgreich gestartet. Die App-Kennung bleibt `at.rehakalender.personal`.

Die [Simulatorvorschau](apple-voice-preview.md) bleibt der Nachweis der vorherigen UI-Prüfungen. Eine [unveränderte Aufnahme vom echten iPhone](device/2026-09-26-s12/mehr.png) zeigt die installierte neue Oberfläche. Der Mac-Audiofehler betrifft die Simulatorausgabe; die installierte App verwendet lokale Modelle und die Audiohardware des iPhones.

## Sicherung und Datenerhalt

Die frische Sicherung liegt ausschließlich lokal unter `artifacts/private/kokoro-device-20260926-s12/backup/`. Sie enthält 103 Dateien mit insgesamt 534.550.620 Byte. App-Container und beide App-Group-Domänen wurden ausgelesen. Die beiden Gruppen enthielten nur leere Verzeichnisse; die Nutz- und Wiederherstellungsdaten liegen im App-Container. Alle Sicherungsdateien wurden mit SHA-256 erfasst und nach der Prüfung erneut gegen das Manifest geprüft.

Die vorherige signierte Version 2026092606 bleibt unter `artifacts/private/ui-refresh-20260926-s12/` erhalten; ihre Paketprüfsumme wurde vor der Installation bestätigt. Die neue signierte IPA und die Installationsnachweise liegen neben der frischen Sicherung. Private Originale, Datenbanken, Gerätekennungen, Sicherungen und signierte Pakete bleiben außerhalb von Git.

| Vergleich nach Installation und erstem Start | Ergebnis |
| --- | --- |
| SQLite-Integrität und Schema | `ok`, weiterhin Schema 7 |
| Datenbanktabellen | Alle 14 Tabellen vollständig unverändert |
| Pläne / Scans / Importdatensätze | 17 / 14 / 36 erhalten |
| Originalbilder | Alle 14 bytegleich |
| Dauerhafte Dateien | 69 bytegleich; ein Agenda-JSON semantisch identisch, lediglich anders serialisiert |
| Einstellungen | Alle vorhandenen Schlüssel und Werte unverändert |
| Kalender- und Wiederherstellungsdaten | Bestehende Import-, Operations-, Annahme- und Mutationsdaten unverändert |
| Kalenderaktionen während technischer Installation | Keine Termine angelegt, geändert oder gelöscht |

Nachweise: `backup-manifest.json`, `before-state.json`, `retention-after-install.json`, `installed-before.json`, `installed-after.json`, `install-result.json` und `processes-final.json` im privaten Auslieferungsverzeichnis. Die ursprüngliche App-Datencontainer-ID blieb beim Update erhalten.

## Signatur und Build

App und drei Erweiterungen wurden mit der bestehenden Entwickleridentität signiert. Alle vier Profile berechtigen das angeschlossene iPhone. Der Paketprüfer bestätigte App-Kennung, Version, App-Gruppen, Signaturen, vier Erkennungsdateien, 15 Kokoro-Dateien und sämtliche Lizenzprüfsummen.

- IPA-SHA-256: `60544525b52ea8ddab0f1daca03d69702d7b028eb481e54b630d40191acda6dc`
- Paketgröße: 339.884.582 Byte
- Profilablauf: 26. September 2026; früheste Erweiterung um 11:56:33 UTC. Vor Ablauf erneut signieren und ohne Deinstallation installieren.

Der erste Archivversuch innerhalb des von einem Dateianbieter verwalteten Arbeitsverzeichnisses scheiterte an Finder-Metadaten. Ein sauberer Archivbuild unter `/tmp/reha-kokoro-device-build` war erfolgreich; das daraus erzeugte Paket wurde vor Installation unabhängig verifiziert.

## Geräteprüfung

Die neue App wurde installiert, gestartet und direkt über die Entwicklerverbindung auf dem iPhone betrachtet. Die zusätzliche XCTest-App konnte noch nicht installiert werden: Das kostenlose Entwicklerprofil erlaubt höchstens drei gleichzeitig installierte Apps; alle drei Plätze sind bereits durch bestehende Apps belegt. Es wurde keine dieser Apps entfernt oder ersetzt.

Für Wiederholungen kann ausschließlich die Testkennung mit `REHA_TEST_BUNDLE_IDENTIFIER` an ein vorhandenes Profil angepasst werden. Der Standard bleibt `at.rehakalender.personal.native-tests`; `at.rehakalender.tests.RehaSmoke` wurde mit dem vorhandenen Profil erfolgreich gebaut und signiert. Die Kennungen der produktiven App und ihrer Erweiterungen werden dadurch nicht verändert. Der folgende Geräte-Testlauf scheiterte anschließend am belegten App-Limit, bevor ein Test ausgeführt wurde:

```sh
xcodebuild -project apple/Termine.xcodeproj -scheme Termine -configuration Release \
  -destination 'platform=iOS,id=<iPhone-UDID>' \
  -derivedDataPath /tmp/reha-kokoro-device-build -parallel-testing-enabled NO \
  -only-testing:TermineUITests/NativeFlowTests/testNeuralPlaybackStopAndRepeat \
  -only-testing:TermineUITests/NativeFlowTests/testVoiceTabIsExplicitAndPlaybackStopsOnTabChange \
  REHA_TEST_BUNDLE_IDENTIFIER=at.rehakalender.tests.RehaSmoke \
  -allowProvisioningUpdates test
```

Die direkte Bildschirmaufnahme und das Auslesen der Bedienungshilfen-Hierarchie über die bereits vertraute Entwicklerverbindung funktionieren. Die Aktivierung von Bedienelementen wird über diesen Weg auf dem Gerät nicht ausgeführt; der für alternative Berührungssteuerung benötigte Displaydienst wird nicht angeboten.

Die Hörbewertung von Martin wurde am installierten Gerät angefragt: **Sprechen → Zahnrad → Vorlesen**. Die tatsächliche Wiedergabe, Stopp/Wiederholen, Mikrofoneingabe mit langen Pausen, hörbares VoiceOver, Audio-Unterbrechungen und ein mit Wiedergabe bewegter Orb bleiben bis zu einer erfolgreichen Geräteprüfung offen. Vorhandene Simulatorprüfungen und erzeugte WAV-Dateien werden nicht als Ersatz für diese Prüfung ausgewiesen.
