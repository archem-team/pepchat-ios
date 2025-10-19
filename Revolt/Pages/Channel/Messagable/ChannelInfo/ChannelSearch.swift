//
//  ChannelSearch.swift
//  Revolt
//
//  Created by Angelo on 29/08/2024.
//

import Foundation
import SwiftUI
import Types

/// A view that allows users to search through messages in a specific channel.
struct ChannelSearch: View {
    @EnvironmentObject var viewState: ViewState // Observes the application's view state.
    
    @Binding var channel: Channel // The channel in which to perform the search.
    
    @State var searchQuery: String = "" // The current search query entered by the user.
    @State var results: [Types.Message] = [] // Array to store the search results.
    
    @State private var searchTextFieldState : PeptideTextFieldState = .default
    @State private var selectedSort : ChannelSearchPayload.MessageSort = .latest
    
    @State private var isLoading : Bool = false
    @State private var timer: Timer?
    @State private var isNavigatingToMessage = false // Track if we're navigating to a message
    
    var body: some View {
        // Retrieves the server associated with the channel, if available.
        let server = channel.server.map { $viewState.servers[$0] } ?? .constant(nil)
        
        VStack(spacing: .zero){
            
            PeptideDivider(backgrounColor: .bgDefaultPurple13)
            
            
            VStack(spacing: .zero){
                
                HStack(spacing: .padding4){
                    
                    PeptideIconButton(icon: .peptideCloseLiner,
                                      color: .iconGray07,
                                      size: .size24,
                                      disabled: false){
                        
                        // Don't clear target message immediately, let the view controller handle it
                        // Instead, send a notification that we're closing search to return to the same channel
                        print("🎯 ChannelSearch: Close button pressed - Returning to channel without clearing target")
                        
                        // Send notification that we're closing search for this channel
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ChannelSearchClosing"),
                            object: ["channelId": channel.id, "isReturning": true]
                        )
                        // Also send a second notification that search was closed (compat flag)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ChannelSearchClosed"),
                            object: channel.id
                        )
                        
                        viewState.path.removeLast()
                        
                    }
                                      .padding(.padding8)
                    
                    PeptideTextField(text: $searchQuery,
                                     state: $searchTextFieldState,
                                     placeholder: self.channel.isSavedMessages ? "Search in saved notes" : "Search in group",
                                     icon: .peptideSearch,
                                     cornerRadius: .radiusLarge,
                                     height: .size40,
                                     keyboardType: .default)
                    
                }
                .padding(.padding16)
               
                
                HStack(spacing: .zero){
                    
                    ForEach(ChannelSearchPayload.MessageSort.allCases, id: \.self) { sortOption in
                        
                        PeptideTabItemIndicator(isSelected: sortOption == selectedSort, label: "\(sortOption.rawValue)"){
                            selectedSort = sortOption
                        }
                        
                    }
                }
                .padding(.vertical, .padding8)
                
                
                if searchQuery.count <= 1 {
                    
                    PeptideText(textVerbatim: "Search past conversations in this group.",
                                font: .peptideFootnote,
                                textColor: .textGray07)
                    .padding(.vertical, .padding24)
                    .padding(.horizontal, .padding16)

                } else {
                    
                    if isLoading {
                        /*LoadingSpinnerView(frameSize: CGSize(width: 32, height: 32), isActionComplete: .constant(false))
                            .padding(.top, .padding24)*/
                        
                        ProgressView()
                            .tint(.iconDefaultGray01)
                            .padding(.top, .padding24)

                       
                        
                    } else {
                        if results.isEmpty {
                            
                            
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
                            List {
                                // Displays each message found in the search results.
                                
                                Section {
                                    
                                    Color.bgGray12
                                        .frame(height: .padding16)
                                    
                                    ForEach(results) { result in
                                        MessageView(
                                            viewModel: .init(
                                                viewState: viewState, // Passes the view state to the message view.
                                                message: .constant(result), // The message object being displayed.
                                                author: .constant(viewState.users[result.author]!), // The author of the message.
                                                member: .constant(channel.server.flatMap({ viewState.members[$0]?[result.author] })), // The member associated with the author.
                                                server: server, // The server associated with the channel.
                                                channel: $channel, // A binding to the channel.
                                                replies: .constant([]), // Currently no replies are shown.
                                                channelScrollPosition: .empty, // Placeholder for channel scroll position.
                                                editing: .constant(nil) // No message is currently being edited.
                                            ),
                                            isStatic: true
                                        )
                                        .padding(.horizontal, .padding16)
                                        .contentShape(Rectangle()) // Make the entire message area tappable
                                        .onTapGesture {
                                            navigateToMessage(result)
                                        }
                                    }
                                }
                                .listRowInsets(.init())
                                .listRowSeparator(.hidden)
                                .listRowSpacing(0)
                                .listRowBackground(Color.clear)
                                
                                
                            }
                            .environment(\.defaultMinListRowHeight, 0)
                            .frame(maxWidth: .infinity)
                            .scrollContentBackground(.hidden)
                            .listStyle(.plain)
                            .background(Color.bgGray12)
                            .listStyle(.plain)
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                }
                
                
                Spacer(minLength: .zero)
                
            }
            .background{
                UnevenRoundedRectangle(topLeadingRadius: .radiusLarge, topTrailingRadius: .radiusLarge)
                    .fill(Color.bgGray12)
            }
           
        }
        //.searchable(text: $searchQuery) // Enables the search bar with a binding to the search query.
        .onChange(of: selectedSort, {_ , sort in
            self.search(query: searchQuery)
        })
        .onChange(of: searchQuery, { _, query in
            debounceRequest(with: query)
        })
        .onDisappear{
            timer?.invalidate()
            
            // Only clear target message ID if we're not navigating to a message AND not returning to the same channel
            if !isNavigatingToMessage {
                // Check if we're returning to the same channel (close button pressed)
                // In this case, we don't want to clear the target message ID
                print("🎯 ChannelSearch: onDisappear - Not navigating to message, preserving target for return")
                // Don't clear currentTargetMessageId here, let the view controller handle it
            } else {
                print("🎯 ChannelSearch: onDisappear - Preserving currentTargetMessageId for navigation")
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden)
        .fillMaxSize()
    }
    
    
    private func debounceRequest(with text: String) {
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            search(query: text)
        }
    }
    
