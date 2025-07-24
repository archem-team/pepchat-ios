//
//  MessageableChannelErrors.swift
//  Revolt
//
//

import Foundation

enum MessageableChannelError: Error {
    case noMessagesFound
    case networkError(String)
    case permissionDenied
    case invalidChannelId
    case messageNotFound(String)
    case loadingTimeout
    case rateLimited(retryAfter: Int)
    
    var localizedDescription: String {
        switch self {
        case .noMessagesFound:
            return "No messages found"
        case .networkError(let message):
            return "Network error: \(message)"
        case .permissionDenied:
            return "Permission denied"
        case .invalidChannelId:
            return "Invalid channel ID"
        case .messageNotFound(let messageId):
            return "Message not found: \(messageId)"
        case .loadingTimeout:
            return "Loading timeout"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(retryAfter) seconds"
        }
    }
}

// Loading states
enum LoadingState: Equatable {
    case loading
    case notLoading
}

