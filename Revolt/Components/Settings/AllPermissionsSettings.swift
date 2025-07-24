//
//  AllPermissionsSettings.swift
//  Revolt
//
//  Created by Angelo on 25/09/2024.
//

import Foundation
import SwiftUI
import Types

struct PermissionSetting: View {
    var title: String
    var description: String
    var value: Permissions // Represents a specific permission
    
    @Binding var permissions: Overwrite // Binding to the current set of permissions
    
    // Custom binding to manage the state of a permission
    var customBinding: Binding<Bool?> {
        Binding {
            if permissions.a.contains(value) {
                return true // Permission granted
            } else if permissions.d.contains(value) {
                return false // Permission denied
            } else {
                return nil // Permission not set
            }
        } set: { newValue in
            var temp = permissions
            switch newValue {
                case .some(true):
                    temp.a.insert(value)
                    temp.d.remove(value)
                case .some(false):
                    temp.d.insert(value)
                    temp.a.remove(value)
                case .none:
                    temp.a.remove(value)
                    temp.d.remove(value)
            }
            permissions = temp

        }
    }
    
    var body: some View {
        PermissionToggle(value: customBinding) {
            
            VStack(alignment: .leading, spacing: .zero){
                PeptideText(textVerbatim: title,
                            font: .peptideCallout,
                            textColor: .textDefaultGray01)
                
                PeptideText(textVerbatim: description,
                            font: .peptideFootnote,
                            textColor: .textGray06,
                            alignment: .leading)
            }
        }
        //.padding(.horizontal, .padding16)
    }
}

struct AllPermissionSettings: View {
    enum RolePermissions {
        case role(Binding<Overwrite>) // Binding for role-specific permissions
        case defaultRole(Binding<Permissions>) // Binding for default role permissions
    }
    
    var permissions: RolePermissions // Current permissions context
    var filter: Permissions = .all // Filter for which permissions to display
    
    var body: some View {
        ForEach(Array(filter.makeIterator()), id: \.self) { perm in
            switch permissions {
            case .role(let binding):
                PermissionSetting(title: perm.name, description: perm.description, value: perm, permissions: binding)
                
                //if perm != .connect {
                    PeptideDivider(backgrounColor: .borderGray12)
                        .padding(.trailing, 28 * 3)
                        .padding(.vertical, .padding12)
                //}
                
            case .defaultRole(let binding):
                
                HStack(spacing: .spacing8){
                    
                    VStack(alignment: .leading){
                        PeptideText(textVerbatim: perm.name,
                                    font: .peptideCallout,
                                    textColor: .textDefaultGray01)
                        
                        PeptideText(textVerbatim: perm.description,
                                    font: .peptideFootnote,
                                    textColor: .textGray06,
                                    alignment: .leading)
                    }
                    
                    Spacer(minLength: .zero)
                    
                    Toggle("",
                           isOn: Binding {
                            binding.wrappedValue.contains(perm) // Check if permission is granted
                    } set: { isOn in
                        
                        if isOn {
                            binding.wrappedValue.insert(perm) // Grant permission
                        } else {
                            binding.wrappedValue.remove(perm) // Revoke permission
                        }
                        
                    })
                    .toggleStyle(PeptideSwitchToggleStyle())
                }
                
                //if perm != .react {
                    PeptideDivider(backgrounColor: .borderGray12)
                        .padding(.trailing, 48 + 8)
                        .padding(.vertical, .padding12)
                //}
                
                
            }
        }
    }
}
