//
//  DetachRealm.swift
//  Revolt
//
//  Created by L-MAN on 9/6/25.
//
// This file holds utilities for removing reference of the objects

import Foundation
import RealmSwift

protocol RealmListDetachable {
	
	func detached() -> Self
}

// MARK: Realm List
extension List: RealmListDetachable where Element: Object {
	
	/// Removes the reference from DB
	func detached() -> List<Element> {
		let detached = self.detached
		let result = List<Element>()
		result.append(objectsIn: detached)
		return result
	}
	
}

// MARK: Realm Object
@objc extension Object {
	
	/// Removes the reference from DB
	public func detached() -> Self {
		let detached = type(of: self).init()
		for property in objectSchema.properties {
			guard let value = value(forKey: property.name) else { continue }
			
			if let detachable = value as? Object {
				detached.setValue(detachable.detached(), forKey: property.name)
			} else if let list = value as? RealmListDetachable {
				detached.setValue(list.detached(), forKey: property.name)
			} else {
				detached.setValue(value, forKey: property.name)
			}
		}
		return detached
	}
}

extension Sequence where Iterator.Element: Object {
	
	public var detached: [Element] {
		return self.map({ $0.detached() })
	}
	
}
