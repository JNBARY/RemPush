//
//  ContentView.swift
//  RemPush
//
//  Created by Jonas Ranft on 2026-06-14.
//

import SwiftUI
import Combine
import UserNotifications
import UIKit
import UniformTypeIdentifiers
import RemPushCore

private struct ConflictResolutionView: View {
    let conflict: SyncConflict
    let onResolve: (ConflictChoice) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Differing Versions of this Page exist. Decide what to keep:")
                    .font(.headline)
                ScrollView {
                    Text(conflict.diff)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                HStack {
                    Button("Upload Local to iCloud") { onResolve(.local) }
                        .buttonStyle(.bordered)
                    Button("Downlod from iCloud and delete Local") { onResolve(.remote) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Sync-Konflikt")
        }
    }
}

public struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showingSettings = false

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                TabView(selection: $viewModel.selectedPageIndex) {
                    ForEach(viewModel.store.pages, id: \.id) { page in
                        NotePageContainer(
                            page: page,
                            selectedIndex: $viewModel.selectedPageIndex,
                            onSave: { title, body in
                                viewModel.save(index: page.index, title: title, body: body)
                            },
                            onDelete: {
                                viewModel.delete(index: page.index)
                            },
                            onNotify: {
                                viewModel.notify(index: page.index)
                            }
                        )
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                

                if let toast = viewModel.toastMessage {
                    ToastView(message: toast)
                        .id(toast)
                        .padding(.top, 18)
                        .transition(
                            .move(edge: .top)
                            .combined(with: .opacity)
                        )
                        .task(id: toast) {
                            await viewModel.dismissToast(after: .seconds(2), matching: toast)
                        }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(viewModel: viewModel)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("complete") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        .sheet(
            item: Binding(
                get: { viewModel.pendingConflicts.first },
                set: { _ in }
            )
        ) { conflict in
            ConflictResolutionView(
                conflict: conflict
            ) { choice in
                viewModel.resolve(
                    conflict,
                    choosing: choice
                )
            }
        }
    }

    fileprivate static func pageColorStatic(_ index: Int) -> Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink
        ]
        return colors[index % colors.count].opacity(0.4)
    }

    private func pageBackgroundColor(for index: Int) -> Color {
        pageColor(index)
    }

    private func pageColor(_ index: Int) -> Color {
        let colors: [Color] = [
            .red,
            .orange,
            .yellow,
            .green,
            .mint,
            .cyan,
            .blue,
            .purple,
            .pink
        ]

        return colors[index % colors.count]
            .opacity(0.4)
    }
}

private struct NotePageContainer: View {
    let page: NotePage
    @Binding var selectedIndex: Int
    let onSave: (String, String) -> Void
    let onDelete: () -> Void
    let onNotify: () -> Void

    var body: some View {
        NotePageView(
            page: page,
            onSave: onSave,
            onDelete: onDelete,
            onNotify: onNotify
        )
        .tag(page.index)
        .background(
            ContentView.pageColorStatic(page.index)
                .ignoresSafeArea()
        )
    }
}

