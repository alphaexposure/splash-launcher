import Foundation
import XCTest
@testable import SplashLauncher

final class SplashProcessControllerTests: XCTestCase {

    private func makeController(
        runProcess: @escaping SplashProcessController.ProcessRunner,
        stopProcess: @escaping SplashProcessController.ProcessStopper,
        statusClient: SplashStatusFetching = FakeStatusClient(),
        portChecker: SplashPortChecking = FakePortChecker(),
        keyStore: SplashAPIKeyStoring = FakeKeyStore()
    ) -> SplashProcessController {
        SplashProcessController(
            configuration: SplashConfiguration(),
            executable: SplashExecutable(path: "/opt/homebrew/bin/splash-m1"),
            runProcess: runProcess,
            stopProcess: stopProcess,
            statusClient: statusClient,
            portChecker: portChecker,
            keyStore: keyStore
        )
    }

    func testReasoningSelectionResetsOnLoadAndModelChange() {
        var configuration = SplashConfiguration()
        configuration.defaultReasoningEffort = "max"
        let controller = SplashProcessController(
            configuration: configuration, executable: nil, runProcess: { _ in 42 },
            keyStore: FakeKeyStore()
        )
        XCTAssertEqual(controller.configuration.defaultReasoningEffort, "")
        controller.configuration.defaultReasoningEffort = "xhigh"
        controller.configuration.model = "incoai/Qwen3.6-35B-A3B-Splash"
        XCTAssertEqual(controller.configuration.defaultReasoningEffort, "")
        controller.configuration.defaultReasoningEffort = "none"
        controller.configuration.model = "incoai/Qwen3.8-27B-Splash"
        XCTAssertEqual(controller.configuration.defaultReasoningEffort, "none")
    }

    // MARK: - start()

    func testStartTransitionsToRunningWithReturnedPID() {
        let controller = makeController(
            runProcess: { _ in 12345 },
            stopProcess: { _ in }
        )
        controller.start()
        XCTAssertEqual(controller.state, .running(processID: 12345))
        XCTAssertNil(controller.launchErrorMessage)
    }

    func testStartIsIgnoredWhileAlreadyRunning() {
        var runCallCount = 0
        let controller = makeController(
            runProcess: { _ in
                runCallCount += 1
                return 42
            },
            stopProcess: { _ in }
        )
        controller.start()
        controller.start()
        XCTAssertEqual(runCallCount, 1)
        XCTAssertEqual(controller.state, .running(processID: 42))
    }

    func testLaunchFailureStaysStoppedAndReportsError() {
        struct LaunchFailure: Error {}
        let controller = makeController(
            runProcess: { _ in throw LaunchFailure() },
            stopProcess: { _ in }
        )
        controller.start()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertNotNil(controller.launchErrorMessage)
    }

    func testLaunchFailureAllowsRetryAfterStoppingState() {
        var attempt = 0
        let controller = makeController(
            runProcess: { _ in
                attempt += 1
                if attempt == 1 {
                    struct LaunchFailure: Error {}
                    throw LaunchFailure()
                }
                return 777
            },
            stopProcess: { _ in }
        )
        controller.start()
        XCTAssertEqual(controller.state, .stopped)
        controller.start()
        XCTAssertEqual(controller.state, .running(processID: 777))
        XCTAssertNil(controller.launchErrorMessage)
    }

    func testStartWithoutExecutableReportsErrorAndStaysStopped() {
        let controller = SplashProcessController(
            configuration: SplashConfiguration(),
            executable: nil,
            runProcess: { _ in 1 },
            stopProcess: { _ in },
            portChecker: FakePortChecker(),
            keyStore: FakeKeyStore()
        )
        XCTAssertFalse(controller.hasExecutable)
        controller.start()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(controller.launchErrorMessage, "No Splash executable found.")
    }

    // MARK: - stop()

    func testStopStopsOwnedProcessAndExitTransitionsToStopped() {
        var stopCallCount = 0
        let controller = makeController(
            runProcess: { _ in 12345 },
            stopProcess: { _ in stopCallCount += 1 }
        )
        controller.start()
        controller.stop()
        XCTAssertEqual(stopCallCount, 1)
        controller.handleProcessExit()
        XCTAssertEqual(controller.state, .stopped)
    }

    func testStopIsNoopWhenNotRunning() {
        var stopCallCount = 0
        let controller = makeController(
            runProcess: { _ in 1 },
            stopProcess: { _ in stopCallCount += 1 }
        )
        controller.stop()
        XCTAssertEqual(stopCallCount, 0)
        XCTAssertEqual(controller.state, .stopped)
    }

