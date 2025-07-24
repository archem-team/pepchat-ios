//
//  MemberSheet.swift
//  Revolt
//
//  Created by Angelo on 23/10/2023.
//

import Foundation
import SwiftUI
import Flow
import Types
import ExyteGrid



/// A view that displays the header for a user's profile, including their avatar and username.
struct UserSheetHeader: View {
    @EnvironmentObject var viewState: ViewState  // Environment object containing the app's state
    var user: User  // User whose information is displayed
    var member: Member?  // Optional member information
    var profile: Profile?  // Profile containing user's background
    @Binding var isShowingBlockPopup: Bool
    @Binding var isPresentedStatusPreviewSheet : Bool
    
    var body: some View {
        
        let isCurrentUser = user.id == viewState.currentUser?.id;
        let isBlocked = viewState.getUserRelation(userId: user.id) == .Blocked
        
        VStack(alignment: .leading, spacing: .zero) {
            
            ZStack(alignment: .bottomLeading) {
                
                ZStack(alignment: .topTrailing){
                    
                    VStack(spacing: .zero){
                        
                        if let banner = profile?.background {
                            
                            ZStack {
                                LazyImage(source: .file(banner), height: 130, clipTo: RoundedRectangle(cornerRadius: .zero))
                                    .overlay{
                                        RoundedRectangle(cornerRadius: .zero)
                                            .fill(Color.bgDefaultPurple13.opacity(0.6))
                                            .frame(height: 130)
                                    }
                            }
                            
                        } else {
                            Image(.coverPlaceholder)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 130)
                        
                                
                        }
                        
                        
                        RoundedRectangle(cornerRadius: .zero)
                            .fill(Color.bgGray12)
                            .frame(height: .size32)
                        
                    }
                    
                    if(!isCurrentUser && !isBlocked){
                    
                        HStack {
                               
                               Menu {
                                   Button(action: {
                                       
                                       self.isShowingBlockPopup.toggle()
                                       
                                   }) {
                                       PeptideButton(title: "Block User", leadingIcon: .peptideCancelFriendRequest){}
                                   }
                               } label: {
                                   PeptideIcon(iconName: .peptideMore,
                                               size: .size20,
                                               color: .iconDefaultGray01)
                                   .frame(width: .size32,
                                          height: .size32)
                                   .background(Circle().fill(Color.bgPurple13Alpha60))
                                   .padding(.padding8)
                               }
                           }
                        
                    }
                    
                }
                
                
                HStack(spacing: .zero){
                
                    Avatar(user: user, width: 64, height: 64, withPresence: false)
                        .frame(width: 72, height: 72)
                        .background{
                            Circle()
                                .fill(Color.bgGray12)
                        }
                        .padding(.leading, .padding16)
                    
                    if let status = user.status?.text{
                        
                        ZStack(alignment: .topLeading){
                            
                            Image(.peptideUnion)
                                .renderingMode(.template)
                                .foregroundStyle(.bgGray11)
                            
                                HStack(spacing: .spacing4){
                                    
                                    PeptideText(text: status,
                                                font: .peptideSubhead,
                                                textColor: .textGray07)
                                    
                                }
                                .padding(leading: .padding8, trailing: .padding12)
                                .frame(minWidth: 80, minHeight: .size36)
                                .background{
                                    RoundedRectangle(cornerRadius: .radiusXSmall)
                                        .fill(Color.bgGray11)
                                }
                                .padding(.padding16)
                            
                            
                        }
                        .onTapGesture {
                            self.isPresentedStatusPreviewSheet.toggle()
                        }
                        
                    }
                    
                }
                
            }
            
            
            VStack(alignment: .leading, spacing: .spacing2) {
                if let display_name = user.display_name {
                    
                    PeptideText(textVerbatim: display_name,
                                font: .peptideTitle4,
                                textColor: .textDefaultGray01)
                }
                
                HStack(spacing: .spacing4) {
                    
                    let username = "\(user.username)#\(user.discriminator)"
                    
                    PeptideText(textVerbatim: username,
                                font: .peptideBody4,
                                textColor: .textGray07)
                    .onTapGesture {
                        copyText(text: user.usernameWithDiscriminator())
                        self.viewState.showAlert(message: "Username Copied!", icon: .peptideDoneCircle)
                    }
                    
                    PeptideIconButton(icon: .peptideCopy,
                                      color: .iconGray07,
                                      size: .size12){
                        
                        copyText(text: user.usernameWithDiscriminator())
                        self.viewState.showAlert(message: "User ID Copied!", icon: .peptideDoneCircle)
                    }
                    
                    
                }
            }
            .padding(top: .padding16, bottom: .padding20)
            .padding(.horizontal, .padding16)
            
            
            PeptideDivider(size: .size4, backgrounColor: .borderGray11)
            
            
        }
        
    }
}


