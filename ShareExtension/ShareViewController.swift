import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var viewModel: ShareExtensionViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = ShareExtensionViewModel(extensionContext: extensionContext)
        viewModel = model

        let host = UIHostingController(rootView: ShareExtensionRootView(viewModel: model))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = UIColor(red: 0.07, green: 0.06, blue: 0.10, alpha: 1)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        Task { await model.load() }
    }
}

@MainActor
final class ShareExtensionViewModel: ObservableObject {
    @Published var caption = ""
    @Published var query = ""
    @Published var recipientIndex: ShareRecipientIndex?
    @Published var attachments: [ShareAttachmentFile] = []
    @Published var selectedDestinations: [ShareDestination] = []
    @Published var expandedServerIds: Set<String> = []
    @Published var isLoading = true
    @Published var isSending = false
    @Published var sendProgress = 0.0
    @Published var alert: ShareExtensionAlert?

    private weak var extensionContext: NSExtensionContext?
    private var tempDirectory: URL?
    private let maxSelectedDestinations = 3

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    func load() async {
        recipientIndex = ShareStorage.loadRecipientIndex()
        do {
            attachments = try await loadAttachments()
        } catch {
            presentAlert(title: "Attachment Error", message: "Could not read the shared attachment.")
        }
        if recipientIndex == nil {
            presentAlert(title: "Open ZekoChat", message: ShareSendError.missingRecipientIndex.localizedDescription)
        }
        isLoading = false
    }

    var recentDestinations: [ShareDestination] {
        guard let index = recipientIndex else { return [] }
        let destinationsById = Dictionary(uniqueKeysWithValues: index.allDestinations.map { ($0.id, $0) })
        return index.recentChannelIds.compactMap { destinationsById[$0] }
    }

    var filteredDms: [ShareDestination] {
        filter(recipientIndex?.dms ?? [])
    }

    var filteredGroupDms: [ShareDestination] {
        filter(recipientIndex?.groupDms ?? [])
    }

