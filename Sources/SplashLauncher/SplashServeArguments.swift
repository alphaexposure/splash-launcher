import Foundation

/// Builds an explicit argument array for Splash. API keys are never arguments.
enum SplashServeArguments {
    static func serveArguments(_ configuration: SplashConfiguration) -> [String] {
        var arguments = [
            "serve",
            "--model", configuration.model,
            "--host", configuration.host,
            "--port", String(configuration.port),
        ]
        for name in configuration.servedModelNames { arguments += ["--served-model-name", name] }
        if !configuration.defaultReasoningEffort.isEmpty {
            arguments += ["--default-reasoning-effort", configuration.defaultReasoningEffort]
        }
        if configuration.kvFormat != "int8" { arguments += ["--kv-format", configuration.kvFormat] }
        if !configuration.maxMemory.isEmpty { arguments += ["--max-memory", configuration.maxMemory] }
        if !configuration.maxContext.isEmpty { arguments += ["--max-context", configuration.maxContext] }
        for host in configuration.allowedHosts { arguments += ["--allowed-host", host] }
        if !configuration.maxRequestSize.isEmpty { arguments += ["--max-request-size", configuration.maxRequestSize] }
        if !configuration.maxImagePixels.isEmpty { arguments += ["--max-image-pixels", configuration.maxImagePixels] }
        if configuration.noWebUI { arguments.append("--no-webui") }
        return arguments
    }
}
