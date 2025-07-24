//
//  Binding.swift
//  Revolt
//
//  Created by Angelo on 25/09/2024.
//

import Foundation
import SwiftUI

// Extension to add functionality to the Binding type.
extension Binding {
    
    /// Returns a new binding that provides a default value when the original binding's value is nil.
    /// - Parameter defaultValue: The default value to use if the original binding's value is nil.
    /// - Returns: A new Binding<T> that resolves to the original value or the default value.
    func bindOr<T>(defaultTo defaultValue: T) -> Binding<T> where Value == T? {
        .init(
            get: { self.wrappedValue ?? defaultValue }, // Return the wrapped value or the default value if nil.
            set: { self.wrappedValue = $0 } // Set the wrapped value.
        )
    }
    
    
    func bindEmptyToNil() -> Binding<String> where Value == String? {
            .init(
                get: { self.wrappedValue ?? "" },
                set: { new in
                    if new.isEmpty {
                        self.wrappedValue = nil
                    } else {
                        self.wrappedValue = new
                    }
                }
            )
        }
}
