import XCTest
@testable import SplashLauncher

final class SplashRequestMetricsTests: XCTestCase {
    func testParsesCompletedRequestLine() throws {
        let request = try XCTUnwrap(SplashRequestMetrics(logLine: "15:00:11 Done · input 813 · cached 0 · output 9 · TTFT 14.1s · 3.1 tok/s"))
        XCTAssertEqual(request, SplashRequestMetrics(finishedAt: "15:00:11", promptTokens: 813, cachedTokens: 0,
                                                     outputTokens: 9, ttftSeconds: 14.1, decodeTokensPerSecond: 3.1))
    }

    func testParsesGroupedNumbersToolsAndCancellation() throws {
        let request = try XCTUnwrap(SplashRequestMetrics(logLine: "09:41:05 Cancelled · input 12,345 · cached 10,000 · output 1,024 · tools 6·a1b2 · TTFT 2.5s · 41.0 tok/s\n"))
        XCTAssertTrue(request.cancelled)
        XCTAssertEqual(request.promptTokens, 12_345)
        XCTAssertEqual(request.cachedTokens, 10_000)
        XCTAssertEqual(request.outputTokens, 1_024)
        XCTAssertEqual(request.ttftSeconds, 2.5)
        XCTAssertEqual(request.decodeTokensPerSecond, 41.0)
    }

    func testAllowsMissingTimings() throws {
        let request = try XCTUnwrap(SplashRequestMetrics(logLine: "10:00:00 Done · input 50 · cached 0 · output 0"))
        XCTAssertNil(request.ttftSeconds)
        XCTAssertNil(request.decodeTokensPerSecond)
        XCTAssertEqual(request.decodeSeconds, 0)
        XCTAssertNil(request.totalSeconds)
    }

    func testIgnoresOtherServerOutput() {
        XCTAssertNil(SplashRequestMetrics(logLine: "14:51:36 Loading"))
        XCTAssertNil(SplashRequestMetrics(logLine: "14:53:14 Error · not_found · HEAD /api/hello"))
        XCTAssertNil(SplashRequestMetrics(logLine: "Done · input 1 · output 1"))
        XCTAssertNil(SplashRequestMetrics(logLine: "10:00:00 Done · cached 0 · output 1"))
        XCTAssertNil(SplashRequestMetrics(logLine: ""))
    }

    func testDerivedTimingsAndRates() throws {
        let request = SplashRequestMetrics(finishedAt: "10:00:00", promptTokens: 1_200, cachedTokens: 200,
                                           outputTokens: 101, ttftSeconds: 20, decodeTokensPerSecond: 4)
        XCTAssertEqual(request.prefilledTokens, 1_000)
        XCTAssertEqual(request.prefillSeconds, 20)
        XCTAssertEqual(request.prefillTokensPerSecond, 50)
        XCTAssertEqual(request.decodeSeconds, 25)
        XCTAssertEqual(request.totalSeconds, 45)
        XCTAssertEqual(try XCTUnwrap(request.endToEndTokensPerSecond), 101.0 / 45, accuracy: 0.0001)
    }

    func testFullyCachedPromptHasNoPrefillRate() {
        let request = SplashRequestMetrics(finishedAt: "10:00:00", promptTokens: 500, cachedTokens: 500,
                                           outputTokens: 1, ttftSeconds: 0.4, decodeTokensPerSecond: nil)
        XCTAssertEqual(request.prefilledTokens, 0)
        XCTAssertNil(request.prefillTokensPerSecond)
        XCTAssertEqual(request.totalSeconds, 0.4)
    }
}
