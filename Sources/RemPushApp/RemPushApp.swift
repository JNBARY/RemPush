#if canImport(SwiftUI)
import SwiftUI
import UserNotifications
import RemPushCore

@main
public struct RemPushApp: App {
    @StateObject private var viewModel = AppViewModel()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var store: NoteStore
    @Published public var selectedPageIndex: Int
    @Published public var toastMessage: String?
    @Published public var settings: AppSettings
    @Published public var pendingConflicts: [SyncConflict] = []

    private let scheduler: LocalNotificationScheduler
    private let persistence: JSONFilePersistence
    private let syncEngine = SyncEngine()

    public init(
        scheduler: LocalNotificationScheduler = LocalNotificationScheduler(),
        persistence: JSONFilePersistence = JSONFilePersistence(directoryURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
    ) {
        self.scheduler = scheduler
        self.persistence = persistence
        self.settings = (try? persistence.loadSettings()) ?? AppSettings()
        let snapshot = try? persistence.loadSnapshot()
        self.store = NoteStore(snapshot: snapshot ?? RemPushSnapshot(pages: [], lastUsedPageIndex: 0), notificationScheduler: scheduler)
        let destination = store.launchDestination()
        self.selectedPageIndex = destination.pageIndex
        self.toastMessage = destination.message
        exportPreviousMonthIfNeeded()
    }

    public func save(index: Int, title: String, body: String) {
        objectWillChange.send()
        try? store.save(pageIndex: index, title: title, body: body)
        persistSnapshot()
    }

    public func delete(index: Int) {
        objectWillChange.send()
        store.delete(pageIndex: index)
        persistSnapshot()
        toastMessage = "Seite \(index + 1) gelöscht."
    }

    public func notify(index: Int) {
        Task {
            do {
                try await scheduler.requestAuthorizationIfNeeded()
                try store.scheduleTitleNotification(pageIndex: index)
                await MainActor.run { toastMessage = "Push für den Titel geplant." }
            } catch {
                await MainActor.run { toastMessage = "Push konnte nicht geplant werden." }
            }
        }
    }

    public func applyRemoteSnapshot(_ snapshot: RemPushSnapshot) {
        let result = syncEngine.merge(localPages: store.pages, remotePages: snapshot.pages)
        objectWillChange.send()
        for page in result.0 { try? store.replace(page: page) }
        pendingConflicts = result.1
        persistSnapshot()
    }

    public func resolve(_ conflict: SyncConflict, choosing choice: ConflictChoice) {
        let resolved = syncEngine.resolve(conflict, choosing: choice)
        objectWillChange.send()
        try? store.replace(page: resolved)
        pendingConflicts.removeAll { $0.id == conflict.id }
        persistSnapshot()
    }

    public func chooseArchiveDirectory(path: String) {
        settings.archiveDirectoryPath = path
        persistSettings()
        toastMessage = "Archivordner gespeichert."
    }

    public func exportPreviousMonthIfNeeded() {
        var mutableSettings = settings
        do {
            let service = MonthlyExportService(writer: FileArchiveWriter())
            if let result = try service.exportPreviousMonthIfNeeded(now: Date(), pages: store.pages, settings: &mutableSettings) {
                settings = mutableSettings
                persistSettings()
                toastMessage = "Monatsarchiv gespeichert: \(result.archive.fileName)"
            }
        } catch RemPushError.archiveDirectoryMissing {
            return
        } catch {
            toastMessage = "Monatsarchiv konnte nicht gespeichert werden."
        }
    }

    private func persistSnapshot() {
        try? persistence.saveSnapshot(store.snapshot)
    }

    private func persistSettings() {
        try? persistence.saveSettings(settings)
    }
}

public struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    public var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.04), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            TabView(selection: $viewModel.selectedPageIndex) {
                ForEach(viewModel.store.pages) { page in
                    NotePageView(page: page) { title, body in
                        viewModel.save(index: page.index, title: title, body: body)
                    } onDelete: {
                        viewModel.delete(index: page.index)
                    } onNotify: {
                        viewModel.notify(index: page.index)
                    }
                    .tag(page.index)
                    .background(pageColor(page.index).ignoresSafeArea())
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if let toast = viewModel.toastMessage {
                ToastView(message: toast)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.easeOut(duration: 0.25)) { viewModel.toastMessage = nil }
                    }
            }
        }
        .sheet(item: Binding(get: { viewModel.pendingConflicts.first }, set: { _ in })) { conflict in
            ConflictResolutionView(conflict: conflict) { choice in
                viewModel.resolve(conflict, choosing: choice)
            }
        }
    }

    private func pageColor(_ index: Int) -> Color {
        [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink][index].opacity(0.18)
    }
}

