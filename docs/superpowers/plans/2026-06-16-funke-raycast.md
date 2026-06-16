# Funke Raycast-Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine Raycast-Extension, die Text schnell (inline) oder mehrzeilig (Formular) erfasst und über den bestehenden Funke-`CaptureIntent` (via Apple Shortcut) routet — ohne Logik der Swift-App zu duplizieren.

**Architecture:** Raycast → `shortcuts run "Funke erfassen"` (Text über `/dev/stdin`) → Apple Shortcut mit Aktion `CaptureIntent` → CaptureRouter (Auto-Klassifizierung, ClickUp/Vault/Relay, Offline-Queue). Die testbare Kernlogik (`runCapture`) ist von der Raycast-UI und vom realen Shortcut-Aufruf getrennt; der reale Aufruf ist ein dünner, injizierter Runner.

**Tech Stack:** Raycast Extension (`@raycast/api`), TypeScript, React (für das Formular). Tests mit Nodes eingebautem Test-Runner (`node:test`, native TS-Unterstützung in Node 26 — keine zusätzlichen Test-Deps).

---

## Dateistruktur

Alles unter `raycast/funke/`:

- `package.json` — Raycast-Manifest: zwei Commands (`erfassen` no-view mit Argument, `notiz` view), Scripts, Deps.
- `tsconfig.json` — Standard-Raycast-TS-Config.
- `.gitignore` — node_modules, build-Artefakte, generierte `raycast-env.d.ts`.
- `assets/funke-icon.png` — Extension-Icon (Kopie des App-Icons).
- `src/capture.ts` — Kernlogik: `runCapture(text, run)` (rein, testbar) + `shortcutRunner` (realer Aufruf via `child_process`). **Importiert nichts aus `@raycast/api`.**
- `src/capture.test.ts` — `node:test`-Tests für `runCapture`.
- `src/erfassen.tsx` — Inline-Command (no-view), liest Argument `text`, ruft `runCapture(shortcutRunner)`, zeigt Toast.
- `src/notiz.tsx` — Formular-Command (view), `Form.TextArea`, Submit → `runCapture(shortcutRunner)`, Toast + `popToRoot()`.
- `README.md` — einmalige Shortcut-Einrichtung + Dev-Hinweise.

---

## Task 1: Extension-Gerüst & Dependencies

**Files:**
- Create: `raycast/funke/package.json`
- Create: `raycast/funke/tsconfig.json`
- Create: `raycast/funke/.gitignore`
- Create: `raycast/funke/assets/funke-icon.png` (Kopie)

- [ ] **Step 1: package.json anlegen**

`raycast/funke/package.json`:

```json
{
  "$schema": "https://www.raycast.com/schemas/extension.json",
  "name": "funke",
  "title": "Funke",
  "description": "Schnelle Erfassung in Funke (Task oder Notiz via Auto-Klassifizierung)",
  "icon": "funke-icon.png",
  "author": "ruben",
  "license": "MIT",
  "commands": [
    {
      "name": "erfassen",
      "title": "Funke: Erfassen",
      "subtitle": "Funke",
      "description": "Text schnell in Funke erfassen (Auto-Klassifizierung)",
      "mode": "no-view",
      "arguments": [
        {
          "name": "text",
          "type": "text",
          "placeholder": "Was möchtest du erfassen?",
          "required": false
        }
      ]
    },
    {
      "name": "notiz",
      "title": "Funke: Notiz erfassen",
      "subtitle": "Funke",
      "description": "Längere Notiz in Funke erfassen (mehrzeilig)",
      "mode": "view"
    }
  ],
  "scripts": {
    "build": "ray build",
    "dev": "ray develop",
    "lint": "ray lint",
    "fix-lint": "ray lint --fix",
    "test": "node --test src/"
  }
}
```

- [ ] **Step 2: tsconfig.json anlegen**

`raycast/funke/tsconfig.json`:

