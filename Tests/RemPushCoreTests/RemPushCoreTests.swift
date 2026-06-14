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

    func testWhenFullLaunchesLastUsedWithToast() throws {
        let store = NoteStore(clock: { Date(timeIntervalSince1970: 1) })
        for index in 0..<9 { try store.save(pageIndex: index, title: "T\(index)", body: "B") }
        try store.save(pageIndex: 4, title: "Last", body: "B")
        let destination = store.launchDestination()
        XCTAssertEqual(destination.pageIndex, 4)
        XCTAssertEqual(destination.message, "Alle 9 Seiten sind bereits gefüllt.")
    }

    func testPushRequestUsesPageTitle() throws {
        let scheduler = RecordingNotificationScheduler()
        let store = NoteStore(clock: { Date(timeIntervalSince1970: 1) }, notificationScheduler: scheduler)
        try store.save(pageIndex: 0, title: "Push mich", body: "B")
        try store.scheduleTitleNotification(pageIndex: 0)
        XCTAssertEqual(scheduler.requests, [.init(title: "Push mich", body: "RemPush Gedankenstütze")])
    }

    func testMonthlyExportIsChronological() throws {
        let store = NoteStore(clock: { Date(timeIntervalSince1970: 1) })
        try store.save(pageIndex: 1, title: "Später", body: "B")
        store.pages[1].createdAt = ISO8601DateFormatter().date(from: "2026-06-20T10:00:00Z")!
        try store.save(pageIndex: 0, title: "Früher", body: "A")
        store.pages[0].createdAt = ISO8601DateFormatter().date(from: "2026-06-01T10:00:00Z")!
        let export = MonthlyExporter().renderMonthlyArchive(pages: store.pages, month: 6, year: 2026)
        XCTAssertLessThan(export.range(of: "Früher")!.lowerBound, export.range(of: "Später")!.lowerBound)
        XCTAssertTrue(export.contains("2026-06-01T10:00:00Z"))
    }

    func testSyncConflictKeepsBothVersionsAndDiffUntilResolved() throws {
        let local = NotePage(index: 0, title: "Lokal", body: "A", createdAt: .init(timeIntervalSince1970: 1), updatedAt: .init(timeIntervalSince1970: 3), revision: 2)
        let remote = NotePage(index: 0, title: "Remote", body: "B", createdAt: .init(timeIntervalSince1970: 1), updatedAt: .init(timeIntervalSince1970: 4), revision: 2)
        let result = SyncEngine().merge(local: local, remote: remote)
        guard case .conflict(let conflict) = result else { return XCTFail("Expected conflict") }
        XCTAssertEqual(conflict.local.title, "Lokal")
        XCTAssertEqual(conflict.remote.title, "Remote")
        XCTAssertTrue(conflict.diff.contains("- title: Lokal"))
        XCTAssertEqual(SyncEngine().resolve(conflict, choosing: .remote).title, "Remote")
    }
}
