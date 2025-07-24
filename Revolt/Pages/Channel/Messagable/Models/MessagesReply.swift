//
//  MessagesReply.swift
//  Revolt
//

import Foundation
import Types

// Structure that represents a reply to a message, matching the SwiftUI version but with a different name
struct MessagesReply: Identifiable, Equatable {
    var message: Message             // The original message being replied to
    var mention: Bool = true         // Always mention the user
    
    var id: String { message.id }
    
    static func == (lhs: MessagesReply, rhs: MessagesReply) -> Bool {
        lhs.id == rhs.id
    }
}

