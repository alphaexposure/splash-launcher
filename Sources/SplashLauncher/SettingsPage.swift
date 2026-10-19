import AppKit
import SwiftUI

/// Model, connection and server options, the installed models list, and the API key.
struct SettingsPage: View {
    @ObservedObject var controller: SplashProcessController
    @State private var installedModels: [String] = []
    @State private var modelStorage: SplashModelStorage?
    @State private var useCustomModel = false
    @State private var keyDraft = ""

    private var aliases: Binding<String> {
        Binding(
            get: { controller.configuration.servedModelNames.joined(separator: ", ") },
            set: { controller.configuration.servedModelNames = splitList($0) }
        )
    }
    private var allowedHosts: Binding<String> {
        Binding(
            get: { controller.configuration.allowedHosts.joined(separator: ", ") },
            set: { controller.configuration.allowedHosts = splitList($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MissingSplashNotice(controller: controller)
            if controller.state.isRunning {
                Notice("Stop Splash to edit server settings. Changes apply on the next start.", symbol: "lock")
            }
            Panel("Model & connection", symbol: "cpu") {
                HStack {
                    SettingLabel("Executable", helpText: "The installed splash-m1 program this launcher starts. Choose a different executable if automatic discovery found the wrong one.")
                    Text(controller.executable?.path ?? "Not found")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { chooseSplashExecutable(for: controller) }
                        .disabled(controller.state.isRunning)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SettingLabel("Model", defaultValue: "incoai/Qwen3.8-27B-Splash",
                                     helpText: "Choose an installed Splash model, or select Other model to enter a Hugging Face owner/repository ID, optionally followed by :VARIANT for GGUF models in Splash 1.1 or newer. Stop the server before changing models.")
                        Picker("Model", selection: Binding(
                            get: { useCustomModel || !installedModels.contains(controller.configuration.model) ? "__custom__" : controller.configuration.model },
                            set: { value in
                                useCustomModel = value == "__custom__"
                                if !useCustomModel { controller.configuration.model = value }
                            }
                        )) {
                            ForEach(installedModels, id: \.self) { Text($0).tag($0) }
                            Text("Other model…").tag("__custom__")
                        }
                        .labelsHidden().frame(width: 300)
                        .accessibilityLabel("Installed model")
                        .disabled(controller.state.isRunning)
                    }
                    if useCustomModel || !installedModels.contains(controller.configuration.model) {
                        field("Model ID", text: $controller.configuration.model,
                                     prompt: "owner/repository", defaultValue: "incoai/Qwen3.8-27B-Splash",
                                     helpText: "Enter a supported model ID, such as incoai/Qwen3.8-27B-Splash. Splash 1.1 or newer also accepts GGUF variants such as unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M. Splash may download it the next time you start the server.")
                    }
                    HStack {
                        Text(installedModels.isEmpty ? "No installed models found." : "\(String(installedModels.count)) installed models")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") { refreshModels() }
                    }
                    installedModelsList
                }
                .onAppear { refreshModels() }
                field("Host", text: $controller.configuration.host,
                             prompt: "127.0.0.1", defaultValue: "127.0.0.1",
                             helpText: "The network address Splash listens on. 127.0.0.1 allows connections from this Mac only; 0.0.0.0 listens on all IPv4 interfaces.")
                HStack {
                    SettingLabel("Port", defaultValue: "8000",
                                 helpText: "The network port for Splash's API and browser chat page. Use a port that is not already in use.")
                    TextField("", value: $controller.configuration.port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                        .accessibilityLabel("Port")
                        .disabled(controller.state.isRunning)
                }
            }

            Panel("Server settings", symbol: "slider.horizontal.3") {
                field("Model aliases", text: aliases,
                             prompt: "Comma-separated names", defaultValue: "None",
                             helpText: "Extra names that API clients can use for the loaded model. Separate names with commas. This does not load additional models.")
                HStack {
                    SettingLabel("Reasoning effort", helpText: "The default thinking level when a request does not specify one. Model default leaves the choice to the model. Higher levels may take longer and use more tokens.")
                    Picker("", selection: $controller.configuration.defaultReasoningEffort) {
                        Text("Model default").tag("")
                        ForEach(controller.configuration.reasoningEfforts, id: \.self) { Text(controller.configuration.reasoningLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                    .accessibilityLabel("Reasoning effort")
                    .disabled(controller.state.isRunning)
                }
                if let guide = controller.configuration.reasoningGuide {
                    Text(guide + " Chat apps can override this default with their own reasoning setting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    SettingLabel("KV cache format", helpText: "Precision of the context cache. int8 uses less memory; bf16 uses more memory for higher precision.")
                    Picker("", selection: $controller.configuration.kvFormat) {
                        Text("int8 (default)").tag("int8")
                        Text("bf16").tag("bf16")
                    }
                    .labelsHidden()
                    .frame(width: 230)
                    .accessibilityLabel("KV cache format")
                    .disabled(controller.state.isRunning)
                }
                field("Maximum memory", text: $controller.configuration.maxMemory,
                             prompt: "e.g. 28GB", defaultValue: "Automatic when blank",
                             helpText: "Caps the memory Splash may use for Metal. Leave blank to let Splash choose. Splash treats GB as 1,024 cubed bytes.")
                field("Maximum context (tokens)", text: $controller.configuration.maxContext,
                             prompt: "e.g. 128K", defaultValue: "Automatic when blank",
                             helpText: "Limits the number of tokens in one request's context. 128K means 131,072 tokens. Blank lets Splash choose within the memory budget.")
                field("Additional allowed hosts", text: allowedHosts,
                             prompt: "Comma-separated hosts", defaultValue: "None",
                             helpText: "Extra HTTP Host names the server accepts. This does not change which network address Splash listens on.")
                field("Maximum request size", text: $controller.configuration.maxRequestSize,
                             prompt: "e.g. 128MB", defaultValue: "128MB when blank",
                             helpText: "Largest HTTP request body Splash accepts, including text and images. Splash treats MB as 1,024 squared bytes.")
                field("Maximum image pixels", text: $controller.configuration.maxImagePixels,
                             prompt: "e.g. 1048576", defaultValue: "4,194,304 pixels when blank",
                             helpText: "Maximum number of pixels in an image after Splash resizes it for processing. A lower limit can reduce image detail and memory use.")
                HStack {
                    SettingLabel("Disable web UI", defaultValue: "Web UI enabled",
                                 helpText: "Hides Splash's built-in browser chat page. The API remains available.")
                    Toggle("", isOn: $controller.configuration.noWebUI)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Disable web UI")
                        .disabled(controller.state.isRunning)
                }
            }

            Panel("API access", symbol: "lock.shield") {
                Text(controller.hasAPIKey ? "Saved in Keychain" : "No API key saved")
                    .foregroundStyle(.secondary)
                HStack {
                    SettingLabel("New API key", helpText: "Optional key saved in macOS Keychain. API clients must send it as a Bearer token. The saved key is never shown here.")
                    SecureField("", text: $keyDraft, prompt: Text("Enter a key"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 230)
                        .accessibilityLabel("New API key")
                        .disabled(controller.state.isRunning)
                        .onSubmit(saveKey)
                }
                HStack {
                    Button("Save key", action: saveKey)
                        .disabled(keyDraft.isEmpty || controller.state.isRunning)
                    Button("Remove key") { controller.removeAPIKey() }
                        .disabled(!controller.hasAPIKey || controller.state.isRunning)
                }
                // Splash reads the key only when it starts, so changes wait until it's stopped.
                if controller.state.isRunning {
                    Notice("Stop Splash to change the API key. The key is applied when Splash starts.", symbol: "lock")
                }
                if let error = controller.keyErrorMessage { Text(error).foregroundStyle(.red) }
            }
        }
    }

    private func refreshModels() {
        installedModels = SplashModelDiscovery.installedModels()
        Task {
            let storage = await Task.detached(priority: .utility) { SplashModelStorage.scan() }.value
            modelStorage = storage
        }
    }

    /// Each installed model's real size and location. Splash's models folder holds only links,
    /// so "Show files" opens the folder that actually contains the model's files.
    @ViewBuilder
    private var installedModelsList: some View {
        if let storage = modelStorage, !storage.models.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(storage.models) { model in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.id).font(.callout).textSelection(.enabled)
                            Text(modelDetail(model)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(formattedFileSize(model.bytes + model.preparedBytes)).font(.callout.weight(.medium)).monospacedDigit()
                        Button("Show files") { revealInFinder(model.locations.first) }
                            .disabled(model.locations.isEmpty)
                            .help(model.locations.map(\.path).joined(separator: "\n"))
                    }
                    .padding(.vertical, 9)
                    Divider()
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Prepared weights cache").font(.callout)
                        Text(preparedCacheDetail(storage)).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(formattedFileSize(storage.preparedCacheBytes)).font(.callout.weight(.medium)).monospacedDigit()
                    Button("Show files") { revealInFinder(SplashModelStorage.preparedCacheDirectory) }
                        .disabled(storage.preparedCacheBytes == 0)
                }
                .padding(.vertical, 9)
            }
            .padding(.horizontal, 14)
            .background(SplashTheme.inset, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func modelDetail(_ model: SplashModelStorage.Model) -> String {
        var parts = [model.format.rawValue]
        if model.preparedBytes > 0 {
            parts.append("\(formattedFileSize(model.bytes)) download + \(formattedFileSize(model.preparedBytes)) prepared")
        }
        if model.sharedBytes > 0 { parts.append("\(formattedFileSize(model.sharedBytes)) shared with other models") }
        if model.locations.count > 1 { parts.append("files in \(model.locations.count) folders") }
        return parts.joined(separator: " · ")
    }

    private func preparedCacheDetail(_ storage: SplashModelStorage) -> String {
        let summary = "Weights Splash converted for its engine. Rebuilt automatically if removed."
        guard storage.orphanedPreparedBytes > 0 else { return summary }
        return "\(formattedFileSize(storage.orphanedPreparedBytes)) is from models that are no longer installed. "
            + "Splash doesn't remove it when a model is deleted; it's safe to delete. " + summary
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func revealInFinder(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func saveKey() {
        guard !keyDraft.isEmpty, !controller.state.isRunning else { return }
        controller.saveAPIKey(keyDraft)
        if controller.keyErrorMessage == nil { keyDraft = "" }
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var isLocked: Bool { controller.state.isRunning }

    private func field(_ title: String, text: Binding<String>, prompt: String,
                       defaultValue: String, helpText: String) -> some View {
        SettingField(title, text: text, prompt: prompt, defaultValue: defaultValue,
                     helpText: helpText, isLocked: isLocked)
    }
}
