# MD-Connect

MD-Connect ist ein iPadOS-Client (SwiftUI) für einen **FiveNet**-Roleplay-Server.
Die App verbindet sich über gRPC-Web mit FiveNet-Instanzen und
bietet Zugriff auf Bürger-/Fahrzeugdatenbank, LiveMap, Leitstelle, Wiki, Dokumente, Berufe,
Qualifikationen, Kalender, Mail und weitere Module.

> **Hinweis:** MD-Connect ist **nicht Teil des FiveNet-Projekts** und wird vom FiveNet-Team
> weder unterstützt noch gesponsert. Weitere Details siehe [Marken-Hinweis](#marke) und `NOTICE`.

## Funktionen

- **Übersicht** – Modul-Grid, Profil-Hero, Schnellzugriff; alternativ **Schnellansicht** („Effizienz-Layout“) mit Deiner Einheit, Deinem Einsatz, offenen Einsätzen & Modul-Tiles
- **Bürger / Fahrzeuge** – durchsuchbare Datenbanken mit Pagination, WANTED-Badges, Detailansichten
- **LiveMap** – Karte mit Einheiten-/Einsatz-Markern, Einsatz-Heatmap, „Meine Einheit“-Ansicht, Einheit beitreten/verlassen
- **Leitstelle** – Einsätze erstellen/übernehmen, Einsatz-Zeitstrahl, Einheiten, Aktivität, Archiv, Duty-Unit
- **Wiki** – Seiten mit Inhaltsverzeichnis, Pins, Live-Suche, Rich-Content (Tiptap/HTML)
- **Dokumente** – Suche, Kategorien, Status-Segmente, Aktionen (Schließen/Genehmigen/Anfragen/Reminder/Löschen), Inhalt-Editor
- **Berufe** – Übersicht, Kollegen mit Labels, Aktivität, Stempeluhr, Führungsregister, Urlaub
- **Qualifikationen** – eigene & alle Qualifizierungen, Detail mit Inhalt/Tutor (Anfragen & Ergebnisse benoten)
- **Kalender** – Monatsansicht mit Urlauben & FiveNet-Kalendern, Datums-Sprung, Termin erstellen
- **Mail** – Posteingang/Archiv, Suche, Thread-Detail, Verfassen/Antworten
- **Einstellungen** – Job-Props, Rollen & Berechtigungen, Audit-Log, Discord, Leitstelle, Gesetzbücher, Datenspeicher, Konten, Config, Cron
- **Alarm** – roter Vollbild-Alarm bei Einsatz-Zuweisung + Verstärkung-Alarm
- **Global Search** – modulübergreifende Suche (Bürger/Fahrzeuge/Einsätze/Dokumente/Wiki)
- **Live-Alarmglocke**, offline-erkannte Verbindung, Karten-Design-System

Alle Änderungen: siehe [CHANGELOG.md](CHANGELOG.md).

## Kompatibilität

- Zielplattform: iOS 26.5+ (SwiftUI, pure Swift — keine Storyboards)
- Server: FiveNet (https://github.com/fivenet-app/fivenet), selbst gehostet, oder die
  offizielle Demo-Instanz `demo.fivenet.app`

## Build

```sh
xcodebuild -project "MD-Connect.xcodeproj" -scheme "MD-Connect" \
  -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/dd build
```

Neue Swift-Dateien werden automatisch eingebunden
(`PBXFileSystemSynchronizedRootGroup`, Xcode 16) — einfach unter `MD-Connect/UI/` ablegen.

## Projektstruktur

- `MD-Connect/UI/` – SwiftUI-Views
- `MD-Connect/Generated/Core/` – AppState, GRPC-Client, Fehlerübersetzung
- `MD-Connect/Generated/Protobuf/` – generierte Swift-Protobuf-Bindungen
  (aus den FiveNet-Proto-Definitionen, via `Scripts/generate-protos.sh`)

## License & Trademark

### Lizenz

Dieses Projekt ist unter der **Apache License, Version 2.0** lizenziert —
siehe [`LICENSE`](LICENSE) und [`NOTICE`](NOTICE).

**Keine Garantie:** Die Software wird „AS IS" und ohne jegliche Garantie oder Gewährleistung
bereitgestellt. Details in Apache License §7 (Disclaimer of Warranty) und §8
(Limitation of Liability).

### Drittanbieter-Software / Attribution

Teile dieser Software basieren auf dem **FiveNet**-Projekt:

- FiveNet, https://github.com/fivenet-app/fivenet — Copyright 2023 Alexander Trost
  (Apache License 2.0). Betrifft insbesondere die Protobuf-Dienstdefinitionen und die
  daraus generierten Client-Bindungen unter `MD-Connect/Generated/`.
- SwiftProtobuf: https://github.com/apple/swift-protobuf — Copyright 2014–2017 Apple Inc.
  und die Swift-Projekt-Autoren (Apache License 2.0).

### Markenrecht / Namensverwendung

Apache License 2.0 §6 erlaubt die Verwendung der Marken des Lizenzgebers nur zur
Beschreibung der Herkunft, nicht als eigenen Produktnamen. Daher:

- Der Produktname dieser App lautet **„MD-Connect“** — eine Bezeichnung, die nicht
  irreführend als offizielle App aufgefasst werden kann. 
- Der Begriff **„FiveNet“** wird ausschließlich beschreibend verwendet
  („Client für FiveNet-Server“, „Kompatibel mit FiveNet“), nicht als eigener
  Produktname.
- `NOTICE` und die Über-Seite der App enthalten den Marken-Disclaimer
  (keine Affiliation/Endorsement).

**Frage „MD-Connect for FiveNet“ als Name:** Eine Benennung als „… for FiveNet“
ist als **nominative Kennzeichnung** (nominative fair use) in der Regel vertretbar —
das Produkt lässt sich ohne den Markenbegriff nur schwer beschreiben, die Marke wird
nur „so viel wie nötig“ verwendet und es wird kein offizieller Bezug behauptet — **sofern**
(a) die Kompatibilität tatsächlich gegeben ist (gegeben), (b) überall ein klarer
Nicht-Affiliations-/Endorsement-Disclaimer steht (vorhanden in NOTICE/Über-Seite) und
(c) keine Logos oder geschützten Gestaltungen übernommen werden. Die strengere Variante
„MD-Connect“ (nur mit beschreibender Erwähnung im Fließtext) trägt das **geringste**
Rechtsrisiko und entspricht der aktuellen Implementierung. Markenrecht ist jurisdiktions-
abhängig; dies ist keine Rechtsberatung.

## API-Nutzung / Nutzungsbedingungen

- FiveNet ist **Open Source** (Apache License 2.0) und darf selbst gehostet werden;
  die App spricht das gRPC/Connect-Interface, das der Server selbst bereitstellt.
  Eigene, separate „API“-Terms hat das FiveNet-Projekt nach aktuellem Kenntnisstand
  **nicht** veröffentlicht (nur die fivenet.cloud-Hosting-AGB).
- Die Nutzung der **Demo-Instanz** (`demo.fivenet.app`) unterliegt den Bedingungen des
  Betreibers (siehe https://fivenet.app) — bei Verwendung bitte prüfen.
- Verantwortung: Der Betreiber der jeweiligen Serverinstanz muss sicherstellen, dass
  die dort geltenden Regeln eingehalten werden.

## Acknowledgements

- FiveNet-Team & Alexander Trost für das großartige Open-Source-System, das diese App
  überhaupt erst möglich macht.
- Apple / Swift-Protobuf-Autoren für die Protobuf-Laufzeit.
