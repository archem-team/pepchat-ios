//
//  String.swift
//  Revolt
//
//

import Foundation

extension String {
    var isNotEmpty: Bool {
        return !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Checks if the string is a valid URL.
    /// - Returns: `true` if the string is a valid URL, `false` otherwise.
    var isValidURL: Bool {
        guard !self.isEmpty else { return false }
        
        // Use URL initializer for basic URL validation
        if let url = URL(string: self), url.scheme != nil, url.host != nil {
            return true
        }
        
        // Regex pattern for URL validation
        let urlPattern = #"^(https?|ftp)://[^\s/$.?#].[^\s]*$"#
        let result = NSPredicate(format: "SELF MATCHES %@", urlPattern)
        
        return result.evaluate(with: self)
    }
    
    /// Checks if the string is a valid email format.
    /// - Returns: `true` if the string is in a valid email format, `false` otherwise.
    var isValidEmail: Bool {
        let emailPattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$"#
        let result = NSPredicate(format: "SELF MATCHES %@", emailPattern)
        return result.evaluate(with: self)
    }
    
    /// Checks if the string meets password strength requirements.
        /// - Returns: `true` if the password meets the required criteria, `false` otherwise.
        var isValidPassword: Bool {
            let passwordPattern = #"^(?=.*[A-Za-z])(?=.*\d).{6,}$"#
            let result = NSPredicate(format: "SELF MATCHES %@", passwordPattern)
            return result.evaluate(with: self)
        }
}
