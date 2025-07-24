//
//  Utils.swift
//  Revolt
//
//  Created by Angelo on 14/10/2023.
//

import Foundation
import ULID
import Types

/// Returns the creation date of a given ULID string.
///
/// - Parameter id: A string representing a ULID (Universally Unique Lexicographically Sortable Identifier).
/// - Returns: A `Date` object representing the timestamp of the ULID.
func createdAt(id: String) -> Date {
    // Check if this is a valid ULID before trying to extract timestamp
    if let ulid = ULID(ulidString: id) {
        return ulid.timestamp
    } else {
        // For non-ULID strings (like pending message nonces), return current time
        return Date()
    }
}


func formattedMessageDate(from date: Date) -> String {
    let calendar = Calendar.current
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm a" // 12-hour format with AM/PM

    let fullFormatter = DateFormatter()
    fullFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"

    if calendar.isDateInToday(date) {
        return "Today at \(timeFormatter.string(from: date))"
    } else if calendar.isDateInYesterday(date) {
        return "Yesterday at \(timeFormatter.string(from: date))"
    } else {
        return fullFormatter.string(from: date)
    }
}


/// An enumeration representing different file categories in the Revolt application.
enum FileCategory: String {
    case attachment = "attachments"   // Represents file attachments
    case avatar = "avatars"           // Represents user avatars
    case background = "backgrounds"   // Represents background images
    case icon = "icons"               // Represents icons
    case banner = "banners"           // Represents banners
    case emoji = "emojis"             // Represents emojis
}

/// An enumeration representing the different types of channels in the Revolt application.
enum ChannelType {
    case text      // Text channels for messaging
    case voice     // Voice channels for audio communication
    case group     // Group channels for multiple users
    case dm        // Direct message channels for private conversations
    case saved      // Channels for saving messages or content
}

/// A protocol that defines the requirements for messageable entities.
///
/// Types conforming to this protocol must provide:
/// - A unique identifier
/// - A channel type that indicates the nature of the channel they belong to
protocol Messageable: Identifiable {
    var channelType: ChannelType { get } // The type of channel the message belongs to
}


struct LocalFile: Equatable {
    var content: Data
    var filename: String
}

enum SettingImage: Equatable {
    case remote(File?)
    case local(LocalFile?)
}

enum Icon: Equatable {
    case remote(File?)
    case local(Data?)
    
    func isNotEmpty() -> Bool{
        switch self{
        case .remote(let file): return file != nil
        case .local(let data): return data != nil
        }
    }
}