```json
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "include": ["src/**/*", "raycast-env.d.ts"],
  "compilerOptions": {
    "lib": ["ES2023"],
    "module": "commonjs",
    "target": "ES2022",
    "strict": true,
    "isolatedModules": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "jsx": "react-jsx",
    "resolveJsonModule": true
  }
}
```

- [ ] **Step 3: .gitignore anlegen**

`raycast/funke/.gitignore`:

```
node_modules
dist
raycast-env.d.ts
.DS_Store
```

- [ ] **Step 4: Icon kopieren**

Run:
```bash
mkdir -p raycast/funke/assets
cp Funke/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png raycast/funke/assets/funke-icon.png
```
Expected: Datei `raycast/funke/assets/funke-icon.png` existiert (kein Fehler).

- [ ] **Step 5: Dependencies installieren**

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && npm install @raycast/api@latest @raycast/utils@latest && npm install --save-dev @types/node@latest @types/react@latest typescript@latest @raycast/eslint-config@latest eslint@latest prettier@latest
```
Expected: `node_modules/` entsteht, `package.json` enthält jetzt `dependencies` + `devDependencies`, `package-lock.json` wird erzeugt, kein Fehler.

- [ ] **Step 6: Build-Smoke-Test**

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && npx ray build -e dist 2>&1 | tail -20
```
Expected: Build läuft (es darf über fehlende `src/*`-Dateien meckern, falls noch keine da — dann ist dieser Step ok, sobald `ray` startet). Wenn `ray` selbst nicht gefunden wird → `@raycast/api` neu installieren. Sobald die echten src-Dateien existieren (spätere Tasks), muss dieser Build sauber durchlaufen.

> Hinweis: Wenn `ray build` ohne `src/`-Commands fehlschlägt, ist das hier akzeptabel — der echte Build-Check erfolgt in Task 7. Ziel dieses Steps ist nur zu sehen, dass die Toolchain (`ray`) installiert ist.

- [ ] **Step 7: Commit**

```bash
cd /Users/rubeen/dev/personal/apps/funke
git add raycast/funke/package.json raycast/funke/package-lock.json raycast/funke/tsconfig.json raycast/funke/.gitignore raycast/funke/assets/funke-icon.png
git commit -m "Raycast: Funke-Extension-Geruest (Manifest, tsconfig, Icon, Deps)"
```

---

## Task 2: Kernlogik `runCapture` (TDD)

**Files:**
- Create: `raycast/funke/src/capture.test.ts`
- Create: `raycast/funke/src/capture.ts`

- [ ] **Step 1: Failing Test schreiben**

`raycast/funke/src/capture.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { runCapture } from "./capture.ts";

test("leerer Text wird abgelehnt, Runner nicht aufgerufen", async () => {
  let called = false;
  const result = await runCapture("   ", async () => {
    called = true;
    return { stdout: "egal", exitCode: 0 };
  });
  assert.equal(result.ok, false);
  assert.equal(called, false);
  assert.match(result.message, /Text/);
});

test("erfolgreicher Lauf gibt getrimmte stdout-Meldung zurueck", async () => {
  const result = await runCapture("Milch kaufen", async (text) => {
    assert.equal(text, "Milch kaufen");
    return { stdout: "Aufgabe angelegt\n", exitCode: 0 };
  });
  assert.equal(result.ok, true);
  assert.equal(result.message, "Aufgabe angelegt");
});

test("leere stdout bei Erfolg liefert Fallback-Meldung", async () => {
  const result = await runCapture("Hallo", async () => ({ stdout: "  \n", exitCode: 0 }));
  assert.equal(result.ok, true);
  assert.equal(result.message, "Erfasst");
});

test("non-zero exitCode wird als Fehler mit Shortcut-Hinweis gemeldet", async () => {
  const result = await runCapture("Hallo", async () => ({ stdout: "", exitCode: 1 }));
  assert.equal(result.ok, false);
  assert.match(result.message, /Funke erfassen/);
});

test("geworfener Runner-Fehler wird abgefangen", async () => {
  const result = await runCapture("Hallo", async () => {
    throw new Error("spawn ENOENT");
  });
  assert.equal(result.ok, false);
  assert.match(result.message, /Funke erfassen/);
});
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && node --test src/capture.test.ts 2>&1 | tail -20
```
Expected: FAIL — `Cannot find module './capture.ts'` bzw. `runCapture is not a function`.

