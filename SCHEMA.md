# HTML-Präsentationsschema (Version 1)

Eine Präsentation ist eine ganz normale HTML-Datei. Innerhalb einer Folie ist **alles erlaubt**: beliebiges HTML, CSS, JavaScript, Canvas, SVG, Videos, iframes, Interaktion. Vereinbart sind nur drei Dinge:

1. **Welche Elemente Folien sind** – `data-slide`
2. **Wie tief eine Folie hängt** – `data-level` (für Unterfolien)
3. **Wo die Notizen stehen** – `data-notes`

Alles andere (Anzeigen, Skalieren, Blättern, Synchronisieren mit dem Beamer) übernimmt die Laufzeit `runtime/presentation.js` bzw. die HTML-Presenter-App.

## Minimalbeispiel

```html
<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="presentation" content="width=1600, height=900">
  <title>Meine Präsentation</title>
  <script src="presentation.js"></script>
</head>
<body>
  <section data-slide>
    <h1>Titel</h1>
    <aside data-notes>Begrüßung, kurz vorstellen.</aside>
  </section>

  <section data-slide>
    <h2>Kapitel A</h2>
  </section>
    <section data-slide data-level="2"><h2>A, Detail 1</h2></section>
    <section data-slide data-level="2"><h2>A, Detail 2</h2></section>

  <section data-slide>
    <h2>Kapitel B</h2>
  </section>
</body>
</html>
```

Ergibt die Folien **1**, **2**, **2.1**, **2.2**, **3**.

## Folien

| Markierung | Bedeutung |
|---|---|
| `data-slide` | Dieses Element ist eine Folie. Meist `<section>`, aber jedes Element geht. Reihenfolge = Reihenfolge im Dokument. |
| `data-level="2"` | Gliederungsebene. Fehlt es, gilt `1` (Rückgrat). `2` = Unterfolie der letzten Folie davor mit Ebene 1, `3` = Unter-Unterfolie usw. Beliebig tief. |
| `id` oder `data-id` | Optionaler, stabiler Name, z. B. für Links (`#rosette`). Fehlt er, gilt die Nummer. |
| `data-title` | Optionaler Titel für Übersicht und Pult. Fehlt er, nimmt die Laufzeit die erste Überschrift (`h1`–`h6`) der Folie. |

Die Nummern (`1`, `2.1`, `4.2.1` …) werden **automatisch** aus Reihenfolge und Ebene berechnet; man schreibt sie nie selbst.

**Warum flach und nicht verschachtelt im DOM?** Folien stehen nebeneinander im Dokument, die Hierarchie steckt nur in `data-level` – wie bei `h1`/`h2`/`h3`. So stört keine Verschachtelung das eigene CSS, jede Folie ist ein eigenständiger Block, und Unterfolien lassen sich durch Ändern einer Zahl umhängen. Die Einrückung im Quelltext ist reine Kosmetik.

Eine Ebene darf nicht übersprungen werden: Folgt auf eine Folie der Ebene 1 eine mit `data-level="3"`, wird sie als Ebene 2 behandelt.

## Notizen

```html
<section data-slide>
  <h2>Der Stein von Rosette</h2>
  <aside data-notes>
    <p>Hier kurz innehalten.</p>
    <ul><li>Fundjahr 1799 nennen</li></ul>
  </aside>
</section>
```

- Element mit `data-notes` irgendwo **innerhalb** der Folie; Inhalt ist beliebiges HTML.
- Notizen sind in der Präsentation immer unsichtbar und erscheinen nur im Pult.
- Mehrere Notiz-Elemente in einer Folie werden aneinandergehängt.

## Format

```html
<meta name="presentation" content="width=1600, height=900">
```

- **Mit** dieser Angabe gestaltet man jede Folie für eine feste Bühne (hier 1600×900 px). Die Laufzeit skaliert sie passend auf jeden Bildschirm, mit Rand in der Hintergrundfarbe (`--presentation-backdrop`, Standard Schwarz).
- **Ohne** sie füllt jede Folie das ganze Fenster; um responsives Layout kümmert man sich dann selbst.

## Was die Laufzeit an die Folien schreibt

Damit man mit CSS und JavaScript auf den Zustand reagieren kann:

