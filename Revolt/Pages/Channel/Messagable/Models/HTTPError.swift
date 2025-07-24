//
//  HTTPError.swift
//  Revolt
//
//

import Foundation

// MARK: - HTTPError Definition
// Define HTTPError enum to handle API errors
enum HTTPError: Error {
    case failure(Int, String?)
    
    var localizedDescription: String {
        switch self {
        case .failure(let statusCode, let message):
            return "HTTP Error \(statusCode): \(message ?? "Unknown error")"
        }
    }
}

