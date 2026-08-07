import Foundation
import Security

enum AttachmentSharingConstants {
    static let appGroupIdentifier = "group.pepchat.shared.data"
    static let keychainService = "chat.peptide.app"
    static let sessionTokenKey = "sessionToken"
    static let sharedKeychainAccessGroup = "R8387T64JW.chat.zeko.app.shared"
    static let shareIndexSchemaVersion = 1
    static let defaultBaseURL = "https://peptide.chat/api"
}

enum ShareDestinationType: String, Codable {
    case directMessage
    case groupDM
    case serverChannel
}

struct ShareDestination: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let avatarFileName: String?
    let type: ShareDestinationType
    let canSendMessages: Bool
    let canUploadFiles: Bool
    let lastMessageId: String?
    let openUserId: String?
}

struct ShareServerDestination: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let iconFileName: String?
    let channels: [ShareDestination]
}

struct ShareRecipientIndex: Codable {
    let schemaVersion: Int
    let userId: String
    let baseURL: String
    let generatedAt: Date
    let recentChannelIds: [String]
    let dms: [ShareDestination]
    let groupDms: [ShareDestination]
    let servers: [ShareServerDestination]

    var allDestinations: [ShareDestination] {
        dms + groupDms + servers.flatMap(\.channels)
    }
}

struct ShareSessionMetadata: Codable {
    let userId: String
    let baseURL: String
}

enum ShareStorage {
    private static let sessionMetadataKey = "share_session_metadata"
    private static let latestIndexFileNameKey = "share_latest_index_file"

