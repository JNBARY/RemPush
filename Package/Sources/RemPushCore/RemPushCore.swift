import Foundation

public enum RemPushConstants {
    public static let pageCount = 9
    public static let fullPagesMessage = "Alle 9 Seiten sind bereits gefüllt."
}

public struct NotePage: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public var title: String
    public var body: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var revision: Int

    public init(index: Int, title: String = "", body: String = "", createdAt: Date? = nil, updatedAt: Date? = nil, revision: Int = 0) {
        self.index = index
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
    }

    public var isEmpty: Bool { createdAt == nil }
}

public struct RemPushSnapshot: Codable, Equatable, Sendable {
    public var pages: [NotePage]
    public var lastUsedPageIndex: Int

    public init(pages: [NotePage], lastUsedPageIndex: Int) {
        self.pages = Self.normalized(pages)
        self.lastUsedPageIndex = min(max(lastUsedPageIndex, 0), RemPushConstants.pageCount - 1)
    }

    private static func normalized(_ pages: [NotePage]) -> [NotePage] {
        (0..<RemPushConstants.pageCount).map { index in
            pages.first(where: { $0.index == index }) ?? NotePage(index: index)
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var archiveDirectoryPath: String?
    public var archiveDirectoryBookmark: Data?
    public var lastExportedMonthIdentifier: String?

    public init(archiveDirectoryPath: String? = nil, archiveDirectoryBookmark: Data? = nil, lastExportedMonthIdentifier: String? = nil) {
        self.archiveDirectoryPath = archiveDirectoryPath
        self.archiveDirectoryBookmark = archiveDirectoryBookmark
        self.lastExportedMonthIdentifier = lastExportedMonthIdentifier
    }
}

public struct LaunchDestination: Equatable, Sendable {
    public let pageIndex: Int
    public let message: String?
}

public struct NotificationRequest: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public protocol NotificationScheduling: AnyObject {
    func schedule(_ request: NotificationRequest) throws
}

public final class RecordingNotificationScheduler: NotificationScheduling {
    public private(set) var requests: [NotificationRequest] = []
    public init() {}
    public func schedule(_ request: NotificationRequest) { requests.append(request) }
}

public enum RemPushError: Error, Equatable {
    case invalidPageIndex
    case emptyPageCannotNotify
    case archiveDirectoryMissing
    case notificationAuthorizationDenied
    case notificationSchedulerMissing
}

public final class NoteStore {
    public private(set) var pages: [NotePage]
    public private(set) var lastUsedPageIndex: Int

    private let clock: () -> Date
    private let notificationScheduler: NotificationScheduling?

    public init(pages: [NotePage]? = nil, lastUsedPageIndex: Int = 0, clock: @escaping () -> Date = Date.init, notificationScheduler: NotificationScheduling? = nil) {
        let snapshot = RemPushSnapshot(pages: pages ?? [], lastUsedPageIndex: lastUsedPageIndex)
        self.pages = pages == nil ? (0..<RemPushConstants.pageCount).map { NotePage(index: $0) } : snapshot.pages
        self.lastUsedPageIndex = snapshot.lastUsedPageIndex
        self.clock = clock
        self.notificationScheduler = notificationScheduler
    }

    public convenience init(snapshot: RemPushSnapshot, clock: @escaping () -> Date = Date.init, notificationScheduler: NotificationScheduling? = nil) {
        self.init(pages: snapshot.pages, lastUsedPageIndex: snapshot.lastUsedPageIndex, clock: clock, notificationScheduler: notificationScheduler)
    }

    public var snapshot: RemPushSnapshot {
        RemPushSnapshot(pages: pages, lastUsedPageIndex: lastUsedPageIndex)
    }

    public func launchDestination() -> LaunchDestination {
        if let firstEmpty = pages.first(where: \.isEmpty) {
            return LaunchDestination(pageIndex: firstEmpty.index, message: nil)
        }
        return LaunchDestination(pageIndex: lastUsedPageIndex, message: RemPushConstants.fullPagesMessage)
    }

    public func save(pageIndex: Int, title: String, body: String) throws {
        guard pages.indices.contains(pageIndex) else { throw RemPushError.invalidPageIndex }
        let now = clock()
        if pages[pageIndex].createdAt == nil {
            pages[pageIndex].createdAt = now
        }
        pages[pageIndex].title = title
        pages[pageIndex].body = body
        pages[pageIndex].updatedAt = now
        pages[pageIndex].revision += 1
        lastUsedPageIndex = pageIndex
    }

    public func replace(page: NotePage) throws {
        guard pages.indices.contains(page.index) else { throw RemPushError.invalidPageIndex }
        pages[page.index] = page
        lastUsedPageIndex = page.index
    }

    public func delete(pageIndex: Int) {
        guard pages.indices.contains(pageIndex) else { return }
        pages[pageIndex] = NotePage(index: pageIndex)
        lastUsedPageIndex = pageIndex
    }

    public func notificationRequest(pageIndex: Int) throws -> NotificationRequest {
        guard pages.indices.contains(pageIndex) else { throw RemPushError.invalidPageIndex }
        let page = pages[pageIndex]
        guard !page.isEmpty else { throw RemPushError.emptyPageCannotNotify }
        let title = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotificationRequest(title: title.isEmpty ? "RemPush Seite \(pageIndex + 1)" : title, body: pages[pageIndex].body)
    }

    public func scheduleTitleNotification(pageIndex: Int) throws {
        guard let notificationScheduler else { throw RemPushError.notificationSchedulerMissing }
        try notificationScheduler.schedule(notificationRequest(pageIndex: pageIndex))
    }
}

public struct MonthlyArchive: Equatable, Sendable {
    public let fileName: String
    public let content: String
}

public struct MonthlyExporter: Sendable {
    public init() {}

    public func previousMonthArchive(for date: Date, pages: [NotePage], calendar: Calendar = .init(identifier: .gregorian)) -> MonthlyArchive {
        let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: date) ?? date
        let components = calendar.dateComponents([.month, .year], from: previousMonthDate)
        return renderMonthlyArchive(pages: pages, month: components.month ?? 1, year: components.year ?? 1970, calendar: calendar)
    }

    public func renderMonthlyArchive(pages: [NotePage], month: Int, year: Int, calendar: Calendar = .init(identifier: .gregorian)) -> MonthlyArchive {
        let formatter = ISO8601DateFormatter()
        let selected = pages.compactMap { page -> NotePage? in
            guard let createdAt = page.createdAt else { return nil }
            let comps = calendar.dateComponents([.month, .year], from: createdAt)
            return comps.month == month && comps.year == year ? page : nil
        }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        let content = selected.map { page in
            let date = page.createdAt.map { formatter.string(from: $0) } ?? "ohne Datum"
            return "Erstellt: \(date)\nTitel: \(page.title)\nInhalt:\n\(page.body)"
        }.joined(separator: "\n\n---\n\n")
        return MonthlyArchive(fileName: String(format: "RemPush-%04d-%02d.txt", year, month), content: content)
    }
}

public struct ArchiveWriteResult: Equatable, Sendable {
    public let filePath: String
    public let archive: MonthlyArchive
}

public protocol ArchiveWriting {
    func write(_ archive: MonthlyArchive, toDirectoryPath directoryPath: String) throws -> ArchiveWriteResult
}

public struct FileArchiveWriter: ArchiveWriting, Sendable {
    public init() {}
    public func write(_ archive: MonthlyArchive, toDirectoryPath directoryPath: String) throws -> ArchiveWriteResult {
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(archive.fileName)
        try archive.content.write(to: fileURL, atomically: true, encoding: .utf8)
        return ArchiveWriteResult(filePath: fileURL.path, archive: archive)
    }
}

public struct MonthlyExportService<Writer: ArchiveWriting> {
    public let exporter: MonthlyExporter
    public let writer: Writer

