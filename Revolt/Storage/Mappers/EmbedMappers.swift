//
//  EmbedMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

// MARK: - YouTube Special Mapper

extension YoutubeSpecial {
    func toRealm() -> YoutubeSpecialRealm {
        let realm = YoutubeSpecialRealm()
        realm.id = self.id
        realm.timestamp = self.timestamp
        return realm
    }
}

extension YoutubeSpecialRealm {
    func toOriginal() -> YoutubeSpecial {
        return YoutubeSpecial(id: self.id, timestamp: self.timestamp)
    }
}

// MARK: - Twitch Special Mapper

extension TwitchSpecial {
    func toRealm() -> TwitchSpecialRealm {
        let realm = TwitchSpecialRealm()
        realm.content_type = self.content_type.rawValue
        realm.id = self.id
        return realm
    }
}

extension TwitchSpecialRealm {
    func toOriginal() -> TwitchSpecial {
        return TwitchSpecial(
            content_type: TwitchSpecial.ContentType(rawValue: self.content_type)!,
            id: self.id
        )
    }
}

// MARK: - Spotify Special Mapper

extension SpotifySpecial {
    func toRealm() -> SpotifySpecialRealm {
        let realm = SpotifySpecialRealm()
        realm.content_type = self.content_type
        realm.id = self.id
        return realm
    }
}

extension SpotifySpecialRealm {
    func toOriginal() -> SpotifySpecial {
        return SpotifySpecial(content_type: self.content_type, id: self.id)
    }
}

// MARK: - Soundcloud Special Mapper

extension SoundcloudSpecial {
    func toRealm() -> SoundcloudSpecialRealm {
        return SoundcloudSpecialRealm()
    }
}

extension SoundcloudSpecialRealm {
    func toOriginal() -> SoundcloudSpecial {
        return SoundcloudSpecial()
    }
}

// MARK: - Bandcamp Special Mapper

extension BandcampSpecial {
    func toRealm() -> BandcampSpecialRealm {
        let realm = BandcampSpecialRealm()
        realm.content_type = self.content_type.rawValue
        realm.id = self.id
        return realm
    }
}

extension BandcampSpecialRealm {
    func toOriginal() -> BandcampSpecial {
        return BandcampSpecial(
            content_type: BandcampSpecial.ContentType(rawValue: self.content_type)!,
            id: self.id
        )
    }
}

// MARK: - Lightspeed Special Mapper

extension LightspeedSpecial {
    func toRealm() -> LightspeedSpecialRealm {
        let realm = LightspeedSpecialRealm()
        realm.content_type = self.content_type.rawValue
        realm.id = self.id
        return realm
    }
}

extension LightspeedSpecialRealm {
    func toOriginal() -> LightspeedSpecial {
        return LightspeedSpecial(
            content_type: LightspeedSpecial.ContentType(rawValue: self.content_type)!,
            id: self.id
        )
    }
}

// MARK: - Streamable Special Mapper

extension StreamableSpecial {
    func toRealm() -> StreamableSpecialRealm {
        let realm = StreamableSpecialRealm()
        realm.id = self.id
        return realm
    }
}

extension StreamableSpecialRealm {
    func toOriginal() -> StreamableSpecial {
        return StreamableSpecial(id: self.id)
    }
}

// MARK: - WebsiteSpecial Mapper

extension WebsiteSpecial {
    func toRealm() -> WebsiteSpecialRealm {
        let realm = WebsiteSpecialRealm()
        
        switch self {
        case .none:
            realm.type = "none"
        case .gif:
            realm.type = "gif"
        case .youtube(let youtubeSpecial):
            realm.type = "youtube"
            realm.youtubeSpecial = youtubeSpecial.toRealm()
        case .lightspeed(let lightspeedSpecial):
            realm.type = "lightspeed"
            realm.lightspeedSpecial = lightspeedSpecial.toRealm()
        case .twitch(let twitchSpecial):
            realm.type = "twitch"
            realm.twitchSpecial = twitchSpecial.toRealm()
        case .spotify(let spotifySpecial):
            realm.type = "spotify"
            realm.spotifySpecial = spotifySpecial.toRealm()
        case .soundcloud(let soundcloudSpecial):
            realm.type = "soundcloud"
            realm.soundcloudSpecial = soundcloudSpecial.toRealm()
        case .bandcamp(let bandcampSpecial):
            realm.type = "bandcamp"
            realm.bandcampSpecial = bandcampSpecial.toRealm()
        case .streamable(let streamableSpecial):
            realm.type = "streamable"
            realm.streamableSpecial = streamableSpecial.toRealm()
        }
        
        return realm
    }
}

