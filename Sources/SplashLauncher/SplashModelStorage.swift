import Foundation

/// Where installed models really live and how much space they use. Splash's models folder
/// holds only links; the files are in the Hugging Face cache, sometimes shared between models.
/// Read-only: the launcher never moves or deletes Splash data.
struct SplashModelStorage: Equatable {
    struct Model: Equatable, Identifiable {
        enum Format: String { case package = "Splash package", gguf = "GGUF", other = "Other" }

        let id: String
        let format: Format
        /// Unique bytes of every file the model uses, including files shared with other models.
        let bytes: Int64
        /// The part of `bytes` that other installed models also use.
        let sharedBytes: Int64
        /// Folders holding the real files, largest share first (e.g. a Hugging Face repo folder).
        let locations: [URL]
        /// Copies Splash converted from this model's files, in the prepared weights cache.
        let preparedBytes: Int64
    }

    let models: [Model]
    /// Splash's cache of weights converted for its engine. Rebuilt on demand if removed.
    let preparedCacheBytes: Int64
    /// Cache entries converted from models that are no longer installed. Splash doesn't
    /// remove these when a model is deleted.
    let orphanedPreparedBytes: Int64

    static var preparedCacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Splash/weights", isDirectory: true)
    }

    static func scan(modelsRoot: URL = SplashModelDiscovery.directory,
                     preparedCache: URL = preparedCacheDirectory) -> SplashModelStorage {
        let ids = SplashModelDiscovery.installedModels(in: modelsRoot)
        let filesByModel = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, realFiles(under: modelsRoot.appendingPathComponent($0)))
        })
        var users: [String: Int] = [:]
        for files in filesByModel.values { for path in files.keys { users[path, default: 0] += 1 } }
        func size(_ files: [String: RealFile]) -> Int64 { files.values.reduce(0) { $0 + $1.bytes } }

        // Each cache entry records the model file it was converted from.
        let modelRoots = ids.map { id in (id, modelsRoot.appendingPathComponent(id).resolvingSymlinksInPath().path + "/") }
        var preparedByModel: [String: Int64] = [:]
        var orphanedPrepared: Int64 = 0
        for entry in preparedEntries(in: preparedCache) {
            guard let source = entry.source else { continue }
            let realSource = URL(fileURLWithPath: source).resolvingSymlinksInPath().path
            let owner = modelRoots.first { source.hasPrefix($0.1) }?.0
                ?? ids.first { filesByModel[$0]?[realSource] != nil }
            if let owner { preparedByModel[owner, default: 0] += entry.bytes } else { orphanedPrepared += entry.bytes }
        }

        let models = ids.map { id -> Model in
            let files = filesByModel[id] ?? [:]
            var bytesByLocation: [URL: Int64] = [:]
            for (path, file) in files { bytesByLocation[location(of: path), default: 0] += file.bytes }
            let names = Set(files.values.map(\.name))
            let format: Model.Format = names.contains { $0.hasSuffix(".gguf") } ? .gguf
                : names.contains("manifest.json") ? .package : .other
            return Model(
                id: id, format: format,
                bytes: size(files),
                sharedBytes: size(files.filter { (users[$0.key] ?? 0) > 1 }),
                locations: bytesByLocation.sorted { $0.value > $1.value }.map(\.key),
                preparedBytes: preparedByModel[id] ?? 0
            )
        }
        return SplashModelStorage(models: models,
                                  preparedCacheBytes: size(realFiles(under: preparedCache)),
                                  orphanedPreparedBytes: orphanedPrepared)
    }

    struct PreparedEntry: Equatable {
        let bytes: Int64
        /// The model file the entry was converted from, as Splash recorded it.
        let source: String?
    }

    /// Entries of Splash's prepared weights cache. Each folder holds the converted weights and a
    /// `source` file with lines such as `source /path/to/model/target/model.gguf`.
    static func preparedEntries(in cache: URL) -> [PreparedEntry] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: cache, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return folders.map { folder in
            let record = (try? String(contentsOf: folder.appendingPathComponent("source"), encoding: .utf8)) ?? ""
            let source = record.split(separator: "\n").first { $0.hasPrefix("source ") }
                .map { String($0.dropFirst("source ".count)) }
            return PreparedEntry(bytes: realFiles(under: folder).values.reduce(0) { $0 + $1.bytes }, source: source)
        }
    }

    struct RealFile: Equatable {
        let bytes: Int64
        /// The name the model uses; Hugging Face stores the real file under a hash.
        let name: String
    }

    /// Every regular file reachable from `root`, following links, keyed by its real path.
    static func realFiles(under root: URL) -> [String: RealFile] {
        var files: [String: RealFile] = [:]
        var visitedDirectories = Set<String>()
        func visit(_ url: URL) {
            let real = url.resolvingSymlinksInPath()
            guard let values = try? real.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            else { return }
            if values.isDirectory == true {
                guard visitedDirectories.insert(real.path).inserted else { return }
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: real, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
                children.forEach(visit)
            } else if values.isRegularFile == true {
                files[real.path] = RealFile(bytes: Int64(values.fileSize ?? 0), name: url.lastPathComponent)
            }
        }
        visit(root)
        return files
    }

    /// The Hugging Face repo folder (`models--owner--name`) holding a file, else its parent folder.
    static func location(of path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        var candidate = url.deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.lastPathComponent.hasPrefix("models--") { return candidate }
            candidate.deleteLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }
}
