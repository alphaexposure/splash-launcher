import AppKit
import SwiftUI

private final class SplashAppCoordinator {
    static let shared = SplashAppCoordinator()
    weak var controller: SplashProcessController?
}

final class SplashAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.module.url(forResource: "Splash", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = SplashAppCoordinator.shared.controller else { return .terminateNow }
        let waiting = controller.stopBeforeQuit {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return waiting ? .terminateLater : .terminateNow
    }
}

@main
struct SplashLauncherApp: App {
    @NSApplicationDelegateAdaptor(SplashAppDelegate.self) private var appDelegate
    @AppStorage("SplashLauncher.appearance") private var appearance = "system"
    @StateObject private var controller: SplashProcessController

    /// The appearance chosen on the App page; nil follows macOS.
    private var colorScheme: ColorScheme? {
        switch appearance {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    init() {
        let settings = SplashSettingsStore()
        let savedPath = settings.loadExecutablePath()
        let discovery = SplashExecutableDiscovery.filesystem
        let executable = savedPath.flatMap { discovery.discover(candidatePaths: [$0]) } ?? discovery.discover()
        let controller = SplashProcessController(
            configuration: settings.loadConfiguration(),
            executable: executable,
            settingsStore: settings
        )
        _controller = StateObject(wrappedValue: controller)
        SplashAppCoordinator.shared.controller = controller
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(controller: controller)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1040, height: 790)
        MenuBarExtra {
            SplashMenuView(controller: controller)
                .preferredColorScheme(colorScheme)
        } label: {
            Image(nsImage: SplashMark.menuBarImage())
                .accessibilityLabel("Splash Launcher")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct SplashMenuView: View {
    @ObservedObject var controller: SplashProcessController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Splash Launcher")
            } icon: {
                SplashMarkShape().fill(SplashTheme.accent).frame(width: 20, height: 20)
            }
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(SplashTheme.accent)
            Text("Process: \(controller.isStopping ? "Stopping" : controller.state.label)")
            Text("Readiness: \(controller.isStopping ? "Shutting down" : controller.readiness.label)")
            if let pid = controller.state.processID { Text("PID: \(String(pid))") }
            HStack {
                Button("Start") { controller.start() }
                    .disabled(!controller.hasExecutable || controller.state.isRunning)
                Button("Stop") { controller.stop() }
                    .disabled(!controller.state.isRunning || controller.isStopping)
                Button("Restart") { controller.restart() }
                    .disabled(!controller.hasExecutable)
            }
            if let message = controller.shutdownMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let error = controller.launchErrorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            Divider()
            HStack {
                Button("Open Launcher") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(22)
        .frame(width: 340)
        .background(SplashTheme.canvas)
        .tint(SplashTheme.accent)
    }
}
