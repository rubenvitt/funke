import SwiftUI

/// Quick-Capture auf der Watch: Diktat-Feld + Senden. Klassifikation und Vault-/
/// ClickUp-Routing übernimmt das iPhone (Relay). Texteingabe öffnet auf watchOS
/// automatisch Diktat/Scribble.
struct WatchCaptureView: View {
    @ObservedObject private var relay = WatchRelay.shared
    @State private var text: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                TextField("Diktieren…", text: $text, axis: .vertical)
                    .lineLimit(1...4)

                Button {
                    relay.send(text: text)
                    text = ""
                } label: {
                    Label("Senden", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let status = relay.lastStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .navigationTitle("Funke")
        .onAppear { relay.start() }
    }
}
