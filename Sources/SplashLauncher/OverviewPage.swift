import SwiftUI

/// Server status, live metrics from Splash, and the latest request.
struct OverviewPage: View {
    @ObservedObject var controller: SplashProcessController

    private var liveStatus: SplashStatus? {
        controller.readiness == .ready && !controller.isStopping ? controller.status : nil
    }

    /// The model shown in the Server panel: the one Splash reports while ready (nil if it
    /// reports none), otherwise the selected model.
    private var displayedModel: String? {
        liveStatus == nil ? controller.configuration.model : liveStatus?.instance?.model
    }

    private var copyModelButton: some View {
        CopyButton(text: displayedModel ?? "", help: "Copy the model name to the clipboard") { copied in
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .frame(width: 26, height: 26)
                .background(SplashTheme.inset, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(displayedModel == nil)
        .accessibilityLabel("Copy model name")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MissingSplashNotice(controller: controller)
            Panel("Server", symbol: "power") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(liveStatus == nil ? "Selected model" : "Loaded model")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 8) {
                            Text(displayedModel ?? "Unavailable")
                                .font(.system(size: 18, weight: .semibold))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            copyModelButton
                        }
                    }
                    Spacer(minLength: 12)
                    StatusBadge(controller: controller)
                }
                if let status = liveStatus {
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                        if let host = status.instance?.host, let port = status.instance?.port {
                            Text("\(host):\(String(port))").textSelection(.enabled)
                        } else { Text("Address unavailable") }
                        Spacer()
                        if let pid = controller.state.processID { Text("PID \(String(pid))") }
                    }.font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(controller.isStopping ? "Waiting for Splash to finish shutting down…" : controller.state.isRunning ? "Loading the model and starting the server…" : "Ready when you are. Start Splash to load your model.")
                        .font(.callout).foregroundStyle(.secondary)
                }

            }
            HStack {
                Text("Live overview").font(.headline)
                Spacer()
                Text(liveStatus == nil ? "Available once the server is ready" : "Reported by Splash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                metricCard("Effective context limit", value: liveStatus?.maximumContextTokens.map { $0.formatted() } ?? "—", detail: "tokens", symbol: "text.alignleft", help: "Maximum tokens Splash reports it can handle in one request after automatic sizing or your chosen cap.")
                metricCard("Memory in use", value: liveStatus.map { formattedBytes($0.memoryActual?.currentBytes) } ?? "—", detail: "current Splash usage", symbol: "memorychip", help: "Current memory use reported by Splash. It can change while requests run.")
                metricCard("Memory budget", value: liveStatus.map { formattedBytes($0.memoryGovernor?.limitBytes) } ?? "—", detail: "effective limit", symbol: "gauge.with.dots.needle.50percent", help: "Effective memory limit chosen by Splash or your cap. This is a ceiling, not memory reserved in advance.")
                metricCard("HTTP request limit", value: liveStatus.map { formattedBytes($0.http?.maxRequestBytes) } ?? "—", detail: "incoming data, not tokens", symbol: "arrow.up.doc", help: "Largest incoming HTTP request body, including messages, conversation history, JSON, and encoded images. This is a byte limit, not a prompt token limit. There is no fixed conversion from MB to tokens; the model tokenizer and image processing determine the token count.")
            }
            HStack {
                Text("Token activity").font(.headline)
                Spacer()
                Text("Across all requests · this server session")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                metricCard("Prompt tokens processed", value: liveStatus?.metrics?.prefillInputTokens.map { $0.formatted() } ?? "—", detail: "cumulative prefill tokens", symbol: "text.badge.plus", help: "Splash's cumulative count of tokens processed during prompt ingestion (prefill). Cached prompt content can be reused, so this is not the size of the latest prompt or the amount of context currently occupied. Resets when the server restarts.")
                metricCard("Output tokens generated", value: liveStatus?.metrics?.decodeOutputTokens.map { $0.formatted() } ?? "—", detail: "cumulative decode tokens", symbol: "text.bubble", help: "Splash's cumulative output token counter across all requests in this server session. This is an engine counter, not a word count or the length of the latest visible answer. Resets when the server restarts.")
                metricCard("Prompt processing speed", value: tokenRate(liveStatus?.metrics?.prefillTokensPerSecond, tokens: liveStatus?.metrics?.prefillInputTokens), detail: "tokens/sec · server-reported rate", symbol: "arrow.down.doc", help: "The prefill rate Splash reports: how quickly the engine processes input tokens. This is a server-wide measurement, not a live speedometer for one chat. A dash means no measured token activity is available yet.")
                metricCard("Generation speed", value: tokenRate(liveStatus?.metrics?.decodeTokensPerSecond, tokens: liveStatus?.metrics?.decodeOutputTokens), detail: "tokens/sec · server-reported rate", symbol: "speedometer", help: "The decode rate Splash reports: how quickly the engine generates output tokens. This is a server-wide measurement and can remain visible while idle; it is not the current chat's instantaneous speed. A dash means no measured token activity is available yet.")
            }
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(SplashTheme.accent)
                Text("Memory pressure")
                SettingHelpIcon(title: "Memory pressure", message: "Splash's current assessment of memory availability.")
                Spacer()
                Text(liveStatus?.memoryPressure?.capitalized ?? "—").foregroundStyle(.secondary)
            }
            .font(.callout).padding(18).background(SplashTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            latestRequestSection
        }
    }

    @ViewBuilder
    private var latestRequestSection: some View {
        let request = controller.lastRequest
        HStack {
            Text("Latest request").font(.headline)
            Spacer()
            Text(request.map { "\($0.cancelled ? "Cancelled" : "Finished") at \($0.finishedAt) · from Splash's request log" }
                 ?? (controller.state.isRunning ? "Waiting for the first request" : "Available once Splash handles a request"))
                .font(.caption).foregroundStyle(.secondary)
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            requestRow("Prompt tokens", value: request.map { "\($0.promptTokens.formatted()) (\($0.cachedTokens.formatted()) cached)" },
                       help: "Input tokens in the request, as counted by Splash. Cached tokens were reused from an earlier request and did not need processing again.")
            requestRow("Prefill time", value: request?.prefillSeconds.map { "≈ " + formattedSeconds($0) },
                       help: "Time spent processing the prompt before the first token. Splash doesn't report this separately, so the launcher uses TTFT, which also includes any time the request waited in the queue.")
            requestRow("Output tokens", value: request.map { $0.outputTokens.formatted() },
                       help: "Tokens the model generated, including any reasoning (thinking) tokens.")
            requestRow("Prompt processing", value: request?.prefillTokensPerSecond.map { "≈ " + formattedRate($0) },
                       help: "Uncached prompt tokens ÷ prefill time. Because prefill time includes any queue wait, this can read slightly low.")
            requestRow("Reasoning tokens", value: request.map { _ in "Not reported" },
                       help: "Splash counts reasoning tokens in its API responses but not in its request log, which is what the launcher reads. They are included in Output tokens.")
            requestRow("Decode time", value: request?.decodeSeconds.map { "≈ " + formattedSeconds($0) },
                       help: "Time from the first generated token to the last: output tokens after the first ÷ decode speed. With speculative decoding the first step can emit several tokens, so this can read slightly high.")
            requestRow("Time to first token", value: request?.ttftSeconds.map(formattedSeconds),
                       help: "TTFT as reported by Splash: from receiving the request to emitting the first token, including any queue wait.")
            requestRow("Decode speed", value: request?.decodeTokensPerSecond.map(formattedRate),
                       help: "Generation speed reported by Splash for this request, measured from the first emitted token to completion.")
            requestRow("Total response time", value: request?.totalSeconds.map { "≈ " + formattedSeconds($0) },
                       help: "TTFT + decode time. Splash doesn't print the request's total time, so this is calculated.")
            requestRow("End-to-end speed", value: request?.endToEndTokensPerSecond.map { "≈ " + formattedRate($0) },
                       help: "Output tokens ÷ total response time: the effective speed you experienced, including the wait for the first token.")
        }
        .padding(18)
        .background(SplashTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SplashTheme.border, lineWidth: 1))
    }

    private func requestRow(_ title: String, value: String?, help: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            SettingHelpIcon(title: title, message: help)
            Spacer(minLength: 8)
            Text(value ?? "—").font(.callout.weight(.medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8).textSelection(.enabled)
        }
    }

    private func formattedSeconds(_ seconds: Double) -> String {
        guard seconds >= 60 else { return seconds.formatted(.number.precision(.fractionLength(1))) + " s" }
        let whole = Int(seconds.rounded())
        return "\(whole / 60) min \(String(format: "%02d", whole % 60)) s"
    }

    private func formattedRate(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(1))) + " tok/s"
    }

    private func metricCard(_ title: String, value: String, detail: String, symbol: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(SplashTheme.accent)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                SettingHelpIcon(title: title, message: help)
            }
            Text(value).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(SplashTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SplashTheme.border, lineWidth: 1))
    }

    private func tokenRate(_ rate: Double?, tokens: Int?) -> String {
        guard let rate, rate.isFinite, rate >= 0, let tokens, tokens > 0 else { return "—" }
        return rate.formatted(.number.precision(.fractionLength(1)))
    }

    private func formattedBytes(_ bytes: Int?) -> String {
        guard let bytes, bytes >= 0 else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}