    var filteredServers: [ShareServerDestination] {
        let servers = recipientIndex?.servers ?? []
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return servers }
        let needle = query.lowercased()
        return servers.compactMap { server in
            let serverMatches = server.title.lowercased().contains(needle)
            let channels = server.channels.filter {
                serverMatches || $0.title.lowercased().contains(needle) || ($0.subtitle?.lowercased().contains(needle) ?? false)
            }
            return channels.isEmpty ? nil : ShareServerDestination(id: server.id, title: server.title, iconFileName: server.iconFileName, channels: channels)
        }
    }

    func toggleServer(_ server: ShareServerDestination) {
        if expandedServerIds.contains(server.id) {
            expandedServerIds.remove(server.id)
        } else {
            expandedServerIds.insert(server.id)
        }
    }

    var selectedDestinationIds: Set<String> {
        Set(selectedDestinations.map(\.id))
    }

    var selectionSummary: String {
        "\(selectedDestinations.count)/\(maxSelectedDestinations) selected"
    }

    func toggleSelection(_ destination: ShareDestination) {
        guard destination.canSendMessages && destination.canUploadFiles else { return }
        if let index = selectedDestinations.firstIndex(where: { $0.id == destination.id }) {
            selectedDestinations.remove(at: index)
            return
        }
        guard selectedDestinations.count < maxSelectedDestinations else {
            presentAlert(title: "Selection Limit", message: "You can share to up to \(maxSelectedDestinations) chats at once.")
            return
        }
        selectedDestinations.append(destination)
    }

    func send() {
        let destinations = selectedDestinations
        guard !destinations.isEmpty else { return }
        guard let token = SharedKeychain.readSessionToken() else {
            presentAlert(title: "Sign In Required", message: ShareSendError.missingSession.localizedDescription)
            return
        }
        let baseURL = recipientIndex?.baseURL ?? ShareStorage.loadSessionMetadata()?.baseURL ?? AttachmentSharingConstants.defaultBaseURL
        isSending = true

        Task {
            do {
                let sender = ShareAttachmentSender(baseURL: baseURL, sessionToken: token)
                let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                for (index, destination) in destinations.enumerated() {
                    let channelId = try await sender.resolveChannelId(for: destination)
                    try await sender.send(
                        files: attachments,
                        caption: trimmedCaption,
                        channelId: channelId
                    ) { [weak self] progress in
                        let aggregateProgress = (Double(index) + progress) / Double(destinations.count)
                        Task { @MainActor in self?.sendProgress = aggregateProgress }
                    }
                }
                cleanup()
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                isSending = false
                presentAlert(for: error)
            }
        }
    }

    func presentAlert(title: String, message: String) {
        alert = ShareExtensionAlert(title: title, message: message)
    }

    private func presentAlert(for error: Error) {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("MissingPermission") || message.localizedCaseInsensitiveContains("permission") {
            presentAlert(title: "Missing Permission", message: "You do not have permission to send messages or upload files in one of the selected chats.")
        } else {
            presentAlert(title: "Could Not Share", message: message)
        }
    }

    func cancel() {
        cleanup()
        extensionContext?.cancelRequest(withError: NSError(domain: "chat.zeko.share", code: 0))
    }

    func openApp() {
        guard let url = URL(string: "revoltchat://") else { return }
        extensionContext?.open(url)
    }

    private func filter(_ destinations: [ShareDestination]) -> [ShareDestination] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return destinations }
        let needle = trimmed.lowercased()
        return destinations.filter {
            $0.title.lowercased().contains(needle) || ($0.subtitle?.lowercased().contains(needle) ?? false)
        }
    }

    private func loadAttachments() async throws -> [ShareAttachmentFile] {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        tempDirectory = ShareStorage.temporaryShareDirectory()

        var files: [ShareAttachmentFile] = []
        for provider in providers.prefix(10) {
            if provider.hasShareableFileRepresentation, let file = try? await loadFile(from: provider) {
                files.append(file)
                continue
            }
            if let text = try? await loadText(from: provider), !text.isEmpty {
                caption = caption.isEmpty ? text : "\(caption)\n\(text)"
                continue
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier), let file = try? await loadFile(from: provider) {
                files.append(file)
            }
        }
        return files
    }

    private func loadText(from provider: NSItemProvider) async throws -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return try await loadStringItem(from: provider, typeIdentifier: UTType.url.identifier)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return try await loadStringItem(from: provider, typeIdentifier: UTType.plainText.identifier)
        }
        return nil
    }

    private func loadStringItem(from provider: NSItemProvider, typeIdentifier: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let string = item as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadFile(from provider: NSItemProvider) async throws -> ShareAttachmentFile {
        guard let tempDirectory else { throw NSError(domain: "chat.zeko.share", code: 2) }
        let candidates = provider.shareableTypeIdentifiers

        for candidate in candidates {
            if candidate.type.conforms(to: .url), !candidate.type.conforms(to: .fileURL) {
                if let sourceURL = try? await loadFileItemURL(from: provider, typeIdentifier: candidate.identifier), sourceURL.isFileURL {
                    let safeName = sanitizedFileName(provider.suggestedName ?? sourceURL.lastPathComponent, type: candidate.type)
                    return try copyFile(from: sourceURL, to: tempDirectory, fileName: safeName)
                }
                continue
            }

            if let sourceURL = try? await loadFileItemURL(from: provider, typeIdentifier: candidate.identifier), sourceURL.isFileURL {
                let safeName = sanitizedFileName(provider.suggestedName ?? sourceURL.lastPathComponent, type: candidate.type)
                return try copyFile(from: sourceURL, to: tempDirectory, fileName: safeName)
            }

            if let sourceURL = try? await loadFileURL(from: provider, typeIdentifier: candidate.identifier) {
                let safeName = sanitizedFileName(provider.suggestedName ?? sourceURL.lastPathComponent, type: candidate.type)
                return try copyFile(from: sourceURL, to: tempDirectory, fileName: safeName)
            }

            if let sourceURL = try? await loadInPlaceFileURL(from: provider, typeIdentifier: candidate.identifier) {
                let safeName = sanitizedFileName(provider.suggestedName ?? sourceURL.lastPathComponent, type: candidate.type)
                return try copyFile(from: sourceURL, to: tempDirectory, fileName: safeName)
            }

            if let data = try? await loadData(from: provider, typeIdentifier: candidate.identifier) {
                let safeName = sanitizedFileName(provider.suggestedName ?? "attachment", type: candidate.type)
                return try writeFile(data, to: tempDirectory, fileName: safeName)
            }
        }

        if provider.canLoadObject(ofClass: UIImage.self) {
            let image = try await loadImage(from: provider)
            guard let data = image.jpegData(compressionQuality: 0.92) else {
                throw NSError(domain: "chat.zeko.share", code: 6)
            }
            let safeName = sanitizedFileName(provider.suggestedName ?? "photo", type: .jpeg)
            return try writeFile(data, to: tempDirectory, fileName: safeName)
        }

        throw NSError(domain: "chat.zeko.share", code: 4)
    }

    private func loadFileItemURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: NSError(domain: "chat.zeko.share", code: 7))
                }
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: NSError(domain: "chat.zeko.share", code: 1))
                }
            }
        }
    }

    private func loadInPlaceFileURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: NSError(domain: "chat.zeko.share", code: 8))
                }
            }
        }
    }

    private func loadData(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "chat.zeko.share", code: 3))
                }
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            provider.loadObject(ofClass: UIImage.self) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image = item as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: NSError(domain: "chat.zeko.share", code: 5))
                }
            }
        }
    }

    private func copyFile(from sourceURL: URL, to directory: URL, fileName: String) throws -> ShareAttachmentFile {
        let destination = uniqueDestination(in: directory, fileName: fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ShareAttachmentFile(url: destination, fileName: destination.lastPathComponent, size: size)
    }

    private func writeFile(_ data: Data, to directory: URL, fileName: String) throws -> ShareAttachmentFile {
        let destination = uniqueDestination(in: directory, fileName: fileName)
        try data.write(to: destination, options: .atomic)
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ShareAttachmentFile(url: destination, fileName: destination.lastPathComponent, size: size)
    }

    private func uniqueDestination(in directory: URL, fileName: String) -> URL {
        let sanitized = sanitizedFileName(fileName, type: .data)
        var destination = directory.appendingPathComponent(sanitized)
        guard FileManager.default.fileExists(atPath: destination.path) else { return destination }

        let base = destination.deletingPathExtension().lastPathComponent
        let pathExtension = destination.pathExtension
        let uniqueName = pathExtension.isEmpty
            ? "\(base)-\(UUID().uuidString)"
            : "\(base)-\(UUID().uuidString).\(pathExtension)"
        destination = directory.appendingPathComponent(uniqueName)
        return destination
    }

    private func sanitizedFileName(_ fileName: String, type: UTType) -> String {
        let fallback = "attachment-\(UUID().uuidString)"
        var name = fileName.isEmpty ? fallback : fileName
        if !name.contains("."), let preferredExtension = type.preferredFilenameExtension {
            name += ".\(preferredExtension)"
        }
        return name.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    private func cleanup() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }
}

