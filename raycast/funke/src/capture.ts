import { spawn } from "node:child_process";

const SHORTCUT_NAME = "Funke erfassen";
const SHORTCUT_MISSING_HINT =
  "Konnte nicht senden. Lege den Shortcut 'Funke erfassen' an (siehe README).";

export interface CaptureOutcome {
  ok: boolean;
  message: string;
}

export type ShortcutRunner = (
  text: string,
) => Promise<{ stdout: string; exitCode: number }>;

export async function runCapture(
  rawText: string,
  run: ShortcutRunner,
): Promise<CaptureOutcome> {
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
    return { ok: true, message: message.length > 0 ? message : "An Funke gesendet" };
  } catch {
    return { ok: false, message: SHORTCUT_MISSING_HINT };
  }
}

export const shortcutRunner: ShortcutRunner = (text) =>
  new Promise((resolve, reject) => {
    // App Intents lassen sich von der CLI nur über die Shortcuts-Engine auslösen.
    // Der Text wird inline als echte Shortcut-Eingabe übergeben — NICHT als Datei
    // via `--input-path /dev/stdin`: dabei bekäme der Shortcut die Datei und beim
    // Text-Zwang nur deren Namen ("stdin") statt des Inhalts.
    const url =
      `shortcuts://run-shortcut?name=${encodeURIComponent(SHORTCUT_NAME)}` +
      `&input=text&text=${encodeURIComponent(text)}`;
    // `-g`: im Hintergrund öffnen, ohne die Shortcuts-App in den Vordergrund zu holen.
    // Fire-and-forget: `open` liefert keine Shortcut-Ausgabe zurück (stdout bleibt leer).
    const child = spawn("open", ["-g", url]);
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout: "", exitCode: code ?? 1 }));
  });