private struct NotePageView: View {
    let page: NotePage
    let onSave: (String, String) -> Void
    let onDelete: () -> Void
    let onNotify: () -> Void
    @State private var title: String
    @State private var body: String
    @FocusState private var focusedField: Field?

    private enum Field { case title, body }

    init(page: NotePage, onSave: @escaping (String, String) -> Void, onDelete: @escaping () -> Void, onNotify: @escaping () -> Void) {
        self.page = page
        self.onSave = onSave
        self.onDelete = onDelete
        self.onNotify = onNotify
        _title = State(initialValue: page.title)
        _body = State(initialValue: page.body)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader
                TextField("Titel", text: $title, axis: .vertical)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .body }
                TextEditor(text: $body)
                    .font(.system(.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .focused($focusedField, equals: .body)
                    .accessibilityLabel("Gedankeninhalt")
                footer
            }
            .padding(22)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: title) { _, newValue in onSave(newValue, body) }
            .onChange(of: body) { _, newValue in onSave(title, newValue) }
            .task {
                if page.isEmpty { focusedField = .body }
            }
        }
    }

    private var pageHeader: some View {
        HStack {
            Text("Seite \(page.index + 1)/\(RemPushConstants.pageCount)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
            Spacer()
            if page.isEmpty {
                Text("Leer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let createdAt = page.createdAt {
                Text("Erstellt: \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Diktieren über das Mikrofon der iOS-Tastatur, danach frei bearbeiten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { onNotify() } label: { Image(systemName: "bell.badge") }
                .disabled(page.isEmpty)
                .accessibilityLabel("Titel als Push anzeigen")
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                .disabled(page.isEmpty)
                .accessibilityLabel("Seite löschen")
        }
    }
}

private struct ConflictResolutionView: View {
    let conflict: SyncConflict
    let onResolve: (ConflictChoice) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Es gibt zwei Versionen dieser Seite. Keine wurde überschrieben.")
                    .font(.headline)
                ScrollView {
                    Text(conflict.diff)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                HStack {
                    Button("Lokale Version behalten") { onResolve(.local) }
                        .buttonStyle(.bordered)
                    Button("iCloud-Version übernehmen") { onResolve(.remote) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Sync-Konflikt")
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

    var body: some View {
        Form {
            Section("iCloud Sync") {
                Text("Konflikte werden als Diff angezeigt und erst nach Auswahl einer Version aufgelöst.")
                Text("Offene Seiten werden lokal persistiert und sind für den iCloud-Adapter als Snapshot verfügbar.")
                    .foregroundStyle(.secondary)
            }
            Section("Monatsarchiv") {
                Text(viewModel.settings.archiveDirectoryPath ?? "Noch nicht festgelegt")
                    .foregroundStyle(.secondary)
                TextField("Archivpfad", text: $path)
                Button("Speicherort übernehmen") {
                    viewModel.chooseArchiveDirectory(path: path)
                    viewModel.exportPreviousMonthIfNeeded()
                }
                Button("Monatsarchiv jetzt prüfen") {
                    viewModel.exportPreviousMonthIfNeeded()
                }
            }
        }
        .onAppear { path = viewModel.settings.archiveDirectoryPath ?? "" }
    }
}

public final class LocalNotificationScheduler: NotificationScheduling {
    private var authorized = false
    public init() {}

    public func requestAuthorizationIfNeeded() async throws {
        guard !authorized else { return }
        authorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    public func schedule(_ request: NotificationRequest) throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let notification = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(notification)
    }
}
#endif
