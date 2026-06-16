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
  const result = await runCapture("Hallo", async () => ({
    stdout: "  \n",
    exitCode: 0,
  }));
  assert.equal(result.ok, true);
  assert.equal(result.message, "Erfasst");
});

test("non-zero exitCode wird als Fehler mit Shortcut-Hinweis gemeldet", async () => {
  const result = await runCapture("Hallo", async () => ({
    stdout: "",
    exitCode: 1,
  }));
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
