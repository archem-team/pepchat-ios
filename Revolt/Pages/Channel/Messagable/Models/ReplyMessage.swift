//
//  ReplyMessage.swift
//  Revolt
//

import Foundation
import Types

// Create a typealias to the Dictionary type to resolve the ambiguity
typealias RevoltMessagesReply = Dictionary<String, Types.Message>

// Define a new struct for message replies to avoid ambiguity issues
struct ReplyMessage {
    let messageId: String
    let message: Types.Message
    let mention: Bool
    
    init(message: Types.Message, mention: Bool) {
        self.messageId = message.id
        self.message = message
        self.mention = mention
    }
}

