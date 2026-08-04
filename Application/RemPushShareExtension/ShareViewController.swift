import SwiftUI
import UIKit
import UniformTypeIdentifiers
import RemPushCore

private enum ShareExtensionStorage {
    static let appGroupIdentifier = "group.JNBARY.RemPush"

    static var persistence: JSONFilePersistence {
        JSONFilePersistence(directoryURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) ?? FileManager.default.temporaryDirectory)
    }
}

public final class ShareViewController: UIViewController {
    private let model = ShareImportViewModel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        installHostingController()
        model.load(context: extensionContext)
    }

    private func installHostingController() {
        let rootView = ShareImportView(
            model: model,
            onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: CancellationError()) },
            onComplete: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
}

@MainActor
private final class ShareImportViewModel: ObservableObject {
    @Published var sharedText = ""
    @Published var pages: [NotePage] = (0..<RemPushConstants.pageCount).map { NotePage(index: $0) }
    @Published var selectedIndex = 0
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var overwriteCandidate: Int?

    private let persistence = ShareExtensionStorage.persistence

    func load(context: NSExtensionContext?) {
        pages = ((try? persistence.loadSnapshot()) ?? RemPushSnapshot(pages: [], lastUsedPageIndex: 0)).pages
        selectedIndex = pages.first(where: \.isEmpty)?.index ?? 0
        Task { [weak self] in
            let text = await Self.extractText(from: context)
            await MainActor.run {
                guard let self else { return }
                self.sharedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isLoading = false
                if self.sharedText.isEmpty {
                    self.errorMessage = "No shared text was found."
                }
            }
        }
    }

    func prepareSave(onComplete: @escaping () -> Void) {
        guard !sharedText.isEmpty else {
            errorMessage = "No shared text was found."
            return
        }
        if !pages[selectedIndex].isEmpty || !pages[selectedIndex].body.isEmpty || !pages[selectedIndex].title.isEmpty {
            overwriteCandidate = selectedIndex
            return
        }
        save(into: selectedIndex, onComplete: onComplete)
    }

    func saveOverwrite(onComplete: @escaping () -> Void) {
        guard let overwriteCandidate else { return }
        self.overwriteCandidate = nil
        save(into: overwriteCandidate, onComplete: onComplete)
    }

    private func save(into pageIndex: Int, onComplete: @escaping () -> Void) {
        do {
            let store = NoteStore(snapshot: (try persistence.loadSnapshot()) ?? RemPushSnapshot(pages: pages, lastUsedPageIndex: selectedIndex))
            try store.save(pageIndex: pageIndex, title: Self.title(from: sharedText, pageIndex: pageIndex), body: sharedText)
            try persistence.saveSnapshot(store.snapshot)
            onComplete()
        } catch {
            errorMessage = "The shared text could not be saved."
        }
    }

    private static func title(from text: String, pageIndex: Int) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Shared Text Page \(pageIndex + 1)" : String(trimmed.prefix(80))
    }

    private static func extractText(from context: NSExtensionContext?) async -> String {
        let providers = context?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
               let text = await loadString(from: provider, typeIdentifier: UTType.text.identifier) {
                return text
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let urlText = await loadString(from: provider, typeIdentifier: UTType.url.identifier) {
                return urlText
            }
        }
        return ""
    }

    private static func loadString(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private struct ShareImportView: View {
    @ObservedObject var model: ShareImportViewModel
    let onCancel: () -> Void
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if model.isLoading {
                    ProgressView("Loading shared text…")
                } else {
                    WheelPickerView(pages: model.pages, selectedIndex: $model.selectedIndex)
                        .frame(width: 270, height: 310)
                    Text("Page \(model.selectedIndex + 1)")
                        .font(.headline)
                    preview
                    Button("Save to selected page") {
                        model.prepareSave(onComplete: onComplete)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sharedText.isEmpty)
                }
            }
            .padding(20)
            .navigationTitle("Save in RemPush")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .alert("Overwrite page?", isPresented: Binding(
                get: { model.overwriteCandidate != nil },
                set: { if !$0 { model.overwriteCandidate = nil } }
            )) {
                Button("Overwrite", role: .destructive) { model.saveOverwrite(onComplete: onComplete) }
                Button("Choose another page", role: .cancel) { model.overwriteCandidate = nil }
            } message: {
                Text("This page already contains text. Do you want to replace it with the shared content?")
            }
            .alert("Import failed", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var preview: some View {
        Text(model.sharedText.isEmpty ? "No text available" : model.sharedText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WheelPickerView: View {
    let pages: [NotePage]
    @Binding var selectedIndex: Int
    @State private var rotation: Angle = .zero

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(0..<RemPushConstants.pageCount, id: \.self) { index in
                    WheelSegment(index: index, count: RemPushConstants.pageCount)
                        .fill(pageColor(index))
                        .overlay(WheelSegment(index: index, count: RemPushConstants.pageCount).stroke(.white.opacity(0.75), lineWidth: 2))
                }
                ForEach(0..<RemPushConstants.pageCount, id: \.self) { index in
                    segmentLabel(index: index)
                }
                Circle().fill(.regularMaterial).frame(width: 76, height: 76)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .offset(y: -150)
            }
            .rotationEffect(rotation)
            .gesture(DragGesture(minimumDistance: 8).onChanged(updateRotation(_:)).onEnded(finishRotation(_:)))
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: rotation)
            Text("Rotate the wheel until the pointer shows the target page.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear { rotation = angle(for: selectedIndex) }
        .onChange(of: selectedIndex) { _, newValue in rotation = angle(for: newValue) }
    }

    private func segmentLabel(index: Int) -> some View {
        let filled = pages.indices.contains(index) && (!pages[index].isEmpty || !pages[index].body.isEmpty || !pages[index].title.isEmpty)
        return Text(filled ? "📝\n\(index + 1)" : "\(index + 1)")
            .font(.caption.bold())
            .multilineTextAlignment(.center)
            .rotationEffect(.degrees(Double(index) * 360 / Double(RemPushConstants.pageCount) + 20))
            .offset(y: -92)
            .rotationEffect(.degrees(-rotation.degrees))
    }

    private func updateRotation(_ value: DragGesture.Value) {
        rotation = Angle(radians: atan2(value.location.y - 135, value.location.x - 135)) + .degrees(90)
        selectedIndex = selectedIndex(for: rotation)
    }

    private func finishRotation(_ value: DragGesture.Value) {
        selectedIndex = selectedIndex(for: rotation)
        rotation = angle(for: selectedIndex)
    }

    private func selectedIndex(for rotation: Angle) -> Int {
        let segmentSize = 360 / Double(RemPushConstants.pageCount)
        let normalized = (360 - rotation.degrees).truncatingRemainder(dividingBy: 360)
        return max(0, min(RemPushConstants.pageCount - 1, Int((normalized / segmentSize).rounded()) % RemPushConstants.pageCount))
    }

    private func angle(for index: Int) -> Angle {
        .degrees(-Double(index) * 360 / Double(RemPushConstants.pageCount))
    }

    private func pageColor(_ index: Int) -> Color {
        [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink][index % RemPushConstants.pageCount].opacity(0.9)
    }
}

private struct WheelSegment: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let segment = 360 / Double(count)
        let start = Angle.degrees(-90 + Double(index) * segment)
        let end = Angle.degrees(-90 + Double(index + 1) * segment)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}
