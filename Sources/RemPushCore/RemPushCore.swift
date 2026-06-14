import Foundation

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
}

public final class NoteStore {
    public var pages: [NotePage]
    public private(set) var lastUsedPageIndex: Int

    private let clock: () -> Date
    private weak var notificationScheduler: NotificationScheduling?

    public init(pages: [NotePage]? = nil, lastUsedPageIndex: Int = 0, clock: @escaping () -> Date = Date.init, notificationScheduler: NotificationScheduling? = nil) {
        self.pages = pages ?? (0..<9).map { NotePage(index: $0) }
        self.lastUsedPageIndex = lastUsedPageIndex
        self.clock = clock
        self.notificationScheduler = notificationScheduler
    }

    public func launchDestination() -> LaunchDestination {
        if let firstEmpty = pages.first(where: \ .isEmpty) {
            return LaunchDestination(pageIndex: firstEmpty.index, message: nil)
        }
        return LaunchDestination(pageIndex: lastUsedPageIndex, message: "Alle 9 Seiten sind bereits gefüllt.")
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

    public func delete(pageIndex: Int) {
        guard pages.indices.contains(pageIndex) else { return }
        pages[pageIndex] = NotePage(index: pageIndex)
        lastUsedPageIndex = pageIndex
    }

    public func scheduleTitleNotification(pageIndex: Int) throws {
        guard pages.indices.contains(pageIndex) else { throw RemPushError.invalidPageIndex }
        let page = pages[pageIndex]
        guard !page.isEmpty else { throw RemPushError.emptyPageCannotNotify }
        try notificationScheduler?.schedule(NotificationRequest(title: page.title, body: "RemPush Gedankenstütze"))
    }
}

public struct MonthlyExporter: Sendable {
    public init() {}
    public func renderMonthlyArchive(pages: [NotePage], month: Int, year: Int, calendar: Calendar = .init(identifier: .gregorian)) -> String {
        let formatter = ISO8601DateFormatter()
        let selected = pages.compactMap { page -> NotePage? in
            guard let createdAt = page.createdAt else { return nil }
            let comps = calendar.dateComponents([.month, .year], from: createdAt)
            return comps.month == month && comps.year == year ? page : nil
        }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        return selected.map { page in
            let date = page.createdAt.map { formatter.string(from: $0) } ?? "ohne Datum"
            return "Erstellt: \(date)\nTitel: \(page.title)\nInhalt:\n\(page.body)"
        }.joined(separator: "\n\n---\n\n")
    }
}

public struct SyncConflict: Equatable, Sendable {
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

    public func resolve(_ conflict: SyncConflict, choosing choice: ConflictChoice) -> NotePage {
        choice == .local ? conflict.local : conflict.remote
    }

    private func diff(local: NotePage, remote: NotePage) -> String {
        var lines: [String] = []
        if local.title != remote.title {
            lines.append("- title: \(local.title)")
            lines.append("+ title: \(remote.title)")
        }
        if local.body != remote.body {
            lines.append("- body: \(local.body)")
            lines.append("+ body: \(remote.body)")
        }
        return lines.joined(separator: "\n")
    }
}
