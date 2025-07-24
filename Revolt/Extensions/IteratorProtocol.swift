//
//  IteratorProtocol.swift
//  Revolt
//
//  Created by Angelo on 19/06/2024.
//

import Foundation

/// An extension to the `IteratorProtocol` that provides additional functionality
/// for iterators, allowing retrieval of multiple elements at once.
extension IteratorProtocol {
    
    /// Retrieves the next `n` elements from the iterator.
    ///
    /// This method returns an array containing the next `n` elements
    /// produced by the iterator. If there are fewer than `n` elements
    /// remaining, it will return as many as are available.
    ///
    /// - Parameter n: The number of elements to retrieve from the iterator.
    /// - Returns: An array containing up to `n` elements retrieved from the iterator.
    mutating func next(n: Int) -> [Self.Element] {
        var values: [Self.Element] = []
        
        // Retrieve the next `n` elements
        for _ in 0..<n {
            if let v = self.next() {
                values.append(v)
            }
        }
        
        return values
    }
    
    /// Groups the elements produced by the iterator into arrays of size `n`.
    ///
    /// This method returns an array of arrays, where each inner array contains
    /// up to `n` elements retrieved from the iterator. The method will continue
    /// grouping elements until there are no more elements left to retrieve.
    ///
    /// - Parameter n: The size of each group of elements.
    /// - Returns: An array of arrays, each containing up to `n` elements
    ///            from the iterator.
    mutating func groups(n: Int) -> [[Self.Element]] {
        var values: [[Self.Element]] = []
        
        while true {
            let group = self.next(n: n)
            
            // If the group has elements, add it to the values
            if group.count > 0 {
                values.append(group)
            }
            
            // If the group has fewer than `n` elements, stop retrieving
            if group.count != n {
                return values
            }
        }
    }
}
