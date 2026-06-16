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
