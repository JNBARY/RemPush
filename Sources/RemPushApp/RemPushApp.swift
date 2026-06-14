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
    @Published public var exportDirectoryDescription = "Noch nicht festgelegt"
    private let scheduler: LocalNotificationScheduler

    public init(scheduler: LocalNotificationScheduler = LocalNotificationScheduler()) {
        self.scheduler = scheduler
        self.store = NoteStore(notificationScheduler: scheduler)
        let destination = store.launchDestination()
        self.selectedPageIndex = destination.pageIndex
        self.toastMessage = destination.message
    }

    public func save(index: Int, title: String, body: String) {
        objectWillChange.send()
        try? store.save(pageIndex: index, title: title, body: body)
    }

    public func delete(index: Int) {
        objectWillChange.send()
        store.delete(pageIndex: index)
    }

    public func notify(index: Int) {
        Task {
            try? await scheduler.requestAuthorizationIfNeeded()
            try? store.scheduleTitleNotification(pageIndex: index)
        }
    }
}

public struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    public var body: some View {
        ZStack(alignment: .top) {
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
                    .background(pageColor(page.index))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 18)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { viewModel.toastMessage = nil }
                    }
            }
        }
    }

    private func pageColor(_ index: Int) -> Color {
        [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink][index].opacity(0.22)
    }
}

private struct NotePageView: View {
    let page: NotePage
    let onSave: (String, String) -> Void
    let onDelete: () -> Void
    let onNotify: () -> Void
    @State private var title: String
    @State private var body: String

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
            VStack(spacing: 16) {
                TextField("Titel diktieren oder tippen", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2.bold())
                TextEditor(text: $body)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.3)))
                    .accessibilityLabel("Gedankeninhalt")
                if let createdAt = page.createdAt {
                    Text("Erstellt: \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Seite \(page.index + 1)")
            .toolbar {
                Button("Push") { onNotify() }.disabled(page.isEmpty)
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
            }
            .onChange(of: title) { _, newValue in onSave(newValue, body) }
            .onChange(of: body) { _, newValue in onSave(title, newValue) }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Form {
            Section("iCloud Sync") {
                Text("Konflikte werden als Diff angezeigt und erst nach Auswahl einer Version aufgelöst.")
            }
            Section("Monatsarchiv") {
                Text(viewModel.exportDirectoryDescription)
                Button("Speicherort auswählen") {
                    viewModel.exportDirectoryDescription = "Dokumentenauswahl für iOS-Adapter vorbereitet"
                }
            }
        }
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
