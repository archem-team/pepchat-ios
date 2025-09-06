//
//  ServerChannel.swift
//  Types
//
//

import Foundation

public struct ServerChannel : Codable {
    public let server : Server
    public let channels : [Channel]
    
    public init(server: Server, channels: [Channel]) {
        self.server = server
        self.channels = channels
    }
}
