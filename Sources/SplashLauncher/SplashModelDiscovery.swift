import Foundation

struct SplashModelDiscovery {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Splash/models", isDirectory: true)
    }

    /// Splash registers packages and 1.1 assemblies as owner/repository[:variant] links.
    static func installedModels(in root: URL = directory) -> [String] {
        let files = FileManager.default
        let owners = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                    options: .skipsHiddenFiles)) ?? []
        return owners.flatMap { owner -> [String] in
            let repos = (try? files.contentsOfDirectory(at: owner, includingPropertiesForKeys: nil,
                                                       options: .skipsHiddenFiles)) ?? []
            return repos.compactMap { repo in
                guard ["manifest.json", "model.json"].contains(where: {
                    files.fileExists(atPath: repo.appendingPathComponent($0).path)
                }) else { return nil }
                let id = "\(owner.lastPathComponent)/\(repo.lastPathComponent)"
                var configuration = SplashConfiguration()
                configuration.model = id
                return configuration.validationError == nil ? id : nil
            }
        }.sorted()
    }
}
