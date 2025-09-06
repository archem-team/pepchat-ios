//
//  FileModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - SizedMetadata Realm Object

class SizedMetadataRealm: Object {
    @Persisted var height: Int = 0
    @Persisted var width: Int = 0
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - SimpleMetadata Realm Object

class SimpleMetadataRealm: Object {
    // Empty structure, can be expanded in the future
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - FileMetadata Realm Object

class FileMetadataRealm: Object {
    @Persisted var type: String = "" // "image", "video", "file", "text", "audio"
    @Persisted var sizedMetadata: SizedMetadataRealm?
    @Persisted var simpleMetadata: SimpleMetadataRealm?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - File Realm Object

class FileRealm: Object {
    @Persisted var id: String = ""
    @Persisted var tag: String = ""
    @Persisted var size: Int64 = 0
    @Persisted var filename: String = ""
    @Persisted var metadata: FileMetadataRealm?
    @Persisted var content_type: String = ""
    
    override static func primaryKey() -> String? {
        return "id"
    }
}
