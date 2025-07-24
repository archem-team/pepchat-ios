//
//  ServerChannel.swift
//  Types
//
//

import Foundation

public struct ServerChannel : Codable {
    public let server : Server
    public let channels : [Channel]
}