- [ ] **Step 3: Minimale Implementierung schreiben**

`raycast/funke/src/capture.ts`:

```ts
import { spawn } from "node:child_process";

const SHORTCUT_NAME = "Funke erfassen";
const SHORTCUT_MISSING_HINT =
  "Konnte nicht senden. Lege den Shortcut 'Funke erfassen' an (siehe README).";

export interface CaptureOutcome {
  ok: boolean;
  message: string;
}

export type ShortcutRunner = (text: string) => Promise<{ stdout: string; exitCode: number }>;

export async function runCapture(rawText: string, run: ShortcutRunner): Promise<CaptureOutcome> {
  const text = rawText.trim();
  if (text.length === 0) {
    return { ok: false, message: "Bitte gib Text ein." };
  }
  try {
    const { stdout, exitCode } = await run(text);
    if (exitCode !== 0) {
      return { ok: false, message: SHORTCUT_MISSING_HINT };
    }
    const message = stdout.trim();
    return { ok: true, message: message.length > 0 ? message : "Erfasst" };
  } catch {
    return { ok: false, message: SHORTCUT_MISSING_HINT };
  }
}

export const shortcutRunner: ShortcutRunner = (text) =>
  new Promise((resolve, reject) => {
    const child = spawn("shortcuts", [
      "run",
      SHORTCUT_NAME,
      "--input-path",
      "/dev/stdin",
      "--output-path",
      "/dev/stdout",
    ]);
    let stdout = "";
    child.stdout.on("data", (chunk) => (stdout += chunk.toString()));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, exitCode: code ?? 1 }));
    child.stdin.write(text);
    child.stdin.end();
  });
```

- [ ] **Step 4: Test laufen lassen, Erfolg bestätigen**

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && node --test src/capture.test.ts 2>&1 | tail -20
```
Expected: PASS — `# pass 5`, `# fail 0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/rubeen/dev/personal/apps/funke
git add raycast/funke/src/capture.ts raycast/funke/src/capture.test.ts
git commit -m "Raycast: runCapture-Kernlogik + shortcutRunner (TDD)"
```

---

## Task 3: Inline-Command `erfassen`

**Files:**
- Create: `raycast/funke/src/erfassen.tsx`

- [ ] **Step 1: Command implementieren**

`raycast/funke/src/erfassen.tsx`:

```tsx
import { showToast, Toast, LaunchProps } from "@raycast/api";
import { runCapture, shortcutRunner } from "./capture";

export default async function Command(props: LaunchProps<{ arguments: { text: string } }>) {
  const text = props.arguments.text ?? "";
  const toast = await showToast({ style: Toast.Style.Animated, title: "Erfasse in Funke …" });

  const result = await runCapture(text, shortcutRunner);

  toast.style = result.ok ? Toast.Style.Success : Toast.Style.Failure;
  toast.title = result.ok ? result.message : "Fehler";
  if (!result.ok) {
    toast.message = result.message;
  }
}
```

- [ ] **Step 2: TypeScript prüfen**

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && npx tsc --noEmit 2>&1 | tail -20
```
Expected: keine Fehler (leere Ausgabe).

- [ ] **Step 3: Commit**

```bash
cd /Users/rubeen/dev/personal/apps/funke
git add raycast/funke/src/erfassen.tsx
git commit -m "Raycast: Inline-Command 'Funke: Erfassen'"
```

---

## Task 4: Formular-Command `notiz`

**Files:**
- Create: `raycast/funke/src/notiz.tsx`

