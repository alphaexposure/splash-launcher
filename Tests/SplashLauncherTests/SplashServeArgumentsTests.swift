import XCTest
@testable import SplashLauncher

final class SplashServeArgumentsTests: XCTestCase {

    func testServeArgumentsProducesServeSubcommandAndFlags() {
        let arguments = SplashServeArguments.serveArguments(
            SplashConfiguration(model: "incoai/Qwen3.8-27B-Splash", host: "127.0.0.1", port: 8000)
        )
        XCTAssertEqual(
            arguments,
            [
                "serve",
                "--model", "incoai/Qwen3.8-27B-Splash",
                "--host", "127.0.0.1",
                "--port", "8000",
            ]
        )
    }

    func testServeArgumentsFollowFlagThenValueOrdering() {
        let arguments = SplashServeArguments.serveArguments(
            SplashConfiguration(model: "some/model", host: "0.0.0.0", port: 9999)
        )
        XCTAssertEqual(arguments[0], "serve")
        XCTAssertEqual(arguments[1], "--model")
        XCTAssertEqual(arguments[2], "some/model")
        XCTAssertEqual(arguments[3], "--host")
        XCTAssertEqual(arguments[4], "0.0.0.0")
        XCTAssertEqual(arguments[5], "--port")
        XCTAssertEqual(arguments[6], "9999")
        XCTAssertEqual(arguments.count, 7)
    }

    func testServeArgumentsFromConfiguration() {
        let configuration = SplashConfiguration(
            model: "custom/model",
            host: "10.0.0.1",
            port: 7000
        )
        XCTAssertEqual(
            SplashServeArguments.serveArguments(configuration),
            ["serve", "--model", "custom/model", "--host", "10.0.0.1", "--port", "7000"]
        )
    }

    func testServeArgumentsUsesDefaultConfiguration() {
        XCTAssertEqual(
            SplashServeArguments.serveArguments(SplashConfiguration()),
            [
                "serve",
                "--model", "incoai/Qwen3.8-27B-Splash",
                "--host", "127.0.0.1",
                "--port", "8000",
            ]
        )
    }

    func testOptionalServeFlagsUseExplicitArgumentsWithoutAPIKey() {
        var configuration = SplashConfiguration()
        configuration.servedModelNames = ["alias-one", "alias-two"]
        configuration.defaultReasoningEffort = "xhigh"
        configuration.kvFormat = "bf16"
        configuration.maxMemory = "28G"
        configuration.maxContext = "128K"
        configuration.allowedHosts = ["localhost", "example.local"]
        configuration.maxRequestSize = "256M"
        configuration.maxImagePixels = "1048576"
        configuration.noWebUI = true
        XCTAssertEqual(SplashServeArguments.serveArguments(configuration), [
            "serve", "--model", configuration.model, "--host", "127.0.0.1", "--port", "8000",
            "--served-model-name", "alias-one", "--served-model-name", "alias-two",
            "--default-reasoning-effort", "xhigh", "--kv-format", "bf16",
            "--max-memory", "28G", "--max-context", "128K",
            "--allowed-host", "localhost", "--allowed-host", "example.local",
            "--max-request-size", "256M", "--max-image-pixels", "1048576", "--no-webui"
        ])
    }

    func testPortIsFormattedAsDecimalString() {
        let arguments = SplashServeArguments.serveArguments(
            SplashConfiguration(model: "m", host: "h", port: 1)
        )
        XCTAssertEqual(arguments.last, "1")
    }
}