private struct NotePageView: View {
    let page: NotePage
    let onSave: (String, String) -> Void
    let onDelete: () -> Void
    let onNotify: () -> Void
    @State private var title: String
    @State private var noteBody: String
    @State private var isApplyingPageUpdate = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, body }

    init(page: NotePage, onSave: @escaping (String, String) -> Void, onDelete: @escaping () -> Void, onNotify: @escaping () -> Void) {
        self.page = page
        self.onSave = onSave
        self.onDelete = onDelete
        self.onNotify = onNotify
        _title = State(initialValue: page.title)
        _noteBody = State(initialValue: page.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
                pageHeader
                TextField("Titel", text: $title, axis: .vertical)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .body }
                TextEditor(text: $noteBody)
                    .font(.system(.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(pageAccent.opacity(0.35), lineWidth: 1)
                    )
                    .focused($focusedField, equals: .body)
                    .accessibilityLabel("Your thoughts")
            footer
        }
        .padding(22)
        .background(pageAccent.opacity(0.16).ignoresSafeArea())
        .toolbar { toolbarContent }
        .onChange(of: title) { _, newValue in
            guard !isApplyingPageUpdate else { return }
            onSave(newValue, noteBody)
        }
        .onChange(of: noteBody) { _, newValue in
            guard !isApplyingPageUpdate else { return }
            onSave(title, newValue)
        }
        .task {
            if page.isEmpty { focusedField = .body }
        }
        .onChange(of: page) { _, newPage in
            synchronizeDraft(with: newPage)
        }
        .tint(pageAccent)
    }

    private func synchronizeDraft(with newPage: NotePage) {
        guard title != newPage.title || noteBody != newPage.body else { return }
        isApplyingPageUpdate = true
        title = newPage.title
        noteBody = newPage.body
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1))
            isApplyingPageUpdate = false
        }
    }

    private var pageAccent: Color {
        pagePalette[page.index % pagePalette.count]
    }

    private var pagePalette: [Color] {
        [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink]
    }

    private var pageHeader: some View {
        HStack {
            Text("Page \(page.index + 1) of \(RemPushConstants.pageCount)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(pageAccent.opacity(0.24), in: Capsule())
            Spacer()
            if page.isEmpty {
                Text("is empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let createdAt = page.createdAt {
                Text("Created: \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { onNotify() } label: { Image(systemName: "bell.badge") }
                
                .accessibilityLabel("Show Title as PushNotification")
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                
                .accessibilityLabel("Delete Note")
        }
    }
}


private struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 12, y: 6)
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var path: String = ""
    @State private var showingArchiveDirectoryPicker = false

    var body: some View {
        Form {
            Section("iCloud Sync") {
                Text("Konflikte werden als Diff angezeigt und erst nach Auswahl einer Version aufgelöst.")
                Text("Offene Seiten werden automatisch über NSUbiquitousKeyValueStore übertragen, sobald iCloud für die App verfügbar ist.")
                    .foregroundStyle(.secondary)
            }
            Section("Monatsarchiv") {
                Text(viewModel.settings.archiveDirectoryPath ?? "Noch nicht festgelegt")
                    .foregroundStyle(.secondary)
                Button("Archivordner auswählen") {
                    showingArchiveDirectoryPicker = true
                }
                TextField("Archivpfad manuell", text: $path)
                Button("Manuellen Speicherort übernehmen") {
                    viewModel.chooseArchiveDirectory(path: path)
                    viewModel.exportPreviousMonthIfNeeded()
                }
                Button("Monatsarchiv jetzt prüfen") {
                    viewModel.exportPreviousMonthIfNeeded()
                }
            }
        }
        .onAppear { path = viewModel.settings.archiveDirectoryPath ?? "" }
        .sheet(isPresented: $showingArchiveDirectoryPicker) {
            ArchiveDirectoryPicker { url in
                viewModel.chooseArchiveDirectory(url: url)
                viewModel.exportPreviousMonthIfNeeded()
            }
        }
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    public let objectWillChange = ObservableObjectPublisher()
    
    @Published public var store: NoteStore
    @Published public var selectedPageIndex: Int
    @Published public var toastMessage: String?
    @Published public var settings: AppSettings
    @Published public var pendingConflicts: [SyncConflict] = []

    private let scheduler: LocalNotificationScheduler
    private let persistence: JSONFilePersistence
    private let syncEngine = SyncEngine()
    private let cloudSync: ICloudSnapshotSync
    private var isApplyingRemoteSnapshot = false
    private var pendingCloudPublishTask: Task<Void, Never>?

    public init(
        scheduler: LocalNotificationScheduler,
        persistence: JSONFilePersistence = JSONFilePersistence(directoryURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
    ) {
        self.scheduler = scheduler
        self.persistence = persistence
        self.cloudSync = ICloudSnapshotSync()

        // Compute everything with local values first to avoid using `self` before full initialization
        let loadedSettings = (try? persistence.loadSettings()) ?? AppSettings()
        let loadedSnapshot = (try? persistence.loadSnapshot()) ?? RemPushSnapshot(pages: [], lastUsedPageIndex: 0)
        let initialStore = NoteStore(snapshot: loadedSnapshot, notificationScheduler: scheduler)
        let destination = initialStore.launchDestination()

        // Now assign stored properties
        self.settings = loadedSettings
        self.store = initialStore
        self.selectedPageIndex = destination.pageIndex
        self.toastMessage = destination.message

        // Defer iCloud and archive work until after the first local render so startup stays responsive.
        Task { @MainActor in
            await Task.yield()
            startBackgroundServices(initialSnapshot: initialStore.snapshot)
        }
    }

    /// Convenience initializer to safely create defaults on the main actor
    public convenience init(
        persistence: JSONFilePersistence = JSONFilePersistence(directoryURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
    ) {
        self.init(scheduler: LocalNotificationScheduler(), persistence: persistence)
    }

    public func save(index: Int, title: String, body: String) {
        objectWillChange.send()
        try? store.save(pageIndex: index, title: title, body: body)
        persistSnapshot(debounced: true)
    }

    public func delete(index: Int) {
        objectWillChange.send()
        store.delete(pageIndex: index)
        selectedPageIndex = index
        persistSnapshot()
        showToast("Deleted Page \(index + 1)")
    }

    public func notify(index: Int) {
        Task { @MainActor in
            do {
                try await scheduler.requestAuthorizationIfNeeded()
                let request = try store.notificationRequest(pageIndex: index)
                try await scheduler.schedule(request)
                showToast("Sceduled Notification")
            } catch {
                showToast("Failed to schedule Notification")
            }
        }
    }

    public func applyRemoteSnapshot(_ snapshot: RemPushSnapshot) {
        flushPendingSnapshotPersistence()
        isApplyingRemoteSnapshot = true
        defer { isApplyingRemoteSnapshot = false }
        let result = syncEngine.merge(localPages: store.pages, remotePages: snapshot.pages)
        objectWillChange.send()
        for page in result.0 { try? store.replace(page: page) }
        pendingConflicts = result.1
        persistSnapshot()
        if !result.1.isEmpty {
            showToast("Detedted iCloud-Conflict")
        }
    }

    public func resolve(_ conflict: SyncConflict, choosing choice: ConflictChoice) {
        let resolved = syncEngine.resolve(conflict, choosing: choice)
        objectWillChange.send()
        try? store.replace(page: resolved)
        pendingConflicts.removeAll { $0.id == conflict.id }
        persistSnapshot()
        cloudSync.publish(snapshot: store.snapshot)
    }

    public func chooseArchiveDirectory(path: String) {
        settings.archiveDirectoryPath = path
        settings.archiveDirectoryBookmark = nil
        persistSettings()
        showToast("Saved Archive Directory")
    }

    public func chooseArchiveDirectory(url: URL) {
        do {
            settings.archiveDirectoryPath = url.path
            settings.archiveDirectoryBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            persistSettings()
            showToast("Saved Archive Directory")
        } catch {
            showToast("Failded to Save Archive Directory")
        }
    }

    public func exportPreviousMonthIfNeeded() {
        var mutableSettings = settings
        do {
            let service = MonthlyExportService(writer: FileArchiveWriter())
            let settingsSnapshot = mutableSettings
            let result = try withArchiveDirectoryAccess(settings: &mutableSettings) {
                // Work on a separate local copy so we don't read from mutableSettings while it's passed as inout.
                var exportSettings = settingsSnapshot
                let exportResult = try service.exportPreviousMonthIfNeeded(
                    now: Date(),
                    pages: store.pages,
                    settings: &exportSettings
                )
                // Return both the possibly updated settings and the export result.
                return (exportSettings, exportResult)
            }
            // Unpack results from the operation and apply them after the inout access ends.
            let (updatedSettings, exportResult) = result
            mutableSettings = updatedSettings
            if let exportResult {
                settings = mutableSettings
                persistSettings()
                showToast("Saved montly Archive: \(exportResult.archive.fileName)")
            }
        } catch RemPushError.archiveDirectoryMissing {
            return
        } catch {
            showToast("Failded to Save montly Archive.")
        }
    }
    


    public func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
        }
    }

    public func dismissToast(after duration: Duration, matching message: String) async {
        try? await Task.sleep(for: duration)
        guard toastMessage == message else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            toastMessage = nil
        }
    }

    public func flushPendingSnapshotPersistence() {
        pendingCloudPublishTask?.cancel()
        pendingCloudPublishTask = nil
        publishCurrentSnapshotIfNeeded()
    }

    private func startBackgroundServices(initialSnapshot: RemPushSnapshot) {
        cloudSync.onRemoteSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                self?.applyRemoteSnapshot(snapshot)
            }
        }
        cloudSync.start()
        if let cloudSnapshot = cloudSync.loadSnapshot() {
            applyRemoteSnapshot(cloudSnapshot)
        } else {
            cloudSync.publish(snapshot: initialSnapshot)
        }
        exportPreviousMonthIfNeeded()
    }

    private func withArchiveDirectoryAccess<T>(settings: inout AppSettings, operation: () throws -> T) throws -> T {
        guard let bookmark = settings.archiveDirectoryBookmark else {
            return try operation()
        }
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        settings.archiveDirectoryPath = url.path
        if isStale {
            settings.archiveDirectoryBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }

    private func persistSnapshot(debounced: Bool = false) {
        let snapshot = store.snapshot
        try? persistence.saveSnapshot(snapshot)
        pendingCloudPublishTask?.cancel()
        guard debounced else {
            pendingCloudPublishTask = nil
            publish(snapshot: snapshot)
            return
        }
        pendingCloudPublishTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            publishCurrentSnapshotIfNeeded()
            pendingCloudPublishTask = nil
        }
    }

    private func publishCurrentSnapshotIfNeeded() {
        publish(snapshot: store.snapshot)
    }

    private func publish(snapshot: RemPushSnapshot) {
        if !isApplyingRemoteSnapshot {
            cloudSync.publish(snapshot: snapshot)
        }
    }

    private func persistSettings() {
        try? persistence.saveSettings(settings)
    }
}


