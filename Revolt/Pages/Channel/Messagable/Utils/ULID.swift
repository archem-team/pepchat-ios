//
//  ULID.swift
//  Revolt
//

import Foundation

// MARK: - ULID Implementation
// Simple ULID structure to handle message timestamp conversion
struct ULID {
    let value: String
    let timestamp: Date
    
    init?(ulidString: String) {
        guard ulidString.count == 26 else { return nil }
        self.value = ulidString
        
        // ULIDs have timestamp in the first 10 characters (48 bits in base32)
        // This is a simplified implementation
        let timestampPart = String(ulidString.prefix(10))
        
        // Convert base32 timestamp to milliseconds since epoch
        if let timestampMillis = ULID.decodeBase32(timestampPart) {
            self.timestamp = Date(timeIntervalSince1970: Double(timestampMillis) / 1000.0)
        } else {
            self.timestamp = Date()
        }
    }
    
    // Simplified base32 decoder for ULIDs
    static func decodeBase32(_ value: String) -> UInt64? {
        let base32Chars = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
        var result: UInt64 = 0
        
        for char in value.uppercased() {
            if let value = base32Chars.firstIndex(of: char) {
                let index = base32Chars.distance(from: base32Chars.startIndex, to: value)
                result = result * 32 + UInt64(index)
            } else {
                return nil
            }
        }
        
        return result
    }
}