/// A view that represents the user sheet, containing user details and actions.
struct UserSheet: View {
    @EnvironmentObject var viewState: ViewState
    @State private var sheetHeight: CGFloat = .zero
    
    
    var user: User  // User to display
    var member: Member?  // Optional member information
    
    @State var profile: Profile?  // User's profile
    @State var owner: User = .init(id: String(repeating: "0", count: 26), username: "Unknown", discriminator: "0000")
    @State var mutualServers: [String] = []
    @State var mutualFriends: [String] = []
    @State private var commonGroupDMChannelCount: Int = 0
    @State private var isShowingUnfriendPopup: Bool = false
    @State private var removeFriendShipType: RemoveFriendShipType = .withdrawal
    @State private var isShowingBlockPopup: Bool = false
    @State private var isPresentedStatusPreviewSheet: Bool = false
    @State private var mutualConnection: MutualConnection = .friends
    @State private var isShowingMutulConnectionsSheet: Bool = false
    
    /// Returns the color style for a given role.
    /// - Parameter role: The role for which to determine the color.
    /// - Returns: The shape style for the role's color.
    func getRoleColour(role: Role) -> AnyShapeStyle {
        if let colour = role.colour {
            return parseCSSColor(currentTheme: viewState.theme, input: colour)
        } else {
            return AnyShapeStyle(viewState.theme.foreground)  // Default color
        }
    }
    
    
    func findCommonGroupDMChannel(
        channels: [Channel],
        currentUserId: String?,
        otherUserId: String?
    ) -> [GroupDMChannel] {
        guard let currentUserId = currentUserId, let otherUserId = otherUserId else {
            return []
        }
        
        return channels.compactMap { channel in
            if case let .group_dm_channel(groupChannel) = channel {
                if groupChannel.recipients.contains(currentUserId) && groupChannel.recipients.contains(otherUserId) {
                    return groupChannel
                }
            }
            return nil
        }
    }
    
    func getTitle(relation: Relation) -> String?{
        
        switch relation {
        case .Friend: return "Message"
        case .Blocked: return "Unblock"
        case .BlockedOther: return nil
        case .Incoming: return "Add Friend"
        case .None: return "Add Friend"
        case .Outgoing: return "Pending"
        case .User: return nil
        default: return nil
            
        }
    }

    func getImage(relation: Relation) -> ImageResource?{
        
        switch relation {
        case .Friend: return .peptideMessage
        case .Blocked: return .peptideUnblock
        case .BlockedOther: return nil
        case .Incoming: return .peptideMessage
        case .None: return .peptideNewUser
        case .Outgoing: return .peptideTimeCancelPendingSvg
        case .User: return nil
        default: return nil
        }
        }
        
