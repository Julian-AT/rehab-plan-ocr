> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Termine 0.3.0: Agenda, Widgets und Erinnerungen

Die normale Oberfläche verwendet die Referenz `image.png`: helle Flächen,
24-Punkt-Karten, große Uhrzeiten und eine schwarze schwebende Navigation. Die
Systemdarstellung, Terminprüfung, Originalfotos, Feldbestätigungen, gespeicherten
Korrekturen und Kalenderbestätigungen bleiben verfügbar. Die Entwickleransicht
ist über Einstellungen erreichbar.

## Daten und Zuständigkeit

`src-tauri/src/agenda.rs` übergibt ausschließlich erfolgreiche `ImportRecord`s
mit EventKit-ID. OCR-Entwürfe und ICS-Exporte sind ausgeschlossen. `AgendaService`
liest aktuelle EventKit-Werte auf derselben seriellen Queue wie Kalenderimporte.
Fehlender Zugriff beziehungsweise ein nicht mehr verfügbarer Kalender ist kein
Löschbeweis. Nach verlorenen EventKit-IDs wird zusätzlich nach dem App-Marker im
ursprünglichen Kalender gesucht. Mehrdeutige oder fremde Bindungen bleiben geschützt.

`agenda-private-v1.json` liegt im bisherigen privaten Application-Support-Verzeichnis.
Es enthält den nativen Import-Cache, Einstellungen, ausstehende Öffnungen und das
Alarmjournal. Es ersetzt weder SQLite noch geprüfte Werte. Das App-Group-Verzeichnis
`group.at.rehakalender.personal` enthält ausschließlich `agenda-v1.json` mit
Schema-Version, Aktualisierungszeit, Zugriffsstatus und Termin-ID, Beginn/Ende,
Zeitzone, Behandlung, Raum und Aktualisierungsstatus. Das Schreiben erfolgt atomar
mit Dateischutz bis zur ersten Geräteentsperrung und Ausschluss aus Backups. Fotos, Quelltext, Therapeuten,
Notizen und Kalender-IDs werden nicht in den gemeinsamen Datensatz geschrieben.

Die native Registrierung erfolgt vor `ffi::start_app()`. Widget-URLs verwenden
das offizielle Tauri-Deep-Link-Plugin. Mitteilungsöffnungen werden privat gespeichert,
von der Weboberfläche gelesen und erst nach der Übernahme quittiert.

## Erinnerungen

Erst „Erinnerungen aktivieren“ fragt die Systemberechtigung an. Standard sind zehn
Minuten, alternativ aus/5/15/30/60 Minuten, jeweils mit Ton und Detailvorschau als
separaten Optionen. Die Anzeige und Zustellung folgen weiterhin den iOS-Einstellungen.

`ReminderTransfer` journalisiert die Phasen `calendar`, `scheduling`, `app` und
`restoring`. Eine App-Mitteilung muss bestätigt sein, bevor ein passender eigener
Kalenderalarm entfernt wird. Bei Fehlern wird zuerst die Kalenderreserve bestätigt
und danach die App-Mitteilung entfernt. Ein erneuter Abgleich kann jede Phase
wiederholen. Einstellungen ändern keine klinischen Freigaben oder SQLite-Bindungen.

Es werden höchstens 60 reguläre Mitteilungen geplant. Drei weitere Plätze sind für
Schlummern und ein Platz für die erfundene Testmitteilung reserviert. Weiter in der Zukunft liegende
Termine behalten die gewählte Kalenderreserve. Schlummern wird gegen den aktuellen
EventKit-Beginn geprüft und nur angenommen, wenn fünf Minuten später noch vor dem
Beginn liegt. Mehrere, absolute, ortsabhängige oder manuell veränderte Alarme,
Wiederholungen und schreibgeschützte Kalender bleiben geschützt.