| Attribut | Wo | Werte |
|---|---|---|
| `data-state` | jede Folie | `past`, `current`, `future` |
| `data-slide-number` | jede Folie | ihre Nummer, z. B. `4.2.1` – praktisch als Seitenzahl: `content: attr(data-slide-number)` |
| `data-current-slide` | `<html>` | Nummer der aktuellen Folie, z. B. `2.1` |
| `data-presentation-mode` | `<html>` | `browser` (Datei direkt im Browser), `beamer`, `presenter` (Live-Folie im Pult), `snapshot` (Miniatur wird fotografiert) |

Grundregel der Laufzeit: Nur die Folie mit `data-state="current"` ist sichtbar. Alle Grundstile liegen in der CSS-Ebene `@layer presentation` – **eigenes CSS gewinnt also immer**, ohne `!important`.

Beispiel Überblendung:

```css
[data-slide] { transition: opacity .4s, visibility .4s; }
[data-slide]:not([data-state="current"]) { opacity: 0; }
```

Beispiel: eigene Bedienelemente nur im Browser zeigen:

```css
html:not([data-presentation-mode="browser"]) .meine-knoepfe { display: none; }
```

Im Modus `snapshot` sind alle Übergänge und Animationen abgeschaltet, damit Miniaturen den Endzustand zeigen.

## Ereignisse

| Ereignis | Ziel | `detail` |
|---|---|---|
| `presentation:ready` | `document` | `{ slides }` |
| `presentation:change` | `document` | `{ index, previous, slide }` |
| `presentation:enter` | die Folie, die erscheint (bubbelt) | `{ index, slide }` |
| `presentation:leave` | die Folie, die verschwindet (bubbelt) | `{ index, slide }` |

```js
document.querySelector('#zeitleiste').addEventListener('presentation:enter', () => starteAnimation());
```

## Innerhalb der Präsentation springen

- `<button data-goto="rosette">` – Klick springt zur Folie mit dieser `id`, oder `data-goto="3.2"` zur Nummer.
- `<a href="#rosette">` funktioniert ebenfalls.
- Aus JavaScript: `presentation.goto('rosette')`.

Solche Sprünge kommen auch im Pult und auf dem Beamer an.

## Tastatur (im Browser)

| Taste | Wirkung |
|---|---|
| → Leertaste Bild↓ | nächste Folie (inkl. Unterfolien: 2 → 2.1 → 2.2 → 3) |
| ← Bild↑ | vorige Folie |
| ⇧→ | nächste Rückgrat-Folie, Unterfolien überspringen (2.1 → 3) |
| ⇧← | zur eigenen Rückgrat-Folie (2.2 → 2), von dort zur vorigen (2 → 1) |
| Pos1 / Ende | erste / letzte Folie |
| F | Vollbild |

Hat ein eigenes Skript die Taste schon behandelt (`event.preventDefault()`) oder steht der Fokus in einem Eingabefeld, blättert die Laufzeit nicht. In der App übernimmt die App die Tastatur.

## JavaScript-Schnittstelle `window.presentation`

| Mitglied | Bedeutung |
|---|---|
| `version` | Schema-Version, `1` |
| `mode` | wie `data-presentation-mode` |
| `size` | `{ width, height }` oder `null` |
| `slides` | Liste mit `{ index, number, level, id, title, notes, parent, children }`; `notes` ist HTML, `parent` und `children` sind Indizes |
| `current` | Index der aktuellen Folie (ab 0) |
| `goto(ref)` | `ref` = Index (Zahl), Nummer (`"2.1"`) oder `id`; liefert `true`/`false` |
| `next()`, `prev()` | linear blättern |
| `nextSection()`, `prevSection()` | im Rückgrat blättern |
| `ready` | Promise, erfüllt, sobald die Folien eingelesen sind |

**Eigene Laufzeit:** Wer Navigation komplett selbst bauen will, darf das. Definiert die Seite selbst ein `window.presentation` mit dieser Schnittstelle (und meldet Folienwechsel an die App, siehe Quelltext von `presentation.js`), nutzt die App diese statt der mitgelieferten.

## Checkliste für Generatoren

- Jede Folie ist ein Element mit `data-slide`; Unterfolien bekommen `data-level="2"` (oder tiefer).
- Notizen als `<aside data-notes>` in die jeweilige Folie.
- `<meta name="presentation" content="width=…, height=…">`, wenn mit fester Bühne gestaltet wird.
- `<script src="presentation.js"></script>` einbinden, damit die Datei auch direkt im Browser läuft (Pfad anpassen oder Inhalt einbetten).
- Innerhalb der Folien: freie Hand. Keine Folie muss etwas über die anderen wissen.
