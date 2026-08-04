import XCTest
@testable import RemPushCore

final class RemPushCoreTests: XCTestCase {
    func testStoreStartsWithNineEmptyPagesAndOpensFirstEmpty() throws {
        let store = NoteStore(clock: { Date(timeIntervalSince1970: 100) })
        XCTAssertEqual(store.pages.count, 9)
        XCTAssertEqual(store.launchDestination().pageIndex, 0)
        XCTAssertNil(store.launchDestination().message)
    }

    func testCreatedAtIsSetOnceAndSurvivesEdits() throws {
        var now = Date(timeIntervalSince1970: 100)
        let store = NoteStore(clock: { now })
        try store.save(pageIndex: 0, title: "Erster Gedanke", body: "Body")
        now = Date(timeIntervalSince1970: 900)
        try store.save(pageIndex: 0, title: "Geändert", body: "Neuer Body")
        XCTAssertEqual(store.pages[0].createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(store.pages[0].updatedAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(store.pages[0].title, "Geändert")
    }

    func testNoAutomaticRemovalAndExplicitDeleteOnly() throws {
        let store = NoteStore(clock: { Date(timeIntervalSince1970: 1) })
        try store.save(pageIndex: 0, title: "T", body: "B")
        try store.save(pageIndex: 0, title: "", body: "")
        XCTAssertFalse(store.pages[0].isEmpty)
        store.delete(pageIndex: 0)
        XCTAssertTrue(store.pages[0].isEmpty)
    }

    func testSnapshotRestoresNinePagesAndLastUsedPage() throws {
        let snapshot = RemPushSnapshot(pages: [NotePage(index: 4, title: "T", body: "B", createdAt: .init(timeIntervalSince1970: 1), updatedAt: nil, revision: 1)], lastUsedPageIndex: 4)
        let store = NoteStore(snapshot: snapshot)
        XCTAssertEqual(store.pages.count, 9)
        XCTAssertEqual(store.pages[4].title, "T")
        XCTAssertEqual(store.launchDestination().pageIndex, 0)
    }

    func testWhenFullLaunchesLastUsedWithToast() throws {
        let store = NoteStore(clock: { Date(timeIntervalSince1970: 1) })
        for index in 0..<9 { try store.save(pageIndex: index, title: "T\(index)", body: "B") }
        try store.save(pageIndex: 4, title: "Last", body: "B")
        let destination = store.launchDestination()
        XCTAssertEqual(destination.pageIndex, 4)
        XCTAssertEqual(destination.message, RemPushConstants.fullPagesMessage)
    }

    func testPushRequestUsesPageTitle() throws {
        let scheduler = RecordingNotificationScheduler()
        let store = NoteStore(clock: { Date(timeIntervalSince1970: 1) }, notificationScheduler: scheduler)
        try store.save(pageIndex: 0, title: "Push mich", body: "B")
        try store.scheduleTitleNotification(pageIndex: 0)
        XCTAssertEqual(scheduler.requests, [.init(title: "Push mich", body: pages[pageIndex].body)])
    }

    func testPushRequestFallsBackWhenTitleIsEmptyAndRequiresScheduler() throws {
        let storeWithoutScheduler = NoteStore(clock: { Date(timeIntervalSince1970: 1) })
        try storeWithoutScheduler.save(pageIndex: 1, title: "", body: "Nur Body")
        XCTAssertEqual(try storeWithoutScheduler.notificationRequest(pageIndex: 1), .init(title: "RemPush Seite 2", body: pages[pageIndex].body))
        XCTAssertThrowsError(try storeWithoutScheduler.scheduleTitleNotification(pageIndex: 1)) { error in
            XCTAssertEqual(error as? RemPushError, .notificationSchedulerMissing)
        }
    }

    func testMonthlyExportIsChronologicalAndNamed() throws {
        let store = NoteStore(clock: { Date(timeIntervalSince1970: 1) })
        try store.save(pageIndex: 1, title: "Später", body: "B")
        try store.replace(page: NotePage(index: 1, title: "Später", body: "B", createdAt: ISO8601DateFormatter().date(from: "2026-06-20T10:00:00Z")!, updatedAt: nil, revision: 1))
        try store.save(pageIndex: 0, title: "Früher", body: "A")
        try store.replace(page: NotePage(index: 0, title: "Früher", body: "A", createdAt: ISO8601DateFormatter().date(from: "2026-06-01T10:00:00Z")!, updatedAt: nil, revision: 1))
        let archive = MonthlyExporter().renderMonthlyArchive(pages: store.pages, month: 6, year: 2026)
        XCTAssertEqual(archive.fileName, "RemPush-2026-06.txt")
        XCTAssertLessThan(archive.content.range(of: "Früher")!.lowerBound, archive.content.range(of: "Später")!.lowerBound)
        XCTAssertTrue(archive.content.contains("2026-06-01T10:00:00Z"))
    }

    func testMonthlyExportServiceWritesPreviousMonthOnceToConfiguredDirectory() throws {
        let writer = RecordingArchiveWriter()
        var settings = AppSettings(archiveDirectoryPath: "/tmp/rempush-archive")
        let service = MonthlyExportService(writer: writer)
        let page = NotePage(index: 0, title: "Mai", body: "Text", createdAt: ISO8601DateFormatter().date(from: "2026-05-31T10:00:00Z")!, updatedAt: nil, revision: 1)
        let now = ISO8601DateFormatter().date(from: "2026-06-01T00:05:00Z")!

        let first = try service.exportPreviousMonthIfNeeded(now: now, pages: [page], settings: &settings)
        let second = try service.exportPreviousMonthIfNeeded(now: now, pages: [page], settings: &settings)

        XCTAssertEqual(first?.archive.fileName, "RemPush-2026-05.txt")
        XCTAssertEqual(first?.filePath, "/tmp/rempush-archive/RemPush-2026-05.txt")
        XCTAssertNil(second)
        XCTAssertEqual(writer.writes.count, 1)
    }

    func testJSONPersistenceRoundTripsSnapshotAndSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = JSONFilePersistence(directoryURL: directory)
        let snapshot = RemPushSnapshot(pages: [NotePage(index: 2, title: "Persistiert", body: "B", createdAt: .init(timeIntervalSince1970: 2), updatedAt: nil, revision: 1)], lastUsedPageIndex: 2)
        let settings = AppSettings(archiveDirectoryPath: "/archive", archiveDirectoryBookmark: Data([1, 2, 3]), lastExportedMonthIdentifier: "2026-06")

        try persistence.saveSnapshot(snapshot)
        try persistence.saveSettings(settings)

        XCTAssertEqual(try persistence.loadSnapshot(), snapshot)
        XCTAssertEqual(try persistence.loadSettings(), settings)
    }

    func testSyncConflictKeepsBothVersionsAndDiffUntilResolved() throws {
        let local = NotePage(index: 0, title: "Lokal", body: "A", createdAt: .init(timeIntervalSince1970: 1), updatedAt: .init(timeIntervalSince1970: 3), revision: 2)
        let remote = NotePage(index: 0, title: "Remote", body: "B", createdAt: .init(timeIntervalSince1970: 1), updatedAt: .init(timeIntervalSince1970: 4), revision: 2)
        let result = SyncEngine().merge(local: local, remote: remote)
        guard case .conflict(let conflict) = result else { return XCTFail("Expected conflict") }
        XCTAssertEqual(conflict.local.title, "Lokal")
        XCTAssertEqual(conflict.remote.title, "Remote")
        XCTAssertTrue(conflict.diff.contains("- Titel: Lokal"))
        let resolved = SyncEngine().resolve(conflict, choosing: .remote)
        XCTAssertEqual(resolved.title, "Remote")
        XCTAssertEqual(resolved.revision, 3)
    }

    func testSyncArrayMergeReturnsMergedPagesAndConflictsWithoutDataLoss() throws {
        let local = NotePage(index: 0, title: "Lokal", body: "A", createdAt: .init(timeIntervalSince1970: 1), updatedAt: nil, revision: 2)
        let remoteNewer = NotePage(index: 1, title: "Remote neuer", body: "B", createdAt: .init(timeIntervalSince1970: 2), updatedAt: nil, revision: 3)
        let remoteConflict = NotePage(index: 0, title: "Remote", body: "A", createdAt: .init(timeIntervalSince1970: 1), updatedAt: nil, revision: 2)

        let result = SyncEngine().merge(localPages: [local], remotePages: [remoteConflict, remoteNewer])

        XCTAssertEqual(result.0[1].title, "Remote neuer")
        XCTAssertEqual(result.1.count, 1)
        XCTAssertEqual(result.1[0].local.title, "Lokal")
        XCTAssertEqual(result.1[0].remote.title, "Remote")
    }
}

private final class RecordingArchiveWriter: ArchiveWriting {
    private(set) var writes: [(archive: MonthlyArchive, directoryPath: String)] = []

    func write(_ archive: MonthlyArchive, toDirectoryPath directoryPath: String) throws -> ArchiveWriteResult {
        writes.append((archive, directoryPath))
        return ArchiveWriteResult(filePath: directoryPath + "/" + archive.fileName, archive: archive)
    }
}
