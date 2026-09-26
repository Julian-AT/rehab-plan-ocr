> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Lokale Artefakte und Arbeitsreserve

`make inventory-artifacts CLEANUP_MANIFEST=.local/maintenance/<neuer-name>.json`
erstellt eine Vorschau. `make clean-artifacts CLEANUP_MANIFEST=<derselbe-pfad>`
führt genau diese Vorschau aus. Es gibt keine altersbasierte Löschung unbekannter
Bestände. Die versionierte [Aufbewahrungsregel](../../config/storage/retention.json)
benennt erlaubte Zwischenprodukte, Verbraucher und Wiederaufbau pro Gruppe.

Die erste Regel umfasst ausschließlich Compiler-Zwischenprodukte und Indizes.
Modelle, Checkpoints samt Optimizer, Datensätze, Versuchsberichte, Originale,
Referenzen, Gerätesicherungen, Binärprodukte und Archive bleiben erhalten.
Fremde Simulatoren und externe Originale werden weder durchlaufen noch gelöscht.
Ein reiner Textsuchtreffer oder dessen Fehlen erlaubt keine Löschung.

Vor Vorschau und Ausführung werden laufende Buildprozesse, offene Dateien,
registrierte Worktrees, versionierte Dateien und symbolische Verbraucher geprüft.
Ein exklusiver Dateilock serialisiert Bereinigungen. Vorhandene aktive Verbraucher
verhindern die Ausführung. Während der Bereinigung keine neuen Builds, Trainings,
Downloads oder Datenprüfungen starten; fremde Prozesse verwenden diesen Lock nicht.
Neu auftauchende/geänderte Dateien führen zum Abbruch, sie werden nicht rekursiv
mitgelöscht. Leere Verzeichnisse bleiben bewusst bestehen.

Die Vorschau enthält SHA-256, Größe, Modus und Dateiidentität jedes Kandidaten.
Die geschützten lokalen Dateien und Symlink-Ziele erhalten eine gemeinsame
Inhaltsprüfsumme; diese wird vor und nach der Ausführung erneut geprüft.
Vorschau, Journal und Abschlussbeleg bleiben privat unter `.local/maintenance`.
Historische Berichte werden nicht umgeschrieben.

Vor jedem Unlink wird die Absicht dauerhaft protokolliert. Nach einem Abbruch
denselben Ausführungsbefehl wiederholen: fehlende Dateien sind nur mit zuvor
geschriebener Löschabsicht zulässig. Nach einem abgeschlossenen Durchlauf liefert
eine Wiederholung nur den vorhandenen Beleg und entfernt keinen späteren Neubau.
Eine geänderte Regel oder Datei benötigt eine neue Vorschau. Beschädigte Belege
werden zur Untersuchung erhalten und nicht überschrieben.

`make check-storage PEAK_GIB=4` prüft 20 GiB Reserve **plus** vier GiB erwarteten
Spitzenbedarf. Logische Größen und belegte Blöcke sind keine garantierte Ersparnis:
APFS kann Extents teilen. Der Abschlussbeleg nennt die tatsächlich beobachtete
Änderung des freien Volume-Speichers; parallele Systemaktivität bleibt ein Einfluss.

Die großen Make-Einstiege für App-/Assistentenbuilds, Training/Wiederaufnahme und
Export prüfen diese Reserve vor ihrer Arbeit. `quality.py build`, `test-ios` und
die Speicherprüfungen des nativen Buildskripts verwenden dieselbe Regel. Die
Spitzenbudgets sind konservative Planwerte (3/4/8 GiB), noch keine gemessenen
Höchststände. Direkte historische Trainingsskripte behalten ihre quellidentischen
Wiederaufnahmeverträge; sie sind kein alternativer Einstieg zur Speicherumgehung.

Noch offen: zentrale unveränderliche Modellobjekte, checkpointbewusste Begrenzung
aktiver Trainings und bereinigte alte Exportduplikate. Diese erste geprüfte Regel
erlaubt deren Entfernung ausdrücklich noch nicht.

## Ausgeführt am 26. September 2026

Vorschau `.local/maintenance/intermediates-20260926-s18-002.json`, SHA-256
`070214fc5ec02b67e01795aaa263e8df19ca2eaf79be9d5da8e6057d80a0eef5`:
4.518 Dateien mit 148.424.974 logischen Bytes entfernt. Gemessene Volume-Differenz
135.393.280 Bytes (129,1 MiB), frei danach 3.069.435.904 Bytes. **20 GiB nicht erreicht.**
Die Inhaltsprüfsumme aller 116.748 geschützten Dateien/Symlink-Ziele blieb vor und
nach Ausführung identisch:
`85fd462bf4fc718859b00f389b9bb2833cba84d2216dbd35aa1463108557f39a`.
Journal und Abschlussbeleg liegen neben der Vorschau. Eine abgeschlossene
Wiederholung wird geprüft; zusätzlicher Systemverbrauch bleibt separat sichtbar.
