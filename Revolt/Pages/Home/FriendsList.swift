//
//  FriendsList.swift
//  Revolt
//
//  Created by Angelo on 14/11/2023.
//

import Foundation
import SwiftUI
import Types

enum UserSort{
    case alphabetical;
    case status;
}

/// `Friends` is a model struct that holds lists of users categorized by their relationship status.
/// It includes outgoing, incoming, friends, blocked, and blockedBy categories.
struct Friends {
    var outgoing: [User]  // Users to whom the current user sent friend requests.
    var incoming: [User]  // Users who sent friend requests to the current user.
    var friends: [User]   // Current friends.
    var blocked: [User]   // Users blocked by the current user.
    var blockedBy: [User] // Users who have blocked the current user.
}

private let toolbarConfig : ToolbarConfig = .init(isVisible: true,
                                                  title: "Friends",
                                                  //backButtonIcon: .peptideCloseLiner,
                                                  showBackButton: false,
                                                  showBottomLine: true)

/// `FriendsList` is the main view displaying all friends, friend requests, and blocked users.
/// It uses dynamic sections for different user groups and provides actions for accepting, removing, or blocking users.
struct FriendsList: View {
    @EnvironmentObject var viewState: ViewState  // Access to global state and users' relationships.
    
    
    @State var searchQuery: String = ""
    @State var userSort: UserSort = .alphabetical
    @State private var searchTextFieldState : PeptideTextFieldState = .default
    
    
    /// Retrieves the list of users categorized into friends, requests, and blocked lists.
    /*func getFriends() -> Friends {
     var friends = Friends(outgoing: [], incoming: [], friends: [], blocked: [], blockedBy: [])
     
     for user in viewState.users.values {
     switch user.relationship ?? .None {
     case .Blocked:
     friends.blocked.append(user)
     case .BlockedOther:
     friends.blockedBy.append(user)
     case .Friend:
     friends.friends.append(user)
     case .Incoming:
     friends.incoming.append(user)
     case .Outgoing:
     friends.outgoing.append(user)
     default:
     break
     }
     }
     
     return friends
     }*/
    
    
    var groupedFriends: [String: [User]] {
        let query = searchQuery.lowercased()
        
        let friends = viewState.users.values
            .filter { user in
                guard user.relationship == .Friend else { return false }
                
                let username = user.username.lowercased()
                let displayName = user.display_name?.lowercased()
                
                return query.isEmpty ||
                username.contains(query) ||
                (displayName?.contains(query) ?? false)
            }
        
        return Dictionary(grouping: friends) { String($0.username.prefix(1)).uppercased() }
            .sorted { $0.key < $1.key }
            .reduce(into: [:]) { result, group in
                result[group.key] = group.value
            }
    }
    
    
    var groupedUsersByStatus: [String: [User]] {
        let query = searchQuery.lowercased()
        
        let filteredUsers = viewState.users.values
            .filter { user in
                guard user.relationship == .Friend else { return false }
                
                let username = user.username.lowercased()
                let displayName = user.display_name?.lowercased()
                
                return query.isEmpty ||
                username.contains(query) ||
                (displayName?.contains(query) ?? false)
            }
        
        let groupedUsers = Dictionary(grouping: filteredUsers) { user in
            user.status?.presence?.rawValue ?? "offline"
        }
        
        let sortedGroups = groupedUsers.sorted { $0.key < $1.key }
        
        return sortedGroups.reduce(into: [:]) { result, group in
            result[group.key] = group.value
        }
    }
    
    var usersWithRequest: [User] {
        let usersWithRequest = viewState.users.values
            .filter { user in
                user.relationship == .Incoming
            }
        
        return usersWithRequest
    }
    
    var selectedSortUsers: [String: [User]]{
        return userSort == .alphabetical ? groupedFriends : groupedUsersByStatus;
    }
    
    
    