Der Abgleich läuft nach Kalenderübernahmen und Einstellungsänderungen, beim Start,
im Vordergrund, nach EventKit-Änderungen und bei verfügbaren BGAppRefresh-Aufrufen.
Ohne Kalenderzugriff werden App-Mitteilungen zurückgenommen; das private Journal
bleibt für die spätere Wiederherstellung erhalten. Ohne Zugriff kann die App keine
bereits entfernten Kalenderalarme zurückschreiben. Dieser Zustand wird angezeigt.
Beim Löschen aller App-Daten werden verwaltete Kalenderreserven zuerst hergestellt;
ein nicht zugänglicher Kalender verhindert diesen Löschvorgang.

## Native Ansichten und Projektneuerzeugung

- `apps/ios/Extensions/Widgets/AgendaWidget.swift`: kleine/mittlere Homescreen- und rechteckige
  Sperrbildschirmansicht. Kalenderarithmetik bestimmt Tageswechsel einschließlich
  Sommerzeit. Vorberechnete Einträge berücksichtigen Beginn, Ende und Veraltung.
- `apps/ios/Extensions/NotificationContent/NotificationViewController.swift`: gemeinsame SwiftUI-
  Terminkarte in der aufgeklappten Systemmitteilung, mit Systemaktionen zum Öffnen
  und Schlummern. `UserNotificationsUI.framework` ist ausdrücklich im Target
  verlinkt; ein Swift-Protokollimport allein lädt den Erweiterungskontext nicht.
- `plugins/calendar/ios/Sources/AgendaShared`: gemeinsame Daten, Formatierung,
  Terminkarte und testbare Alarmzuständigkeit.
- `ios/extensions.yml` und `scripts/sync-ios-project.mjs`: versionierte Targets,
  Entitlements und früher Startaufruf. `npm run ios:sync` stellt sie nach
  `npm run tauri ios init -- --ci` wieder her. `prebuild` und `predev` übernehmen
  ebenfalls den Abgleich. App-ID und Signierungsteam bleiben unverändert.

