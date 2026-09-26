> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Ruhiger Gesprächsbildschirm – Build 2026092611

Version 0.3.0. Diese Überarbeitung ersetzt den Orb-Entwurf aus Build 2026092610. Die [neue Simulatorvorschau](preview/2026-09-26-s12-smooth-voice/README.md) ist die Grundlage für die nächste Gerätefreigabe.

## Oberfläche

Die grüne Kugel bleibt kreisrund. Im Inneren fließen helle und dunklere Grüntöne weich ineinander. Die gemessenen Mikrofon- und Wiedergabepegel beeinflussen die Verläufe und eine dezente Größenänderung; Pegelsprünge werden über 220 Millisekunden interpoliert. Die bisherige wellige Außenkontur entfällt. „Bewegung reduzieren“ friert die Darstellung vollständig ein; bei inaktiver App pausiert der Animationszeitgeber.

Unten steht ein nativer SwiftUI-Knopf **Gespräch starten** mit dem SF Symbol `mic`. Während einer Aufnahme wird daraus **Fertig** mit `checkmark`. Größe, Schrift, Form und Interaktion folgen dem nativen prominenten Schaltflächenstil. Das Emoji und die eigene Beschriftungsgestaltung entfallen.

Oben links bleibt Abbrechen. Oben rechts stehen **Gesprächsdetails** und Spracheinstellungen als native Werkzeugleistenknöpfe. Gesprächsdetails enthalten weiterhin Texteingabe, Transkript, Antworten, Wiederholen und manuelle Kalenderaktionen.

Kalender, Kamera, lokale Victoria-Stimme, Erkennung und Gesprächslogik bleiben gegenüber Build 2026092610 erhalten. Es gibt keine Datenmigration, zusätzliche Abhängigkeit oder Änderung öffentlicher Schnittstellen.

## Abnahme

Die [Vorschau mit Prüfnachweisen](preview/2026-09-26-s12-smooth-voice/README.md) enthält Hell/Dunkel, größte Bedienungshilfenschrift, reduzierte Bewegung und einen Mitschnitt während tatsächlicher Victoria-Wiedergabe. Der Bildschirmmitschnitt enthält keine Audiospur; die unveränderten Victoria-Hörproben sind daneben verlinkt.

Die schon bekannten Simulatorgrenzen gelten weiterhin: lokale deutsche Diktiererkennung ist dort nicht verfügbar, freie Foundation-Models-Antworten scheitern an fehlenden Systemmodelldaten. Mikrofontranskription und freie Antworten müssen deshalb auf dem iPhone geprüft werden. Diese Überarbeitung ändert die betroffenen Schnittstellen nicht.

Das Geräteupdate wartet auf ausdrückliche Freigabe der neuen Vorschau und der Hörproben gemäß `AGENTS.md`. Danach frisch sichern, ohne Deinstallation aktualisieren und dauerhafte Daten vergleichen. Bis dahin bleibt Build 2026092609 installiert.

API-Grundlage: Apples [MeshGradient](https://developer.apple.com/documentation/swiftui/meshgradient) für die interpolierten Verläufe und native SwiftUI-Schaltflächen.
