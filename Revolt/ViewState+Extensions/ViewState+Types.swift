//
//  ViewState+Types.swift
//  Revolt
//
//  Created by Akshat Srivastava on 31/01/26.
//

import Foundation
import Combine
import SwiftUI
import Alamofire
import ULID
import Collections
import Sentry
@preconcurrency import Types
import UserNotifications
import KeychainAccess
import Darwin
import Network

enum UserStateError: Error {
    case signInError
    case signOutError
}

enum LoginState {
    case Success
    case Mfa(ticket: String, methods: [String])
    case Disabled
    case Invalid
    case Onboarding
}

struct LoginSuccess: Decodable {
    let result: String
    let _id: String
    let user_id: String
    let token: String
    let name: String
}

struct LoginMfa: Decodable {
    let result: String
    let ticket: String
    let allowed_methods: [String]
}

struct LoginDisabled: Decodable {
    let result: String
    let user_id: String
}

enum LoginResponse {
    case Success(LoginSuccess)
    case Mfa(LoginMfa)
    case Disabled(LoginDisabled)
}

extension LoginResponse: Decodable {
    enum CodingKeys: String, CodingKey { case result }
    enum Tag: String, Decodable { case Success, MFA, Disabled }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch try container.decode(Tag.self, forKey: .result) {
        case .Success:
            self = .Success(try singleValueContainer.decode(LoginSuccess.self))
        case .MFA:
            self = .Mfa(try singleValueContainer.decode(LoginMfa.self))
        case .Disabled:
            self = .Disabled(try singleValueContainer.decode(LoginDisabled.self))
        }
    }
}

enum ConnectionState {
    case connecting, connected, signedOut
}


enum MainSelection: Hashable, Codable {
    case server(String)
    case dms
    case discover
    
    var id: String? {
        switch self {
        case .server(let id):
            id
        case .dms:
            nil
        case .discover:
            nil
        }
    }
}

enum ChannelSelection: Hashable, Codable {
    case channel(String)
    case home
    case friends
    case noChannel
    
    var id: String? {
        switch self {
        case .channel(let id): id
        default: nil
        }
    }
}

enum NavigationDestination: Hashable, Codable {
    case discover
    case settings
    case about_settings
    case developer_settings
    case server_settings(String)
    case channel_info(String,String?)
    case add_members_to_channel(String)
    case channel_settings(String)
    case add_friend
    case create_group([String])
    case channel_search(String)
    case invite(String)
    case maybeChannelView
    case create_group_name
    case create_group_add_memebers(String)
    case report(Types.User?,String?,String?)
    case channel_overview_setting(String,String?)
    case server_channel_overview_setting(String,String)
    case server_role_setting(String)
    case server_overview_settings(String)
    case server_channels(String)
    case server_category(String,String)
    case channel_category_create(String, ChannelCategoryCreateType)
    case profile_setting
    case server_emoji_settings(String)
    case validate_password_view(ValidatePasswordReason)
    case show_recovery_codes(String, Bool)
    case enable_authenticator_app(String)
    case blocked_users_view
    case user_settings
    case role_setting(serverId:String, channelId: String, roleId : String, roleTitle : String, value:ChannelRolePermissionsSettings.Value)
    case server_members_view(String)
    case member_permissions(String, Member)
    case server_invites(String)
    case server_banned_users(String)
    case create_server_role(serverId : String)
    case default_role_settings(serverId : String)
    case role_settings(serverId : String, roleId : String)
    case channel_permissions_settings(serverId : String?, channelId : String)
    case sessions_settings
    case username_view
    case change_email_view
    case change_password_view
}

struct UserMaybeMember: Identifiable {
    var user: Types.User
    var member: Member?
    
    var id: String { user.id }
    
    var avatar: File? {
        return member?.avatar ?? user.avatar
    }
    
    var nickname: String? {
        return member?.nickname ?? user.display_name ?? user.username
    }
}

