//
//  PlatformConfig.swift
//  Revolt
//
//

import Foundation

struct PlatformConfig: Codable, Identifiable {
    let id = UUID()
    let title: String
    let image: String
    let url: String
    
    enum CodingKeys: String, CodingKey {
        case title, image, url
    }
}

struct PlatformConfigResponse: Codable {
    let platforms: [PlatformConfig]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        platforms = try container.decode([PlatformConfig].self)
    }
}