    var body: some View {
        /*let friends = getFriends()
         
         let arr = [
         ("Incoming", friends.incoming),  // Incoming friend requests.
         ("Outgoing", friends.outgoing),  // Outgoing friend requests.
         ("Friends", friends.friends),    // Current friends.
         ("Blocked", friends.blocked),    // Users blocked by the user.
         ("Blocked By", friends.blockedBy)  // Users who blocked the user.
         ].filter({ !$0.1.isEmpty })  // Filters out empty sections.*/
        
        ZStack(alignment: .bottomTrailing){
            
            PeptideTemplateView(toolbarConfig: toolbarConfig){_,_ in
                
                if !usersWithRequest.isEmpty {
                    FriendRequestCard(users: usersWithRequest)
                }
                
                if !(searchQuery.isEmpty && selectedSortUsers.isEmpty){
                    
                    HStack(spacing: .spacing8){
                        
                        PeptideTextField(text: $searchQuery,
                                         state: $searchTextFieldState,
                                         placeholder: "Search in the friends list",
                                         icon: .peptideSearch,
                                         cornerRadius: .radiusLarge,
                                         height: .size40,
                                         keyboardType: .default)
                        
                        Menu {
                            Button{
                                self.userSort = .alphabetical
                            } label: {
                                HStack{
                                    PeptideText(text: "Alphabet")
                                    
                                    if(self.userSort == .alphabetical){
                                        PeptideIcon(iconName: .peptideDoneCircle,
                                                    size: .size20,
                                                    color: .iconYellow07)
                                    }
                                    
                                }
                            }
                            Button{
                                self.userSort = .status
                            } label: {
                                
                                HStack{
                                    PeptideText(text: "Status")
                                    
                                    if(self.userSort == .status){
                                        PeptideIcon(iconName: .peptideDoneCircle,
                                                    size: .size20,
                                                    color: .iconYellow07)
                                    }
                                    
                                }
                            }
                            
                        } label: {
                            PeptideIcon(iconName: .peptideSort)
                                .frame(width: .size40, height: .size40)
                                .background{
                                    Circle().fill(Color.bgGray11)
                                }
                        }
                        
                        
                    }
                    .padding(.top, .padding12)
                    .padding(.horizontal, .size16)
                    
                }
                
                if selectedSortUsers.isEmpty {
                    
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
                    
                    if(searchQueryIsEmpty){
                        PeptideButton(buttonType: .medium(),
                                      title: "Add Friend",
                                      bgColor: .bgYellow07,
                                      contentColor: .textInversePurple13,
                                      buttonState: .default,
                                      isFullWidth: true,
                                      onButtonClick: {
                            viewState.path.append(NavigationDestination.add_friend)
                        })
                        .padding(bottom: .padding36,
                                 leading: .padding16,
                                 trailing: .padding16)
                    }
                    
                    Spacer(minLength: .zero)
                    
                    
                    
                } else {
                    
                    VStack{
                        
                        LazyVStack(spacing: .zero) {
                            
                            /*VStack(spacing: .spacing4){
                             
                             
                             NavigationLink(value: NavigationDestination.create_group_name) {
                             PeptideActionButton(icon: .peptideNewGroup,
                             title: "New Group")
                             }
                             
                             PeptideDivider()
                             .padding(.leading, .padding48)
                             
                             NavigationLink(value: NavigationDestination.add_friend) {
                             
                             
                             PeptideActionButton(icon: .peptideNewUser,
                             title: "Add a Friend")
                             
                             
                             }
                             
                             }
                             .padding(top: .padding4, bottom: .padding4)
                             .background{
                             RoundedRectangle(cornerRadius: .radiusMedium).fill(Color.bgGray11)
                             }
                             .padding(top: .padding24, bottom: .padding16)*/
                            
                            ForEach(selectedSortUsers.keys.sorted(), id: \.self) { key in
                                Section(header: HStack(spacing: .zero) {
                                    
                                    PeptideText(text: "\(key) - \(selectedSortUsers[key]?.count ?? 0)",
                                                font: .peptideHeadline,
                                                textColor: .textDefaultGray01)
                                    
                                    Spacer(minLength: .zero)
                                    
                                    
                                }
                                    .padding(top: .padding16, bottom: .padding8, leading: .padding8, trailing: .padding8)) {
                                        ForEach(selectedSortUsers[key] ?? []) { user in
                                            
                                            
                                            HStack(spacing: .spacing8) {
                                                
                                                Button{
                                                    
                                                    viewState.openUserSheet(user: user)
                                                    
                                                } label:{
                                                    Avatar(user: user,
                                                           width: .size40,
                                                           height: .size40,
                                                           withPresence: true)
                                                }
                                                
                                                
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
                                                
                                                PeptideIcon(iconName: .peptideMessage,
                                                            size: .size20,
                                                            color: .iconGray07)
                                            }
                                            .padding(.padding8)
                                            .background(Color.bgGray11)
                                            .cornerRadius(.radius8)
                                            .onLongPressGesture{
                                                self.viewState.openUserOptionsSheet(withId: user.id)
                                            }
                                            .onTapGesture{
                                                self.viewState.navigateToDm(with: user.id)
                                            }
                                            .padding(.bottom, .padding8)
                                            
                                            
                                            
                                        }
                                    }
                            }
                            
                            
                            /*ForEach(arr, id: \.0) { (title, users) in
                             Section {
                             ForEach(users) { user in
                             Button {
                             viewState.openUserSheet(user: user)  // Opens detailed user info.
                             } label: {
                             HStack {
                             // User's avatar and display name.
                             HStack(spacing: 12) {
                             Avatar(user: user, withPresence: true)
                             .frame(width: 16, height: 16)
                             .frame(width: 24, height: 24)
                             
                             Text(user.display_name ?? user.username)
                             }
                             
                             Spacer()
                             
                             // Accept incoming friend request.
                             if user.relationship == .Incoming {
                             Button {
                             Task {
                             if case .success(_) = await viewState.http.acceptFriendRequest(user: user.id) {
                             viewState.users[user.id]!.relationship = .Friend  // Update to friend on success.
                             }
                             }
                             } label: {
                             Image(systemName: "checkmark.circle.fill")
                             .resizable()
                             .foregroundStyle(viewState.theme.foreground2.color)
                             .frame(width: 16, height: 16)
                             .frame(width: 24, height: 24)
                             }
                             }
                             
                             // Remove friend or cancel request.
                             if [.Incoming, .Outgoing, .Friend].contains(user.relationship) {
                             Button {
                             Task {
                             if case .success(_) = await viewState.http.removeFriend(user: user.id) {
                             viewState.users[user.id]!.relationship = .None  // Remove relationship.
                             }
                             }
                             } label: {
                             Image(systemName: "x.circle.fill")
                             .resizable()
                             .foregroundStyle(viewState.theme.foreground2.color)
                             .frame(width: 16, height: 16)
                             .frame(width: 24, height: 24)
                             }
                             }
                             
                             // Unblock blocked user.
                             if user.relationship == .Blocked {
                             Button {
                             Task {
                             if case .success(_) = await viewState.http.unblockUser(user: user.id) {
                             viewState.users[user.id]!.relationship = .None  // Reset relationship after unblock.
                             }
                             }
                             } label: {
                             Image(systemName: "person.crop.circle.fill.badge.xmark")
                             .resizable()
                             .foregroundStyle(viewState.theme.foreground2.color)
                             .frame(width: 16, height: 16)
                             .frame(width: 24, height: 24)
                             }
                             }
                             }
                             }
                             }
                             } header: {
                             // Section header with title and user count.
                             HStack {
                             Text(title)
                             Spacer()
                             Text("\(users.count)")
                             }
                             }
                             .listRowBackground(viewState.theme.background2.color)  // Custom background for the section.
                             }*/
                            
                            
                        }
                        .padding(.horizontal, .padding16)
                        
                        Spacer(minLength: .zero)
                        
                    }
                    
                    
                }
                
            }
            
            if !(searchQuery.isEmpty && selectedSortUsers.isEmpty)  {
                
                
                Menu {
                    Button{
                        viewState.path.append(NavigationDestination.create_group_name)
                    } label: {
                        HStack{
                            PeptideText(text: "New Group")
                            
                            
                            PeptideIcon(iconName: .peptideArrowRight,
                                        size: .size20,
                                        color: .iconYellow07)
                            
                            
                        }
                    }
                    Button{
                        viewState.path.append(NavigationDestination.add_friend)
                    } label: {
                        
                        HStack{
                            
                            PeptideText(text: "Add a Friend")
                            
                            PeptideIcon(iconName: .peptideArrowRight,
                                        size: .size20,
                                        color: .iconYellow07)
                            
                        }
                    }
                    
                } label: {
                    PeptideIcon(iconName:  .peptideAdd,
                                size: .size24,
                                color: .iconInverseGray13)
                    .frame(width: .size48, height: .size48)
                    .background{
                        Circle().fill(Color.bgYellow07)
                    }
                    .padding(.all, .size16)
                }
                
            }
            
        }
        
    }
}

#Preview {
    
    @Previewable @StateObject var viewState : ViewState = .preview()
    
    FriendsList()
        .applyPreviewModifiers(withState:viewState)
        .preferredColorScheme(.dark)
}