    static var appGroupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AttachmentSharingConstants.appGroupIdentifier)
    }

    static var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: AttachmentSharingConstants.appGroupIdentifier)
    }

    static func saveSessionMetadata(userId: String, baseURL: String) {
        guard let data = try? JSONEncoder().encode(ShareSessionMetadata(userId: userId, baseURL: baseURL)) else { return }
        appGroupDefaults?.set(data, forKey: sessionMetadataKey)
    }

    static func loadSessionMetadata() -> ShareSessionMetadata? {
        guard let data = appGroupDefaults?.data(forKey: sessionMetadataKey) else { return nil }
        return try? JSONDecoder().decode(ShareSessionMetadata.self, from: data)
    }

    static func saveRecipientIndex(_ index: ShareRecipientIndex) {
        guard let directory = appGroupURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = recipientIndexFileName(userId: index.userId, baseURL: index.baseURL)
        let url = directory.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: url, options: .atomic)
        appGroupDefaults?.set(fileName, forKey: latestIndexFileNameKey)
    }

    static func loadRecipientIndex() -> ShareRecipientIndex? {
        guard let directory = appGroupURL else { return nil }
        let fileName: String
        if let metadata = loadSessionMetadata() {
            fileName = recipientIndexFileName(userId: metadata.userId, baseURL: metadata.baseURL)
        } else if let latest = appGroupDefaults?.string(forKey: latestIndexFileNameKey) {
            fileName = latest
        } else {
            return nil
        }

        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let index = try? decoder.decode(ShareRecipientIndex.self, from: data) else { return nil }
        guard index.schemaVersion == AttachmentSharingConstants.shareIndexSchemaVersion else { return nil }
        return index
    }

    static func clearShareData() {
        appGroupDefaults?.removeObject(forKey: sessionMetadataKey)
        appGroupDefaults?.removeObject(forKey: latestIndexFileNameKey)
        guard let directory = appGroupURL,
              let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for url in contents where url.lastPathComponent.hasPrefix("share_recipients_") || url.lastPathComponent.hasPrefix("share_tmp_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func temporaryShareDirectory() -> URL? {
        guard let directory = appGroupURL else { return nil }
        let temp = directory.appendingPathComponent("share_tmp_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    private static func recipientIndexFileName(userId: String, baseURL: String) -> String {
        "share_recipients_\(safeFileComponent(userId))_\(safeFileComponent(baseURL)).json"
    }

    private static func safeFileComponent(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }
}

enum SharedKeychain {
    static func readSessionToken() -> String? {
        readString(key: AttachmentSharingConstants.sessionTokenKey, accessGroup: AttachmentSharingConstants.sharedKeychainAccessGroup)
            ?? readString(key: AttachmentSharingConstants.sessionTokenKey, accessGroup: nil)
    }

    static func writeSessionToken(_ token: String?) {
        if let token {
            writeString(token, key: AttachmentSharingConstants.sessionTokenKey, accessGroup: AttachmentSharingConstants.sharedKeychainAccessGroup)
            writeString(token, key: AttachmentSharingConstants.sessionTokenKey, accessGroup: nil)
        } else {
            deleteString(key: AttachmentSharingConstants.sessionTokenKey, accessGroup: AttachmentSharingConstants.sharedKeychainAccessGroup)
            deleteString(key: AttachmentSharingConstants.sessionTokenKey, accessGroup: nil)
        }
    }

    private static func baseQuery(key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AttachmentSharingConstants.keychainService,
            kSecAttrAccount as String: key
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func readString(key: String, accessGroup: String?) -> String? {
        var query = baseQuery(key: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeString(_ value: String, key: String, accessGroup: String?) {
        let data = Data(value.utf8)
        let query = baseQuery(key: key, accessGroup: accessGroup)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func deleteString(key: String, accessGroup: String?) {
        SecItemDelete(baseQuery(key: key, accessGroup: accessGroup) as CFDictionary)
    }
}

struct ShareAttachmentFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let fileName: String
    let size: Int64
}

struct ShareAttachmentSender {
    struct ApiInfo: Decodable {
        struct Features: Decodable {
            struct Autumn: Decodable {
                let url: String
            }
            let autumn: Autumn
        }
        let features: Features
    }

    struct UploadResponse: Decodable {
        let id: String
    }

    struct OpenDMResponse: Decodable {
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "_id"
        }
    }

    let baseURL: String
    let sessionToken: String

    func resolveChannelId(for destination: ShareDestination) async throws -> String {
        guard let userId = destination.openUserId else {
            return destination.id
        }
        return try await openDM(userId: userId).id
    }

    func send(files: [ShareAttachmentFile], caption: String, channelId: String, progress: @escaping (Double) -> Void) async throws {
        let autumnURL = try await fetchApiInfo().features.autumn.url
        var attachmentIds: [String] = []
        for (index, file) in files.enumerated() {
            let data = try Data(contentsOf: file.url)
            let upload = try await upload(data: data, fileName: file.fileName, autumnURL: autumnURL)
            attachmentIds.append(upload.id)
            progress(Double(index + 1) / Double(max(files.count, 1)) * 0.85)
        }
        try await postMessage(channelId: channelId, content: caption, attachments: attachmentIds)
        progress(1.0)
    }

    private func fetchApiInfo() async throws -> ApiInfo {
        let url = URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.addValue(sessionToken, forHTTPHeaderField: "x-session-token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ApiInfo.self, from: data)
    }

    private func openDM(userId: String) async throws -> OpenDMResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/users/\(userId)/dm")!)
        request.httpMethod = "GET"
        request.addValue(sessionToken, forHTTPHeaderField: "x-session-token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(OpenDMResponse.self, from: data)
    }

    private func upload(data: Data, fileName: String, autumnURL: String) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "\(autumnURL)/attachments")!)
        request.httpMethod = "POST"
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(data: data, fileName: fileName, boundary: boundary)
        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: responseData)
        return try JSONDecoder().decode(UploadResponse.self, from: responseData)
    }

    private func postMessage(channelId: String, content: String, attachments: [String]) async throws {
        let payload = SendMessagePayload(replies: [], content: content, attachments: attachments, nonce: UUID().uuidString)
        var request = URLRequest(url: URL(string: "\(baseURL)/channels/\(channelId)/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(sessionToken, forHTTPHeaderField: "x-session-token")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func multipartBody(data: Data, fileName: String, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Request failed"
            throw ShareSendError.http(status: httpResponse.statusCode, body: body)
        }
    }

    private struct SendMessagePayload: Encodable {
        let replies: [String]
        let content: String
        let attachments: [String]
        let nonce: String
    }
}

enum ShareSendError: LocalizedError {
    case http(status: Int, body: String)
    case missingSession
    case missingRecipientIndex

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "Request failed (\(status)): \(body)"
        case .missingSession:
            return "Please open ZekoChat and sign in again."
        case .missingRecipientIndex:
            return "Open ZekoChat once so your chats can be prepared for sharing."
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
