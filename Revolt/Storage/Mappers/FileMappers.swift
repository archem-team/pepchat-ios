//
//  FileMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - SizedMetadata Mapper

extension SizedMetadata {
    func toRealm() -> SizedMetadataRealm {
        let realm = SizedMetadataRealm()
        realm.height = self.height
        realm.width = self.width
        return realm
    }
}

extension SizedMetadataRealm {
    func toOriginal() -> SizedMetadata {
        return SizedMetadata(height: self.height, width: self.width)
    }
}

// MARK: - SimpleMetadata Mapper

extension SimpleMetadata {
    func toRealm() -> SimpleMetadataRealm {
        return SimpleMetadataRealm()
    }
}

extension SimpleMetadataRealm {
    func toOriginal() -> SimpleMetadata {
        return SimpleMetadata()
    }
}

// MARK: - FileMetadata Mapper

extension FileMetadata {
    func toRealm() -> FileMetadataRealm {
        let realm = FileMetadataRealm()
        
        switch self {
        case .image(let sizedMetadata):
            realm.type = "image"
            realm.sizedMetadata = sizedMetadata.toRealm()
        case .video(let sizedMetadata):
            realm.type = "video"
            realm.sizedMetadata = sizedMetadata.toRealm()
        case .file(let simpleMetadata):
            realm.type = "file"
            realm.simpleMetadata = simpleMetadata.toRealm()
        case .text(let simpleMetadata):
            realm.type = "text"
            realm.simpleMetadata = simpleMetadata.toRealm()
        case .audio(let simpleMetadata):
            realm.type = "audio"
            realm.simpleMetadata = simpleMetadata.toRealm()
        }
        
        return realm
    }
}

extension FileMetadataRealm {
    func toOriginal() -> FileMetadata {
        switch self.type {
        case "image":
            return .image(self.sizedMetadata!.toOriginal())
        case "video":
            return .video(self.sizedMetadata!.toOriginal())
        case "file":
            return .file(self.simpleMetadata!.toOriginal())
        case "text":
            return .text(self.simpleMetadata!.toOriginal())
        case "audio":
            return .audio(self.simpleMetadata!.toOriginal())
        default:
            return .file(SimpleMetadata()) // fallback
        }
    }
}

// MARK: - File Mapper

extension File {
    func toRealm() -> FileRealm {
        let realm = FileRealm()
        realm.id = self.id
        realm.tag = self.tag
        realm.size = self.size
        realm.filename = self.filename
        realm.metadata = self.metadata.toRealm()
        realm.content_type = self.content_type
        return realm
    }
}

extension FileRealm {
    func toOriginal() -> File {
        return File(
            id: self.id,
            tag: self.tag,
            size: self.size,
            filename: self.filename,
            metadata: self.metadata!.toOriginal(),
            content_type: self.content_type
        )
    }
}
