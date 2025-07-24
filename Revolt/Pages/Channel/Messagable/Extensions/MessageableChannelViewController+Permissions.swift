//
//  MessageableChannelViewController+Permissions.swift
//  Revolt
//
//

import UIKit
import Types

extension MessageableChannelViewController {
    
    // MARK: - Permission Properties
    
    var sendMessagePermission: Bool {
        return permissionsManager.sendMessagePermission
    }
    
    // MARK: - Permission Methods
    
    func userHasPermission(_ permission: Types.Permissions) -> Bool {
        return permissionsManager.userHasPermission(permission)
    }
    
    func userHasPermissions(_ permissions: Types.Permissions) -> Bool {
        return permissionsManager.userHasPermissions(permissions)
    }
    
    func configureUIBasedOnPermissions() {
        permissionsManager.configureUIBasedOnPermissions()
    }
}

