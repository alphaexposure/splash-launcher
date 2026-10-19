import AppKit
import SwiftUI

/// The main window: sidebar, page header with the server controls, and the selected page.
struct ContentView: View {
    @ObservedObject var controller: SplashProcessController
    @State private var page: LauncherPage = .overview

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(SplashTheme.border).frame(width: 1)
            VStack(spacing: 0) {
                pageHeader
                    .padding(.horizontal, 30)
                    .padding(.top, 30)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 1000, alignment: .leading)
                pageContent
            }
            .frame(maxWidth: .infinity)
            .background(SplashTheme.canvas)
        }
        .tint(SplashTheme.accent)
        .frame(minWidth: 850, minHeight: 650)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .overview: scrolling { OverviewPage(controller: controller) }
        case .settings: scrolling { SettingsPage(controller: controller) }
        case .app: scrolling { AppPage() }
        case .logs:
            // The log has its own scroll view, so it fills the window instead of scrolling with the page.
            LogsPage(controller: controller)
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                .frame(maxWidth: 1000, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity)
        }
    }

    private func scrolling<Page: View>(@ViewBuilder _ page: () -> Page) -> some View {
        ScrollView {
            page()
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }

    private var pageTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.rawValue).font(.system(size: 28, weight: .semibold))
            Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    pageTitle.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    serverControls
                }
                VStack(alignment: .leading, spacing: 16) {
                    pageTitle
                    serverControls
                }
            }
            if let message = controller.shutdownMessage { Notice(message, symbol: "hourglass") }
            if let error = controller.statusErrorMessage { Notice(error, symbol: "exclamationmark.circle") }
            if let error = controller.launchErrorMessage { Notice(error, symbol: "exclamationmark.triangle", isError: true) }
        }
    }

    private var serverControls: some View {
        HStack(spacing: 10) {
            Button { controller.start() } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .tint(SplashTheme.accentFill)
                .disabled(!controller.hasExecutable || controller.state.isRunning)
            Button { controller.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .disabled(!controller.state.isRunning || controller.isStopping)
            Button { controller.restart() } label: { Label("Restart", systemImage: "arrow.clockwise") }
                .disabled(!controller.hasExecutable)
            Button {
                if let url = controller.webUIURL { NSWorkspace.shared.open(url) }
            } label: { Label("Open Web UI", systemImage: "arrow.up.right.square") }
                .disabled(controller.webUIURL == nil)
        }
        .controlSize(.large).buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                SplashMarkShape()
                    .fill(SplashTheme.accent)
                    .frame(width: 24, height: 24)
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                    .background(SplashTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                // Two lines so the full name fits the sidebar without truncating.
                VStack(alignment: .leading, spacing: 0) {
                    Text("Splash").font(.system(size: 17, weight: .semibold))
                    Text("Launcher").font(.system(size: 17, weight: .semibold))
                    Text("FOR SPLASH-M1").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(.secondary).padding(.top, 3)
                }
                .lineLimit(1)
                .fixedSize()
            }
            VStack(spacing: 6) {
                ForEach(LauncherPage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.symbol).frame(width: 18)
                            Text(item.rawValue).fontWeight(page == item ? .semibold : .regular)
                            Spacer()
                        }
                        .padding(.horizontal, 13).padding(.vertical, 11)
                        .foregroundStyle(page == item ? SplashTheme.accent : Color.primary.opacity(0.75))
                        .background(page == item ? SplashTheme.accent.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == item ? [.isSelected] : [])
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                StatusBadge(controller: controller)
                Text("Always within reach")
                    .font(.caption.weight(.semibold))
                Text("Use the Splash Launcher menu bar icon to reopen this window or stop your server.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
            .padding(.horizontal, 5)
        }
        .padding(20)
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(SplashTheme.sidebar)
    }
}
