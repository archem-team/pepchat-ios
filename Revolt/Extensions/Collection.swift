//
//  Collection.swift
//  Revolt
//
//  Created by Angelo on 19/06/2024.
//

import Foundation

/// An extension to the `Collection` protocol that provides safe access to its elements.
extension Collection {
    
    /// Safely accesses an element at the specified index.
    ///
    /// This subscript returns an optional element. If the index is within the bounds of the collection,
    /// the corresponding element is returned. If the index is out of bounds, `nil` is returned
    /// instead of causing a runtime error.
    ///
    /// - Parameter index: The index of the element to access.
    /// - Returns: The element at the specified index, or `nil` if the index is out of bounds.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// Extension to Array that provides chunking functionality for batch processing
extension Array {
    
    /// Splits the array into chunks of the specified size.
    ///
    /// This method returns an array of arrays, where each inner array contains
    /// up to `size` elements from the original array. The last chunk may contain
    /// fewer elements if the array's count is not evenly divisible by the chunk size.
    ///
    /// - Parameter size: The maximum size of each chunk.
    /// - Returns: An array of arrays, each containing up to `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