    func testStopAfterProcessExitedIsNoop() {
        var stopCallCount = 0
        let controller = makeController(
            runProcess: { _ in 5 },
            stopProcess: { _ in stopCallCount += 1 }
        )
        controller.start()
        controller.handleProcessExit()
        controller.stop()
        XCTAssertEqual(stopCallCount, 0)
        XCTAssertEqual(controller.state, .stopped)
    }

    // MARK: - process exit

    func testProcessExitTransitionsToStopped() {
        let controller = makeController(
            runProcess: { _ in 77 },
            stopProcess: { _ in }
        )
        controller.start()
        XCTAssertEqual(controller.state, .running(processID: 77))
        controller.handleProcessExit()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertNil(controller.state.processID)
    }

    // MARK: - status polling

    func testReadyFalseThenTrueTransitionsWithoutChangingProcessOwnership() {
        let client = FakeStatusClient()
        let controller = makeController(runProcess: { _ in 100 }, stopProcess: { _ in }, statusClient: client)
        controller.start()
        XCTAssertEqual(controller.readiness, .loading)
        XCTAssertEqual(client.requests.count, 1)

        client.complete(.success(SplashStatus(schemaVersion: 1, ready: false, maximumContextTokens: nil, memoryPressure: nil)))
        XCTAssertEqual(controller.readiness, .loading)
        XCTAssertEqual(controller.state, .running(processID: 100))

        controller.pollStatus()
        client.complete(.success(SplashStatus(schemaVersion: 1, ready: true, maximumContextTokens: 32768, memoryPressure: "normal")))
        XCTAssertEqual(controller.readiness, .ready)
        XCTAssertEqual(controller.status?.maximumContextTokens, 32768)
        XCTAssertEqual(controller.status?.memoryPressure, "normal")
        XCTAssertEqual(controller.state, .running(processID: 100))
    }

    func testStartupStatusTimeoutIsHiddenUntilReady() {
        let client = FakeStatusClient()
        let controller = makeController(runProcess: { _ in 201 }, stopProcess: { _ in }, statusClient: client)
        controller.start()
        client.complete(.failure(URLError(.timedOut)))
        XCTAssertEqual(controller.readiness, .loading)
        XCTAssertNil(controller.statusErrorMessage)
        XCTAssertEqual(controller.state, .running(processID: 201))

        controller.pollStatus()
        client.complete(.success(SplashStatus(schemaVersion: 1, ready: true, maximumContextTokens: nil, memoryPressure: nil)))
        XCTAssertEqual(controller.readiness, .ready)
        XCTAssertNil(controller.statusErrorMessage)
    }

    func testUnexpectedExitDuringStartupShowsFailure() {
        let controller = makeController(runProcess: { _ in 202 }, stopProcess: { _ in })
        controller.start()
        controller.handleProcessExit()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(controller.launchErrorMessage, "Splash stopped before it was ready. Check the logs for details.")
    }

    func testFailureKeepsOwnedProcessRunningAndAllowsNextPoll() {
        struct NetworkFailure: LocalizedError {
            var errorDescription: String? { "Unavailable" }
        }
        let client = FakeStatusClient()
        let controller = makeController(runProcess: { _ in 200 }, stopProcess: { _ in }, statusClient: client)
        controller.start()
        client.complete(.success(SplashStatus(schemaVersion: 1, ready: true, maximumContextTokens: nil, memoryPressure: nil)))
        XCTAssertEqual(controller.readiness, .ready)

        controller.pollStatus()
        client.complete(.failure(NetworkFailure()))
        XCTAssertEqual(controller.readiness, .loading)
        XCTAssertEqual(controller.state, .running(processID: 200))
        XCTAssertEqual(controller.statusErrorMessage, "Unavailable")

        controller.pollStatus()
        client.complete(.success(SplashStatus(schemaVersion: 1, ready: true, maximumContextTokens: nil, memoryPressure: nil)))
        XCTAssertEqual(controller.readiness, .ready)
        XCTAssertNil(controller.statusErrorMessage)
    }

    func testPollsDoNotOverlapAndExitCancelsRequestAndIgnoresLateResponse() {
        let client = FakeStatusClient()
        let controller = makeController(runProcess: { _ in 300 }, stopProcess: { _ in }, statusClient: client)
        controller.start()
        controller.pollStatus()
        XCTAssertEqual(client.requests.count, 1)

        controller.handleProcessExit()
        XCTAssertTrue(client.requests[0].cancelled)
        XCTAssertEqual(controller.readiness, .stopped)
        client.complete(.success(SplashStatus(schemaVersion: 1, ready: true, maximumContextTokens: nil, memoryPressure: nil)))
        XCTAssertEqual(controller.readiness, .stopped)
        XCTAssertNil(controller.status)
        controller.pollStatus()
        XCTAssertEqual(client.requests.count, 1)
    }


