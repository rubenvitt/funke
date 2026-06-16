# Funke Raycast-Extension — Design

**Datum:** 2026-06-16
**Status:** Approved (Design)

## Ziel

Ein Raycast-Pendant zur Funke-macOS-App: schnelle Erfassung von Text, der wie in
der App über die `Auto`-Klassifizierung geroutet wird (ClickUp-Task vs.
Obsidian-Notiz). Input-Parität auf Text-Ebene; bewusst ohne Modus-Picker.

## Architektur-Entscheidung

Raycast **wiederverwendet die bestehende Smart-Logik der Swift-App** über den
vorhandenen `CaptureIntent` (App Intent, `openAppWhenRun=false`). Es wird **kein**
Code der Swift-App geändert und **keine** Logik (Routing, KI-Klassifizierung,
ClickUp/Vault/Relay, Offline-Queue, Keychain) in Raycast dupliziert.

Da Raycast App Intents nicht direkt aufrufen kann, läuft der Aufruf über einen
**Apple Shortcut** als Brücke.

## Komponenten

Eine eigenständige Raycast-Extension (TypeScript, npm-Package) unter
`raycast/funke/` im selben Repo. Zwei Commands, ein gemeinsamer Code-Pfad:

1. **„Funke: Erfassen" (inline)** — Command mit optionalem `text`-Argument.
   Eingabe direkt in der Raycast-Leiste → Enter → feuert sofort ohne Fenster.
   Schnellster Weg für einzeilige Captures.
2. **„Funke: Notiz erfassen" (Formular)** — `view`-Command mit `Form` +
   mehrzeiligem `TextArea` + Submit. Für längere Notizen mit Zeilenumbrüchen.
   Nach Erfolg `popToRoot()`.

Beide rufen dieselbe Funktion `capture(text: string)` auf
(`src/capture.ts` o.ä.).

## Datenfluss

```
Raycast (Text)
  → echo "<text>" | shortcuts run "Funke erfassen"   (Text via stdin)
      → Apple Shortcut: Aktion "In Funke erfassen" (CaptureIntent) mit Shortcut-Input
          → CaptureRouter: Auto-Klassifizierung → ClickUp / Vault / Relay / Offline-Queue
  ← stdout: Bestätigungstext ("Aufgabe angelegt" / "Notiz gespeichert" / "offline gepuffert")
Raycast: Erfolgs-Toast mit dieser Meldung
```

## Brücke Raycast → App Intent (einmalige manuelle Einrichtung)

Der User legt **einmalig** in der Shortcuts-App einen Shortcut „Funke erfassen" an:

- Eingabe: Text (Shortcut-Input akzeptiert Text)
- Aktion: „In Funke erfassen" (= `CaptureIntent`), `Text`-Parameter ← Shortcut-Input
- Letzte Aktion gibt das Intent-Ergebnis aus (für stdout)

Schritt-für-Schritt-Anleitung wird mit der Extension ausgeliefert (README).

Die Extension ruft den Shortcut per `shortcuts run "Funke erfassen"` mit dem Text
über stdin auf und liest stdout für die Toast-Meldung.

## Fehlerbehandlung

- Leerer/whitespace-only Text → Validierungs-Toast, kein Aufruf.
- Shortcut nicht gefunden / non-zero exit / leerer stdout → Failure-Toast mit
  Hinweis „Shortcut 'Funke erfassen' anlegen (siehe README)".
- Erfolg → Toast (Style success) mit der Intent-Meldung aus stdout.

## Bewusst draußen (YAGNI)

- Kein Modus-Picker (alles `Auto`).
- Keine KI-/Klassifizierungslogik in Raycast.
- Kein direkter ClickUp-/Vault-/Relay-Zugriff aus Raycast.
- Kein Mic/Diktat-Button (Raycasts eigenes Diktat funktioniert im TextArea).

## Ablage & Test

- `raycast/funke/` — `package.json`, `src/`, `README.md`, Assets/Icon.
- Dev/Test: `npm install && npm run dev` (Raycast lädt die Extension lokal im
  Dev-Modus). Manuelle Verifikation: inline + Formular-Command gegen den
  eingerichteten Shortcut.

## Voraussetzungen

- Funke-macOS-App installiert & konfiguriert (Keychain/Settings — der Intent liest
  daraus).
- Apple Shortcut „Funke erfassen" eingerichtet.
- Raycast installiert, Node/npm für Build.
