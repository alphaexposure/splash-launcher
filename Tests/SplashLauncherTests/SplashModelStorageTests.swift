import Foundation
import XCTest
@testable import SplashLauncher

final class SplashModelStorageTests: XCTestCase {
    private let files = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? files.removeItem(at: root) }

    /// A Hugging Face style repo: content in blobs/, readable names in snapshots/rev/ linking to them.
    @discardableResult
    private func repo(_ name: String, files entries: [String: Int]) throws -> URL {
        let repo = root.appendingPathComponent("hub/models--\(name.replacingOccurrences(of: "/", with: "--"))")
        let snapshot = repo.appendingPathComponent("snapshots/rev")
        for (path, size) in entries {
            let blob = repo.appendingPathComponent("blobs/\(UUID().uuidString)")
            try files.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: size).write(to: blob)
            let link = snapshot.appendingPathComponent(path)
            try files.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.createSymbolicLink(at: link, withDestinationURL: blob)
        }
        return snapshot
    }

    private func register(_ id: String, at target: URL) throws {
        let link = root.appendingPathComponent("models/\(id)")
        try files.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.createSymbolicLink(at: link, withDestinationURL: target)
    }

    /// A GGUF assembly: Splash's own folder of links into the GGUF repo and the shared draft repo.
    @discardableResult
    private func assembly(_ id: String, gguf: URL, draft: URL) throws -> URL {
        let folder = root.appendingPathComponent("models/.resolved/\(UUID().uuidString)")
        try files.createDirectory(at: folder.appendingPathComponent("target"), withIntermediateDirectories: true)
        try files.createDirectory(at: folder.appendingPathComponent("draft"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("model.json"))
        try files.createSymbolicLink(at: folder.appendingPathComponent("target/model.gguf"), withDestinationURL: gguf)
        try files.createSymbolicLink(at: folder.appendingPathComponent("draft/model.safetensors"), withDestinationURL: draft)
        try register(id, at: folder)
        return folder
    }

    /// A prepared weights cache entry as Splash writes it: weights plus a `source` record.
    /// Returns the bytes written, which is what the entry occupies.
    @discardableResult
    private func preparedEntry(in cache: URL, bytes: Int, source: String?) throws -> Int64 {
        let folder = cache.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: folder.appendingPathComponent("weights"))
        if let source {
            let record = "splash-prepared-weight-v1\ncomponent target/layer-0.bin\ninputs abc\nsource \(source)\n"
            try Data(record.utf8).write(to: folder.appendingPathComponent("source"))
            return Int64(bytes + record.utf8.count)
        }
        return Int64(bytes)
    }

    func testFollowsLinksToRealFilesAndCountsSharedDraftOnce() throws {
        let package = try repo("incoai/Pkg", files: ["manifest.json": 10, "target/layer-0.bin": 1_000, "draft/layer-0.bin": 200])
        try register("incoai/Pkg", at: package)
        let draft = try repo("incoai/Draft", files: ["model.safetensors": 300])
        let q4 = try repo("unsloth/Q-GGUF", files: ["Q-Q4.gguf": 2_000, "Q-Q3.gguf": 1_500])
        try assembly("unsloth/Q-GGUF:Q4", gguf: q4.appendingPathComponent("Q-Q4.gguf"),
                     draft: draft.appendingPathComponent("model.safetensors"))
        try assembly("unsloth/Q-GGUF:Q3", gguf: q4.appendingPathComponent("Q-Q3.gguf"),
                     draft: draft.appendingPathComponent("model.safetensors"))

        let storage = SplashModelStorage.scan(modelsRoot: root.appendingPathComponent("models"),
                                              preparedCache: root.appendingPathComponent("absent"))
        let models = Dictionary(uniqueKeysWithValues: storage.models.map { ($0.id, $0) })

        let pkg = try XCTUnwrap(models["incoai/Pkg"])
        XCTAssertEqual(pkg.format, .package)
        XCTAssertEqual(pkg.bytes, 1_210)
        XCTAssertEqual(pkg.sharedBytes, 0, "a package's own draft is not shared")
        XCTAssertEqual(pkg.locations.map(\.lastPathComponent), ["models--incoai--Pkg"])

        let q4Model = try XCTUnwrap(models["unsloth/Q-GGUF:Q4"])
        XCTAssertEqual(q4Model.format, .gguf)
        XCTAssertEqual(q4Model.bytes, 2_000 + 300 + 2, "GGUF, draft and the assembly's model.json")
        XCTAssertEqual(q4Model.sharedBytes, 300)
        XCTAssertEqual(q4Model.locations.first?.lastPathComponent, "models--unsloth--Q-GGUF")
        XCTAssertTrue(q4Model.locations.contains { $0.lastPathComponent == "models--incoai--Draft" })
        XCTAssertEqual(storage.preparedCacheBytes, 0)
    }

    func testIgnoresBrokenLinksAndLinkLoops() throws {
        let package = try repo("incoai/Pkg", files: ["manifest.json": 5])
        try files.createSymbolicLink(at: package.appendingPathComponent("missing.bin"),
                                     withDestinationURL: root.appendingPathComponent("gone"))
        try files.createSymbolicLink(at: package.appendingPathComponent("loop"), withDestinationURL: package)
        try register("incoai/Pkg", at: package)
        let storage = SplashModelStorage.scan(modelsRoot: root.appendingPathComponent("models"),
                                              preparedCache: root.appendingPathComponent("absent"))
        XCTAssertEqual(storage.models.first?.bytes, 5)
    }

    func testAttributesPreparedWeightsToModelsAndFlagsLeftovers() throws {
        let package = try repo("incoai/Pkg", files: ["manifest.json": 10, "target/layer-0.bin": 1_000])
        try register("incoai/Pkg", at: package)
        let draft = try repo("incoai/Draft", files: ["model.safetensors": 300])
        let gguf = try repo("unsloth/Q-GGUF", files: ["Q-Q4.gguf": 2_000])
        let folder = try assembly("unsloth/Q-GGUF:Q4", gguf: gguf.appendingPathComponent("Q-Q4.gguf"),
                                  draft: draft.appendingPathComponent("model.safetensors"))
        let cache = root.appendingPathComponent("weights")
        let target = try preparedEntry(in: cache, bytes: 700, source: folder.appendingPathComponent("target/model.gguf").path)
        let draftEntry = try preparedEntry(in: cache, bytes: 50, source: folder.appendingPathComponent("draft/model.safetensors").path)
        // Recorded through the Hugging Face snapshot rather than Splash's models folder.
        let packaged = try preparedEntry(in: cache, bytes: 40, source: package.appendingPathComponent("target/layer-0.bin").path)
        let leftover = try preparedEntry(in: cache, bytes: 900, source: root.appendingPathComponent("models/.resolved/deleted/target/old.gguf").path)
        let unrecorded = try preparedEntry(in: cache, bytes: 5, source: nil)

        let storage = SplashModelStorage.scan(modelsRoot: root.appendingPathComponent("models"), preparedCache: cache)
        let models = Dictionary(uniqueKeysWithValues: storage.models.map { ($0.id, $0.preparedBytes) })
        XCTAssertEqual(models["unsloth/Q-GGUF:Q4"], target + draftEntry)
        XCTAssertEqual(models["incoai/Pkg"], packaged)
        XCTAssertEqual(storage.orphanedPreparedBytes, leftover, "entries without a source record are not called leftovers")
        XCTAssertEqual(storage.preparedCacheBytes, target + draftEntry + packaged + leftover + unrecorded)
    }

    func testAddsUpPreparedWeightsCache() throws {
        let cache = root.appendingPathComponent("weights")
        for (folder, size) in [("a", 400), ("b", 600)] {
            let file = cache.appendingPathComponent("\(folder)/layer.bin")
            try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: size).write(to: file)
        }
        let storage = SplashModelStorage.scan(modelsRoot: root.appendingPathComponent("models"), preparedCache: cache)
        XCTAssertTrue(storage.models.isEmpty)
        XCTAssertEqual(storage.preparedCacheBytes, 1_000)
    }
}