class QueuedMessage: ObservableObject {
    let nonce: String
    let replies: [Revolt.ApiReply]
    let content: String
    let author: String // User ID of the sender
    let channel: String // Channel ID
    let timestamp: Date // When the message was sent locally
    let hasAttachments: Bool // Whether this message has attachments (affects when to show optimistically)
    let attachmentData: [(Data, String)] // Original attachment data for progress tracking
    @Published var uploadProgress: [String: Double] = [:] // Progress per attachment (filename -> progress 0.0-1.0)
    @Published var isUploading: Bool = false // Whether currently uploading
    
    init(nonce: String, replies: [Revolt.ApiReply], content: String, author: String, channel: String, timestamp: Date, hasAttachments: Bool, attachmentData: [(Data, String)] = []) {
        self.nonce = nonce
        self.replies = replies
        self.content = content
        self.author = author
        self.channel = channel
        self.timestamp = timestamp
        self.hasAttachments = hasAttachments
        self.attachmentData = attachmentData
        self.uploadProgress = [:]
        self.isUploading = hasAttachments
        
        // Initialize progress for each attachment
        for (_, filename) in attachmentData {
            self.uploadProgress[filename] = 0.0
        }
    }
    
    // Helper function to determine content type from filename
    private func getContentType(for filename: String) -> String {
        let lowercaseFilename = filename.lowercased()
        
        // Image types
        if lowercaseFilename.hasSuffix(".jpg") || lowercaseFilename.hasSuffix(".jpeg") {
            return "image/jpeg"
        } else if lowercaseFilename.hasSuffix(".png") {
            return "image/png"
        } else if lowercaseFilename.hasSuffix(".gif") {
            return "image/gif"
        } else if lowercaseFilename.hasSuffix(".webp") {
            return "image/webp"
        } else if lowercaseFilename.hasSuffix(".bmp") {
            return "image/bmp"
        } else if lowercaseFilename.hasSuffix(".svg") {
            return "image/svg+xml"
        }
        // Video types
        else if lowercaseFilename.hasSuffix(".mp4") {
            return "video/mp4"
        } else if lowercaseFilename.hasSuffix(".mov") {
            return "video/quicktime"
        } else if lowercaseFilename.hasSuffix(".avi") {
            return "video/x-msvideo"
        } else if lowercaseFilename.hasSuffix(".webm") {
            return "video/webm"
        }
        // Audio types
        else if lowercaseFilename.hasSuffix(".mp3") {
            return "audio/mpeg"
        } else if lowercaseFilename.hasSuffix(".wav") {
            return "audio/wav"
        } else if lowercaseFilename.hasSuffix(".m4a") {
            return "audio/mp4"
        }
        // Default
        else {
            return "application/octet-stream"
        }
    }
    
    // Convert to a temporary Message object for display
    func toTemporaryMessage() -> Message {
        // Create temporary File objects for display if uploading
        let tempAttachments: [Types.File]? = hasAttachments && isUploading ?
            attachmentData.map { (data, filename) in
                // Determine content type based on file extension
                let contentType = getContentType(for: filename)
                
                return Types.File(
                    id: "\(nonce)_\(filename)", // Temporary ID
                    tag: "attachments", // Required tag parameter
                    size: Int64(data.count),
                    filename: filename,
                    metadata: Types.FileMetadata.file(Types.SimpleMetadata()), // Correct metadata type
                    content_type: contentType
                )
            } : nil
        
        return Message(
            id: nonce, // Use nonce as temporary ID
            content: content,
            author: author,
            channel: channel,
            system: nil,
            attachments: tempAttachments,
            mentions: nil,
            replies: replies.isEmpty ? nil : replies.map { $0.id },
            edited: nil,
            masquerade: nil,
            interactions: nil,
            reactions: nil,
            user: nil,
            member: nil,
            embeds: nil,
            webhook: nil
        )
    }
}
