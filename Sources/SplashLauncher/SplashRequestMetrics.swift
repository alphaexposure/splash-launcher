import Foundation

/// One finished request, parsed from the line Splash prints to its console, e.g.
/// `15:00:11 Done · input 813 · cached 0 · output 9 · TTFT 14.1s · 3.1 tok/s`.
/// Values Splash does not print (reasoning tokens, total time) are derived or left out.
struct SplashRequestMetrics: Equatable {
    let finishedAt: String
    let cancelled: Bool
    let promptTokens: Int
    let cachedTokens: Int
    let outputTokens: Int
    /// Splash's TTFT: request received to first emitted token, including any queue wait.
    let ttftSeconds: Double?
    /// Splash's streaming rate, measured from the first emitted token to completion.
    let decodeTokensPerSecond: Double?

    init(finishedAt: String, cancelled: Bool = false, promptTokens: Int, cachedTokens: Int,
         outputTokens: Int, ttftSeconds: Double?, decodeTokensPerSecond: Double?) {
        self.finishedAt = finishedAt
        self.cancelled = cancelled
        self.promptTokens = promptTokens
        self.cachedTokens = cachedTokens
        self.outputTokens = outputTokens
        self.ttftSeconds = ttftSeconds
        self.decodeTokensPerSecond = decodeTokensPerSecond
    }

    /// Returns nil for any line that is not a completed or cancelled request.
    init?(logLine: some StringProtocol) {
        let line = logLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = line.firstIndex(of: " ") else { return nil }
        let time = String(line[..<space])
        guard time.count == 8, time.filter({ $0 == ":" }).count == 2 else { return nil }

        let parts = line[line.index(after: space)...].components(separatedBy: " · ")
        guard let outcome = parts.first, outcome == "Done" || outcome == "Cancelled" else { return nil }

        func value(_ prefix: String) -> String? {
            parts.dropFirst().first { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)).replacingOccurrences(of: ",", with: "") }
        }
        guard let prompt = value("input ").flatMap(Int.init),
              let output = value("output ").flatMap(Int.init) else { return nil }

        finishedAt = time
        cancelled = outcome == "Cancelled"
        promptTokens = prompt
        cachedTokens = value("cached ").flatMap(Int.init) ?? 0
        outputTokens = output
        ttftSeconds = value("TTFT ").flatMap { Double($0.hasSuffix("s") ? String($0.dropLast()) : $0) }
        decodeTokensPerSecond = parts.dropFirst().first { $0.hasSuffix(" tok/s") }
            .flatMap { Double($0.dropLast(" tok/s".count).replacingOccurrences(of: ",", with: "")) }
    }

    /// Prompt tokens Splash actually had to process; cached tokens are reused.
    var prefilledTokens: Int { max(0, promptTokens - cachedTokens) }

    /// Splash does not report prefill separately, so TTFT stands in (it also includes queue wait).
    var prefillSeconds: Double? { ttftSeconds }

    var prefillTokensPerSecond: Double? {
        guard let seconds = prefillSeconds, seconds > 0, prefilledTokens > 0 else { return nil }
        return Double(prefilledTokens) / seconds
    }

    /// Splash's rate excludes the first emitted token, so the remaining tokens are timed against it.
    var decodeSeconds: Double? {
        if outputTokens <= 1 { return 0 }
        guard let rate = decodeTokensPerSecond, rate > 0 else { return nil }
        return Double(outputTokens - 1) / rate
    }

    var totalSeconds: Double? {
        guard let ttftSeconds, let decodeSeconds else { return nil }
        return ttftSeconds + decodeSeconds
    }

    var endToEndTokensPerSecond: Double? {
        guard let totalSeconds, totalSeconds > 0 else { return nil }
        return Double(outputTokens) / totalSeconds
    }
}