    /// Navigates to the original location of a message from search results using the existing URL system
    /// - Parameter message: The message to navigate to
    private func navigateToMessage(_ message: Types.Message) {
        // Set flag to indicate we're navigating to preserve target message ID
        isNavigatingToMessage = true
        
        // Create the appropriate URL for the message based on whether it's in a server or DM
        Task {
            let serverId = viewState.channels[message.channel]?.server
            let messageLink = await generateMessageLink(
                serverId: serverId,
                channelId: message.channel,
                messageId: message.id,
                viewState: viewState
            )
            let messageURL = URL(string: messageLink)!
            
            await MainActor.run {
                print("🔍 Search: Navigating to message URL: \(messageURL.absoluteString)")
                // Use the existing URL handling system by simulating a URL tap
                handleMessageURL(messageURL)
            }
        }
    }
    
    /// Handles message URL navigation using the existing internal URL system
    /// - Parameter url: The message URL to handle
    private func handleMessageURL(_ url: URL) {
        print("🔗 ChannelSearch: Handling message URL: \(url.absoluteString)")
        
        if url.absoluteString.hasPrefix("https://peptide.chat/server/") {
            let components = url.pathComponents
            
            if components.count >= 6 {
                let serverId = components[2]
                let channelId = components[4]
                let messageId = components[5]
                
                // Check if server and channel exist
                if viewState.servers[serverId] != nil && viewState.channels[channelId] != nil {
                    // Check if user is a member of the server
                    guard let currentUser = viewState.currentUser else {
                        print("❌ ChannelSearch: Current user not found")
                        return
                    }
                    
                    let userMember = viewState.getMember(byServerId: serverId, userId: currentUser.id)
                    
                    if userMember != nil {
                        // User is a member - navigate to the channel
                        print("✅ ChannelSearch: User is member, navigating to channel")
                        
                        // Set flag to indicate we're navigating to preserve target message ID
                        isNavigatingToMessage = true
                        
                        // Clear existing messages for this channel
                        viewState.channelMessages[channelId] = []
                        
                        // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                        // This ensures that when user presses back, they go to server list instead of previous channel
                        print("🔄 ChannelSearch: Clearing navigation path to prevent back to previous channel")
                        viewState.path = []
                        
                        // Navigate immediately without delay
                        // Navigate to the server and channel
                        self.viewState.selectServer(withId: serverId)
                        self.viewState.selectChannel(inServer: serverId, withId: channelId)
                        
                        // Set the target message ID for nearby API call
                        self.viewState.currentTargetMessageId = messageId
                        print("🎯 ChannelSearch: Setting target message ID: \(messageId)")
                        
                        self.viewState.path.append(NavigationDestination.maybeChannelView)
                    } else {
                        // User is not a member - show error
                        print("❌ ChannelSearch: User is not member of server")
                        viewState.showAlert(message: "You don't have access to this server", icon: .peptideInfo)
                    }
                } else {
                    // Server or channel not found
                    print("❌ ChannelSearch: Server or channel not found")
                    viewState.showAlert(message: "Channel not found", icon: .peptideInfo)
                }
            }
        } else if url.absoluteString.hasPrefix("https://peptide.chat/channel/") {
            let components = url.pathComponents
            
            if components.count >= 4 {
                let channelId = components[2]
                let messageId = components[3]
                
                if let targetChannel = viewState.channels[channelId] {
                    // Check access for DM channels
                    switch targetChannel {
                    case .dm_channel(let dmChannel):
                        guard let currentUser = viewState.currentUser else {
                            print("❌ ChannelSearch: Current user not found")
                            return
                        }
                        
                        if dmChannel.recipients.contains(currentUser.id) {
                            navigateToChannel(channelId: channelId, messageId: messageId)
                        } else {
                            print("❌ ChannelSearch: User doesn't have access to DM")
                            viewState.showAlert(message: "You don't have access to this channel", icon: .peptideInfo)
                        }
                    case .group_dm_channel(let groupDmChannel):
                        guard let currentUser = viewState.currentUser else {
                            print("❌ ChannelSearch: Current user not found")
                            return
                        }
                        
                        if groupDmChannel.recipients.contains(currentUser.id) {
                            navigateToChannel(channelId: channelId, messageId: messageId)
                        } else {
                            print("❌ ChannelSearch: User doesn't have access to group DM")
                            viewState.showAlert(message: "You don't have access to this channel", icon: .peptideInfo)
                        }
                    default:
                        // Other channel types
                        navigateToChannel(channelId: channelId, messageId: messageId)
                    }
                } else {
                    print("❌ ChannelSearch: Channel not found")
                    viewState.showAlert(message: "Channel not found", icon: .peptideInfo)
                }
            }
        }
    }
    
