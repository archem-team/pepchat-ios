//
//  ModelMappers.swift
//  Revolt
//
//  Created by L-MAN on 2/12/25.
//

import Foundation
import RealmSwift
import Types

/// Main class for coordinating all model mappings between original types and Realm objects
class ModelMappers {
    
    // MARK: - Singleton
    static let shared = ModelMappers()
    private init() {}
    
    // MARK: - Conversion Methods
    
    /// Convert any supported type to its Realm equivalent
    func toRealm<T, R>(_ original: T) -> R? {
        switch original {
        // API Types
        case let obj as CaptchaFeature: return obj.toRealm() as? R
        case let obj as RevoltFeature: return obj.toRealm() as? R
        case let obj as VortexFeature: return obj.toRealm() as? R
        case let obj as ApiFeatures: return obj.toRealm() as? R
        case let obj as ApiInfo: return obj.toRealm() as? R
        case let obj as Session: return obj.toRealm() as? R
            
        // User Types
        case let obj as UserBot: return obj.toRealm() as? R
        case let obj as Status: return obj.toRealm() as? R
        case let obj as UserRelation: return obj.toRealm() as? R
        case let obj as Profile: return obj.toRealm() as? R
		case let obj as Types.User: return obj.toRealm() as? R
            
        // File Types
        case let obj as SizedMetadata: return obj.toRealm() as? R
        case let obj as SimpleMetadata: return obj.toRealm() as? R
        case let obj as FileMetadata: return obj.toRealm() as? R
        case let obj as File: return obj.toRealm() as? R
            
        // Permission Types
        case let obj as UserPermissions: return obj.toRealm() as? R
        case let obj as Permissions: return obj.toRealm() as? R
        case let obj as Overwrite: return obj.toRealm() as? R
            
        // Channel Types
        case let obj as VoiceInformation: return obj.toRealm() as? R
        case let obj as SavedMessages: return obj.toRealm() as? R
        case let obj as DMChannel: return obj.toRealm() as? R
        case let obj as GroupDMChannel: return obj.toRealm() as? R
        case let obj as TextChannel: return obj.toRealm() as? R
        case let obj as VoiceChannel: return obj.toRealm() as? R
        case let obj as Channel: return obj.toRealm() as? R
            
        // Server Types
        case let obj as ServerFlags: return obj.toRealm() as? R
        case let obj as SystemMessages: return obj.toRealm() as? R
		case let obj as Types.Category: return obj.toRealm() as? R
        case let obj as Role: return obj.toRealm() as? R
        case let obj as Server: return obj.toRealm() as? R
        case let obj as MemberId: return obj.toRealm() as? R
        case let obj as Member: return obj.toRealm() as? R
            
        // Message Types
        case let obj as Interactions: return obj.toRealm() as? R
        case let obj as Masquerade: return obj.toRealm() as? R
        case let obj as TextSystemMessageContent: return obj.toRealm() as? R
        case let obj as UserAddedSystemContent: return obj.toRealm() as? R
        case let obj as UserRemovedSystemContent: return obj.toRealm() as? R
        case let obj as UserJoinedSystemContent: return obj.toRealm() as? R
        case let obj as UserLeftSystemContent: return obj.toRealm() as? R
        case let obj as UserKickedSystemContent: return obj.toRealm() as? R
        case let obj as UserBannedSystemContent: return obj.toRealm() as? R
        case let obj as ChannelRenamedSystemContent: return obj.toRealm() as? R
        case let obj as ChannelDescriptionChangedSystemContent: return obj.toRealm() as? R
        case let obj as ChannelIconChangedSystemContent: return obj.toRealm() as? R
        case let obj as ChannelOwnershipChangedSystemContent: return obj.toRealm() as? R
        case let obj as MessagePinnedSystemContent: return obj.toRealm() as? R
        case let obj as SystemMessageContent: return obj.toRealm() as? R
        case let obj as MessageWebhook: return obj.toRealm() as? R
        case let obj as Message: return obj.toRealm() as? R
            
        // Embed Types
        case let obj as YoutubeSpecial: return obj.toRealm() as? R
        case let obj as TwitchSpecial: return obj.toRealm() as? R
        case let obj as SpotifySpecial: return obj.toRealm() as? R
        case let obj as SoundcloudSpecial: return obj.toRealm() as? R
        case let obj as BandcampSpecial: return obj.toRealm() as? R
        case let obj as LightspeedSpecial: return obj.toRealm() as? R
        case let obj as StreamableSpecial: return obj.toRealm() as? R
        case let obj as WebsiteSpecial: return obj.toRealm() as? R
        case let obj as JanuaryImage: return obj.toRealm() as? R
        case let obj as JanuaryVideo: return obj.toRealm() as? R
        case let obj as WebsiteEmbed: return obj.toRealm() as? R
        case let obj as TextEmbed: return obj.toRealm() as? R
        case let obj as Embed: return obj.toRealm() as? R
            
        // Other Types
        case let obj as EmojiParentServer: return obj.toRealm() as? R
        case let obj as EmojiParentDetached: return obj.toRealm() as? R
        case let obj as EmojiParent: return obj.toRealm() as? R
        case let obj as Emoji: return obj.toRealm() as? R
        case let obj as Bot: return obj.toRealm() as? R
        case let obj as ServerInvite: return obj.toRealm() as? R
        case let obj as GroupInvite: return obj.toRealm() as? R
        case let obj as Invite: return obj.toRealm() as? R
        case let obj as ServerChannel: return obj.toRealm() as? R
            
        default:
            return nil
        }
    }
    
