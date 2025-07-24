//
//  CreateGroupAddMembders.swift
//  Revolt
//
//

import Foundation
import SwiftUI
import Types

struct CreateGroupAddMembders: View {
    
    @EnvironmentObject var viewState: ViewState
    
    var groupName : String
    
    @State var selectedUsers: Set<User> = Set()
    
    @State private var createBtnState : ComponentState = .default
    
    @State var searchQuery: String = ""    
    @State private var searchTextFieldState : PeptideTextFieldState = .default

    private var membersCountView : AnyView {
        AnyView(
            
            PeptideText(text: "\(selectedUsers.count + 1) Member",
                        font: .peptideButton,
                        textColor: .textGray07,
                        alignment: .center)
        )
    }
    
    private var allFriendsFriends: [User] {
        let friends = viewState.users.values.filter { user in
            user.relationship == .Friend
        }
        return friends
    }
    
    private var groupedFriends: [String: [User]] {
        let normalizedQuery = searchQuery.lowercased()

        let friends = viewState.users.values.filter { user in
            guard user.relationship == .Friend else { return false }

            let username = user.username.lowercased()
            let displayName = user.display_name?.lowercased() ?? ""

            return normalizedQuery.isEmpty ||
                   username.contains(normalizedQuery) ||
                   displayName.contains(normalizedQuery)
        }

        return Dictionary(grouping: friends) { String($0.username.prefix(1)).uppercased() }
            .sorted { $0.key < $1.key }
            .reduce(into: [:]) { $0[$1.key] = $1.value }
    }
    
    private func createGroup() {
        
        Task {
            
            createBtnState = .loading
            let res = await viewState.http.createGroup(name: groupName, users: selectedUsers.map(\.id))
            createBtnState = .default
            
            switch res {
                case .success(let c):
                    viewState.channels[c.id] = c
                    viewState.channelMessages[c.id] = []
                    viewState.currentChannel = .channel(c.id)
                    viewState.path = []
                    viewState.path.append(NavigationDestination.maybeChannelView)
                
                case .failure(_):
                    self.viewState.showAlert(message: "Failed to create group.", icon: .peptideInfo)
                 
            }
        }
        
    }
    
    
    var body: some View {
        PeptideTemplateView(toolbarConfig: .init(isVisible: true,
                                                 title: "Fantastic Friends",
                                                 backButtonIcon: .peptideCloseLiner,
                                                 customToolbarView: membersCountView,
                                                 showBottomLine: true),
                            fixBottomView: AnyView(
                                HStack(spacing: .zero) {
                                    
                                    PeptideButton(title: "Create",
                                                  buttonState: createBtnState){
                                        createGroup()
                                    }
                                    
                                }
                                .padding(.horizontal, .padding16)
                                .padding(top: .padding8, bottom: .padding24)
                                .background(Color.bgDefaultPurple13)
                            )
        ){_,_ in
            
            VStack {
                
                PeptideTextField(text: $searchQuery,
                                 state: $searchTextFieldState,
                                 placeholder: "Search in the friends list",
                                 icon: .peptideSearch,
                                 cornerRadius: .radiusLarge,
                                 height: .size40,
                                 keyboardType: .default)
                .padding(.top, .size16)
                
                if groupedFriends.isEmpty {
                    
                    let searchQueryIsEmpty = searchQuery.isEmpty
                    
                    if(searchQueryIsEmpty){
                        Spacer(minLength: .zero)
                    }
                    
                   
                    VStack(spacing: .spacing4){
                        
                        Image(searchQueryIsEmpty ? .peptideDmEmpty : .peptideNotFound)
                            .resizable()
                            .frame(width: .size200, height: .size200)
                        
                        PeptideText(text: searchQueryIsEmpty ? "No Connections Yet" : "We Couldn't Find Anyone",
                                    font: .peptideHeadline,
                                    textColor: .textDefaultGray01)
                        .padding(.horizontal, .padding24)
                        
                        PeptideText(text: searchQueryIsEmpty ? "Find friends to message or build a group to get started." : "Double-check the name and try again.",
                                    font: .peptideSubhead,
                                    textColor: .textGray07,
                                    alignment: .center)
                        .padding(.horizontal, .padding24)

                    }
                    .padding(.horizontal, .padding16)
                    .padding(.bottom, .padding16)
                    
                    Spacer(minLength: .zero)
                    
                    
                    
                }else{
                
                    LazyVStack(spacing: .zero) {
                        Section {
                            
                            ForEach(groupedFriends.keys.sorted(), id: \.self) { key in
                                Section(header: HStack(spacing: .zero) {
                                    
                                    PeptideText(text: key,
                                                font: .peptideHeadline,
                                                textColor: .textDefaultGray01)
                                    
                                    Spacer(minLength: .zero)
                                    
                                    
                                }
                                    .padding(top: .padding16, bottom: .padding8, leading: .padding8, trailing: .padding8)) {
                                        ForEach(groupedFriends[key] ?? []) { user in
                                            
                                            HStack(spacing: .spacing8) {
                                                Avatar(user: user,
                                                       width: .size40,
                                                       height: .size40,
                                                       withPresence: true)
                                                
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
                                                    get: { selectedUsers.contains(user) },
                                                    // Add or remove the user from the selection set based on the toggle.
                                                    set: { v in
                                                        if v {
                                                            if selectedUsers.count < 99 {
                                                                selectedUsers.insert(user)
                                                            }
                                                        } else {
                                                            selectedUsers.remove(user)
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
                                            .padding(.bottom, .padding8)
                                            
                                        }
                                    }
                            }

                            Spacer(minLength: .zero)

                            
                        }
                    }
                
                    Spacer()
                    
                }
                                
                
            }
            
            .padding(.horizontal, .padding16)
            
        }
        
    }
}

#Preview {
    CreateGroupAddMembders(groupName: "New Group")
        .applyPreviewModifiers(withState: ViewState.preview())

}