    public init(exporter: MonthlyExporter = MonthlyExporter(), writer: Writer) {
        self.exporter = exporter
        self.writer = writer
    }

    public func exportPreviousMonthIfNeeded(now: Date, pages: [NotePage], settings: inout AppSettings, calendar: Calendar = .init(identifier: .gregorian)) throws -> ArchiveWriteResult? {
        let currentMonthIdentifier = Self.monthIdentifier(for: now, calendar: calendar)
        guard settings.lastExportedMonthIdentifier != currentMonthIdentifier else { return nil }
        guard let directory = settings.archiveDirectoryPath else { throw RemPushError.archiveDirectoryMissing }
        let archive = exporter.previousMonthArchive(for: now, pages: pages, calendar: calendar)
        let result = try writer.write(archive, toDirectoryPath: directory)
        settings.lastExportedMonthIdentifier = currentMonthIdentifier
        return result
    }

    private static func monthIdentifier(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 1970, comps.month ?? 1)
    }
}

public protocol SnapshotPersisting {
    func loadSnapshot() throws -> RemPushSnapshot?
    func saveSnapshot(_ snapshot: RemPushSnapshot) throws
}

public protocol SettingsPersisting {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
}

public struct JSONFilePersistence: SnapshotPersisting, SettingsPersisting, Sendable {
    public let snapshotURL: URL
    public let settingsURL: URL

