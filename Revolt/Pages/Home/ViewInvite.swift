//
//  ViewInvite.swift
//  Revolt
//
//  Created by Angelo on 12/09/2024.
//

import Foundation
import SwiftUI
import Types

/// The `ViewInvite` view handles displaying invite details for either a group or server.
/// It fetches and shows information about the invite based on the invite code passed to it.
struct ViewInvite: View {
    @EnvironmentObject var viewState: ViewState
    
    var code: String
    
    /// Holds the invite information, which could be `nil`, a valid response, or an invalid one.
    @State var info: InviteInfoResponse?? = nil
    @State var isProcessingInvite: Bool = false
    
    var body: some View {
        
        PeptideTemplateView(
            toolbarConfig: .init(isVisible: true)
        ){_,_ in
            
            ZStack {
                // Switch on the invite info to show different views depending on the invite type or state.
                switch info {
                    case .none:
                        // Show loading spinner while waiting for invite data.
                        LoadingSpinnerView(frameSize: CGSize(width: 32, height: 32), isActionComplete: .constant(false))
                    case .some(.none):
                    
                    // Show an error message if the invite is invalid.
                    
                    VStack(spacing: .zero){
                        
                        Image(.peptideLinkInvalid)
                        
                        
                        PeptideText(text: "Link No Longer Valid",
                                    font: .peptideTitle1,
                                    textColor: .textDefaultGray01)
                        .padding(top: .padding32, bottom: .padding4)
                        
                        PeptideText(text: "This link seems invalid or expired. Reach out for a new invite.",
                                    font: .peptideBody3,
                                    textColor: .textGray07,
                                    alignment: .center)
                        
                        PeptideButton(title : "Got it"){
                            Task {
                                await MainActor.run {
                                    // Clear navigation path completely to return to main app screen
                                    viewState.path.removeAll()
                                }
                            }
                        }
                        .padding(.top, .padding32)
                        
                        
                    }
                    .padding(.padding24)
                    .background {
                        RoundedRectangle(cornerRadius: .radius16).fill(Color.bgGray12)
                    }
                    .padding(.padding16)
                    
                    
                    case .group(_):
                        // Placeholder for group invites - to be implemented.
                        Text("Group TODO")
                    case .server(let serverInfo):
                        ServerInviteView(
                            serverInfo: serverInfo,
                            isProcessingInvite: $isProcessingInvite,
                            onAcceptInvite: { handleAcceptInvite(serverInfo: serverInfo) },
                            onDeclineInvite: { handleDeclineInvite() }
                        )
                }
            }

        }
        .task {
            // Fetch invite information using the provided code.
            if let info = try? await viewState.http.fetchInvite(code: code).get() {
                self.info = info
            } else {
                self.info = .some(.none)
            }
        }
    }
    
    private func handleAcceptInvite(serverInfo: ServerInfoResponse) {
        guard !isProcessingInvite else { return }
        
        Task {
            do {
                // Set loading state
                await MainActor.run {
                    isProcessingInvite = true
                }
                
                // Pre-flight checks
                guard !code.isEmpty else {
                    print("❌ Empty invite code")
                    await MainActor.run {
                        self.viewState.showAlert(message: "not valid invite code", icon: .peptideInfo)
                        isProcessingInvite = false
                    }
                    return
                }
                
                // Join server
                guard let join = try? await viewState.http.joinServer(code: code).get() else {
                    await handleJoinFailure(serverInfo: serverInfo)
                    return
                }
                
                // Update server and channels
                await updateServerAndChannels(join: join)
                
                // Check if we should fetch members
                let hasServer = await MainActor.run {
                    self.viewState.servers.contains(where: { $0.key == join.server.id })
                }
                let hasChannel = await MainActor.run {
                    self.viewState.channels.contains(where: { $0.key == serverInfo.channel_id })
                }
                
                if hasServer && hasChannel {
                    await fetchAndProcessMembers(join: join, serverInfo: serverInfo)
                } else {
                    await MainActor.run {
                        self.viewState.selectServer(withId: join.server.id)
                        // CRITICAL FIX: Also select the invite channel
                        self.viewState.selectChannel(inServer: join.server.id, withId: serverInfo.channel_id)
                    }
                }
                
                await MainActor.run {
                    isProcessingInvite = false
                    
                    print("🎫 INVITE_ACCEPT: Before path change - path count: \(viewState.path.count)")
                    print("🎫 INVITE_ACCEPT: Before path change - path: \(viewState.path)")
                    
                    // CRITICAL: Clear entire navigation path and rebuild for server context
                    // This ensures back navigation goes to server channel list, not previous screen
                    viewState.path.removeAll()
                    
                    print("🎫 INVITE_ACCEPT: After removeAll - path count: \(viewState.path.count)")
                    
                    // Navigate to the channel with clean navigation stack
                    viewState.path.append(NavigationDestination.maybeChannelView)
                    
                    print("🎫 INVITE_ACCEPT: After adding maybeChannelView - path count: \(viewState.path.count)")
                    print("🎫 INVITE_ACCEPT: Final path: \(viewState.path)")
                }
                
            } catch {
                print("❌ Critical error in accept invite: \(error)")
                await MainActor.run {
                    self.viewState.showAlert(message: "error accepting invite", icon: .peptideInfo)
                    isProcessingInvite = false
                }
            }
        }
    }
    
