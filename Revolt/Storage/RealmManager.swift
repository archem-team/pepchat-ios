//
//  RealmManager.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import OSLog

actor RealmManager {
    
    // MARK: - Properties
    static let shared = RealmManager()
    
    static let version: UInt64 = 1
        
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "Revolt", category: "RealmManager")
    
    // Returns a Realm instance for the current thread
    private var realmInstance: Realm? {
        do {
            return try Realm()
        } catch {
            let error = NSError(domain: "RealmManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Realm database initialization failed",
                "error": error.localizedDescription,
                "context": "Initializing Realm instance",
                "schemaVersion": Self.version
            ])
            logger.error("Failed to initialize Realm: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Methods
    static func configure() {
        let logger = Logger(subsystem: "Revolt", category: "RealmManager")
        
        let config = Realm.Configuration(
            schemaVersion: version,
            migrationBlock: { migration, oldSchemaVersion in
                logger.info("Performing Realm migration from version \(oldSchemaVersion) to \(version)")
                if oldSchemaVersion < 1 {
                    // Handle migration if needed
                }
            },
            deleteRealmIfMigrationNeeded: false
        )
        Realm.Configuration.defaultConfiguration = config
    }
    
    // MARK: - Write Operations
    
    /// Saves or updates a single object in Realm
    func write<T: Object>(_ object: T) {
        performWrite { realm in
            realm.add(object, update: .modified)
        }
    }
    
    /// Saves or updates multiple objects in Realm
    func writeBatch<T: Object>(_ objects: [T]) {
        performWrite { realm in
            realm.add(objects, update: .modified)
        }
    }
    
    /// Performs an update on existing objects
    func update(_ block: @escaping () -> Void) {
        performWrite { _ in block() }
    }
    
    // MARK: - Read Operations
    
    /// Fetches all objects of a given type
    func fetch<T: Object>(_ type: T.Type) -> Results<T>? {
        do {
            let realm = try Realm()
            return realm.objects(type)
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetches the first object of a given type
    func fetchFirst<T: Object>(_ type: T.Type) -> T? {
        return fetch(type)?.first
    }
    
    /// Fetches objects of a given type that match a predicate
    func fetchFiltered<T: Object>(_ type: T.Type, filter: (T) -> Bool) -> [T]? {
        fetch(type)?.filter(filter)
    }
    
    /// Fetches first object with given primary key
    func fetchItemByPrimaryKey<T: Object>(_ type: T.Type, primaryKey: Any) -> T? {
        do {
            let realm = try Realm()
            return realm.object(ofType: type, forPrimaryKey: primaryKey)
        } catch {
            logger.error("Failed to fetch item by primary key: \(error.localizedDescription)")
            return nil
        }
    }

    
    // MARK: - Delete Operations
    
    /// Deletes a single object from Realm
    func delete<T: Object>(_ object: T) {
        performWrite { realm in
            if !object.isInvalidated {
                realm.delete(object)
            } else {
				self.logger.error("Attempted to delete an invalidated object")
            }
        }
    }
    
    /// Deletes all objects of a given type
    func deleteAll<T: Object>(_ type: T.Type) {
        performWrite { realm in
            if let objects = self.fetch(type) {
                realm.delete(objects)
            } else {
				self.logger.error("No objects found to delete for type \(T.self)")
            }
        }
    }
    
    /// Deletes an object using its primary key
    func deleteByPrimaryKey<T: Object, K>(_ type: T.Type, key: K) {
        do {
            let realm = try Realm()
            
            guard let object = realm.object(ofType: type, forPrimaryKey: key) else {
                logger.error("No object found with primary key for deletion")
                return
            }
            
            try realm.write {
                realm.delete(object)
            }
            
        } catch {
            logger.error("Failed to delete object by primary key: \(error.localizedDescription)")
        }
    }

    
    func clearCache() {
        performWrite { realm in
            realm.deleteAll()
        }
    }
    
    // MARK: - Batch Updates
    
    /// Adds or updates an object and notifies completion
    func updateOrAdd<T: Object>(_ data: T, completion: @escaping (Bool) -> Void) {
        Task {
            let result = await performWriteWithResult { realm in
                realm.add(data, update: .modified)
                return true
            }
            completion(result ?? false)
        }
    }
    
    /// Replaces existing objects with new ones, deleting old ones if needed
    func updateListWithDeletingOldObjects<T: Object>(
        _ objectList: [T],
        objectsToDelete: [T]? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        Task {
            let result = await performWriteWithResult { realm in
                let objectsToRemove = objectsToDelete ?? Array(realm.objects(T.self))
                realm.delete(objectsToRemove)
                realm.add(objectList, update: .modified)
                return true
            }
            completion(result ?? false)
        }
    }
    
    /// Retrieves a list of objects asynchronously
    func getListOfObjects<T: Object>(type: T.Type, completion: @escaping ([T]) -> Void) {
        Task.detached {
            do {
                let realm = try await Realm()
                let results = realm.objects(type)
                let safeCopy = Array(results.map { $0.detached() })
                await MainActor.run { completion(safeCopy) }
            } catch {
                await MainActor.run { completion([]) }
            }
        }
    }
    
    /// Retrieves the first object asynchronously
    func getFirstObject<T: Object>(type: T.Type, completion: @escaping (T?) -> Void) {
        Task {
            let result = fetchFirst(type)
            completion(result)
        }
    }
    
    /// Removes an object asynchronously
    func removeObject<T: Object>(_ object: T, completion: @escaping (Bool) -> Void) {
        Task {
            let result = await performWriteWithResult { realm in
                realm.delete(object)
                return true
            }
            completion(result ?? false)
        }
    }
    
    // MARK: - JSON Storage
    
    /// Reads raw JSON data stored in Realm
//    func readRawData(for path: String, completion: @escaping (String?) -> Void) {
//        Task {
//            guard !path.isEmpty else {
//                logger.error("Attempted to read raw data with empty path")
//                completion(nil)
//                return
//            }
//            
//            let rawData = fetchFiltered(RawDataLC.self) { $0.urlPath == path }?.first?.data
//            completion(rawData)
//        }
//    }
    
    /// Writes raw JSON data to Realm
//    func writeRawData(_ data: String, for path: String, completion: @escaping (Bool) -> Void) {
//        Task {
//            guard !path.isEmpty else {
//                logger.error("Attempted to write raw data with empty path")
//                completion(false)
//                return
//            }
//            
//            guard !data.isEmpty else {
//                logger.error("Attempted to write empty data for path: \(path)")
//                completion(false)
//                return
//            }
//            
//            let result = await performWriteWithResult { realm in
//                let rawData = RawDataLC()
//                rawData.urlPath = path
//                rawData.data = data
//                rawData.updatedAt = Date()
//                realm.add(rawData, update: .modified)
//                return true
//            }
//            completion(result ?? false)
//        }
//    }
    
    /// Creates an Object from a parent class and key
//    func createObject(fromLabel label: String, parentObject: Object) -> Object? {
//        let mirror = Mirror(reflecting: parentObject)
//        
//        for child in mirror.children {
//            guard let propertyLabel = child.label else { continue }
//            
//            if propertyLabel == "_\(label)", let objectTypeName = extractObjectTypeName(from: child.value) {
//                guard let modelType = DataBaseModelRegister(rawValue: objectTypeName) else {
//                    logger.error("Failed to create model type from \(objectTypeName)")
//                    return nil
//                }
//                return createRealmObject(named: modelType)
//            }
//        }
//        
//        logger.error("Failed to create object from label: \(label)")
//        return nil
//    }
    
    
    /// Resolves a ThreadSafeReference into a managed Realm object
    func resolve<T: Object>(_ reference: ThreadSafeReference<T>?) -> T? {
        guard let reference = reference else {
            logger.error("Failed to resolve nil reference")
            return nil
        }
        
        do {
            let realm = try Realm()
            
            guard let resolved = realm.resolve(reference) else {
                logger.error("Failed to resolve thread-safe reference")
                return nil
            }
            
            return resolved
            
        } catch {
            logger.error("Failed to resolve reference: Realm initialization failed - \(error.localizedDescription)")
            return nil
        }
    }

    
    /// Fetching Thread-Safe Reference
    func getThreadSafeReference<T: Object>(_ type: T.Type) -> ThreadSafeReference<T>? {
        guard let object = fetchFirst(type) else { 
            logger.error("Failed to get thread-safe reference: No object found")
            return nil 
        }
        return ThreadSafeReference(to: object)
    }
    
    // MARK: - Private Helper
    
    /// Performs a write operation on Realm
    private func performWrite(_ block: @escaping (Realm) -> Void) {
        do {
            let realm = try Realm()
            
            try realm.write {
                block(realm)
            }
            
        } catch {
            let error = NSError(domain: "RealmManager", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "Realm write transaction failed",
                "error": error.localizedDescription,
                "context": "Executing write transaction",
                "thread": Thread.current.name ?? "unknown"
            ])
            logger.error("Realm Write Error: \(error.localizedDescription)")
        }
    }

    
    /// Performs a write operation and returns a result
    private func performWriteWithResult<T>(_ block: @escaping (Realm) -> T) async -> T? {
        do {
            let realm = try await Realm()
            var result: T?
            
            try realm.write {
                result = block(realm)
            }
            
            return result
            
        } catch {
            let error = NSError(domain: "RealmManager", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "Realm write transaction failed",
                "error": error.localizedDescription,
                "context": "Executing write transaction",
                "thread": Thread.current.name ?? "unknown"
            ])
            logger.error("Realm Write Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func extractObjectTypeName(from value: Any) -> String? {
        let typeDescription = String(describing: type(of: value))
        let pattern = "<([^<>]+)>"
        
        var typeName = typeDescription
        while let range = typeName.range(of: pattern, options: .regularExpression) {
            typeName = String(typeName[range].dropFirst().dropLast())
        }
        
        if typeName.isEmpty {
            logger.error("Failed to extract type name from \(typeDescription)")
            return nil
        }
        
        return typeName
    }

}
