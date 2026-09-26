> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](../retired-assets.json).

# Vorschau – Kalenderseiten und lokales Gespräch

Build **2026092612**, Version **0.3.0**. Ausschließlich synthetische Termine in dieser Vorschau. Nach Nutzerfreigabe auf dem iPhone 17 installiert; [Geräteupdate und Datenvergleich](../continuous-voice-device-update.md) bestanden.

- Kalenderseiten: Wischen, Zurückgleiten und Wochenblättern (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/kalender-seiten.mp4`)
- Victoria mit Text während echter Wiedergabe (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/victoria-text.mp4`)
- Hörprobe: Frühstück eins/zwei, Behandlung zwölf, Räume (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/victoria-fruehstueck.wav`)
- Hörprobe: Datum, Uhrzeiten und Physiotherapie (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/victoria-kalender.wav`)

Die Videos sind Bildschirmmitschnitte ohne Tonspur. Die separaten WAV-Hörproben stammen aus demselben unveränderten Victoria-Modell; sie sind keine nachträglich unterlegte Audiospur der Videos.

| Kalender | Gespräch |
| --- | --- |
| Hell (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/kalender-hell.png`) | Text während Victoria (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/text-waehrend-victoria.png`) |
| Dunkel (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/kalender-dunkel.png`) | Fortschreitender Text (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/text-folgt-audio.png`) |
| Wochenblättern (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/wochenblaettern.png`) | Große Schrift (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/sprechen-grosse-schrift.png`) |
| Farblegende (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/farblegende.png`) | Kalender mit großer Schrift (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/kalender-grosse-schrift.png`) |
| Reduzierte Bewegung (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/bewegung-reduziert.png`) | Vorschlag vor Bestätigung (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/vorschlag-bestaetigen.png`) |
| Geprüfte Kalenderwerkzeuge (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/kalenderwerkzeuge.txt`) | Erst nach Bestätigung gespeichert (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/vorschlag-gespeichert.png`) |

[Umsetzung, Tests und Grenzen](../continuous-calendar-voice.md) · Prüfprotokoll (`git show fc1e934601b4:docs/preview/2026-09-26-s12-continuous/verification.json`). Elf unterschiedliche UI-Prüfungen sind über die dokumentierten Läufe bestanden, darunter echte Victoria-Wiedergabe mit Textfortschritt, Stoppen, Kalenderseiten, große Schrift, reduzierte Bewegung und ausdrückliche Speicherbestätigung. Wortmarken liegen neben den WAV-Dateien; Herkunft der Bilder und Videos ist dokumentiert.

Für die Geräteabnahme stehen insbesondere reale Spracherkennung, Modellfolgefragen, automatische Gesprächsrunden und Echounterdrückung noch aus. Prüffolge nach Installation: „Was habe ich am 26. September 2026?“, „Und am Dienstag danach?“, „Wo ist der zweite Termin?“, eine Datumsberichtigung, „Habe ich keine Termine?“, mehrere Treffer und ein Änderungsvorschlag, der erst am Bildschirm bestätigt wird. Danach kurze/lange Denkpausen, Hineinsprechen, Lautsprecherecho, Geräusche, Pause, X, Hintergrund und Kopfhörerwechsel prüfen.

Die gemäß [AGENTS.md](../../../../AGENTS.md) erforderliche Freigabe liegt vor. Frische Sicherung, Update ohne Deinstallation und Vergleich der dauerhaften Daten sind abgeschlossen.