struct ShareExtensionRootView: View {
    @ObservedObject var viewModel: ShareExtensionViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
            footer
        }
        .background(ShareColors.background.ignoresSafeArea())
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel") { viewModel.cancel() }
                .foregroundStyle(ShareColors.textSecondary)
            Spacer()
            Text("Share to ZekoChat")
                .font(.headline)
                .foregroundStyle(ShareColors.textPrimary)
            Spacer()
            Button("Open") { viewModel.openApp() }
                .foregroundStyle(ShareColors.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(ShareColors.surface)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                attachmentSummary
                captionField
                searchField
                destinationSections
            }
            .padding(16)
        }
    }

    private var attachmentSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ShareColors.textPrimary)
            ForEach(viewModel.attachments) { attachment in
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(ShareColors.accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(ShareColors.surface2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.fileName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(ShareColors.textPrimary)
                        Text(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(ShareColors.textSecondary)
                    }
                    Spacer()
                }
            }
            if viewModel.attachments.isEmpty {
                Text("No file attachment found. Text or URLs will be sent as the message.")
                    .font(.caption)
                    .foregroundStyle(ShareColors.textSecondary)
            }
        }
    }

    private var captionField: some View {
        TextField("Add a message", text: $viewModel.caption, axis: .vertical)
            .lineLimit(1...4)
            .padding(12)
            .foregroundStyle(ShareColors.textPrimary)
            .background(RoundedRectangle(cornerRadius: 8).fill(ShareColors.surface2))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ShareColors.textSecondary)
            TextField("Search DMs and channels", text: $viewModel.query)
                .foregroundStyle(ShareColors.textPrimary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(ShareColors.surface2))
    }

    private var destinationSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            DestinationSection(title: "Recents", destinations: viewModel.recentDestinations, viewModel: viewModel)
            DestinationSection(title: "Direct Messages", destinations: viewModel.filteredDms, viewModel: viewModel)
            DestinationSection(title: "Group DMs", destinations: viewModel.filteredGroupDms, viewModel: viewModel)
            serverSection
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Servers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShareColors.textSecondary)
                .textCase(.uppercase)
            ForEach(viewModel.filteredServers) { server in
                VStack(spacing: 0) {
                    Button { viewModel.toggleServer(server) } label: {
                        HStack {
                            Image(systemName: "circle.grid.2x2.fill")
                                .foregroundStyle(ShareColors.accent)
                            Text(server.title)
                                .foregroundStyle(ShareColors.textPrimary)
                            Spacer()
                            Image(systemName: viewModel.expandedServerIds.contains(server.id) ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(ShareColors.textSecondary)
                        }
                        .padding(.vertical, 10)
                    }
                    if viewModel.expandedServerIds.contains(server.id) || !viewModel.query.isEmpty {
                        ForEach(server.channels) { channel in
                            DestinationRow(destination: channel, isSelected: viewModel.selectedDestinationIds.contains(channel.id)) {
                                viewModel.toggleSelection(channel)
                            }
                            .padding(.leading, 18)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if viewModel.isSending {
                ProgressView(value: viewModel.sendProgress)
                    .tint(ShareColors.accent)
            }
            Text(viewModel.selectionSummary)
                .font(.caption)
                .foregroundStyle(ShareColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.send()
            } label: {
                Text(viewModel.isSending ? "Sending..." : "Send")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.black)
                    .background(RoundedRectangle(cornerRadius: 8).fill(canSend ? ShareColors.accent : ShareColors.disabled))
            }
            .disabled(!canSend)
        }
        .padding(16)
        .background(ShareColors.surface)
    }

    private var canSend: Bool {
        !viewModel.selectedDestinations.isEmpty && !viewModel.isSending && (!viewModel.attachments.isEmpty || !viewModel.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

}

struct ShareExtensionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct DestinationSection: View {
    let title: String
    let destinations: [ShareDestination]
    @ObservedObject var viewModel: ShareExtensionViewModel

    var body: some View {
        if !destinations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShareColors.textSecondary)
                    .textCase(.uppercase)
                ForEach(destinations) { destination in
                    DestinationRow(destination: destination, isSelected: viewModel.selectedDestinationIds.contains(destination.id)) {
                        viewModel.toggleSelection(destination)
                    }
                }
            }
        }
    }
}

