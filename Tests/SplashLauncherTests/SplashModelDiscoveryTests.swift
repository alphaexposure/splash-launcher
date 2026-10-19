import Foundation
import XCTest
@testable import SplashLauncher

final class SplashModelDiscoveryTests: XCTestCase {
    func testFindsNewAssembliesAndVariantsAlongsideLegacyPackages() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let models = root.appendingPathComponent("models")
        for (name, marker) in [("incoai/Legacy", "manifest.json"), ("unsloth/Qwen-GGUF:UD-Q4_K_M", "model.json"), ("mlx-community/Qwen-4bit", "model.json"), (".selections/hash", "model.json"), ("unsloth/Invalid:Q4:extra", "model.json")] {
            let cached = root.appendingPathComponent(UUID().uuidString)
            try files.createDirectory(at: cached, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: cached.appendingPathComponent(marker))
            let link = models.appendingPathComponent(name)
            try files.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.createSymbolicLink(at: link, withDestinationURL: cached)
        }
        XCTAssertEqual(SplashModelDiscovery.installedModels(in: models), ["incoai/Legacy", "mlx-community/Qwen-4bit", "unsloth/Qwen-GGUF:UD-Q4_K_M"])
    }

    func testFindsRegisteredPackagesIncludingSymlinksAndSkipsIncompleteEntries() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let models = root.appendingPathComponent("models")
        let owner = models.appendingPathComponent("incoai")
        let cached = root.appendingPathComponent("cached")
        try files.createDirectory(at: owner.appendingPathComponent("Incomplete"), withIntermediateDirectories: true)
        try files.createDirectory(at: cached, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: cached.appendingPathComponent("manifest.json"))
        try files.createSymbolicLink(at: owner.appendingPathComponent("Qwen-Splash"), withDestinationURL: cached)
        try files.createSymbolicLink(at: owner.appendingPathComponent("Missing"), withDestinationURL: root.appendingPathComponent("absent"))
        XCTAssertEqual(SplashModelDiscovery.installedModels(in: models), ["incoai/Qwen-Splash"])
        XCTAssertTrue(SplashModelDiscovery.installedModels(in: root.appendingPathComponent("absent")).isEmpty)
    }
}