    public init(directoryURL: URL) {
        self.snapshotURL = directoryURL.appendingPathComponent("rempush-snapshot.json")
        self.settingsURL = directoryURL.appendingPathComponent("rempush-settings.json")
    }

    public func loadSnapshot() throws -> RemPushSnapshot? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        return try JSONDecoder.rempush.decode(RemPushSnapshot.self, from: Data(contentsOf: snapshotURL))
    }

    public func saveSnapshot(_ snapshot: RemPushSnapshot) throws {
        try FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.rempush.encode(snapshot)
        try data.write(to: snapshotURL, options: [.atomic])
    }

    public func loadSettings() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return AppSettings() }
        return try JSONDecoder.rempush.decode(AppSettings.self, from: Data(contentsOf: settingsURL))
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.rempush.encode(settings)
        try data.write(to: settingsURL, options: [.atomic])
    }
}

public struct SyncConflict: Equatable, Identifiable, Sendable {
    public var id: Int { local.index }
    public let local: NotePage
    public let remote: NotePage
    public let diff: String
}

public enum SyncMergeResult: Equatable, Sendable {
    case merged(NotePage)
    case conflict(SyncConflict)
}

public enum ConflictChoice: Sendable { case local, remote }

public struct SyncEngine: Sendable {
    public init() {}

    public func merge(local: NotePage, remote: NotePage) -> SyncMergeResult {
        if remote.revision > local.revision { return .merged(remote) }
        if local.revision > remote.revision { return .merged(local) }
        if local == remote { return .merged(local) }
        return .conflict(SyncConflict(local: local, remote: remote, diff: diff(local: local, remote: remote)))
    }

    public func merge(localPages: [NotePage], remotePages: [NotePage]) -> ([NotePage], [SyncConflict]) {
        var merged = RemPushSnapshot(pages: localPages, lastUsedPageIndex: 0).pages
        var conflicts: [SyncConflict] = []
        let normalizedRemote = RemPushSnapshot(pages: remotePages, lastUsedPageIndex: 0).pages
        for index in 0..<RemPushConstants.pageCount {
            switch merge(local: merged[index], remote: normalizedRemote[index]) {
            case .merged(let page): merged[index] = page
            case .conflict(let conflict): conflicts.append(conflict)
            }
        }
        return (merged, conflicts)
    }

    public func resolve(_ conflict: SyncConflict, choosing choice: ConflictChoice) -> NotePage {
        var page = choice == .local ? conflict.local : conflict.remote
        page.revision = max(conflict.local.revision, conflict.remote.revision) + 1
        return page
    }

    private func diff(local: NotePage, remote: NotePage) -> String {
        var lines: [String] = []
        if local.title != remote.title {
            lines.append("- Titel: \(local.title)")
            lines.append("+ Titel: \(remote.title)")
        }
        if local.body != remote.body {
            lines.append("- Inhalt: \(local.body)")
            lines.append("+ Inhalt: \(remote.body)")
        }
        if local.updatedAt != remote.updatedAt {
            lines.append("Lokal geändert: \(local.updatedAt?.description ?? "unbekannt")")
            lines.append("iCloud geändert: \(remote.updatedAt?.description ?? "unbekannt")")
        }
        return lines.joined(separator: "\n")
    }
}

private extension JSONEncoder {
    static var rempush: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var rempush: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
