import Foundation

enum SharedAppStorage {
    static let appGroupIdentifier = "group.JNBARY.RemPush"

    static var persistenceDirectoryURL: URL {
        let sharedDirectory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? legacyDocumentsDirectoryURL
            ?? FileManager.default.temporaryDirectory
        migrateLegacyPersistenceIfNeeded(to: sharedDirectory)
        return sharedDirectory
    }

    private static var legacyDocumentsDirectoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private static func migrateLegacyPersistenceIfNeeded(to sharedDirectory: URL) {
        guard let legacyDirectory = legacyDocumentsDirectoryURL,
              legacyDirectory.standardizedFileURL != sharedDirectory.standardizedFileURL
        else { return }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)

        for fileName in ["rempush-snapshot.json", "rempush-settings.json"] {
            let source = legacyDirectory.appendingPathComponent(fileName)
            let destination = sharedDirectory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path)
            else { continue }
            try? fileManager.copyItem(at: source, to: destination)
        }
    }
}