@MainActor
public final class LocalNotificationScheduler: @MainActor NotificationScheduling {
    private var authorized = false
    public init() {}

    public func requestAuthorizationIfNeeded() async throws {
        guard !authorized else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral {
            authorized = true
            return
        }
        authorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        if !authorized { throw RemPushError.notificationAuthorizationDenied }
    }

    public func schedule(_ request: NotificationRequest) throws {
        _ = Task { @MainActor in
            do {
                try await schedule(request)
            } catch {
                // Swallow the error to avoid propagating from the unstructured task.
                // Scheduling errors are already surfaced to callers of the async API.
            }
        }
    }

    public func schedule(_ request: NotificationRequest) async throws {
        guard authorized else { throw RemPushError.notificationAuthorizationDenied }
        let content = UNMutableNotificationContent()
        content.title = request.title.isEmpty ? "RemPush" : request.title
        content.body = request.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let notification = UNNotificationRequest(identifier: "rempush-page-title-\(UUID().uuidString)", content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(notification)
    }
}

private struct ArchiveDirectoryPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

@MainActor
private final class ICloudSnapshotSync {
    var onRemoteSnapshot: ((RemPushSnapshot) -> Void)?

    private let store = NSUbiquitousKeyValueStore.default
    private let snapshotKey = "rempush.snapshot.v1"
    private let originKey = "rempush.snapshot.origin.v1"
    private let deviceID = UUID().uuidString
    private var observer: NSObjectProtocol?

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            let receiver = strongSelf
            Task { @MainActor in
                receiver.receiveRemoteSnapshotIfNeeded()
            }
        }
        store.synchronize()
    }

    func loadSnapshot() -> RemPushSnapshot? {
        decodeSnapshot(from: store.string(forKey: snapshotKey))
    }

    func publish(snapshot: RemPushSnapshot) {
        guard let data = try? JSONEncoder.rempushApp.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        store.set(json, forKey: snapshotKey)
        store.set(deviceID, forKey: originKey)
        store.synchronize()
    }

    private func receiveRemoteSnapshotIfNeeded() {
        guard store.string(forKey: originKey) != deviceID,
              let snapshot = loadSnapshot() else { return }
        onRemoteSnapshot?(snapshot)
    }

    private func decodeSnapshot(from json: String?) -> RemPushSnapshot? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder.rempushApp.decode(RemPushSnapshot.self, from: data)
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private extension JSONEncoder {
    static var rempushApp: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var rempushApp: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