    // MARK: - later milestones

    func testPortConflictPreventsLaunchWithoutTouchingAnotherProcess() {
        var runs = 0
        let controller = makeController(
            runProcess: { _ in runs += 1; return 1 },
            stopProcess: { _ in },
            portChecker: FakePortChecker(error: "Port 8000 is already in use.")
        )
        controller.start()
        XCTAssertEqual(runs, 0)
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(controller.launchErrorMessage, "Port 8000 is already in use.")
    }

    func testStopWaitsForOwnedProcessExit() {
        var stops = 0
        let controller = makeController(runProcess: { _ in 42 }, stopProcess: { _ in stops += 1 })
        controller.start()
        controller.stop()
        controller.stop()
        XCTAssertEqual(stops, 1)
        XCTAssertTrue(controller.isStopping)
        XCTAssertEqual(controller.state, .running(processID: 42))
        XCTAssertNotNil(controller.shutdownMessage)
        controller.handleProcessExit()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertFalse(controller.isStopping)
    }

    func testRestartStartsOnlyAfterOwnedProcessExits() {
        var runs = 0
        var stops = 0
        let controller = makeController(
            runProcess: { _ in runs += 1; return pid_t(runs) },
            stopProcess: { _ in stops += 1 }
        )
        controller.start()
        controller.restart()
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(stops, 1)
        XCTAssertTrue(controller.isStopping)
        controller.handleProcessExit()
        XCTAssertEqual(runs, 2)
        XCTAssertEqual(controller.state, .running(processID: 2))
    }

    func testQuitWaitsForExitAndCancelsPendingRestart() {
        var runs = 0
        var completionCount = 0
        let controller = makeController(runProcess: { _ in runs += 1; return 1 }, stopProcess: { _ in })
        controller.start()
        controller.restart()
        XCTAssertTrue(controller.stopBeforeQuit { completionCount += 1 })
        XCTAssertEqual(completionCount, 0)
        controller.handleProcessExit()
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(controller.state, .stopped)
    }

    func testKeyUsesEnvironmentAndStatusAuthorizationWithoutAppearingInArgumentsOrLogs() {
        let statusClient = FakeStatusClient()
        var launchedProcess: Process?
        let controller = makeController(
            runProcess: { process in launchedProcess = process; return 1 },
            stopProcess: { _ in },
            statusClient: statusClient,
            keyStore: FakeKeyStore(key: "secret")
        )
        controller.start()
        XCTAssertEqual(launchedProcess?.environment?["SPLASH_API_KEY"], "secret")
        XCTAssertFalse(launchedProcess?.arguments?.joined().contains("secret") ?? true)
        XCTAssertEqual(statusClient.apiKeys, ["secret"])
        controller.appendLog(Data("before sec".utf8))
        XCTAssertFalse(controller.logs.contains("secret"))
        controller.appendLog(Data("ret after extra text".utf8))
        XCTAssertTrue(controller.logs.contains("[REDACTED]"))
        XCTAssertFalse(controller.logs.contains("secret"))
    }

    func testLatestRequestIsReadFromLogLinesSplitAcrossReads() {
        let controller = makeController(runProcess: { _ in 1 }, stopProcess: { _ in },
                                        keyStore: FakeKeyStore(key: "secret"))
        controller.start()
        controller.appendLog(Data("14:52:22 Ready\n15:00:11 Done · input 8".utf8))
        XCTAssertNil(controller.lastRequest)
        controller.appendLog(Data("13 · cached 0 · output 9 · TTFT 14.1s · 3.1 tok/s\n".utf8))
        XCTAssertEqual(controller.lastRequest?.promptTokens, 813)
        controller.appendLog(Data("15:01:00 Done · input 900 · cached 800 · output 20 · TTFT 1.0s · 4.0 tok/s\n".utf8))
        XCTAssertEqual(controller.lastRequest?.finishedAt, "15:01:00")
        controller.clearLogs()
        XCTAssertEqual(controller.lastRequest?.cachedTokens, 800)
    }

    func testProgressBarRedrawsReplaceTheCurrentLine() {
        var log = "Selected model.gguf\n"
        for update in ["\rFetching 2 files:   0%|          | 0/2", "\rFetching 2 files:  50%|█████     | 1/2",
                       "\rFetching 2 files: 100%|██████████| 2/2\n", "14:52:22 Ready\n"] {
            log = SplashProcessController.appendingTerminalOutput(update, to: log)
        }
        XCTAssertEqual(log, "Selected model.gguf\nFetching 2 files: 100%|██████████| 2/2\n14:52:22 Ready\n")
    }

