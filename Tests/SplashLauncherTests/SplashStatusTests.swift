import Foundation
import XCTest
@testable import SplashLauncher

final class SplashStatusTests: XCTestCase {
    func testDecodesLoadingStatusWithOnlyRequiredFields() throws {
        let data = Data(#"{"schema_version":1,"ready":false,"unrelated":{"value":42}}"#.utf8)
        let status = try JSONDecoder().decode(SplashStatus.self, from: data)
        XCTAssertEqual(status.schemaVersion, 1)
        XCTAssertFalse(status.ready)
        XCTAssertNil(status.maximumContextTokens)
        XCTAssertNil(status.memoryPressure)
    }

    func testDecodesReadyStatusAndDisplayedMetrics() throws {
        let data = Data(#"{"schema_version":1,"ready":true,"maximum_context_tokens":32768,"memory_pressure":"warning"}"#.utf8)
        let status = try JSONDecoder().decode(SplashStatus.self, from: data)
        XCTAssertTrue(status.ready)
        XCTAssertEqual(status.maximumContextTokens, 32768)
        XCTAssertEqual(status.memoryPressure, "warning")
    }

    func testDecodesEffectiveRuntimeValues() throws {
        let data = Data(#"{"schema_version":1,"ready":true,"maximum_context_tokens":131072,"memory_pressure":"normal","instance":{"model":"incoai/Qwen3.8-27B-Splash","host":"127.0.0.1","port":8000},"http":{"max_request_bytes":134217728},"memory_actual":{"current_bytes":16106127360},"memory_governor":{"limit_bytes":30064771072}}"#.utf8)
        let status = try JSONDecoder().decode(SplashStatus.self, from: data)
        XCTAssertEqual(status.instance?.model, "incoai/Qwen3.8-27B-Splash")
        XCTAssertEqual(status.instance?.host, "127.0.0.1")
        XCTAssertEqual(status.instance?.port, 8000)
        XCTAssertEqual(status.maximumContextTokens, 131072)
        XCTAssertEqual(status.memoryActual?.currentBytes, 16106127360)
        XCTAssertEqual(status.memoryGovernor?.limitBytes, 30064771072)
        XCTAssertEqual(status.http?.maxRequestBytes, 134217728)
    }

    func testDecodesServerTokenMetricsAndAllowsMissingFields() throws {
        let data = Data(#"{"schema_version":1,"ready":true,"metrics":{"prefill_input_tokens":12000,"decode_output_tokens":1450,"prefill_tokens_per_second":532.25,"decode_tokens_per_second":46.8}}"#.utf8)
        let status = try JSONDecoder().decode(SplashStatus.self, from: data)
        XCTAssertEqual(status.metrics?.prefillInputTokens, 12000)
        XCTAssertEqual(status.metrics?.decodeOutputTokens, 1450)
        XCTAssertEqual(status.metrics?.prefillTokensPerSecond, 532.25)
        XCTAssertEqual(status.metrics?.decodeTokensPerSecond, 46.8)
        let partial = try JSONDecoder().decode(SplashStatus.self, from: Data(#"{"schema_version":1,"ready":true,"metrics":{"decode_output_tokens":0}}"#.utf8))
        XCTAssertEqual(partial.metrics?.decodeOutputTokens, 0)
        XCTAssertNil(partial.metrics?.decodeTokensPerSecond)
        XCTAssertNil(partial.metrics?.prefillInputTokens)
    }

    func testClientRequestsConfiguredStatusURLWithoutNetwork() {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockStatusURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let client = SplashStatusClient(session: session)
        let expectation = expectation(description: "Status request completed")
        MockStatusURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8000/status")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"schema_version":1,"ready":true}"#.utf8))
        }

        _ = client.fetchStatus(configuration: SplashConfiguration(), apiKey: "test-key") { result in
            switch result {
            case .success(let status): XCTAssertTrue(status.ready)
            case .failure(let error): XCTFail("Unexpected error: \(error)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
        MockStatusURLProtocol.handler = nil
        session.invalidateAndCancel()
    }

    func testDecodesWithoutSchemaVersion() throws {
        let status = try JSONDecoder().decode(SplashStatus.self, from: Data(#"{"ready":true}"#.utf8))
        XCTAssertTrue(status.ready)
        XCTAssertNil(status.schemaVersion)
    }

    func testMissingReadyFieldFailsDecoding() {
        let data = Data(#"{"schema_version":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SplashStatus.self, from: data))
    }
}

private final class MockStatusURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("Missing URL handler")
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
