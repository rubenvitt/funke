import {
  Action,
  ActionPanel,
  Form,
  Toast,
  showToast,
  popToRoot,
} from "@raycast/api";
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
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Erfasse in Funke …",
    });
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
          <Action.SubmitForm
            title="In Funke erfassen"
            onSubmit={handleSubmit}
          />
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