    private func handleDeclineInvite() {
        Task {
            await MainActor.run {
                // Clear navigation path completely to return to main app screen
                viewState.path.removeAll()
            }
        }
    }
    
    private func handleJoinFailure(serverInfo: ServerInfoResponse) async {
        if case .server(let serverInfo) = self.info ?? .none {
            await MainActor.run {
                self.viewState.selectServer(withId: serverInfo.server_id)
                
                // Navigate to the invite channel if available
                if let server = viewState.servers[serverInfo.server_id],
                   let channelId = server.channels.first {
                    viewState.selectChannel(inServer: serverInfo.server_id, withId: channelId)
                }
                
                isProcessingInvite = false
                
                // CRITICAL: Clear entire navigation path and rebuild for server context
                viewState.path.removeAll()
                
                // Navigate to the channel with clean navigation stack
                viewState.path.append(NavigationDestination.maybeChannelView)
            }
        } else {
            await MainActor.run {
                self.viewState.showAlert(message: "You have already joined the channel or are restricted from joining it!", icon: .peptideInfo)
                isProcessingInvite = false
            }
        }
    }
    
    private func updateServerAndChannels(join: JoinResponse) async {
        await MainActor.run {
            viewState.servers[join.server.id] = join.server
            
            for channel in join.channels {
                viewState.channels[channel.id] = channel
                viewState.channelMessages[channel.id] = []
            }
            
            // Update app badge count after adding new channels
            // This ensures unread messages in the joined channels are counted
            viewState.updateAppBadgeCount()
        }
    }
    
    private func fetchAndProcessMembers(join: JoinResponse, serverInfo: ServerInfoResponse) async {
        await MainActor.run {
            self.viewState.servers[join.server.id] = join.server
            for channel in join.channels {
                self.viewState.channels[channel.id] = channel
            }
        }
        
        // Only fetch members if server is small
        let shouldFetchAllMembers = serverInfo.member_count < 1000
        
        let res = shouldFetchAllMembers
            ? await self.viewState.http.fetchServerMembers(target: join.server.id, excludeOffline: false)
            : await self.viewState.http.fetchServerMembers(target: join.server.id, excludeOffline: true)
        
        switch res {
        case .success(let response):
            await processServerMembers(response: response, serverId: join.server.id, serverInfo: serverInfo)
        case .failure(_):
            await MainActor.run {
                self.viewState.selectServer(withId: join.server.id)
            }
        }
    }
    
    private func processServerMembers(response: MembersWithUsers, serverId: String, serverInfo: ServerInfoResponse) async {
        // Validate response
        guard response.members.count >= 0, response.users.count >= 0 else {
            print("❌ Invalid response structure")
            await MainActor.run {
                self.viewState.selectServer(withId: serverId)
            }
            return
        }
        
        await MainActor.run {
            // Process members efficiently
            let memberCount = response.members.count
            print("🔄 Processing \(memberCount) members")
            
            // Initialize server members dictionary
            if self.viewState.members[serverId] == nil {
                self.viewState.members[serverId] = [:]
            }
            
            // Process first 50 members immediately
            let maxImmediate = 50
            var processed = 0
            
            for (index, member) in response.members.enumerated() {
                guard index < maxImmediate else { break }
                guard !member.id.user.isEmpty else { continue }
                
                self.viewState.members[serverId]?[member.id.user] = member
                processed += 1
            }
            
            print("✅ Immediately processed \(processed) members")
        }
        
        // Process remaining members in background
        if response.members.count > 50 {
            Task.detached(priority: .background) {
                var backgroundProcessed = 0
                for (index, member) in response.members.enumerated() {
                    guard index >= 50 else { continue }
                    guard !member.id.user.isEmpty else { continue }
                    
                    await MainActor.run {
                        self.viewState.members[serverId]?[member.id.user] = member
                    }
                    backgroundProcessed += 1
                    
                    if backgroundProcessed % 100 == 0 {
                        await Task.yield()
                    }
                }
                print("✅ Background processed \(backgroundProcessed) members")
            }
        }
        
        // Process users with batch processing
        await processUsers(response.users)
        
        await MainActor.run {
            // CRITICAL FIX: Clear channel messages before navigating to ensure full message history is loaded
            // This prevents the issue where only new WebSocket messages are shown
            print("🔄 ViewInvite: Clearing channel messages for invite channel \(serverInfo.channel_id) to ensure full history loads")
            viewState.channelMessages[serverInfo.channel_id] = []
            viewState.preloadedChannels.remove(serverInfo.channel_id)
            
            viewState.selectChannel(inServer: serverId, withId: serverInfo.channel_id)
            
            // IMPORTANT: For invite navigation, store server context for proper back behavior
            print("🎫 INVITE_ACCEPT: Setting lastInviteServerContext to \(serverId)")
            viewState.lastInviteServerContext = serverId
        }
    }
    
