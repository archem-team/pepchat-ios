//
//  Discover.swift
//  Revolt
//
//  Created by  D

import Foundation

struct DiscoverItem {
    let id: String
    let code: String
    let title: String
    let description: String
    let isNew: Bool
    let sortOrder: Int
    let disabled: Bool
    let color: String?
}

struct ServerChat: Codable {
    let id: String
    let name: String
    let description: String
    let inviteCode: String
    let disabled: Bool
    let isNew: Bool
    let sortOrder: Int
    let chronological: Int
    let dateAdded: String?
    let price1: String?
    let price2: String?
    let color: String?
}
