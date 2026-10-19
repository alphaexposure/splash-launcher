import Foundation

struct SplashConfiguration: Codable, Equatable {
    var model: String = "incoai/Qwen3.8-27B-Splash"
    var host: String = "127.0.0.1"
    var port: Int = 8000
    var servedModelNames: [String] = []
    var defaultReasoningEffort: String = ""
    var kvFormat: String = "int8"
    var maxMemory: String = ""
    var maxContext: String = ""
    var allowedHosts: [String] = []
    var maxRequestSize: String = ""
    var maxImagePixels: String = ""
    var noWebUI: Bool = false

    // Based on the tokenizer templates bundled with these two Splash packages.
    // Qwen3.6 ignores effort intensity; Splash maps any non-none effort to thinking on.
    var reasoningEfforts: [String] {
        switch model {
        case "incoai/Qwen3.8-27B-Splash": return ["none", "low", "medium", "xhigh"]
        case "incoai/Qwen3.6-35B-A3B-Splash": return ["none", "high"]
        default: return ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
        }
    }

    var reasoningGuide: String? {
        switch model {
        case "incoai/Qwen3.8-27B-Splash":
            return "Model default: Extra high. Choose thinking off, Low, Medium, or Extra high."
        case "incoai/Qwen3.6-35B-A3B-Splash":
            return "Model default: Thinking on. This model supports on/off, with no separate effort levels."
        default: return nil
        }
    }

    func reasoningLabel(_ effort: String) -> String {
        if reasoningGuide != nil && effort == "none" { return "Thinking off" }
        if model == "incoai/Qwen3.6-35B-A3B-Splash" && effort == "high" { return "Thinking on" }
        if effort == "xhigh" { return "Extra high" }
        return effort.capitalized
    }

    mutating func normalizeReasoningEffort() {
        if !defaultReasoningEffort.isEmpty && !reasoningEfforts.contains(defaultReasoningEffort) {
            defaultReasoningEffort = ""
        }
    }

    var validationError: String? {
        let modelPattern = #"^[A-Za-z0-9_](?:[A-Za-z0-9._-]*[A-Za-z0-9_])?/[A-Za-z0-9_](?:[A-Za-z0-9._-]{0,94}[A-Za-z0-9_])?$"#
        // Match Splash 1.1's owner/repo[:variant] selection syntax.
        let parts = model.split(separator: ":", omittingEmptySubsequences: false)
        let repository = String(parts[0])
        if repository.range(of: modelPattern, options: .regularExpression) == nil || repository.contains("--") || repository.contains("..") || repository.hasSuffix(".git") {
            return "Model must be a full Hugging Face owner/repo ID."
        }
        if parts.count > 1 {
            let variant = String(parts[1])
            let pattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#
            if parts.count != 2 || variant.range(of: pattern, options: .regularExpression) == nil || variant.contains("..") || variant.contains(where: { $0.isWhitespace }) {
                return "Model variant must be a short name such as UD-Q4_K_M (owner/repo:VARIANT)."
            }
        }
        if model.contains(where: { $0.isWhitespace }) { return "Model ID cannot contain whitespace." }
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a host." }
        if !(1...65535).contains(port) { return "Port must be between 1 and 65535." }
        if !["int8", "bf16"].contains(kvFormat) { return "KV format must be int8 or bf16." }
        if !defaultReasoningEffort.isEmpty && !reasoningEfforts.contains(defaultReasoningEffort) {
            return "Choose a supported reasoning effort."
        }
        if !maxImagePixels.isEmpty {
            guard let pixels = Int(maxImagePixels), (65_536...4_194_304).contains(pixels) else {
                return "Maximum image pixels must be between 65,536 and 4,194,304."
            }
        }
        if !maxContext.isEmpty {
            let value = maxContext.uppercased()
            let number: Int?
            if value.hasSuffix("K"), let thousands = Int(value.dropLast()) {
                let (product, overflow) = thousands.multipliedReportingOverflow(by: 1024)
                number = overflow ? nil : product
            } else {
                number = Int(value)
            }
            if value != "AUTO" && (number == nil || !(1...262_144).contains(number!)) {
                return "Maximum context must be 1–262144 or a value such as 128K."
            }
        }
        for (name, value) in [("Maximum memory", maxMemory), ("Maximum request size", maxRequestSize)] where !value.isEmpty {
            let pattern = #"^[1-9][0-9]*(K|M|G|KB|MB|GB|KIB|MIB|GIB)?$"#
            if value.uppercased().range(of: pattern, options: .regularExpression) == nil && !(name == "Maximum memory" && value.uppercased() == "AUTO") {
                return "\(name) must be a positive size such as 28GB."
            }
        }
        if servedModelNames.contains(where: { name in
            name.isEmpty || name.contains(where: { $0.isWhitespace || "\\%?#".contains($0) }) ||
            name.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        }) {
            return "Model aliases must be names without whitespace or URL delimiters."
        }
        if allowedHosts.contains(where: { $0.isEmpty || $0.rangeOfCharacter(from: .whitespacesAndNewlines) != nil }) {
            return "Allowed hosts cannot be empty or contain whitespace."
        }
        return nil
    }
}

final class SplashSettingsStore {
    private let defaults: UserDefaults
    private let configurationKey = "SplashLauncher.configuration"
    private let executablePathKey = "SplashLauncher.executablePath"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadConfiguration() -> SplashConfiguration {
        guard let data = defaults.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(SplashConfiguration.self, from: data)
        else { return SplashConfiguration() }
        return configuration
    }

    func saveConfiguration(_ configuration: SplashConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: configurationKey)
    }

    func loadExecutablePath() -> String? { defaults.string(forKey: executablePathKey) }
    func saveExecutablePath(_ path: String) { defaults.set(path, forKey: executablePathKey) }
}
