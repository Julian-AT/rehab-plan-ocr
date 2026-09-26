> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Zitrus & Olive

Native Umsetzung der gewählten **Palette 07** aus der [HTML-Auswahl](../../decisions/calendar-palette.html) in **Build 2026092624**.

Die Auswahl stand auf 32 % Farbstärke. Kalenderkarten und Tagesliste übernehmen entsprechend **32 % Deckkraft in Hell** und **36 % in Dunkel**. Die dunklen Akzente entsprechen exakt der HTML-Vorschau. Titel und Zusatztexte bleiben neutral, Kalendergrößen und Kartenaufteilung unverändert.

| Terminart | Akzent Hell | Akzent Dunkel |
| --- | --- | --- |
| Therapie | `#85A832` | `#99B653` |
| Ärztliche Termine | `#41A58B` | `#5FB39E` |
| Mahlzeiten | `#EABC21` | `#EDC745` |
| Organisatorisches | `#E8883F` | `#EC9B5E` |
| Sonstiges | `#C97086` | `#D28799` |

Die zugehörige Legende verwendet dieselben adaptiven Akzente. **„Vergangene Termine anzeigen“** erhält im Zustand „Zeit zum Erholen“ ausdrücklich die grüne Schriftfarbe `AppPalette.tint`. Die Aktion zeigt weiterhin die vergangenen Termine an.

Der [Kontrastnachweis](contrast.json) prüft alle fünf Kategorien auf normalen und erhöhten Hintergründen in Hell und Dunkel. Der kleinste Textkontrast innerhalb der Terminkarten beträgt **4,97:1**. Alle Akzentwerte und Deckkräfte stimmen mit der ausgewählten HTML-Palette überein.

## Simulatoransichten

Die nativen Aufnahmen enthalten ausschließlich synthetische Termine.

| Ansicht | Hell | Dunkel |
| --- | --- | --- |
| Kalenderkarten, kurze und überlappende Termine | [Aufnahme](cards-light.png) | [Aufnahme](cards-dark.png) |
| Tagesliste | [Aufnahme](list-light.png) | [Aufnahme](list-dark.png) |
| Weitere Terminarten in der Tagesliste | [Aufnahme](list-lower-light.png) | [Aufnahme](list-lower-dark.png) |
| Farblegende | [Aufnahme](legend-light.png) | [Aufnahme](legend-dark.png) |
| Größte Schrift | [Aufnahme](large-light.png) | [Aufnahme](large-dark.png) |
| Grüner Link nach Tagesabschluss | [Aufnahme](past-events-light.png) | [Aufnahme](past-events-dark.png) |

Die zusätzlichen `large-…-0` bis `-4`-Aufnahmen zeigen die einzelnen Kategorien beim Scrollen mit größter Schrift.

## Prüfung

- Simulator-Build erfolgreich; Swift-Formatierung und `git diff --check` bestanden.
- `CalmCalendarTests/testMutedPaletteCardsListAndLegend`: bestanden, Hell/Dunkel einschließlich Tagesliste und Legende.
- `CalmCalendarTests/testLargeCalendarText`: bestanden, alle Kategorien mit größter Schrift in Hell/Dunkel.
- `AgendaPreviewTests/testFinishedDayAndAutomaticCompletion`: bestanden, abgeschlossener Tag, Öffnen vergangener Termine und automatischer Tagesabschluss.
- Insgesamt **3 UI-Tests, 0 Fehler**, dokumentiert in `/tmp/reha-zitrus-preview.xcresult` und `/tmp/reha-zitrus-ui.log`.
- Der grüne Link wurde zusätzlich im dunklen Simulator geöffnet und visuell kontrolliert; Kalenderkarten und Linkschrift sind in beiden Erscheinungsbildern geprüft.

Build **2026092624** wurde am 26. September 2026 nach ausdrücklicher Freigabe und frischer Sicherung ohne Deinstallation auf dem iPhone installiert. Erster App-Start und Datenerhalt vor und nach diesem Start sind geprüft; der [Gerätebericht](../../releases/history/zitrus-device-update.md) dokumentiert die Nachweise.

## Aktuelle Reproduktion

Die [visuelle Prüfanleitung](../../../apps/ios/Tests/Visual/README.md) erfasst alle
22 Ansichten mit festem Referenzdatum. Die Originalbilder und ihre Prüfsummen
bleiben unverändert. Der jüngste vollständige Lauf `ui-complete-20260926-s20-004`
an `01fbafe` besteht alle 70 UI-Tests einschließlich der drei Aufnahmetests.
Der strenge Vergleich `visual-baseline-20260926-s20-004` erreicht **17/22** exakte
Bildtreffer. Vier Unterschiede liegen ausschließlich in der nativen
Scrollindikatorspur; der dunkle Tagesabschluss hat weiterhin eine kleine
Rasterabweichung. Die vollständige visuelle Freigabe bleibt offen. Frühere
[Prüfberichte](../../../ml/experiments/2026-09-26-s18-visual-baseline.md) bleiben erhalten.

Der [Aufnahmevertrag](capture-contract.md) dokumentiert die einzelnen neun
historischen Abweichungen und die inzwischen reproduzierten Scrollpositionen.
Die Originalbilder und Vergleichsschwellen bleiben erhalten.

Die Ergebnisauswertung prüft ab 26. September 2026 zusätzlich die Identitäten der drei
Aufnahmetests im vollständigen XCTest-Baum. Jeder muss im richtigen Testbundle
genau einmal bestanden sein; die zugehörigen Bilder müssen aus dem jeweils
festgelegten Test stammen. Damit können auch Aufnahmen eines größeren gemeinsamen
UI-Laufs ausgewertet werden. Dessen Gesamtstatus muss weiterhin bestanden sein,
ohne fehlgeschlagene oder übersprungene Tests. Fehlende, wiederholte oder fremde
Aufnahmetests lassen sich nicht durch eine passende Gesamtzahl ersetzen.
Pixelvergleich, Originalhashes und Ausschluss der oberen 160 Systempixel ändern
sich dadurch nicht. Ein historisches Result-Bundle wird weiterhin nicht dem
heutigen App-Quellstand zugeschrieben.