WidgetKit bestimmt den tatsächlichen Aktualisierungszeitpunkt; vorberechnete
Einträge sind keine Zusage sekundengenauer Ausführung.
[Apple: Widgets aktuell halten](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/).
Die äußere Mitteilungsform bleibt systemgesteuert.
[Apple: Mitteilungsansichten](https://developer.apple.com/documentation/usernotificationsui/customizing-the-appearance-of-notifications).

## Reproduzierbare Prüfung

```sh
npm run lint
npm run typecheck
npm test
npm run test:e2e
cargo test -p reha-core
sh scripts/test-agenda.sh
sh scripts/build-ios.sh simulator
xcodegen generate --spec apps/ios/IntegrationTests/project.yml
```

Der Simulator-Build signiert App und Extensions lokal ad hoc mit ihren
App-Group-Entitlements. Damit kann die installierte Simulator-App den gemeinsamen
Speicher tatsächlich verwenden. Die UI-Tests
`testSimulatorExpandedTestNotification` und `testSimulatorColdTestNotification`
planen die erfundene Mitteilung über die echte App, öffnen die Systemkarte und
kehren über „Termin öffnen“ zur App zurück. Vor dem Screenshot wird auf den
Inhalt der Extension gewartet.

Die Swift-Prüfung enthält 52 Assertions zu Sommer-/Winterzeit, laufenden Terminen,
60-Plätze-Auswahl, Schlummergrenzen, fremden Alarmen, Datensparsamkeit und Fehlern
beziehungsweise Abbrüchen zwischen den Übergabeschritten. Die nativen XCTest-Tests
prüfen echte EventKit-Korrekturen, erfolgreiche lokale Einplanung, Alarmrückgabe,
Schlummern, Löschung und tatsächliche SwiftUI-Renderings. Mutationstests sind auf
Simulatoren begrenzt. Webtests verwenden ausschließlich erfundene Termine.

Die signierte Installation und ihre Nachweise werden in
`artifacts/private/iphone-030/` lokal aufbewahrt. Widgets fügt der Benutzer über
die iOS-Widgetauswahl hinzu.

## Stand der Abnahme am 26. September 2026

- 36 Playwright-Tests auf Chromium und mobilem WebKit, 13 TypeScript-Unit-Tests,
  71 Rust-Tests und 52 native Zustandsprüfungen bestanden.
- Native EventKit-/Mitteilungsintegration sowie gerenderte kleine, mittlere,
  Sperrbildschirm- und aufgeklappte Mitteilungsansichten bestanden. Großschrift
  wurde mit den gemeinsamen SwiftUI-Ansichten und der Weboberfläche geprüft.
- Native Öffnung bei kaltem und warmem Start und erneuter Vordergrundwechsel
  bestanden. Die URL-Prüfung verwendet exakt das Schema der Widget-Links.
- Die tatsächlich aufgeklappte Systemmitteilung einschließlich ihres
  SwiftUI-Inhalts und „Termin öffnen“ wurde nach Kalt- und Warmstart erfolgreich
  geprüft. Screenshots liegen als `030-system-expanded-notification-cold.png`
  beziehungsweise `-warm.png` bei den privaten Nachweisen.
- Die installierte Widget-Extension wurde in der iOS-Widget-Galerie gerendert
  und visuell geprüft (`030-system-widget-gallery.png`). Das WidgetKit-Protokoll
  bestätigt erfolgreiche kleine und mittlere Vorschauen samt App-Group-Zugriff.
- `tauri ios init --ci`, anschließende Wiederherstellung und Simulator-Build
  erfolgreich. Signierter Release-Build und IPA-Export mit allen drei Bundle-IDs
  und App-Group-Entitlements erfolgreich; `codesign --verify --deep --strict`
  bestätigt.
- Version 0.3.0 wurde auf dem verbundenen iPhone 17 installiert und gestartet.
  SQLite bleibt integer: 9 Scans, 32 Importe, 32 Operationen, 4 Pläne, 2 Einstellungen
  und 2 Fehlernachweise stimmen direkt nach der Installation zeilenweise mit der
  Sicherung überein. Originalfotos wurden vorab ebenfalls lokal gesichert.
  Der spätere Vollabgleich bestätigt zusätzlich alle 31 bisherigen Original- und
  Begleitdateien bytegleich sowie sämtliche ursprünglichen Datensätze unverändert.
  Ein inzwischen hinzugekommener erneuter Erkennungslauf und die geänderte
  Darstellungseinstellung sind im gesonderten finalen Prüfprotokoll dokumentiert.
- Die individuelle Widget-Platzierung und die Wahrnehmung der Testmitteilung auf
  dem gesperrten Gerät benötigen die Mitwirkung des Benutzers. Getönte Widgets
  verwenden semantische Systemfarben; eine Prüfung aller persönlichen Farbtöne
  und ein vollständiger manueller VoiceOver-Durchlauf sind nicht abgeschlossen.

Die weitergehende Xcode-Geräteautomation wurde durch die Meldung
„iPhone may need to be unlocked to recover from previously reported preparation
errors“ unterbrochen. Der signierte App-Start per `devicectl` ist separat bestätigt.
Der native Import-Cache auf dem Gerät enthält alle 32 bestehenden Kalenderimporte;
reguläre App-Erinnerungen sind vor der ausdrücklichen Aktivierung ausgeschaltet.

Der abschließend korrigierte, signierte Build liegt unter
`artifacts/private/iphone-030/Termine-0.3.0.ipa`. Seine Framework-Verknüpfung und
Signaturen wurden geprüft. Beim Übertragen dieser letzten Korrekturen war das
iPhone inzwischen getrennt (`CoreDeviceError 1011`, Gerät nicht erreichbar).
Dieser Build muss daher noch installiert werden, sobald das iPhone wieder
verbunden und entsperrt ist; der zuvor installierte 0.3.0-Stand bleibt auf dem Gerät.
