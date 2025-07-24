//
//  OptionSet.swift
//  Revolt
//
//  Created by Angelo on 26/09/2024.
//

import Foundation

// Iterator for OptionSet types.
public struct OptionSetIterator<Element: OptionSet>: IteratorProtocol, Sequence where Element.RawValue == Int {
    private let value: Element
    
    public init(element: Element) {
        self.value = element
    }
    
    private lazy var remainingBits = value.rawValue
    private var bitMask = 1

    // Retrieve the next element in the option set.
    public mutating func next() -> Element? {
        while remainingBits != 0 {
            defer { bitMask = bitMask &* 2 } // Shift the bit mask left.
            if remainingBits & bitMask != 0 { // Check if the current bit is set.
                remainingBits = remainingBits & ~bitMask // Clear the bit.
                return Element(rawValue: bitMask) // Return the corresponding OptionSet element.
            }
        }
        return nil // No more bits set, end of iteration.
    }
}

// Extension to make OptionSet types iterable.
extension OptionSet where Self.RawValue == Int {
    public func makeIterator() -> OptionSetIterator<Self> {
        return OptionSetIterator(element: self)
    }
}

extension OptionSet where RawValue == Int {
    public func toArray() -> [Self] {
        var elements: [Self] = []
        var remainingBits = rawValue
        var bitMask = 1
        
        while remainingBits != 0 {
            if remainingBits & bitMask != 0 {
                elements.append(Self(rawValue: bitMask))
                remainingBits &= ~bitMask
            }
            bitMask = bitMask &* 2
        }
        
        return elements
    }
}
