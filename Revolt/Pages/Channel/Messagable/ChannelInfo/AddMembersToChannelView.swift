//
//  AddMembersToChannelView.swift
//  Revolt
//
//

import SwiftUI

import Foundation
import SwiftUI
import Types

struct AddMembersToChannelView: View {
    
    @EnvironmentObject var viewState: ViewState
    @Binding var channel: Channel
    @State var selectedUsers: Set<User> = Set()
    @State private var createBtnState : ComponentState = .disabled
    
    @State private var search: String = ""
    @State private var searchTextFieldState : PeptideTextFieldState = .default
    
    
    private var membersCountView : AnyView {
        AnyView(
            
            PeptideText(text: selectedUsers.count == 0 ? "" : "\(selectedUsers.count) Members",
                        font: .peptideButton,
                        textColor: .textGray07,
                        alignment: .center)
        )
    }
    
    private var groupedFriends: [String: [UserWithStatus]] {
        let friends = viewState.users.values.filter { $0.relationship == .Friend }
        let channelUsers = Set(getUsers.map { $0.user.id })
        
        let filteredFriends = search.isEmpty ? friends : friends.filter {
            $0.username.localizedCaseInsensitiveContains(search) ||
            ($0.display_name?.localizedCaseInsensitiveContains(search) ?? false)
        }
        
        let friendsWithStatus = filteredFriends.map { friend in
            UserWithStatus(user: friend, isDisabled: channelUsers.contains(friend.id))
        }
        
        return Dictionary(grouping: friendsWithStatus) { String($0.user.username.prefix(1)).uppercased() }
            .sorted { $0.key < $1.key }
            .reduce(into: [:]) { $0[$1.key] = $1.value }
    }
    
    
    private var  getUsers : [UserMaybeMember] {
        
        let users: [UserMaybeMember]
        
        switch channel {
        case .saved_messages(_):
            users = [UserMaybeMember(user: viewState.currentUser!)]
            
        case .dm_channel(let dMChannel):
            users =  dMChannel.recipients.map { UserMaybeMember(user: viewState.users[$0]!) }
            
        case .group_dm_channel(let groupDMChannel):
            users =  groupDMChannel.recipients.map { UserMaybeMember(user: viewState.users[$0]!) }
            
        case .text_channel(_), .voice_channel(_):
            users =  viewState.members[channel.server!]!.values.compactMap {
                if let user = viewState.users[$0.id.user], user.status != nil, user.status?.presence != nil, user.status?.presence != .Invisible {
                    return UserMaybeMember(user: user, member: $0)
                } else {
                    return nil
                }
            }
        }
        
        return users
    }
    
    
    
