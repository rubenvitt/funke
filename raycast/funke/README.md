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
