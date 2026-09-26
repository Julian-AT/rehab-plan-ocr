> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Victoria und Kalender · Simulatorvorschau

Laßnitzhöhe **0.3.0, Build 2026092609**. Die Hörproben stammen aus der lokalen Rust-Sprachausgabe mit den originalen Victoria-Gewichten und synthetischen Termindaten.

- [Victoria: Terminansage](victoria-kalender.wav)
- [Victoria: langsames Sprechtempo](victoria-langsam.wav)
- [Victoria: längere Antwort](victoria-lange-antwort.wav)

[Umsetzung, Modellherkunft und Prüfung](../../victoria-calendar-update.md).

| Kalender | Sprechen |
| --- | --- |
| [Grüne Termine](termine-hell.png) | [Victoria-Einstellungen](spracheinstellungen.png) |
| [Beginn 06:00](kalender-ab-sechs.png) | [Ruhezustand](sprechen-ruhe.png) |
| [Ende 18:00](kalender-bis-achtzehn.png) | [Echte Wiedergabe](sprechen-echte-wiedergabe.png) |
| [Überlappungen, dunkel](ueberlappung-dunkel.png) | [Reduzierte Bewegung](bewegung-reduziert.png) |
| [Kurze Termine](kurze-termine.png) | [Große Schrift](sprechen-groesste-schrift.png) |
| [Tagesliste mit großer Schrift](tagesliste-groesste-schrift.png) | [Terminbestätigung](sprachvorschlag-vor-bestaetigung.png) |

Das [Video der Sprachkugel](sprechen-audio.mp4) zeigt 3,35 Sekunden tatsächlicher Victoria-Wiedergabe im Simulator. Es enthält keine Tonspur. Der [Pegelnachweis](audio-meter.json) stammt vom AVAudioPlayer: 103 gemessene Wiedergabeschritte, Spitzenpegel 0,404. Die drei WAV-Hörproben sind separat abspielbar.

Zehn unterschiedliche UI-Prüfungen, 60 Kerntests und die unabhängige Kalenderprobe bestanden. [Prüfergebnisse](verification-results.json), [Modellkonvertierung](model-export.json), [Videoherkunft](video-origin.json) und [Dateiprüfsummen](preview-manifest.json).

Die Bilder enthalten ausschließlich synthetische Termine. Die lokale Spracherkennung ist im Simulator nicht verfügbar; ihr nativer Hinweis und Abbrechen sind geprüft. Mikrofoneingabe und Telefonunterbrechungen auf dem persönlichen Gerät wurden nicht erneut getestet. Eine Klangbewertung bleibt beim Nutzer.

Das [Geräteupdate auf Build 2026092609](../../victoria-calendar-update.md#geräteupdate) ist abgeschlossen: frische Sicherung, Installation ohne Deinstallation, erfolgreicher App-Start und vollständiger Datenerhalt sind geprüft.