    /// Helper function to navigate to a channel with a specific message
    /// - Parameters:
    ///   - channelId: The channel ID to navigate to
    ///   - messageId: The message ID to highlight
    private func navigateToChannel(channelId: String, messageId: String) {
        print("✅ ChannelSearch: Navigating to channel \(channelId) with message \(messageId)")
        
        // Set flag to indicate we're navigating to preserve target message ID
        isNavigatingToMessage = true
        
        // Clear existing messages for this channel
        viewState.channelMessages[channelId] = []
        
        // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
        // This ensures that when user presses back, they go to server list instead of previous channel
        print("🔄 ChannelSearch: Clearing navigation path to prevent back to previous channel")
        viewState.path = []
        
        // Navigate immediately without delay
        // Navigate to the channel
        self.viewState.selectDm(withId: channelId)
        
        // Set the target message ID for nearby API call
        self.viewState.currentTargetMessageId = messageId
        print("🎯 ChannelSearch: Setting target message ID: \(messageId)")
        
        self.viewState.path.append(NavigationDestination.maybeChannelView)
    }

    func search(query : String){
      
        if query.count >= 1, query.count <= 64 {
            Task {
                do {
                    
                    results = []
                    
                    isLoading = true
                    
                    // Asynchronously fetches the search results from the server.
                    let response = try await viewState.http.searchChannel(channel: channel.id,
                                                                          sort: selectedSort,
                                                                          query: query).get()
                    
                    // Updates the user list with new users found in the response.
                    for user in response.users {
                        if !viewState.users.keys.contains(user.id) {
                            viewState.users[user.id] = user
                        }
                    }
                    
                    // Updates the member list with new members found in the response.
                    if let members = response.members {
                        for member in members {
                            if !(viewState.members[member.id.server]?.keys.contains(member.id.user) ?? false) {
                                viewState.members[member.id.server]![member.id.user] = member
                            }
                        }
                    }
                    
                    
                    // Updates the results with the messages found in the response.
                    results = response.messages
                    
                    isLoading = false
                } catch {
                    // Handle errors appropriately (optional)
                    print("Error fetching search results: \(error)") // Log any errors that occur.
                    isLoading = false

                }
            }
        } else {
            isLoading = false
            results = []
        }
    }
}

#Preview {
    // Prepares a preview of the ChannelSearch view for testing or design purposes.
    let viewState = ViewState.preview().applySystemScheme(theme: .dark) // Creates a preview instance of the ViewState.
    
    return ChannelSearch(channel: .constant(viewState.channels["0"]!)) // Displays the search view for a specific channel.
        .applyPreviewModifiers(withState: viewState) // Applies preview modifiers to the view.
}

// MARK: - Helper Functions
/// Generates a dynamic message link based on the current domain
private func generateMessageLink(serverId: String?, channelId: String, messageId: String, viewState: ViewState) async -> String {
    // Get the current base URL and determine the web domain
    let baseURL = await viewState.baseURL ?? viewState.defaultBaseURL
    let webDomain: String
    
    if baseURL.contains("peptide.chat") {
        webDomain = "https://peptide.chat"
    } else if baseURL.contains("app.revolt.chat") {
        webDomain = "https://app.revolt.chat"
    } else {
        // Fallback for other instances - extract domain from API URL
        if let url = URL(string: baseURL),
           let host = url.host {
            webDomain = "https://\(host)"
        } else {
            webDomain = "https://app.revolt.chat" // Ultimate fallback
        }
    }
    
    // Generate proper URL based on channel type
    if let serverId = serverId, !serverId.isEmpty {
        // Server channel
        return "\(webDomain)/server/\(serverId)/channel/\(channelId)/\(messageId)"
    } else {
        // DM channel
        return "\(webDomain)/channel/\(channelId)/\(messageId)"
    }
}
