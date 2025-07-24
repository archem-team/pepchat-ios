//
//  PendingAttachmentsManager.swift
//  Revolt
//
//  Created by Assistant on 1/15/2025.
//

import UIKit
import Foundation
import Combine

// MARK: - PendingAttachmentsManager
@MainActor
class PendingAttachmentsManager: ObservableObject {
    @Published var pendingAttachments: [PendingAttachment] = []
    
    // Maximum number of attachments allowed
    private let maxAttachments = 10
    
    // Maximum file size (8MB)
    private let maxFileSize = 8 * 1024 * 1024
    
    var hasPendingAttachments: Bool {
        return !pendingAttachments.isEmpty
    }
    
    var attachmentCount: Int {
        return pendingAttachments.count
    }
    
    // MARK: - Add Attachments
    
    func addImage(_ image: UIImage, fileName: String? = nil) -> Bool {
        guard pendingAttachments.count < maxAttachments else {
            return false
        }
        
        let attachment = PendingAttachment(image: image, fileName: fileName)
        
        // Check file size
        guard attachment.data.count <= maxFileSize else {
            return false
        }
        
        pendingAttachments.append(attachment)
        return true
    }
    
    func addDocument(data: Data, fileName: String) -> Bool {
        guard pendingAttachments.count < maxAttachments else {
            return false
        }
        
        // Check file size
        guard data.count <= maxFileSize else {
            return false
        }
        
        let attachment = PendingAttachment(data: data, fileName: fileName, type: .document)
        pendingAttachments.append(attachment)
        return true
    }
    
    // MARK: - Remove Attachments
    
    func removeAttachment(withId id: String) {
        pendingAttachments.removeAll { $0.id == id }
    }
    
    func removeAttachment(at index: Int) {
        guard index >= 0 && index < pendingAttachments.count else { return }
        pendingAttachments.remove(at: index)
    }
    
    func clearAllAttachments() {
        pendingAttachments.removeAll()
    }
    
    // MARK: - Get Attachments for Sending
    
    func getAttachmentsForSending() -> [(Data, String)] {
        return pendingAttachments.map { ($0.data, $0.fileName) }
    }
    
    // MARK: - Validation
    
    func canAddMoreAttachments() -> Bool {
        return pendingAttachments.count < maxAttachments
    }
    
    func validateFileSize(_ data: Data) -> Bool {
        return data.count <= maxFileSize
    }
    
    func getMaxFileSizeString() -> String {
        return "8MB"
    }
} 