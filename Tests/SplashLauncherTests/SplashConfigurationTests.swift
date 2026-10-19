import Foundation
import XCTest
@testable import SplashLauncher

final class SplashConfigurationTests: XCTestCase {
    func testConfigurationValidation() {
        var configuration = SplashConfiguration()
        XCTAssertNil(configuration.validationError)
        configuration.model = "bad model"
        XCTAssertNotNil(configuration.validationError)
        configuration.model = "incoai/Qwen3.8-27B-Splash"
        configuration.port = 0
        XCTAssertNotNil(configuration.validationError)
        configuration.port = 8000
        configuration.maxContext = "999999999999999999999K"
        XCTAssertNotNil(configuration.validationError)
        configuration.maxContext = "128K"
        configuration.maxImagePixels = "2"
        XCTAssertNotNil(configuration.validationError)
        configuration.maxImagePixels = "1048576"
        configuration.servedModelNames = ["bad?alias"]
        XCTAssertNotNil(configuration.validationError)
        configuration.servedModelNames = ["good-alias"]
        XCTAssertNil(configuration.validationError)
    }

    func testConfigurationRoundTripsWithoutSecrets() throws {
        var configuration = SplashConfiguration()
        configuration.maxContext = "128K"
        configuration.noWebUI = true
        let data = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(SplashConfiguration.self, from: data), configuration)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("apiKey"))
    }

    func testModelVariantsMatchSplashSelectionSyntax() {
        var configuration = SplashConfiguration()
        for model in ["incoai/Qwen3.8-27B-Splash", "unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M", "prism-ml/Ternary-Bonsai-2-27B-gguf:PQ2_0"] {
            configuration.model = model
            XCTAssertNil(configuration.validationError, model)
            XCTAssertEqual(SplashServeArguments.serveArguments(configuration)[2], model)
        }
        for model in ["", "owner/repo:", "owner/repo:Q4:extra", "owner/repo:../file", "owner/repo:_Q4", "owner/repo:Q4\n", "owner/repo.git:Q4", "owner/repo:Q4 --host", "owner/repo:" + String(repeating: "a", count: 65)] {
            configuration.model = model
            XCTAssertNotNil(configuration.validationError, model)
        }
    }

    func testQwenReasoningChoicesAndNormalization() {
        var configuration = SplashConfiguration()
        XCTAssertEqual(configuration.reasoningEfforts, ["none", "low", "medium", "xhigh"])
        configuration.defaultReasoningEffort = "high"
        XCTAssertNotNil(configuration.validationError)
        configuration.normalizeReasoningEffort()
        XCTAssertEqual(configuration.defaultReasoningEffort, "")
        XCTAssertFalse(SplashServeArguments.serveArguments(configuration).contains("--default-reasoning-effort"))
        configuration.defaultReasoningEffort = "xhigh"
        XCTAssertNil(configuration.validationError)
        configuration.model = "incoai/Qwen3.6-35B-A3B-Splash"
        XCTAssertEqual(configuration.reasoningEfforts, ["none", "high"])
        configuration.normalizeReasoningEffort()
        XCTAssertEqual(configuration.defaultReasoningEffort, "")
        for effort in configuration.reasoningEfforts {
            configuration.defaultReasoningEffort = effort
            XCTAssertNil(configuration.validationError)
            XCTAssertEqual(SplashServeArguments.serveArguments(configuration).last, effort)
        }
        XCTAssertEqual(configuration.reasoningLabel("high"), "Thinking on")
        configuration.model = "other/model"
        XCTAssertEqual(configuration.reasoningEfforts.count, 7)
        XCTAssertNil(configuration.reasoningGuide)
    }

    func testDefaults() {
        let configuration = SplashConfiguration()
        XCTAssertEqual(configuration.model, "incoai/Qwen3.8-27B-Splash")
        XCTAssertEqual(configuration.host, "127.0.0.1")
        XCTAssertEqual(configuration.port, 8000)
    }
}
