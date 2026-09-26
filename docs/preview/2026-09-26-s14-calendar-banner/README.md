> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Roter Kalenderstatus-Banner

„Kalenderdaten unvollständig“ und „Status prüfen“ stehen gemeinsam auf einem roten Banner unter der Tagesauswahl. Beide verwenden dieselbe dynamische Schriftgröße (`subheadline`) und weiße Schrift. Die unterstrichene Statusaktion behält mindestens 44 Punkte Bedienhöhe und öffnet weiterhin den Kalenderstatus.

Bei knapper Breite oder großer Schrift wechselt die Anordnung von nebeneinander zu untereinander. Der Kontrast von Weiß zum Bannerrot beträgt **6,48:1**.

Im iPhone-17-Simulator visuell geprüft: [Hell](light.png), [Dunkel](dark.png) und [größte Schrift](large.png). Der Bannertext und die Statusaktion sind in allen drei Ansichten vollständig sichtbar. Die Aufnahmen zeigen keine persönlichen Termine.

Simulator-Build, Swift-Formatprüfung und `git diff --check` bestanden. Diese Vorschau dokumentiert die Anpassung während des gemeinsamen UI-Durchgangs; sie bestätigt keine Reparatur fehlender Kalenderdaten.
