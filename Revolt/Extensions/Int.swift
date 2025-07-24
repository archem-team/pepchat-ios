//
//  Int.swift
//  Revolt
//
//

import Foundation


extension Int {
    func formattedWithSeparator(separator: String = ",") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = separator
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