extension WebsiteSpecialRealm {
    func toOriginal() -> WebsiteSpecial {
        switch self.type {
        case "none":
            return .none
        case "gif":
            return .gif
        case "youtube":
            return .youtube(self.youtubeSpecial!.toOriginal())
        case "lightspeed":
            return .lightspeed(self.lightspeedSpecial!.toOriginal())
        case "twitch":
            return .twitch(self.twitchSpecial!.toOriginal())
        case "spotify":
            return .spotify(self.spotifySpecial!.toOriginal())
        case "soundcloud":
            return .soundcloud(self.soundcloudSpecial!.toOriginal())
        case "bandcamp":
            return .bandcamp(self.bandcampSpecial!.toOriginal())
        case "streamable":
            return .streamable(self.streamableSpecial!.toOriginal())
        default:
            return .none
        }
    }
}

// MARK: - January Image Mapper

extension JanuaryImage {
    func toRealm() -> JanuaryImageRealm {
        let realm = JanuaryImageRealm()
        realm.url = self.url
        realm.width = self.width
        realm.height = self.height
        realm.size = self.size.rawValue
        return realm
    }
}

extension JanuaryImageRealm {
    func toOriginal() -> JanuaryImage {
        return JanuaryImage(
            url: self.url,
            width: self.width,
            height: self.height,
            size: JanuaryImage.Size(rawValue: self.size)!
        )
    }
}

// MARK: - January Video Mapper

extension JanuaryVideo {
    func toRealm() -> JanuaryVideoRealm {
        let realm = JanuaryVideoRealm()
        realm.url = self.url
        realm.width = self.width
        realm.height = self.height
        return realm
    }
}

extension JanuaryVideoRealm {
    func toOriginal() -> JanuaryVideo {
        return JanuaryVideo(url: self.url, width: self.width, height: self.height)
    }
}

// MARK: - Website Embed Mapper

extension WebsiteEmbed {
    func toRealm() -> WebsiteEmbedRealm {
        let realm = WebsiteEmbedRealm()
        realm.url = self.url
        realm.special = self.special?.toRealm()
        realm.title = self.title
        realm.embedDescription = self.description
        realm.image = self.image?.toRealm()
        realm.video = self.video?.toRealm()
        realm.site_name = self.site_name
        realm.icon_url = self.icon_url
        realm.colour = self.colour
        return realm
    }
}

extension WebsiteEmbedRealm {
    func toOriginal() -> WebsiteEmbed {
        return WebsiteEmbed(
            url: self.url,
            special: self.special?.toOriginal(),
            title: self.title,
            description: self.embedDescription,
            image: self.image?.toOriginal(),
            video: self.video?.toOriginal(),
            site_name: self.site_name,
            icon_url: self.icon_url,
            colour: self.colour
        )
    }
}

// MARK: - Text Embed Mapper

extension TextEmbed {
    func toRealm() -> TextEmbedRealm {
        let realm = TextEmbedRealm()
        realm.icon_url = self.icon_url
        realm.url = self.url
        realm.title = self.title
        realm.embedDescription = self.description
        realm.media = self.media?.toRealm()
        realm.colour = self.colour
        return realm
    }
}

extension TextEmbedRealm {
    func toOriginal() -> TextEmbed {
        return TextEmbed(
            icon_url: self.icon_url,
            url: self.url,
            title: self.title,
            description: self.embedDescription,
            media: self.media?.toOriginal(),
            colour: self.colour
        )
    }
}

// MARK: - Embed Mapper

extension Embed {
    func toRealm() -> EmbedRealm {
        let realm = EmbedRealm()
        
        switch self {
        case .website(let websiteEmbed):
            realm.type = "website"
            realm.websiteEmbed = websiteEmbed.toRealm()
        case .image(let januaryImage):
            realm.type = "image"
            realm.imageEmbed = januaryImage.toRealm()
        case .video(let januaryVideo):
            realm.type = "video"
            realm.videoEmbed = januaryVideo.toRealm()
        case .text(let textEmbed):
            realm.type = "text"
            realm.textEmbed = textEmbed.toRealm()
        case .none:
            realm.type = "none"
        }
        
        return realm
    }
}

extension EmbedRealm {
    func toOriginal() -> Embed {
        switch self.type {
        case "website":
            return .website(self.websiteEmbed!.toOriginal())
        case "image":
            return .image(self.imageEmbed!.toOriginal())
        case "video":
            return .video(self.videoEmbed!.toOriginal())
        case "text":
            return .text(self.textEmbed!.toOriginal())
        case "none":
            return .none
        default:
            return .none
        }
    }
}