struct DestinationRow: View {
    let destination: ShareDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(destination.canUploadFiles ? ShareColors.accent : ShareColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(ShareColors.surface2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(destination.canUploadFiles ? ShareColors.textPrimary : ShareColors.textSecondary)
                        .lineLimit(1)
                    if let subtitle = destination.subtitle {
                        Text(destination.canUploadFiles ? subtitle : "Cannot upload files here")
                            .font(.caption)
                            .foregroundStyle(ShareColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ShareColors.accent)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? ShareColors.selectedSurface : Color.clear))
        }
        .disabled(!destination.canSendMessages || !destination.canUploadFiles)
    }

    private var iconName: String {
        switch destination.type {
        case .directMessage:
            return "person.fill"
        case .groupDM:
            return "person.2.fill"
        case .serverChannel:
            return "number"
        }
    }
}

private extension NSItemProvider {
    struct ShareableType {
        let identifier: String
        let type: UTType
    }

    var hasShareableFileRepresentation: Bool {
        !shareableTypeIdentifiers.isEmpty || canLoadObject(ofClass: UIImage.self)
    }

    var shareableTypeIdentifiers: [ShareableType] {
        let concreteTypes = registeredTypeIdentifiers.compactMap { identifier -> ShareableType? in
            guard let type = UTType(identifier),
                  type.conforms(to: .image) ||
                  type.conforms(to: .movie) ||
                  type.conforms(to: .audiovisualContent) ||
                  type.conforms(to: .fileURL) ||
                  type.conforms(to: .url) ||
                  type.conforms(to: .data)
            else { return nil }
            return ShareableType(identifier: identifier, type: type)
        }

        let fallbackTypes: [UTType] = [.fileURL, .image, .movie, .url, .data]
        let fallbacks = fallbackTypes.compactMap { type -> ShareableType? in
            guard hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
            return ShareableType(identifier: type.identifier, type: type)
        }

        var seen = Set<String>()
        return (concreteTypes + fallbacks)
            .sorted { lhs, rhs in lhs.priority < rhs.priority }
            .filter { candidate in
            seen.insert(candidate.identifier).inserted
        }
    }
}

private extension NSItemProvider.ShareableType {
    var priority: Int {
        if type.conforms(to: .fileURL) { return 0 }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) { return 1 }
        if type.conforms(to: .image) { return 2 }
        if type.conforms(to: .url) { return 3 }
        if type.conforms(to: .data) { return 4 }
        return 5
    }
}

enum ShareColors {
    static let background = Color(red: 0.07, green: 0.06, blue: 0.10)
    static let surface = Color(red: 0.10, green: 0.09, blue: 0.14)
    static let surface2 = Color(red: 0.15, green: 0.14, blue: 0.20)
    static let selectedSurface = Color(red: 0.22, green: 0.18, blue: 0.30)
    static let textPrimary = Color(red: 0.94, green: 0.93, blue: 0.97)
    static let textSecondary = Color(red: 0.62, green: 0.60, blue: 0.68)
    static let accent = Color(red: 1.00, green: 0.84, blue: 0.22)
    static let disabled = Color(red: 0.35, green: 0.34, blue: 0.38)
    static let warningText = Color(red: 1.0, green: 0.78, blue: 0.52)
    static let warningBackground = Color(red: 0.30, green: 0.18, blue: 0.10)
}