    private func addMembersToChannel() {
        
        Task {
            
            var success : Bool = false
            createBtnState = .loading
            
            await withTaskGroup(of: Void.self) { group in
                for user in selectedUsers {
                    group.addTask {
                        let result = await viewState.http.addMemberToGroup(groupId: channel.id, memberId: user.id)
                        
                        switch result {
                        case .success:
                            print("User \(user.id) added successfully")
                            success = true
                        case .failure(let error):
                            print("Failed to add user \(user.id): \(error)")
                        }
                    }
                }
                
                await group.waitForAll()
                createBtnState = .default
                
                if success {
                    viewState.path.removeLast()
                }
                
                
            }
            
            
            
            /*createBtnState = .loading
             let res = await viewState.http.createGroup(name: groupName, users: selectedUsers.map(\.id))
             createBtnState = .default
             
             switch res {
             case .success(let c):
             viewState.channels[c.id] = c
             viewState.channelMessages[c.id] = []
             viewState.currentChannel = .channel(c.id)
             viewState.path = NavigationPath()
             case .failure(_):
             // If the group creation fails, show an error message.
             let _ = "Failed to create group."
             
             }*/
        }
        
    }
    
    
    var body: some View {
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Add Members",
                                                 backButtonIcon: .peptideCloseLiner,
                                                 customToolbarView: membersCountView,
                                                 showBottomLine: true),
                            fixBottomView: AnyView(
                                HStack(spacing: .zero) {
                                    
                                    PeptideButton(title: "Add",
                                                  buttonState: createBtnState){
                                        addMembersToChannel()
                                    }
                                    
                                }
                                    .padding(.horizontal, .padding16)
                                    .padding(top: .padding8, bottom: .padding24)
                                    .background(Color.bgDefaultPurple13)
                            )
        ){_,_ in
            
            VStack {
                
                
                
                LazyVStack(spacing: .zero, pinnedViews: .sectionHeaders) {
                    
                    Section {
                        
                        if groupedFriends.isEmpty {
                            
                            VStack(spacing: .spacing4){
                                
                                Image(.peptideEmptySearch)
                                
                                
                                PeptideText(textVerbatim: "Nothing Matches Your Search",
                                            font: .peptideHeadline,
                                            textColor: .textDefaultGray01)
                                
                                PeptideText(textVerbatim: "Make sure the text is correct or try other terms.",
                                            font: .peptideHeadline,
                                            textColor: .textGray07)
                                
                            }
                            .padding(.vertical, .padding24)
                            .padding(.horizontal, .padding16)
                            
                        } else {
                            ForEach(groupedFriends.keys.sorted(), id: \.self) { key in
                                Section(header: HStack(spacing: .zero) {
                                    
                                    PeptideText(text: key,
                                                font: .peptideHeadline,
                                                textColor: .textDefaultGray01)
                                    
                                    Spacer(minLength: .zero)
                                    
                                    
                                }
                                    .padding(top: .padding16, bottom: .padding8, leading: .padding8, trailing: .padding8)) {
                                        ForEach(groupedFriends[key] ?? []) { friendWithStatus in
                                            
                                            let user = friendWithStatus.user
                                            
                                            HStack(spacing: .spacing8) {
                                                Avatar(user: user,
                                                       width: .size40,
                                                       height: .size40,
                                                       withPresence: false)
                                                
                                                VStack(alignment: .leading, spacing: .zero){
                                                    
                                                    PeptideText(text: user.display_name ?? user.username,
                                                                font: .peptideCallout,
                                                                textColor: .textDefaultGray01)
                                                    
                                                    
                                                    let isOnline = user.online == true
                                                    PeptideText(text: isOnline ?  (user.status?.presence?.rawValue ?? Presence.Online.rawValue) : "Offline",
                                                                font: .peptideCaption1,
                                                                textColor: .textGray07)
                                                    
                                                    
                                                }
                                                
                                                
                                                Spacer(minLength: .zero)
                                                
                                                let binding = Binding(
                                                    // Determine if the user is selected or not.
                                                    get: { selectedUsers.contains(user) || friendWithStatus.isDisabled },
                                                    // Add or remove the user from the selection set based on the toggle.
                                                    set: { v in
                                                        if v {
                                                            if selectedUsers.count < 99 {
                                                                selectedUsers.insert(user)
                                                            }
                                                            createBtnState = .default
                                                        } else {
                                                            selectedUsers.remove(user)
                                                            if selectedUsers.isEmpty {
                                                                createBtnState = .disabled
                                                            } else {
                                                                createBtnState = .default
                                                            }
                                                        }
                                                    }
                                                )
                                                
                                                Toggle("", isOn: binding)
                                                    .toggleStyle(PeptideCheckToggleStyle())
                                                
                                                
                                                
                                                
                                            }
                                            .padding(.padding8)
                                            .padding(.horizontal, .padding4)
                                            .background(Color.bgGray11)
                                            .cornerRadius(.radius8)
                                            .opacity(friendWithStatus.isDisabled ? 0.4 : 1.0)
                                            .padding(.bottom, .padding8)
                                            
                                        }
                                    }
                            }

                        }
                        
                        
                        Spacer(minLength: .zero)
                        
                        
                    } header: {
                        PeptideTextField(text: $search,
                                         state: $searchTextFieldState,
                                         placeholder: "Search in the friends list",
                                         icon: .peptideSearch,
                                         cornerRadius: .radiusLarge,
                                         height: .size40,
                                         keyboardType: .default)
                        .onChange(of: search){_, newQuery in
                            //selectedUsers = []
                            //createBtnState = .disabled
                        }
                        .padding(.top, .padding8)
                        .padding(.vertical, .padding8)
                        .background(Color.bgDefaultPurple13)
                    }
                    
                }
                
                Spacer()
                
                
            }
            
            .padding(.horizontal, .padding16)
            
        }
        
    }
}

struct UserWithStatus: Identifiable {
    let user: User
    let isDisabled: Bool
    
    var id: String { user.id }
}

#Preview {
    
    
    let viewState = ViewState.preview()
    
    return AddMembersToChannelView(channel: .constant(viewState.channels["0"]!))
        .applyPreviewModifiers(withState: viewState)
    
}