- [ ] **Step 1: Command implementieren**

`raycast/funke/src/notiz.tsx`:

```tsx
import { Action, ActionPanel, Form, Toast, showToast, popToRoot, useNavigation } from "@raycast/api";
import { useState } from "react";
import { runCapture, shortcutRunner } from "./capture";

interface FormValues {
  text: string;
}

export default function Command() {
  const [textError, setTextError] = useState<string | undefined>();

  async function handleSubmit(values: FormValues) {
    if (values.text.trim().length === 0) {
      setTextError("Bitte gib Text ein.");
      return;
    }
    const toast = await showToast({ style: Toast.Style.Animated, title: "Erfasse in Funke …" });
    const result = await runCapture(values.text, shortcutRunner);
    toast.style = result.ok ? Toast.Style.Success : Toast.Style.Failure;
    toast.title = result.ok ? result.message : "Fehler";
    if (!result.ok) {
      toast.message = result.message;
      return;
    }
    await popToRoot();
  }

  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm title="In Funke erfassen" onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.TextArea
        id="text"
        title="Text"
        placeholder="Was möchtest du erfassen?"
        enableMarkdown={false}
        error={textError}
        onChange={() => setTextError(undefined)}
      />
    </Form>
  );
}
```

> Hinweis: `useNavigation` ist hier nicht zwingend nötig — falls der Import einen ungenutzten-Import-Lint-Fehler wirft, entferne `useNavigation` aus dem Import. Sauberer Import unten in Step 2 prüfen.

- [ ] **Step 2: Ungenutzten Import bereinigen + TypeScript prüfen**

Entferne `useNavigation` aus dem Import-Statement, falls nicht verwendet (in obigem Code wird es nicht genutzt — also entfernen). Finaler Import-Kopf:

```tsx
import { Action, ActionPanel, Form, Toast, showToast, popToRoot } from "@raycast/api";
import { useState } from "react";
import { runCapture, shortcutRunner } from "./capture";
```

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && npx tsc --noEmit 2>&1 | tail -20
```
Expected: keine Fehler (leere Ausgabe).

- [ ] **Step 3: Commit**

```bash
cd /Users/rubeen/dev/personal/apps/funke
git add raycast/funke/src/notiz.tsx
git commit -m "Raycast: Formular-Command 'Funke: Notiz erfassen'"
```

---

## Task 5: README mit Shortcut-Einrichtung

**Files:**
- Create: `raycast/funke/README.md`

- [ ] **Step 1: README schreiben**

`raycast/funke/README.md`:

```markdown
# Funke (Raycast)

Schnelle Erfassung in [Funke](../../) direkt aus Raycast. Der Text wird über den
bestehenden `CaptureIntent` der Funke-macOS-App geroutet (Auto-Klassifizierung →
ClickUp-Task oder Obsidian-Notiz). Es wird keine Logik dupliziert.

## Voraussetzungen

- Funke-macOS-App installiert und konfiguriert (ClickUp-Token / Vault bzw. Relay).
- Raycast installiert.

## Einmalige Einrichtung: Apple Shortcut „Funke erfassen"

Raycast kann App Intents nicht direkt aufrufen — der Aufruf läuft über einen
Apple Shortcut als Brücke. Lege ihn einmal an:

1. Shortcuts-App öffnen → **neuer Shortcut**, Name exakt: **`Funke erfassen`**.
2. Oben rechts auf das (i)-Symbol → **„Bei Übergabe anzeigen"** so lassen; wichtig ist:
   in den Shortcut-Details unter **Eingabe** „Shortcut-Eingabe" auf **Text** akzeptieren.
3. Aktion hinzufügen: nach **„In Funke erfassen"** suchen (Aktion der Funke-App,
   = `CaptureIntent`) und einfügen.
4. Im `Text`-Parameter dieser Aktion die **Shortcut-Eingabe** einsetzen
   (Variable „Shortcut-Eingabe" / „Bei Ausführung erhalten").