    func showingMutulConnectionsSheet(mutualConnection: MutualConnection){
        
        self.mutualConnection = mutualConnection
        self.isShowingMutulConnectionsSheet.toggle()
        
    }
    
    
    var body: some View {
        
        let _ = self.removeFriendShipType
        
        VStack(alignment: .leading, spacing: .zero) {
            
            let isCurrentUser = user.id == viewState.currentUser?.id;
            
            UserSheetHeader(user: user, member: member, profile: profile, isShowingBlockPopup: $isShowingBlockPopup, isPresentedStatusPreviewSheet: $isPresentedStatusPreviewSheet)
            
            if(isCurrentUser){
                
                PeptideButton(title: "Edit Profile",
                              leadingIcon: .peptideEdit){
                    self.viewState.closeUserSheet()
                    self.viewState.path.append(NavigationDestination.profile_setting)
                }
                              .padding(.horizontal, .size16)
                              .padding(.top, .size24)
                              .padding(.bottom, .size24)
                
            }
            
            if(!isCurrentUser){
                HStack(spacing: .spacing8) {
                    
                    let relation = viewState.getUserRelation(userId: user.id)
                    
                    if let title = getTitle(relation: relation!), let image = getImage(relation: relation!){
                    
                        PeptideIconWithTitleButton(icon: image, title: title){
                            
                            switch relation {
                            case .Friend:
                                Task {
                                    await viewState.openDm(with: user.id)
                                    viewState.closeUserSheet()
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                }
                                
                            case .Blocked:
                                Task {
                                                                        
                                    let response = await viewState.http.unblockUser(user: user.id)
                                    
                                    switch response {
                                    case .success(_):
                                        var user = self.user
                                        user.relationship = .None
                                        viewState.users[user.id] = user
                                        viewState.showAlert(message: "User unblocked! You can add to friends now.", icon: .peptideCopy)
                                    case .failure(_):
                                        viewState.showAlert(message: "Some thing went wronge. Try again a litle later", icon: .peptideClose)
                                    }
                                    
                                }
                                break
                            case .BlockedOther: break
                            case .Incoming:
                                Task{
                                    
                                    let res = await self.viewState.http.sendFriendRequest(username: "\(user.username)#\(user.discriminator)")
                                    
                                    switch res {
                                    case .success(_):
                                        var user = self.user
                                        user.relationship = .Outgoing
                                        viewState.users[user.id] = user
                                    case .failure(_):
                                        self.viewState.showAlert(message: "Something went wronge!", icon: .peptideCloseLiner)
                                    }
                                    
                                }
                            case .None:
                                Task{
                                    
                                    let res = await self.viewState.http.sendFriendRequest(username: "\(user.username)#\(user.discriminator)")
                                    
                                    switch res {
                                    case .success(_):
                                        var user = self.user
                                        user.relationship = .Outgoing
                                        viewState.users[user.id] = user
                                    case .failure(_):
                                        self.viewState.showAlert(message: "Something went wronge!", icon: .peptideCloseLiner)
                                    }
                                    
                                }
                            case .Outgoing:
                                self.removeFriendShipType = .withdrawal
                                self.isShowingUnfriendPopup.toggle()
                            case .User: break
                            default: break
                            }
                        }
                        
                    }
                    
                    if relation == .Friend{
                        
                        PeptideIconWithTitleButton(icon: .peptideRemoveUser, title: "Unfriend"){
                            
                            self.removeFriendShipType = .unfriend
                            self.isShowingUnfriendPopup.toggle()
                        }
                        
                    }
                        
                        PeptideIconWithTitleButton(icon: .peptideReportFlag,
                                                   title: "Report",
                                                   iconColor: .iconRed07,
                                                   titleColor: .textRed07){
                            viewState.closeUserSheet()
                            viewState.path.append(NavigationDestination.report(user, nil, nil))
                            
                            
                            
                        }
                        
                    }
                                               .padding(.horizontal, .padding16)
                                               .padding(.vertical, .padding24)
                }
                
                if(!isCurrentUser && (mutualFriends.count > 0 || commonGroupDMChannelCount > 0 || mutualServers.count > 0)){
                    
                    VStack(spacing: .spacing4){
                        
                        if(mutualFriends.count > 0){
                            
                            Button {
                                
                                self.showingMutulConnectionsSheet(mutualConnection: .friends)
                                
                            } label: {
                                
                                PeptideActionButton(icon: .peptideFriend,
                                                    title: "\(mutualFriends.count) Mutual Friends",
                                                    hasArrow: true)
                            }
                        
                            if(commonGroupDMChannelCount > 0 || mutualServers.count > 0){
                                
                                PeptideDivider()
                                    .padding(.leading, .padding48)
                                
                            }
                            
                        }
                        
                        
                        if(commonGroupDMChannelCount > 0){
                            
                            Button {
                                self.showingMutulConnectionsSheet(mutualConnection: .groups)
                            } label: {
                                
                                
                                PeptideActionButton(icon: .peptideTeamUsers,
                                                    title: "\(commonGroupDMChannelCount) Mutual Group",
                                                    hasArrow: true)
                            }
                        
                            if(mutualServers.count > 0){
                                
                                PeptideDivider()
                                    .padding(.leading, .padding48)
                                
                            }
                            
                        }
                        
                        if(mutualServers.count > 0){
                            
                            Button {
                                self.showingMutulConnectionsSheet(mutualConnection: .servers)
                            } label: {
                                
                                
                                PeptideActionButton(icon: .peptideServer,
                                                    title: "\(mutualServers.count) Mutual Servers",
                                                    hasArrow: true)
                            }
                            
                        }
                        
                        
                    }
                    .backgroundGray11(verticalPadding: .padding4)
                    .padding(.horizontal, .padding16)
                    .padding(.bottom, .padding24)
                    
                }
                
                if let aboutMe = profile?.content {
                    
                    VStack(alignment: .leading, spacing: .zero){
                        
                        PeptideText(
                            text: "About me",
                            font: .peptideHeadline,
                            textColor: .textGray06
                        )
                        .padding(.bottom, .size4)
                        
                        HStack(spacing: .zero){
                            
                            PeptideText(
                                text: aboutMe,
                                font: .peptideBody4,
                                textColor: .textGray04
                            )
                            
                            Spacer(minLength: .zero)
                            
                        }
                        
                        
                    }
                    .padding(.all, .padding16)
                    .backgroundGray11(verticalPadding: .padding4)
                    .padding(.horizontal, .padding16)
                    .padding(.bottom, .padding8)
                    
                }
            
            // Check if the profile is available
            /*if let profile = profile {
             
             // Grid layout for user details
             Grid(tracks: 2, flow: .rows, spacing: 12) {
             UserSheetHeader(user: user, member: member, profile: profile)
             .gridSpan(column: 2)  // Span the header across two columns
             
             // Display user roles if available
             if let member = member,
             let server = viewState.servers[member.id.server],
             let roles = member.roles, !roles.isEmpty
             {
             Tile("Roles") {
             ScrollView {
             // List the roles the user has
             ForEach(roles, id: \.self) { roleId in
             let role = server.roles![roleId]!
             
             HStack {
             Text(role.name)  // Role name
             
             Spacer()
             
             Circle()  // Circle indicating the role color
             .foregroundStyle(getRoleColour(role: role))
             .frame(width: 16, height: 16)
             }
             }
             }
             }
             }
             
             // Display the date the user joined the server
             Tile("Joined") {
             VStack(alignment: .leading) {
             Text(createdAt(id: user.id), style: .date)  // Created date
             Text("Revolt")  // Platform name
             .bold()
             }
             }
             
             // Display badges if available
             if let badges = user.badges {
             Tile("Badges") {
             
             HFlow {
             // Display each badge the user has
             ForEach(Badges.allCases, id: \.self) { value in
             Badge(badges: badges, filename: String(describing: value), value: value.rawValue)
             }
             }
             }
             }
             
             // Check if the user is a bot and display the owner's information
             if let bot = user.bot {
             Tile("Owner") {
             HStack(spacing: 12) {
             Avatar(user: owner)  // Display owner's avatar
             
             Text(owner.display_name ?? owner.username)  // Owner's display name
             }
             }
             .task {
             // Fetch owner's details if not already available
             if let user = viewState.users[bot.owner] {
             owner = user
             } else {
             Task {
             if case .success(let user) = await viewState.http.fetchUser(user: bot.owner) {
             owner = user  // Update the owner variable
             }
             }
             }
             }
             }
             
             // Display mutual friends if available
             if !mutualFriends.isEmpty {
             Tile("Mutual Friends") {
             ScrollView {
             VStack(alignment: .leading, spacing: 8) {
             // List mutual friends
             ForEach(mutualFriends.compactMap { viewState.users[$0] }) { user in
             Button {
             viewState.openUserSheet(user: user)  // Open user sheet for mutual friend
             } label: {
             HStack(spacing: 8) {
             Avatar(user: user, width: 16, height: 16, withPresence: true)  // Friend's avatar
             
             Text(verbatim: user.display_name ?? user.username)  // Friend's display name
             .lineLimit(1)
             }
             }
             }
             }
             }
             }
             }
             
             // Display mutual servers if available
             if !mutualServers.isEmpty {
             Tile("Mutual Servers") {
             ScrollView {
             VStack(alignment: .leading, spacing: 8) {
             // List mutual servers
             ForEach(mutualServers.compactMap { viewState.servers[$0] }) { server in
             Button {
             viewState.selectServer(withId: server.id)  // Select mutual server
             } label: {
             HStack(spacing: 8) {
             ServerIcon(server: server, height: 16, width: 16, clipTo: Circle())  // Server icon
             
             Text(verbatim: server.name)  // Server name
             .lineLimit(1)
             }
             }
             }
             }
             }
             }
             }
             
             // Display user's bio if available
             if let bio = profile.content {
             Tile("Bio") {
             ScrollView {
             Contents(text: .constant(bio), fontSize: 17)  // Bio content
             }
             }
             .gridSpan(column: 2)  // Span the bio tile across two columns
             }
             
             // User action buttons based on relationship status
             Group {
             switch user.relationship ?? .None {
             case .User:
             Button {
             viewState.path.append(NavigationDestination.settings)  // Navigate to edit profile
             } label: {
             HStack {
             Spacer()
             
             Text("Edit profile")  // Edit profile button
             
             Spacer()
             }
             }
             .padding(8)
             .background(viewState.theme.accent, in: RoundedRectangle(cornerRadius: 50))  // Button styling
             
             case .Blocked:
             EmptyView()  // TODO: unblock option
             case .BlockedOther:
             EmptyView()  // Placeholder for blocked status
             case .Friend:
             Button {
             Task {
             await viewState.openDm(with: user.id)  // Open DM with friend
             }
             } label: {
             HStack {
             Spacer()
             
             Text("Send Message")  // Send message button
             
             Spacer()
             }
             }
             .padding(8)
             .background(viewState.theme.accent, in: RoundedRectangle(cornerRadius: 50))  // Button styling
             
             case .Incoming, .None:
             Button {
             Task {
             await viewState.http.sendFriendRequest(username: user.username)  // Send friend request
             }
             } label: {
             HStack {
             Spacer()
             
             Text("Add Friend")  // Add friend button
             
             Spacer()
             }
             }
             .padding(8)
             .background(viewState.theme.accent, in: RoundedRectangle(cornerRadius: 50))  // Button styling
             
             case .Outgoing:
             Button {
             Task {
             await viewState.http.removeFriend(user: user.id)  // Cancel friend request
             }
             } label: {
             HStack {
             Spacer()
             
             Text("Cancel Friend Request")  // Cancel friend request button
             
             Spacer()
             }
             }
             .padding(8)
             .background(viewState.theme.accent, in: RoundedRectangle(cornerRadius: 50))  // Button styling
             }
             }
             .gridSpan(column: 2)  // Span the buttons across two columns
             }
             .gridContentMode(.scroll)  // Enable scrolling for grid content
             .gridFlow(.rows)  // Configure the flow of the grid
             .gridPacking(.sparse)  // Use sparse packing for grid items
             .gridCommonItemsAlignment(.topLeading)  // Align items to the top leading edge
             } else {
             Text("Loading...")  // Loading indicator
             }*/
        }
        
        .overlay {
            GeometryReader { geometry in
                Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
            sheetHeight = newHeight
        }
        .task {
            if let profile = user.profile {
                self.profile = profile
            } else {
                profile = try? await viewState.http.fetchProfile(user: user.id).get()
            }
        }
        .task {
            // Fetch mutual friends and servers if user is not the current user
            if user.id != viewState.currentUser!.id,
               let mutuals = try? await viewState.http.fetchMutuals(user: user.id).get()
            {
                mutualServers = mutuals.servers
                mutualFriends = mutuals.users
            }
        }
        .task {
            
            let commonGroups = findCommonGroupDMChannel(channels: viewState.dms,
                                                        currentUserId: viewState.currentUser?.id,
                                                        otherUserId: user.id)
            
            commonGroupDMChannelCount = commonGroups.count
        }
        .sheet(isPresented: $isShowingMutulConnectionsSheet){
            
            MutualConnectionsSheet(isPresented: $isShowingMutulConnectionsSheet, user: user, selectedTab: self.mutualConnection)
            
        }
        .sheet(isPresented: $isPresentedStatusPreviewSheet){
            StatusPreviewSheet(isPresented: $isPresentedStatusPreviewSheet, user: user)
        }
        .popup(isPresented: $isShowingUnfriendPopup, view: {
            RemoveFriendShipPopup(isPresented: $isShowingUnfriendPopup, user: self.user, removeFriendShipType: self.removeFriendShipType)
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.bottom)
        .popup(isPresented: $isShowingBlockPopup, view: {
            BlockUserPopup(isPresented: $isShowingBlockPopup, user: self.user)
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.bottom)
        
        
    }
}

/// A view that represents an individual badge.
struct Badge: View {
    var badges: Int  // The user's badges represented as an integer
    var filename: String  // Badge image filename
    var value: Int  // Badge value
    
    var body: some View {
        // Check if the user has the specific badge
        if badges & (value << 0) != 0 {
            Image(filename)  // Display badge image
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)  // Badge size
        }
    }
}

/// Preview provider for UserSheet to enable SwiftUI previews.
struct UserSheetPreview: PreviewProvider {
    @StateObject static var viewState: ViewState = ViewState.preview().applySystemScheme(theme: .dark)
    
    static var previews: some View {
        Text("foo")
            .sheet(isPresented: .constant(true)) {
                UserSheet(user: viewState.users["0"]!, member: nil)
            }
            .applyPreviewModifiers(withState: viewState)
    }
}
