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
