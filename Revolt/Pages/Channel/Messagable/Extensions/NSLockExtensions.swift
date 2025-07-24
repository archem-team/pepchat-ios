//
//  NSLockExtensions.swift
//  Revolt
//
//

import Foundation

// MARK: - NSLock Extension for withLock
extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        self.lock()
        defer { self.unlock() }
        return operation()
    }
}