    /// Convert any supported Realm type to its original equivalent
    func toOriginal<T, R>(_ realmObject: T) -> R? {
        switch realmObject {
        // API Types
        case let obj as CaptchaFeatureRealm: return obj.toOriginal() as? R
        case let obj as RevoltFeatureRealm: return obj.toOriginal() as? R
        case let obj as VortexFeatureRealm: return obj.toOriginal() as? R
        case let obj as ApiFeaturesRealm: return obj.toOriginal() as? R
        case let obj as ApiInfoRealm: return obj.toOriginal() as? R
        case let obj as SessionRealm: return obj.toOriginal() as? R
            
        // User Types
        case let obj as UserBotRealm: return obj.toOriginal() as? R
        case let obj as StatusRealm: return obj.toOriginal() as? R
        case let obj as UserRelationRealm: return obj.toOriginal() as? R
        case let obj as ProfileRealm: return obj.toOriginal() as? R
        case let obj as UserRealm: return obj.toOriginal() as? R
            
        // File Types
        case let obj as SizedMetadataRealm: return obj.toOriginal() as? R
        case let obj as SimpleMetadataRealm: return obj.toOriginal() as? R
        case let obj as FileMetadataRealm: return obj.toOriginal() as? R
        case let obj as FileRealm: return obj.toOriginal() as? R
            
        // Permission Types
        case let obj as UserPermissionsRealm: return obj.toOriginal() as? R
        case let obj as PermissionsRealm: return obj.toOriginal() as? R
        case let obj as OverwriteRealm: return obj.toOriginal() as? R
            
        // Channel Types
        case let obj as VoiceInformationRealm: return obj.toOriginal() as? R
        case let obj as SavedMessagesRealm: return obj.toOriginal() as? R
        case let obj as DMChannelRealm: return obj.toOriginal() as? R
        case let obj as GroupDMChannelRealm: return obj.toOriginal() as? R
        case let obj as TextChannelRealm: return obj.toOriginal() as? R
        case let obj as VoiceChannelRealm: return obj.toOriginal() as? R
        case let obj as ChannelRealm: return obj.toOriginal() as? R
            
        // Server Types
        case let obj as ServerFlagsRealm: return obj.toOriginal() as? R
        case let obj as SystemMessagesRealm: return obj.toOriginal() as? R
        case let obj as CategoryRealm: return obj.toOriginal() as? R
        case let obj as RoleRealm: return obj.toOriginal() as? R
        case let obj as ServerRealm: return obj.toOriginal() as? R
        case let obj as MemberIdRealm: return obj.toOriginal() as? R
        case let obj as MemberRealm: return obj.toOriginal() as? R
            
        // Message Types
        case let obj as InteractionsRealm: return obj.toOriginal() as? R
        case let obj as MasqueradeRealm: return obj.toOriginal() as? R
        case let obj as TextSystemMessageContentRealm: return obj.toOriginal() as? R
        case let obj as UserAddedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as UserRemovedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as UserJoinedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as UserLeftSystemContentRealm: return obj.toOriginal() as? R
        case let obj as UserKickedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as UserBannedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as ChannelRenamedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as ChannelDescriptionChangedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as ChannelIconChangedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as ChannelOwnershipChangedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as MessagePinnedSystemContentRealm: return obj.toOriginal() as? R
        case let obj as SystemMessageContentRealm: return obj.toOriginal() as? R
        case let obj as MessageWebhookRealm: return obj.toOriginal() as? R
        case let obj as MessageRealm: return obj.toOriginal() as? R
            
        // Embed Types
        case let obj as YoutubeSpecialRealm: return obj.toOriginal() as? R
        case let obj as TwitchSpecialRealm: return obj.toOriginal() as? R
        case let obj as SpotifySpecialRealm: return obj.toOriginal() as? R
        case let obj as SoundcloudSpecialRealm: return obj.toOriginal() as? R
        case let obj as BandcampSpecialRealm: return obj.toOriginal() as? R
        case let obj as LightspeedSpecialRealm: return obj.toOriginal() as? R
        case let obj as StreamableSpecialRealm: return obj.toOriginal() as? R
        case let obj as WebsiteSpecialRealm: return obj.toOriginal() as? R
        case let obj as JanuaryImageRealm: return obj.toOriginal() as? R
        case let obj as JanuaryVideoRealm: return obj.toOriginal() as? R
        case let obj as WebsiteEmbedRealm: return obj.toOriginal() as? R
        case let obj as TextEmbedRealm: return obj.toOriginal() as? R
        case let obj as EmbedRealm: return obj.toOriginal() as? R
            
        // Other Types
        case let obj as EmojiParentServerRealm: return obj.toOriginal() as? R
        case let obj as EmojiParentDetachedRealm: return obj.toOriginal() as? R
        case let obj as EmojiParentRealm: return obj.toOriginal() as? R
        case let obj as EmojiRealm: return obj.toOriginal() as? R
        case let obj as BotRealm: return obj.toOriginal() as? R
        case let obj as ServerInviteRealm: return obj.toOriginal() as? R
        case let obj as GroupInviteRealm: return obj.toOriginal() as? R
        case let obj as InviteRealm: return obj.toOriginal() as? R
        case let obj as ServerChannelRealm: return obj.toOriginal() as? R
            
        default:
            return nil
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Convert an array of objects to Realm objects
    func toRealmArray<T, R>(_ originalArray: [T]) -> [R] {
        return originalArray.compactMap { toRealm($0) }
    }
    
    /// Convert an array of Realm objects to original objects
    func toOriginalArray<T, R>(_ realmArray: [T]) -> [R] {
        return realmArray.compactMap { toOriginal($0) }
    }
}