5. Die Funke-Aktion liefert eine Bestätigung — diese ist automatisch die Ausgabe
   des Shortcuts (für die Raycast-Toast-Meldung). Keine weitere Aktion nötig.

Test in der Shortcuts-App: Shortcut ausführen, Text eingeben → es sollte eine
Bestätigung erscheinen.

## Entwicklung

```bash
cd raycast/funke
npm install
npm run dev      # lädt die Extension lokal in Raycast (Dev-Modus)
npm test         # Unit-Tests der Kernlogik
npm run lint
```

## Commands

- **Funke: Erfassen** — inline; Text direkt in der Raycast-Leiste eingeben, Enter → sofort.
- **Funke: Notiz erfassen** — Formular mit mehrzeiligem Textfeld für längere Notizen.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/rubeen/dev/personal/apps/funke
git add raycast/funke/README.md
git commit -m "Raycast: README mit Shortcut-Einrichtung"
```

---

## Task 6: Gesamt-Verifikation

**Files:** (keine Änderungen — nur Checks; ggf. kleine Fixes)

- [ ] **Step 1: Tests**

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && npm test 2>&1 | tail -20
```
Expected: `# pass 5`, `# fail 0`.

- [ ] **Step 2: Lint**

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && npm run lint 2>&1 | tail -30
```
Expected: keine Errors. Warnings ggf. mit `npm run fix-lint` beheben, dann erneut.

- [ ] **Step 3: Production-Build**

Run (im Ordner `raycast/funke/`):
```bash
cd raycast/funke && npx ray build -e dist 2>&1 | tail -30
```
Expected: Build erfolgreich, `dist/` entsteht, beide Commands (`erfassen`, `notiz`) ohne Fehler kompiliert.

- [ ] **Step 4: Manuelle Round-Trip-Verifikation (durch den User)**

Voraussetzung: Apple Shortcut „Funke erfassen" ist eingerichtet (Task 5 README).

1. `cd raycast/funke && npm run dev` → Extension erscheint in Raycast.
2. „Funke: Erfassen" aufrufen, inline `Test aus Raycast` eingeben → Enter.
   Erwartung: Erfolgs-Toast mit Bestätigung; Eintrag landet in ClickUp/Obsidian
   wie bei der App.
3. „Funke: Notiz erfassen" → mehrzeiligen Text → Submit.
   Erwartung: Erfolgs-Toast, Fenster schließt (`popToRoot`).

> Falls die Toast-Meldung leer/„Erfasst" bleibt, aber der Eintrag ankommt:
> `--output-path /dev/stdout` liefert auf diesem System keine Shortcut-Ausgabe —
> das ist unkritisch (Erfolg wird trotzdem als Toast gezeigt). Optional im
> Shortcut eine „Ergebnis anzeigen"/Text-Ausgabe als letzte Aktion ergänzen.

- [ ] **Step 5: Abschluss-Commit (falls Fixes nötig waren)**

```bash
cd /Users/rubeen/dev/personal/apps/funke
git add -A raycast/funke
git commit -m "Raycast: Lint/Build-Fixes nach Verifikation"
```

---

## Offene Risiken / Notizen

- **Shortcut-Output via `/dev/stdout`:** Ob die Intent-Bestätigung als stdout
  zurückkommt, hängt von der Shortcut-Konfiguration ab. `runCapture` behandelt
  leere Ausgabe als generischen Erfolg („Erfasst") — der Round-Trip funktioniert
  auch ohne sichtbare Meldung.
- **Node-26-TS-Tests:** `node --test src/capture.test.ts` nutzt native
  TS-Unterstützung (type stripping). Falls eine ältere Node-Version genutzt wird,
  Test mit `node --experimental-strip-types --test src/capture.test.ts` ausführen.
- **App muss installiert/konfiguriert sein:** Der Intent liest ClickUp-Token,
  Vault-/Relay-Settings aus der App (Keychain/UserDefaults).