    func testCarriageReturnSplitAcrossReadsStillEndsTheLine() {
        var log = SplashProcessController.appendingTerminalOutput("Loading\r", to: "")
        log = SplashProcessController.appendingTerminalOutput("\nReady\n", to: log)
        XCTAssertEqual(log, "Loading\nReady\n")
        log = SplashProcessController.appendingTerminalOutput("A\r\nB\r\n", to: log)
        XCTAssertEqual(log, "Loading\nReady\nA\nB\n")
    }

    func testPlainOutputIsAppendedUnchangedAndTrimmed() {
        XCTAssertEqual(SplashProcessController.appendingTerminalOutput("two\n", to: "one\n"), "one\ntwo\n")
        XCTAssertEqual(SplashProcessController.appendingTerminalOutput("abcdef", to: "", limit: 3), "def")
    }

    func testDownloadProgressUpdatesInPlaceInDisplayedLogsWithAPIKey() {
        let controller = makeController(runProcess: { _ in 1 }, stopProcess: { _ in },
                                        keyStore: FakeKeyStore(key: "secret"))
        controller.start()
        controller.appendLog(Data("Fetching:  10%\r".utf8))
        controller.appendLog(Data("Fetching:  90%\rFetching: 100%\n15:00:00 Ready\n".utf8))
        controller.appendLog(Data("more output\n".utf8))
        // The last key.count - 1 characters stay held back until more output arrives (key redaction).
        XCTAssertEqual(controller.logs, "Fetching: 100%\n15:00:00 Ready\nmore ou")
    }

    func testRequestLineSurvivesMultibyteSeparatorSplitAcrossReads() {
        let controller = makeController(runProcess: { _ in 1 }, stopProcess: { _ in })
        controller.start()
        let line = Data("15:00:11 Done · input 813 · cached 0 · output 9 · TTFT 14.1s · 3.1 tok/s\n".utf8)
        let middleOfSeparator = line.firstIndex(of: 0xC2)! + 1
        controller.appendLog(line[..<middleOfSeparator])
        controller.appendLog(line[middleOfSeparator...])
        XCTAssertEqual(controller.lastRequest?.decodeTokensPerSecond, 3.1)
    }

    func testFinalRequestLineWithoutNewlineIsReadWhenProcessExits() {
        let controller = makeController(runProcess: { _ in 1 }, stopProcess: { _ in })
        controller.start()
        controller.appendLog(Data("15:00:11 Done · input 10 · cached 0 · output 2 · TTFT 1.0s · 2.0 tok/s".utf8))
        XCTAssertNil(controller.lastRequest)
        controller.handleProcessExit()
        XCTAssertEqual(controller.lastRequest?.outputTokens, 2)
    }

    // MARK: - state model

    func testStateLabels() {
        XCTAssertEqual(SplashProcessState.stopped.label, "Stopped")
        XCTAssertEqual(SplashProcessState.running(processID: 1).label, "Running")
    }

    func testStateProcessID() {
        XCTAssertNil(SplashProcessState.stopped.processID)
        XCTAssertEqual(SplashProcessState.running(processID: 9).processID, 9)
        XCTAssertFalse(SplashProcessState.stopped.isRunning)
        XCTAssertTrue(SplashProcessState.running(processID: 9).isRunning)
    }
}

private final class FakeStatusClient: SplashStatusFetching {
    private(set) var completions: [(Result<SplashStatus, Error>) -> Void] = []
    private(set) var requests: [FakeStatusRequest] = []
    private(set) var apiKeys: [String?] = []

    func fetchStatus(
        configuration: SplashConfiguration,
        apiKey: String?,
        completion: @escaping (Result<SplashStatus, Error>) -> Void
    ) -> SplashStatusRequest {
        let request = FakeStatusRequest()
        apiKeys.append(apiKey)
        requests.append(request)
        completions.append(completion)
        return request
    }

    func complete(_ result: Result<SplashStatus, Error>, at index: Int? = nil) {
        completions[index ?? completions.count - 1](result)
    }
}

private final class FakeStatusRequest: SplashStatusRequest {
    private(set) var cancelled = false
    func cancel() { cancelled = true }
}

private struct FakePortChecker: SplashPortChecking {
    var error: String? = nil
    func check(_ configuration: SplashConfiguration) -> String? { error }
}

private final class FakeKeyStore: SplashAPIKeyStoring {
    var key: String?
    init(key: String? = nil) { self.key = key }
    func read() throws -> String? { key }
    func save(_ key: String) throws { self.key = key }
    func remove() throws { key = nil }
}
