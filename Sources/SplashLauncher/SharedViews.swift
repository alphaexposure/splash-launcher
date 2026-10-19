import AppKit
import SwiftUI

/// A titled card that groups related content.
struct Panel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(.primary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(SplashTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SplashTheme.border, lineWidth: 1))
    }
}

/// A one-line message with an icon; red when it reports an error.
struct Notice: View {
    let text: String
    let symbol: String
    var isError = false

    init(_ text: String, symbol: String, isError: Bool = false) {
        self.text = text
        self.symbol = symbol
        self.isError = isError
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout).foregroundStyle(isError ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A setting's name, help popover and (optionally) its default value.
struct SettingLabel: View {
    let title: String
    var defaultValue: String?
    let helpText: String

    init(_ title: String, defaultValue: String? = nil, helpText: String) {
        self.title = title
        self.defaultValue = defaultValue
        self.helpText = helpText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                SettingHelpIcon(title: title, message: helpText)
            }
            if let defaultValue {
                Text("Default: \(defaultValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled text setting, locked while Splash is running.
struct SettingField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let defaultValue: String
    let helpText: String
    let isLocked: Bool

    init(_ title: String, text: Binding<String>, prompt: String, defaultValue: String,
         helpText: String, isLocked: Bool) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.defaultValue = defaultValue
        self.helpText = helpText
        self.isLocked = isLocked
    }

    var body: some View {
        HStack {
            SettingLabel(title, defaultValue: defaultValue, helpText: helpText)
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(width: 230)
                .accessibilityLabel(title)
                .disabled(isLocked)
        }
    }
}

/// A button that copies text to the clipboard and briefly confirms it.
struct CopyButton<ButtonLabel: View>: View {
    let text: String
    let help: String
    @ViewBuilder let label: (_ copied: Bool) -> ButtonLabel
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                copied = false
            }
        } label: {
            label(copied)
        }
        .help(help)
        .accessibilityHint(copied ? "Copied to clipboard" : help)
    }
}

/// The server's readiness as a small pill: a spinner while loading, a dot otherwise.
struct StatusBadge: View {
    @ObservedObject var controller: SplashProcessController

    var body: some View {
        HStack(spacing: 7) {
            if controller.readiness == .loading && !controller.isStopping {
                ProgressView().controlSize(.small).accessibilityLabel("Splash is starting")
            } else {
                Circle().fill(controller.readiness == .ready && !controller.isStopping ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 7, height: 7)
            }
            Text(controller.isStopping ? "Stopping" : controller.readiness.label)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(SplashTheme.inset, in: Capsule())
    }
}

struct SettingHelpIcon: View {
    let title: String
    let message: String
    @State private var isShowingHelp = false

    var body: some View {
        Button {
            isShowingHelp.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Help for \(title)")
        .accessibilityHint(message)
        .onHover { isShowingHelp = $0 }
        .popover(isPresented: $isShowingHelp, arrowEdge: .trailing) {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(12)
        }
    }
}

/// Where to get Splash-M1. The launcher links to it but never installs Splash itself.
enum SplashLinks {
    static let splashM1 = URL(string: "https://github.com/paperniuk/splash")!
}

/// Lets the user pick the splash-m1 executable when automatic discovery didn't find it.
@MainActor
func chooseSplashExecutable(for controller: SplashProcessController) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true
    panel.prompt = "Use Executable"
    if panel.runModal() == .OK, let url = panel.url { controller.selectExecutable(path: url.path) }
}

/// Shown while no Splash executable is found: explains why Start is unavailable and where
/// to get Splash-M1.
struct MissingSplashNotice: View {
    @ObservedObject var controller: SplashProcessController

    var body: some View {
        if !controller.hasExecutable {
            VStack(alignment: .leading, spacing: 12) {
                Label("Splash-M1 isn't installed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text("Splash Launcher controls an existing Splash-M1 installation and doesn't install it for you. "
                     + "Install Splash-M1, then reopen the launcher, or choose its splash-m1 executable if it's somewhere else.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Link(destination: SplashLinks.splashM1) {
                        Label("Get Splash-M1", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SplashTheme.accentFill)
                    Button("Choose executable…") { chooseSplashExecutable(for: controller) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(SplashTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SplashTheme.accent.opacity(0.35), lineWidth: 1))
        }
    }
}
