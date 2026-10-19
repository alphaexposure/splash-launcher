import Foundation
import XCTest
@testable import SplashLauncher

final class SplashExecutableDiscoveryTests: XCTestCase {

    // MARK: - discover(candidatePaths:)

    func testSelectsFirstValidExecutable() {
        let discovery = discovery(validPaths: ["/second/splash-m1"])
        let result = discovery.discover(candidatePaths: [
            "/first/splash-m1",
            "/second/splash-m1",
            "/third/splash-m1",
        ])
        XCTAssertEqual(result?.path, "/second/splash-m1")
    }

    func testSelectsFirstCandidateWhenSeveralAreValid() {
        let discovery = discovery(validPaths: ["/first/splash-m1", "/third/splash-m1"])
        let result = discovery.discover(candidatePaths: [
            "/first/splash-m1",
            "/second/splash-m1",
            "/third/splash-m1",
        ])
        XCTAssertEqual(result?.path, "/first/splash-m1")
    }

    func testReturnsNilWhenNoCandidateIsValid() {
        let discovery = discovery(validPaths: [])
        let result = discovery.discover(candidatePaths: [
            "/first/splash-m1",
            "/second/splash-m1",
        ])
        XCTAssertNil(result)
    }

    func testEmptyCandidateListReturnsNil() {
        let discovery = discovery(validPaths: ["/anything"])
        XCTAssertNil(discovery.discover(candidatePaths: []))
    }

    // MARK: - discover() using the standard candidate locations

    func testDiscoverUsesFirstDefaultPathWhenValid() {
        let discovery = SplashExecutableDiscovery(
            isExecutable: { $0 == "/opt/homebrew/bin/splash-m1" },
            expandHome: { $0 }
        )
        XCTAssertEqual(discovery.discover()?.path, "/opt/homebrew/bin/splash-m1")
    }

    func testDiscoverExpandsTildeInDefaultPaths() {
        let discovery = SplashExecutableDiscovery(
            isExecutable: { $0 == "/fake/home/.local/bin/splash-m1" },
            expandHome: { path in
                path.hasPrefix("~/") ? "/fake/home" + String(path.dropFirst(1)) : path
            }
        )
        XCTAssertEqual(discovery.discover()?.path, "/fake/home/.local/bin/splash-m1")
    }

    // MARK: - defaultCandidatePaths

    func testDefaultCandidatePathsAreInPriorityOrder() {
        XCTAssertEqual(
            SplashExecutableDiscovery.defaultCandidatePaths,
            ["/opt/homebrew/bin/splash-m1", "~/.local/bin/splash-m1"]
        )
    }

    // MARK: - expandHomePath

    func testExpandHomePathReplacesTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(
            SplashExecutableDiscovery.expandHomePath("~/foo/bar"),
            home.appendingPathComponent("foo/bar").path
        )
    }

    func testExpandHomePathLeavesAbsolutePathUnchanged() {
        XCTAssertEqual(
            SplashExecutableDiscovery.expandHomePath("/opt/homebrew/bin/splash-m1"),
            "/opt/homebrew/bin/splash-m1"
        )
    }

    // MARK: - SplashExecutable

    func testExecutableURL() {
        let executable = SplashExecutable(path: "/opt/homebrew/bin/splash-m1")
        XCTAssertEqual(executable.url.path, "/opt/homebrew/bin/splash-m1")
    }

    // MARK: - Helpers

    private func discovery(validPaths: Set<String>) -> SplashExecutableDiscovery {
        SplashExecutableDiscovery(
            isExecutable: { validPaths.contains($0) },
            expandHome: { $0 }
        )
    }
}