    private func processUsers(_ users: [User]) async {
        let userCount = users.count
        print("🔄 Processing \(userCount) users from server response")
        
        await MainActor.run {
            // Process first 50 users immediately
            let maxImmediate = 50
            var processed = 0
            
            for (index, user) in users.enumerated() {
                guard index < maxImmediate else { break }
                guard !user.id.isEmpty && user.username.count > 0 else { continue }
                
                self.viewState.users[user.id] = user
                processed += 1
            }
            
            print("✅ Immediately processed \(processed) users")
        }
        
        // Process remaining users in background
        if userCount > 50 {
            Task.detached(priority: .background) {
                var backgroundProcessed = 0
                for (index, user) in users.enumerated() {
                    guard index >= 50 else { continue }
                    guard !user.id.isEmpty && user.username.count > 0 else { continue }
                    
                    await MainActor.run {
                        self.viewState.users[user.id] = user
                    }
                    backgroundProcessed += 1
                    
                    if backgroundProcessed % 100 == 0 {
                        await Task.yield()
                        print("📊 Background processed: \((backgroundProcessed + 50))/\(userCount)")
                    }
                }
                print("✅ Background processing completed. Total: \(backgroundProcessed + 50) users")
            }
        }
    }
}

struct ServerInviteView: View {
    let serverInfo: ServerInfoResponse
    @Binding var isProcessingInvite: Bool
    let onAcceptInvite: () -> Void
    let onDeclineInvite: () -> Void
    
    var body: some View {
        VStack(spacing: .zero) {
            // Banner
            if let banner = serverInfo.server_banner {
                LazyImage(source: .file(banner), clipTo: Rectangle())
                    .frame(minWidth: 0)
            }
            
            VStack(spacing: .zero) {
                // Server icon
                Group {
                    if let server_icon = serverInfo.server_icon {
                        LazyImage(source: .file(server_icon), clipTo: Circle())
                    } else {
                        FallbackServerIcon(name: serverInfo.server_name, clipTo: Circle())
                    }
                }
                .frame(width: .size48, height: .size48)
                
                // Invitation text
                PeptideText(text: "You've been invited to join",
                            font: .peptideBody3,
                            textColor: .textGray07)
                .padding(top: .padding16, bottom: .padding4)
                
                // Server name
                PeptideText(text: serverInfo.server_name,
                            font: .peptideTitle1,
                            textColor: .textDefaultGray01)
                
                // Invited by section
                HStack(spacing: .spacing4) {
                    PeptideText(text: "Invited by",
                                font: .peptideSubhead,
                                textColor: .textGray07)
                    
                    Spacer()
                    
                    if let avatar = serverInfo.user_avatar {
                        LazyImage(source: .file(avatar), clipTo: Circle())
                            .frame(width: .size20, height: .size20)
                    }
                    
                    PeptideText(text: serverInfo.user_name,
                                font: .peptideCallout,
                                textColor: .textDefaultGray01)
                }
                .padding(.horizontal, .padding16)
                .frame(minHeight: .size40)
                .background {
                    RoundedRectangle(cornerRadius: .radiusLarge).stroke(Color.borderGray11, lineWidth: .size1)
                }
                .padding(.vertical, .padding16)
                
                // Channel and member info
                HStack(spacing: .spacing16) {
                    PeptideText(text: "#\(serverInfo.channel_name)",
                                font: .peptideCallout,
                                textColor: .textGray07)
                    
                    HStack(spacing: .spacing2) {
                        PeptideIcon(iconName: .peptideTeamUsers,
                                    size: .size16,
                                    color: .iconGray07)
                        
                        PeptideText(text: "\(serverInfo.member_count.formattedWithSeparator()) users",
                                    font: .peptideCallout,
                                    textColor: .textGray07)
                    }
                }
                
                // Accept button
                Button(action: onAcceptInvite) {
                    if isProcessingInvite {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing...")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        Text("Accept Invite")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessingInvite)
                .padding(top: .padding24, bottom: .padding16)
                
                // No thanks button
                Button(action: onDeclineInvite) {
                    PeptideText(text: "No Thanks",
                                font: .peptideButton,
                                textColor: .textDefaultGray01)
                }
            }
            .padding(.padding24)
            .background {
                RoundedRectangle(cornerRadius: .radius16).fill(Color.bgGray12)
            }
            .padding(.padding16)
        }
    }
}

#Preview{
    ViewInvite(code: "X9atcKxZ")
        .applyPreviewModifiers(withState: ViewState.preview())
        .preferredColorScheme(.dark)
}
