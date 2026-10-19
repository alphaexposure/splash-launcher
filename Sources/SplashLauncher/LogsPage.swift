import SwiftUI

/// Splash's server output, with auto-scroll, Copy and Clear.
struct LogsPage: View {
    @ObservedObject var controller: SplashProcessController
    @State private var followLogs = true
    private let logEndID = "log-end"

    var body: some View {
        Panel("Server output", symbol: "terminal") {
            HStack(spacing: 10) {
                Text("Startup details and server activity").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Toggle("Auto-scroll", isOn: $followLogs)
                    .toggleStyle(.checkbox)
                    .help("Keep the newest output in view. Turn off to read earlier lines while Splash is busy.")
                CopyButton(text: controller.logs,
                           help: "Copy the server output to the clipboard. API keys are already redacted.") { copied in
                    Text(copied ? "Copied" : "Copy")
                }
                .disabled(controller.logs.isEmpty)
                Button("Clear logs") { controller.clearLogs() }.disabled(controller.logs.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(controller.logs.isEmpty ? "No activity yet. Server output will appear here after you start Splash." : controller.logs)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
                        Color.clear.frame(height: 1).id(logEndID)
                    }
                }
                .onAppear { proxy.scrollTo(logEndID, anchor: .bottom) }
                .onChange(of: controller.logs) {
                    if followLogs { proxy.scrollTo(logEndID, anchor: .bottom) }
                }
                .onChange(of: followLogs) {
                    if followLogs { proxy.scrollTo(logEndID, anchor: .bottom) }
                }
            }
            .frame(minHeight: 240, maxHeight: .infinity)
            .background(SplashTheme.inset, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
