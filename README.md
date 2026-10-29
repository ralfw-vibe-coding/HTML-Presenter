# HTML Presenter

Mac-App, die HTML-Präsentationen wie Keynote oder PowerPoint vorführt: Auf dem Beamer läuft die Präsentation im Vollbild, auf dem Mac ein Pult mit Referentenansicht, Übersicht und Spiegel – alles synchron.

Wie eine Präsentation aufgebaut sein muss, steht in [SCHEMA.md](SCHEMA.md). Die App legt das Schema auf Wunsch in die Zwischenablage (Hilfe → Präsentationsschema kopieren), damit man es schnell einer KI vorlegen kann, die eine Präsentation erzeugen soll. Ein vollständiges Beispiel mit Unterfolien und Notizen: [beispiele/hieroglyphen.html](beispiele/hieroglyphen.html).

## Bauen und starten

Kein Xcode-Projekt nötig, nur die Swift-Toolchain:

```bash
./build.sh
open "build/HTML Presenter.app"
```

Oder direkt mit einer Präsentation:

```bash
open -a "build/HTML Presenter.app" beispiele/hieroglyphen.html
```

## Was die App tut

- **Beamer:** Ist ein zweiter Bildschirm angeschlossen (Displays auf „Erweitern“, nicht „Spiegeln“), legt die App dort ein randloses Vollbildfenster an. Ohne zweiten Bildschirm erscheint ein verschiebbares Probefenster. ⇧⌘B schaltet reihum durch die Bildschirme. Wird der Beamer ab- oder angesteckt, ordnet die App die Fenster neu.
- **Pult** (⌘1 / ⌘2 / ⌘3):
  - **Referent** – Live-Folie mit ihren Notizen darunter; rechts die nächste Folie mit ihren Notizen in klein
  - **Übersicht** – wahlweise als Zeilen (je Rückgrat-Folie eine Zeile mit ihren Unterfolien) oder als Matrix (alle Folien der Reihe nach, umbrechend); Unterfolien sind je Ebene 15 % kleiner. Klick wählt aus (türkiser Rahmen) und zeigt rechts die Notizen, Doppelklick oder ⏎ bringt die Folie auf den Beamer (oranger Rahmen). Miniaturen mit −/+ neben der Folienzahl oder per Trackpad-Zoom vergrößern
  - **Spiegel** – genau das, was das Publikum sieht; das Chevron ganz rechts blendet die Kopfleiste aus und an derselben Stelle wieder ein (oder ⌥⌘T). So lässt sich auch mit dem Pult selbst präsentieren (keine Warnungen, keine Sprungeingabe sichtbar)
- **Zeit:** In der Kopfleiste stehen Vortragsdauer (Klick hält an) · Uhrzeit · Sanduhr mit Deadline · Countdown. Die Sanduhr (oder ⇧⌘D) öffnet das Deadline-Blatt: Uhrzeit eintippen oder „in 15/30/45/60/90 Min.“, dort lässt sich auch die Vortragsdauer zurücksetzen. 10, 5 und 1 Minute vorher und bei Ablauf erscheint im Pult eine Warnung, nie auf dem Beamer.
- **Tastatur und Presenter-Fernbedienung** wirken immer, egal welches Fenster vorn ist: → ← Leertaste Bild↑↓, ⇧→ ⇧← fürs Rückgrat, Nummer tippen + ⏎ (z. B. `4.2.1⏎`), B oder `.` für Schwarzbild, esc. Übersicht über alle Kürzel: Menü Hilfe → Tastenkürzel.
- **Neu laden:** Beim Speichern der HTML-Datei lädt die App automatisch neu und bleibt auf der aktuellen Folie (⌘R von Hand).
- Der Mac geht während der Präsentation nicht schlafen. Ton von Videos kommt nur vom Beamer.
- Präsentationen können auch per URL geöffnet werden (⌘L), z. B. von einem lokalen Server.

## Aufbau

| Datei | Aufgabe |
|---|---|
| `runtime/presentation.js` | Laufzeit nach SCHEMA.md; die App fügt sie in jede Seite ein |
| `Sources/HTMLPresenter/PresentationController.swift` | aktuelle Folie, Synchronisation, Miniaturen, Neuladen |
| `Sources/HTMLPresenter/SlideWebView.swift` | WebViews und Nachrichten-Brücke zur Laufzeit |
| `Sources/HTMLPresenter/BeamerController.swift` | Beamer-Fenster, Bildschirmwahl, Schwarzbild |
| `Sources/HTMLPresenter/ConsoleView.swift` | Pult (SwiftUI) |
| `Sources/HTMLPresenter/AppDelegate.swift`, `MainMenu.swift` | Fenster, Tastatur, Menüs |

Es laufen drei WebViews mit derselben Datei: Beamer, Live-Folie im Pult und eine unsichtbare für die Miniaturen. Synchronisiert wird die Foliennummer; was man *innerhalb* einer Folie anklickt, passiert nur in dem Fenster, in dem man klickt.
