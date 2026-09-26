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

Noch offen: zentrale unveränderliche Modellobjekte, checkpointbewusste Begrenzung
aktiver Trainings, bereinigte alte Exportduplikate und automatische Durchsetzung
der Reserve an allen großen Einstiegspunkten. Diese erste geprüfte Regel erlaubt
deren Entfernung ausdrücklich noch nicht.
