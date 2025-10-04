//
//  EmbedModels.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - YouTube Special Realm Object

class YoutubeSpecialRealm: Object {
    @Persisted var id: String = ""
    @Persisted var timestamp: String?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Twitch Special Realm Object

class TwitchSpecialRealm: Object {
    @Persisted var content_type: String = "" // "Channel", "Video", "Clip"
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Spotify Special Realm Object

class SpotifySpecialRealm: Object {
    @Persisted var content_type: String = ""
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Soundcloud Special Realm Object

class SoundcloudSpecialRealm: Object {
    @Persisted var placeholder: Bool = true
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Bandcamp Special Realm Object

class BandcampSpecialRealm: Object {
    @Persisted var content_type: String = ""
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Lightspeed Special Realm Object

class LightspeedSpecialRealm: Object {
    @Persisted var content_type: String = ""
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Streamable Special Realm Object

class StreamableSpecialRealm: Object {
    @Persisted var id: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - WebsiteSpecial Realm Object

class WebsiteSpecialRealm: Object {
    @Persisted var type: String = ""
    
    @Persisted var youtubeSpecial: YoutubeSpecialRealm?
    @Persisted var twitchSpecial: TwitchSpecialRealm?
    @Persisted var spotifySpecial: SpotifySpecialRealm?
    @Persisted var soundcloudSpecial: SoundcloudSpecialRealm?
    @Persisted var bandcampSpecial: BandcampSpecialRealm?
    @Persisted var lightspeedSpecial: LightspeedSpecialRealm?
    @Persisted var streamableSpecial: StreamableSpecialRealm?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - January Image Realm Object

class JanuaryImageRealm: Object {
    @Persisted var url: String = ""
    @Persisted var width: Int = 0
    @Persisted var height: Int = 0
    @Persisted var size: String = ""
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - January Video Realm Object

class JanuaryVideoRealm: Object {
    @Persisted var url: String = ""
    @Persisted var width: Int = 0
    @Persisted var height: Int = 0
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Website Embed Realm Object

class WebsiteEmbedRealm: Object {
    @Persisted var url: String?
    @Persisted var special: WebsiteSpecialRealm?
    @Persisted var title: String?
    @Persisted var embedDescription: String?
    @Persisted var image: JanuaryImageRealm?
    @Persisted var video: JanuaryVideoRealm?
    @Persisted var site_name: String?
    @Persisted var icon_url: String?
    @Persisted var colour: String?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Text Embed Realm Object

class TextEmbedRealm: Object {
    @Persisted var icon_url: String?
    @Persisted var url: String?
    @Persisted var title: String?
    @Persisted var embedDescription: String?
    @Persisted var media: FileRealm?
    @Persisted var colour: String?
    
    override static func primaryKey() -> String? {
        return nil
    }
}

// MARK: - Embed Realm Object (Union Type)

class EmbedRealm: Object {
    @Persisted var type: String = ""
    
    @Persisted var websiteEmbed: WebsiteEmbedRealm?
    @Persisted var imageEmbed: JanuaryImageRealm?
    @Persisted var videoEmbed: JanuaryVideoRealm?
    @Persisted var textEmbed: TextEmbedRealm?
    
    override static func primaryKey() -> String? {
        return nil
    }
}
