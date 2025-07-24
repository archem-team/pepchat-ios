//
//  Permissions.swift
//  Revolt
//
//  Created by Angelo on 18/11/2023.
//

import Foundation
import Types

/// Resolves the server permissions for a given user and member within a server.
///
/// This function checks if the user is either privileged or the owner of the server,
/// in which case they receive all permissions. If not, it calculates the user's permissions
/// based on their roles in the server and applies any role-specific permission overwrites.
/// Additionally, if the member is in a timeout, their permissions are restricted accordingly.
///
/// - Parameters:
///   - user: The `User` object representing the current user.
///   - member: The `Member` object representing the user in the server.
///   - server: The `Server` object containing the roles and default permissions.
/// - Returns: A `Permissions` object that represents the resolved permissions of the user in the server.
func resolveServerPermissions(user: User, member: Member, server: Server) -> Permissions {
    if user.privileged == true || server.owner == user.id {
        return Permissions.all
    }
    
    var permissions = server.default_permissions
    
    for role in member.roles?
        .compactMap({ server.roles?[$0] })
        .sorted(by: { $0.rank < $1.rank }) ?? []
    {
        permissions.formApply(overwrite: role.permissions)
    }
    
    if member.timeout != nil {
        permissions = permissions.intersection(Permissions.defaultAllowInTimeout)
    }

    return permissions
}

/// Resolves the permissions for a user targeting another user within a specific channel.
///
/// This function checks if the user or server owner has elevated privileges. Based on the channel type,
/// it resolves permissions differently:
/// - For direct messages or group channels, permissions depend on user roles and relationships.
/// - For text or voice channels, it applies server and role-based permissions, considering
///   any permission overwrites and the user's member status within the server.
///
/// - Parameters:
///   - from: The `User` object representing the current user initiating the action.
///   - targettingUser: The `User` object being targeted for permission resolution.
///   - targettingMember: An optional `Member` object for users who are part of a server.
///   - channel: The `Channel` object representing the channel being accessed.
///   - server: An optional `Server` object that represents the server the channel belongs to.
/// - Returns: A `Permissions` object representing the calculated permissions for the target user.
func resolveChannelPermissions(from: User, targettingUser user: User, targettingMember member: Member?, channel: Channel, server: Server?) -> Permissions {
    if user.privileged == true || server?.owner == user.id {
        return Permissions.all
    }
    
    switch channel {
        case .saved_messages(let savedMessages):
            if savedMessages.user == user.id {
                return Permissions.all
            } else {
                return Permissions.none
            }
        case .dm_channel(let dMChannel):
            if dMChannel.recipients.contains(user.id) {
                let userPermissions = resolveUserPermissions(from: from, targetting: user)
                
                /*if userPermissions.contains(UserPermissions.sendMessage) {
                    return Permissions.defaultDirectMessages
                } else {
                    return Permissions.defaultViewOnly
                }*/
                
                return Permissions.all
                
            } else {
                return Permissions.none
            }
        case .group_dm_channel(let groupDMChannel):
            if groupDMChannel.owner == user.id {
                return Permissions.all
            } else if groupDMChannel.recipients.contains(user.id) {
                //return Permissions.defaultViewOnly.union(groupDMChannel.permissions ?? Permissions.none)
                return Permissions.defaultViewOnly.union(groupDMChannel.permissions ?? Permissions.defaultGroupDirectMessages)
            } else {
                return Permissions.none
            }
        case .text_channel(let textChannel):
                
        if let server , member != nil {
            
            if server.owner == user.id {
                return Permissions.all
            }
            
            
            var permissions = resolveServerPermissions(user: user, member: member!, server: server)
            
            if let defaultPermissions = textChannel.default_permissions {
                permissions.formApply(overwrite: defaultPermissions)
            }
            
            
            //get roles containt in member roles
            let overwrites = textChannel.role_permissions?
                .compactMap({ (id, overwrite) in
                    
                    guard let role = server.roles?[id],
                          member?.roles?.contains(id) == true else {
                        return nil
                    }
                    
                    return (role, overwrite)
                })
                .sorted(by: { (a, b) in a.0.rank < b.0.rank})
                ?? ([] as [(Role, Overwrite)])
            
                        
            for (_, overwrite) in overwrites {
                permissions.formApply(overwrite: overwrite)
            }
            
            
            if member!.timeout != nil {
                permissions.formIntersection(Permissions.defaultAllowInTimeout)
            }
            
            if !permissions.contains(Permissions.viewChannel) {
                permissions = Permissions.none
            }
                        
            return permissions
            
        }else{
            return Permissions(rawValue: 0)
        }
        
            
        case .voice_channel(let voiceChannel):
            if server!.owner == user.id {
                return Permissions.all
            }
            
            var permissions = resolveServerPermissions(user: user, member: member!, server: server!)
            
            if let defaultPermissions = voiceChannel.default_permissions {
                permissions.formApply(overwrite: defaultPermissions)
            }
            
            let overwrites = voiceChannel.role_permissions?
                        .compactMap({ (id, perm) in server?.roles?[id].map { role in (role, perm) } })
                        .sorted(by: {$0.0.rank < $1.0.rank}) ?? []
        
            for (_, overwrite) in overwrites {
                permissions.formApply(overwrite: overwrite)
            }
            
            if member!.timeout != nil {
                permissions.formIntersection(Permissions.defaultAllowInTimeout)
            }
            
            if !permissions.contains(Permissions.viewChannel) {
                permissions = Permissions.none
            }
            
            return permissions
    }
}

/// Resolves the user-level permissions between two users based on their relationship.
///
/// This function calculates the permissions the `from` user has when interacting with the `targetting` user,
/// based on their relationship status (e.g., friend, blocked, etc.) and whether either user is a bot.
///
/// - Parameters:
///   - from: The `User` object representing the user initiating the action.
///   - targetting: The `User` object being targeted for permission resolution.
/// - Returns: A `UserPermissions` object representing the calculated permissions.
func resolveUserPermissions(from: User, targetting: User) -> UserPermissions {
    if from.privileged == true {
        return UserPermissions.all
    }
    
    if from.id == targetting.id {
        return UserPermissions.all
    }
    
    var permissions = UserPermissions.none
    
    // Resolve permissions based on relationship
    switch targetting.relationship {
        case .Blocked, .BlockedOther:
            return UserPermissions.access
        case .Friend:
            return UserPermissions.all
        case .Incoming, .Outgoing:
            permissions = UserPermissions.access.union(UserPermissions.viewProfile)
        default:
            ()
    }
    
    // Allow messaging if either user is a bot
    if from.bot != nil || targetting.bot != nil {
        permissions = permissions.union(UserPermissions.sendMessage)
    }
    
    return permissions
}
