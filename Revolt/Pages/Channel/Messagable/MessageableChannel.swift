//
//  MessageableChannel.swift
//  Revolt
//
//  Created by Angelo on 18/10/2023.
//

import Foundation
import SwiftUI
import Combine
import Types
import SwiftUIIntrospect
// Add imports for extensions to avoid duplicate implementations
import class UIKit.UIResponder
import UIKit

// MARK: - Extensions Supporting SwiftUI-Introspect

// Edge.Set extensions for ignoresSafeArea modifiers
extension Edge.Set {
    static var container: Edge.Set { .all }
    static var keyboard: Edge.Set { .bottom }
}

// ScrollDismissesKeyboardMode for compatibility
enum ScrollDismissesKeyboardMode {
    case immediately
    case interactively
    case never
}

// Extensions for view modifiers
extension View {
    // Configure ScrollView for chat with SwiftUI-Introspect
    func configureScrollViewForChat() -> some View {
        self.introspect(.scrollView, on: .iOS(.v16, .v17)) { scrollView in
            scrollView.keyboardDismissMode = .interactive
            scrollView.contentInsetAdjustmentBehavior = .always
            scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        }
    }
    
    // Custom scroll dismisses keyboard implementation
    func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View {
        self.introspect(.scrollView, on: .iOS(.v16, .v17)) { scrollView in
            switch mode {
            case .immediately:
                scrollView.keyboardDismissMode = .onDrag
            case .interactively:
                scrollView.keyboardDismissMode = .interactive
            case .never:
                scrollView.keyboardDismissMode = .none
            }
        }
    }
    
    // Default anchor point for scroll view
    func defaultScrollAnchor(_ point: UnitPoint) -> some View {
        self // Placeholder implementation
    }
    
    // Fill maximum size
    func fillMaxSize() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Apply common chat UI fixes
    func applyChatUIFixes() -> some View {
        self.modifier(ChatUIFixesModifier())
    }
    
    // NOTE: keyboardHeight is imported from View+Introspect.swift
}

// Modifier for chat UI fixes
struct ChatUIFixesModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.introspect(.scrollView, on: .iOS(.v16, .v17)) { scrollView in
            scrollView.keyboardDismissMode = .interactive
            scrollView.contentInsetAdjustmentBehavior = .always
            scrollView.automaticallyAdjustsScrollIndicatorInsets = true
            scrollView.decelerationRate = .fast
        }
    }
}

struct ChannelScrollController {
    var proxy: ScrollViewProxy?
    @Binding var highlighted: String?
    
    func scrollTo(message id: String) {
        // print("🎯 ChannelScrollController: Scrolling to message \(id)")
        withAnimation(.easeInOut) {
            proxy?.scrollTo(id)
            highlighted = id
            // print("🎯 ChannelScrollController: Set highlighted to \(id)")
        }
        
        Task {
            do {
                try await Task.sleep(for: .seconds(2))
                
                await MainActor.run {
                    withAnimation(.easeInOut) {
                        highlighted = nil
                        // print("🎯 ChannelScrollController: Cleared highlight")
                    }
                }
            } catch {
                // Handle cancellation gracefully
                // print("Highlight clear task was cancelled")
            }
        }
    }
    
    static var empty: ChannelScrollController {
        .init(proxy: nil, highlighted: .constant(nil))
    }
}

@MainActor
class MessageableChannelViewModel: ObservableObject {
    @ObservedObject var viewState: ViewState
    @Published var channel: Channel
    @Published var server: Server?
    @Binding var messages: [String]

    
    
    init(viewState: ViewState, channel: Channel, server: Server?, messages: Binding<[String]>) {
        self.viewState = viewState
        self.channel = channel
        self.server = server
        self._messages = messages
        
        // Send initial notification only after initialization
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("MessagesDidChange"), object: nil)
        }
        
        // We can't use sink on Binding directly
        // Monitor message changes via other means
    }
    
    // For managing Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    func getMember(message: Message) -> Binding<Member?> {
        guard let server = server else {
            return .constant(nil)
        }
        
        return Binding(
            get: { self.viewState.members[server.id]?[message.author] },
            set: { newValue in
                if let newValue = newValue {
                    self.viewState.members[server.id, default: [:]][message.author] = newValue
                } else {
                    self.viewState.members[server.id]?.removeValue(forKey: message.author)
                }
            }
        )
    }
    
    func loadMoreMessages(before: String? = nil) async -> FetchHistory? {
        if isPreview { return nil }
        
        // Create an array of message IDs to include in the request
        let messageIds: [String] = before != nil ? [before!] : []
        
        // Get the server ID from the channel
        let serverId = channel.server
        
        // SMART LIMIT: Use 10 for specific channel, 50 for others
        let messageLimit = (channel.id == "01J7QTT66242A7Q26A2FH5TD48") ? 10 : 50
        
        let result = (try? await viewState.http.fetchHistory(
            channel: channel.id,
            limit: messageLimit, // Smart limit based on channel
            before: before,
            server: serverId,
            messages: messageIds
        ).get()) ?? FetchHistory(messages: [], users: [])
        
        for user in result.users {
            viewState.users[user.id] = user
        }
        
        if let members = result.members {
            for member in members {
                // Ensure server entry exists and safely assign member
                viewState.members[member.id.server, default: [:]][member.id.user] = member
            }
        }
        
        var ids: [String] = []
        
        for message in result.messages {
            viewState.messages[message.id] = message
            ids.append(message.id)
        }
        
        // Safely handle the case when channelMessages[channel.id] might be nil
        if let existingMessages = viewState.channelMessages[channel.id] {
            viewState.channelMessages[channel.id] = ids.reversed() + existingMessages
        } else {
            viewState.channelMessages[channel.id] = ids.reversed()
        }
        
        // Notify that messages have changed
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("MessagesDidChange"), object: nil)
        }
        
        return result
    }
    
    func loadMoreMessagesIfNeeded(current: Message?) async -> FetchHistory? {
        guard let item = current else {
            return await loadMoreMessages()
        }
        
        // Check if messages array has elements before accessing the first one
        guard let firstMessage = $messages.wrappedValue.first else {
            return await loadMoreMessages()
        }
        
        if firstMessage == item.id {
            return await loadMoreMessages(before: item.id)
        }
        
        return nil
    }
    

    // Notify UIKit controller when typing status changes
    func notifyTypingStatusDidChange(users: [(User, Member?)]) {
        NotificationCenter.default.post(name: NSNotification.Name("TypingStatusDidChange"), object: users)
    }
}

struct MessageActionData {
    var isLoadingAck : Bool = false
    var lastMessageIdAck : String? = nil
    
    var lastPreviousMessageId : String? = nil
    var isLoadingMore : Bool = false
}

struct MessageableChannelView: View {
    @EnvironmentObject var viewState: ViewState
    @ObservedObject var viewModel: MessageableChannelViewModel
    
    @State var over18: Bool = false
    @State var over18HasSeen: Bool = false
    @State var showDetails: Bool = false
    @State var showingSelectEmoji = false
    @State var currentlyEditing: Message? = nil
    @State var highlighted: String? = nil
    @State var replies: [Reply] = []
    @State var scrollPosition: String? = nil
    @State var topMessage: MessageContentsViewModel? = nil
    @State var bottomMessage: MessageContentsViewModel? = nil
    @State var messages: [MessageContentsViewModel] = []
    @State private var keyboardHeight: CGFloat = 0
    @State private var showNSFWSheet = false
    @State private var isLoadingMore : Bool = false
    @State private var isScrolling : Bool = false
    @State private var lastKeyboardChange: Date = Date()
    @State private var scrollView: UIScrollView? = nil

    @State private var fixToScroll : Bool = false
    
    var toggleSidebar: () -> ()
    
    
    @FocusState var focused: Bool
    
    @State private var keyboardLatesItem : String? = nil
    @State private var showNewMessage : Bool = true
    
    var sendMessagePermission : Bool {
        
        if case .dm_channel(let channel) = viewModel.channel {
            
            
            if let otherUser = channel.recipients.filter({ $0 != viewState.currentUser!.id }).first {
                let rel =   viewState.users.first(where: {$0.value.id == otherUser})?.value.relationship
                return rel != .Blocked && rel != .BlockedOther
            }
            
            
        } else {
            let member = viewModel.server.flatMap {
                viewState.members[$0.id]?[viewState.currentUser!.id]
            }
            
            let permissions = resolveChannelPermissions(from: viewState.currentUser!, targettingUser: viewState.currentUser!, targettingMember: member, channel: viewModel.channel, server: viewModel.server)
            
            return permissions.contains(.sendMessages)
        }
        
        return true
        
        
    }
    
    var isCompactMode: Bool {
        return TEMP_IS_COMPACT_MODE.0
    }
    
    func viewMembers() {
        
    }
    
    func createInvite() {
        
    }
    
    func manageNotifs() {
        
    }
    
    func formatRelative(id: String) -> String {
        let created = createdAt(id: id)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        
        return formatter.localizedString(for: created, relativeTo: Date.now)
    }
    
    func getCurrentlyTyping() -> [(User, Member?)]? {
        guard let currentUserId = viewState.currentUser?.id else {
            return nil
        }
        
        return viewState.currentlyTyping[viewModel.channel.id]?.compactMap({ user_id in
            guard let user = viewState.users[user_id], user_id != currentUserId else {
                return nil
            }
            
            var member: Member?
            
            if let server = viewModel.server {
                member = viewState.members[server.id]?[user_id]
            }
            
            return (user, member)
        })
    }
    
    
    func formatTypingIndicatorText(withUsers users: [(User, Member?)]) -> String {
        let base = ListFormatter.localizedString(byJoining: users.map({ (user, member) in member?.nickname ?? user.display_name ?? user.username }))
        
        let ending = users.count == 1 ? "is typing" : "are typing"
        
        return "\(base) \(ending)..."
    }
    
    func getAuthor(message: Binding<Message>) -> Binding<User> {
        Binding($viewState.users[message.author.wrappedValue]) ?? .constant(User(id: String(repeating: "0", count: 26), username: "Unknown", discriminator: "0000"))
    }
    
    func getMessages(scrollProxy: ScrollViewProxy?) -> [MessageContentsViewModel] {
        // Step 1: Get flat message bindings
        let flatMessages = $viewModel.messages.compactMap { messageIdBinding in
            let messageId = messageIdBinding.wrappedValue
            if let message = viewState.messages[messageId] {
                return Binding(get: { message }, set: { viewState.messages[messageId] = $0 })
            }
            return nil
        }
    
        // Step 2: Update viewModel messages
        DispatchQueue.main.async {
            let messageIds = flatMessages.map { $0.wrappedValue.id }
            viewModel.messages = messageIds
        }
            
        // Step 3: Handle compact mode with a simpler approach
        if isCompactMode {
            let compactModeMessages = flatMessages.map { msg in
                createMessageViewModel(
                    message: msg,
                    scrollProxy: scrollProxy,
                    isFirstInGroup: true,
                    isLastInGroup: true
                )
            }
            return compactModeMessages
        } 
        // Step 4: Handle standard mode with message grouping
        else {
            // Group messages by author and timestamp
            let groupedMessageResults = groupMessages(flatMessages)
            
            // Create view models from grouped messages
            let messages = createMessageViewModels(
                from: groupedMessageResults,
                with: scrollProxy
            )
            
            // Step 5: Handle loading more messages if needed
            Task(priority: .high) {
                topMessage = messages.first
                bottomMessage = messages.last
                
                if messages.isEmpty {
                    await loadMoreMessages(before: nil)
                } else if messages.count < 50 {
                    isLoadingMore = true
                    await loadMoreMessages(before: topMessage?.message.id)
                }
            }
            
            // Ensure uniqueness based on message ID
            var uniqueMessages: [MessageContentsViewModel] = []
            var processedIds = Set<String>()
            
            for message in messages {
                if !processedIds.contains(message.message.id) {
                    uniqueMessages.append(message)
                    processedIds.insert(message.message.id)
                }
            }
            
            return uniqueMessages
        }
    }
    
    // Helper function to create a MessageContentsViewModel
    private func createMessageViewModel(
        message: Binding<Message>,
        scrollProxy: ScrollViewProxy?,
        isFirstInGroup: Bool,
        isLastInGroup: Bool
    ) -> MessageContentsViewModel {
                    return MessageContentsViewModel(
                        viewState: viewState,
            message: message,
            author: getAuthor(message: message),
            member: viewModel.getMember(message: message.wrappedValue),
                        server: $viewModel.server,
                        channel: $viewModel.channel,
                        replies: $replies,
                        channelScrollPosition: ChannelScrollController(proxy: scrollProxy, highlighted: $highlighted),
                        editing: $currentlyEditing,
            isFirstInGroup: isFirstInGroup,
            isLastInGroup: isLastInGroup
                    )
                }
    
    // Helper function to group messages by author and time proximity
    private func groupMessages(_ messages: [Binding<Message>]) -> [[Binding<Message>]] {
                var groupedMessages: [[Binding<Message>]] = []
                var currentGroup: [Binding<Message>] = []
                var lastAuthor: String?
                var lastTimestamp: Date?
                
        for msg in messages {
                    let currentMessage = msg.wrappedValue
                    let createdAtTime = createdAt(id: currentMessage.id)
                    let isFirstInGroup: Bool
                    
            // Determine if this message should start a new group
                    if currentMessage.system != nil {
                        isFirstInGroup = true
            } else if let lastAuthor = lastAuthor, let lastTimestamp = lastTimestamp {
                        let sameAuthor = lastAuthor == currentMessage.author
                        let timeDiff = lastTimestamp.distance(to: createdAtTime)
                        let hasReplies = (currentMessage.replies?.count ?? 0) > 0
                        
                        isFirstInGroup = !(sameAuthor && timeDiff < (5 * 60) && !hasReplies)
                    } else {
                        isFirstInGroup = true
                    }
                    
            // Create a new group if needed
                    if isFirstInGroup, !currentGroup.isEmpty {
                        groupedMessages.append(currentGroup)
                        currentGroup = []
                    }
                    
            // Add to current group and update tracking variables
                    currentGroup.append(msg)
                    lastAuthor = currentMessage.author
                    lastTimestamp = createdAtTime
                }
                
        // Add the last group if not empty
                if !currentGroup.isEmpty {
                    groupedMessages.append(currentGroup)
                }
                
        return groupedMessages
    }
    
    // Helper function to create view models from grouped messages
    private func createMessageViewModels(
        from groupedMessages: [[Binding<Message>]],
        with scrollProxy: ScrollViewProxy?
    ) -> [MessageContentsViewModel] {
        return groupedMessages.flatMap { group in
            group.enumerated().map { index, msg in
                        let isFirstInGroup = index == 0
                        let isLastInGroup = index == group.count - 1
                        
                return createMessageViewModel(
                            message: msg,
                    scrollProxy: scrollProxy,
                            isFirstInGroup: isFirstInGroup,
                            isLastInGroup: isLastInGroup
                        )
                    }
                }
    }
    
    func loadMoreMessages(before message: String?) async {
        if !viewState.atTopOfChannel.contains(viewModel.channel.id) {
            if let new = await viewModel.loadMoreMessages(before: message), new.messages.count < 50 {
                viewState.atTopOfChannel.insert(viewModel.channel.id)
            }
        } else {
            isLoadingMore = false
        }
    }
    
    // MARK: - View Components
    
    /// Main message list view
    @ViewBuilder
    private func messageListView() -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Empty state or loading indicator
                if viewState.atTopOfChannel.contains(viewModel.channel.id) && !isLoadingMore {
                    channelEmptyStateView()
                } else if isLoadingMore {
                    ProgressView()
                        .padding(40)
                }
                
                // Messages
                LazyVStack(spacing: .zero) {
                    ForEach(messages, id: \.message.id) { msgViewModel in
                        messageRow(msgViewModel: msgViewModel)
                            .id(msgViewModel.message.id)
                            .background(
                                msgViewModel.message.id == messages.last?.message.id ? 
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: PositionPreferenceKey.self, 
                                        value: geometry.frame(in: .global).maxY
                                    )
                                } : nil
                            )
                    }
                }
                .onPreferenceChange(PositionPreferenceKey.self) { value in
                    self.lastMessageBottomPosition = value
                    adjustScroll(proxy: nil)
                }
                .scrollTargetLayout()
                
                // Increase bottom spacing
                Spacer()
                    .frame(height: 100)
                    .id("bottomSpacer")
            }
            .padding(.bottom, 8)
        }
        .introspect(.scrollView, on: .iOS(.v16, .v17)) { scrollView in
            self.scrollView = scrollView
            scrollView.keyboardDismissMode = .interactive
            scrollView.contentInsetAdjustmentBehavior = .always
            scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        }
        .background(Color.bgDefaultPurple13)
        .onChange(of: viewModel.messages) { _, _ in
            DispatchQueue.main.async {
                // Store the last message ID before updating
                let wasAtBottom = messages.isEmpty || (messages.last?.message.id == viewModel.messages.last)
                
                // Update messages
                messages = []
                messages = getMessages(scrollProxy: nil)
                scrollPosition = messages.last?.message.id
                
                // Force scrolling to last message with a small delay to ensure UI updates first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToLastMessage(proxy: nil, animated: true)
                    
                    // Double check with another small delay to ensure scrolling happens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToLastMessage(proxy: nil, animated: true)
                    }
                }
            }
        }
        .task {
            DispatchQueue.main.async {
                messages = getMessages(scrollProxy: nil)
                scrollToLastMessage(proxy: nil, animated: false)
            }
        }
    }
    
    /// Chat content area including messages and typing indicator
    @ViewBuilder
    private func chatContentArea() -> some View {
        ZStack(alignment: .bottom) {
            // Message list
            messageListView()
            
            // Typing indicator
            if let users = getCurrentlyTyping(), !users.isEmpty {
                typingIndicator(users: users)
                    .transition(.move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgDefaultPurple13)
    }
    
    /// Input section based on permissions
    @ViewBuilder
    private func inputSection() -> some View {
        if sendMessagePermission {
            MessageBox(
                channel: viewModel.channel,
                server: viewModel.server,
                channelReplies: $replies,
                focusState: $focused,
                showingSelectEmoji: $showingSelectEmoji,
                editing: $currentlyEditing
            )
        } else {
            noPermissionMessageView()
        }
    }
    
    /// NSFW sheet configuration
    private func configureNSFWPopup(_ params: Any) -> Any {
        return params
    }
    
    // MARK: - Main View Body
    
    @State private var inputTopPosition: CGFloat = 0
    @State private var lastMessageBottomPosition: CGFloat = 0
    @State private var safeSpacing: CGFloat = 12 // Safe spacing between the last message and input

    // 1. Define a structure for transferring position with preference key
    struct PositionPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Main content area 
                VStack(spacing: 0) {
                    // Header
                    channelHeaderView()
                        .background(Color.bgDefaultPurple13)
                    
                    // Content
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                // Empty state or loading indicator
                                if viewState.atTopOfChannel.contains(viewModel.channel.id) && !isLoadingMore {
                                    channelEmptyStateView()
                                } else if isLoadingMore {
                                    ProgressView()
                                        .padding(40)
                                }
                                
                                // Messages
                                LazyVStack(spacing: .zero) {
                                    ForEach(messages, id: \.message.id) { msgViewModel in
                                        let isLastMessage = msgViewModel.message.id == messages.last?.message.id
                                        
                                        messageRow(msgViewModel: msgViewModel)
                                            .id(msgViewModel.message.id)
                                            .background(
                                                Group {
                                                    if isLastMessage {
                                                        GeometryReader { geometry in
                                                            Color.clear.preference(
                                                                key: PositionPreferenceKey.self, 
                                                                value: geometry.frame(in: .global).maxY
                                                            )
                                                        }
                                                    } else {
                                                        Color.clear
                                                    }
                                                }
                                            )
                                    }
                                }
                                .onPreferenceChange(PositionPreferenceKey.self) { value in
                                    self.lastMessageBottomPosition = value
                                    adjustScroll(proxy: proxy)
                                }
                                .scrollTargetLayout()
                                
                                // Increase bottom spacing
                                Spacer()
                                    .frame(height: 100)
                                    .id("bottomSpacer")
                            }
                        }
                        .introspect(.scrollView, on: .iOS(.v16, .v17)) { scrollView in
                            self.scrollView = scrollView
                            scrollView.keyboardDismissMode = .interactive
                            scrollView.contentInsetAdjustmentBehavior = .always
                            scrollView.automaticallyAdjustsScrollIndicatorInsets = true
                            scrollView.contentInset.bottom = 80
                        }
                        .defaultScrollAnchor(.bottom)
                        .background(Color.bgDefaultPurple13)
                        .onChange(of: viewModel.messages) { _, _ in
                            // Update messages without clearing them first to avoid jumping
                            messages = getMessages(scrollProxy: proxy)
                            
                            // Only scroll if we're at the bottom or it's a new message
                            if messages.isEmpty || scrollPosition == messages.last?.message.id {
                                scrollToLastMessage(proxy: proxy, animated: false)
                            }
                        }
                        .onChange(of: keyboardHeight) { oldValue, newValue in
                            // Always scroll to the latest message when keyboard height changes
                            if oldValue != newValue && !isScrolling {
                                isScrolling = true
                                let delay: Double = newValue > 0 ? 0.1 : 0.3
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        if let lastMessageId = messages.last?.message.id {
                                            proxy.scrollTo(lastMessageId, anchor: .bottom)
                                        } else {
                                            proxy.scrollTo("bottomSpacer", anchor: .bottom)
                                        }
                                    }
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isScrolling = false
                                    }
                                }
                            }
                        }
                        .task {
                            // Load messages and immediately scroll to bottom without animation
                            messages = getMessages(scrollProxy: proxy)
                            // Set initial scroll position to the last message
                            scrollPosition = messages.last?.message.id
                            
                            // Immediately scroll to bottom without delay to prevent jumping
                            if let lastMessageId = messages.last?.message.id {
                                proxy.scrollTo(lastMessageId, anchor: .bottom)
                            } else {
                                proxy.scrollTo("bottomSpacer", anchor: .bottom)
                            }
                        }
                    }
                    
                    // Typing indicator
                    if let users = getCurrentlyTyping(), !users.isEmpty {
                        typingIndicator(users: users)
                            .transition(.move(edge: .bottom))
                    }
                }
                // Add padding to content section based on keyboard height
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight : 0)
                
                // Input section - with position tracking
                VStack(spacing: 0) {
                    if sendMessagePermission {
                        MessageBox(
                            channel: viewModel.channel,
                            server: viewModel.server,
                            channelReplies: $replies,
                            focusState: $focused,
                            showingSelectEmoji: $showingSelectEmoji,
                            editing: $currentlyEditing
                        )
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: PositionPreferenceKey.self,
                                    value: geometry.frame(in: .global).minY
                                )
                            }
                        )
                        .onPreferenceChange(PositionPreferenceKey.self) { value in
                            if value > 0 && value != inputTopPosition {
                                self.inputTopPosition = value
                                adjustScroll(proxy: nil)
                            }
                        }
                    } else {
                        noPermissionMessageView()
                    }
                }
                .padding(.bottom, keyboardHeight > 0 ? max(0, keyboardHeight - 25) : 0)
            }
            .background(Color.bgDefaultPurple13)
            .onTapGesture {
                focused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
                    .keyboardHeight(keyboardHeight: $keyboardHeight)
        .animation(.easeInOut(duration: 0.25), value: keyboardHeight)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .blur(radius: self.showNSFWSheet ? 10 : 0)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ChannelSearchClosing"))) { notification in
            if let userInfo = notification.object as? [String: Any],
               let channelId = userInfo["channelId"] as? String,
               let isReturning = userInfo["isReturning"] as? Bool,
               channelId == viewModel.channel.id && isReturning {
                
                print("🔍 SWIFTUI: Received search closing notification, reloading messages")
                
                // Check if we have messages in ViewState
                let hasMessages = !(viewModel.viewState.channelMessages[channelId]?.isEmpty ?? true)
                
                if hasMessages {
                    // Reload messages to ensure they show up
                    DispatchQueue.main.async {
                        messages = getMessages(scrollProxy: nil)
                        
                        // Scroll to bottom if messages exist
                        if !messages.isEmpty {
                            scrollToLastMessage(proxy: nil, animated: false)
                        }
                    }
                } else {
                    // No messages in ViewState, need to reload from API
                    print("🔍 SWIFTUI: No messages in ViewState, reloading from API")
                    
                    Task {
                        await loadMoreMessages(before: nil)
                    }
                }
            }
        }
            .popup(isPresented: $showNSFWSheet, 
                   view: {
                       NSFWConfirmationSheet(
                           isPresented: $showNSFWSheet,
                           channelName: viewModel.channel.getName(viewState)
                       ) { confirmed in
                           if !confirmed {
                               viewState.path.removeLast()
                           }
                       }
                   }, 
                   customize: { params in
                       params.type(.default)
                           .isOpaque(true)
                           .appearFrom(.bottomSlide)
                           .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
                           .closeOnTap(false)
                           .closeOnTapOutside(false)
                   })
            .task {
                if viewModel.channel.nsfw && !self.over18HasSeen {
                    self.over18HasSeen = true
                    self.showNSFWSheet = true
                }
            }
            .toolbar(.hidden)
            
            // Loading overlay - show when channel is loading
            if viewState.isLoadingChannelMessages {
                ChannelLoadingView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
    
    @State private var scrollViewContentInsetBottom: CGFloat = 60
    
    /// Scroll to the bottom of the chat
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if !messages.isEmpty {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottomSpacer", anchor: .bottom)
            }
        }
    }
    
    /// Scroll to the last message, optionally with animation
    private func scrollToLastMessage(proxy: ScrollViewProxy?, animated: Bool = true, extraOffset: CGFloat = 0) {
        // Determine the target to scroll to
        let targetId = messages.last?.message.id ?? "bottomSpacer"
        
        // Define the scroll action
        let scrollAction = {
            if let proxy = proxy {
                proxy.scrollTo(targetId, anchor: .bottom)
            } else if let scrollView = self.scrollView, targetId != "bottomSpacer" {
                // Fallback for when proxy isn't available
                if let lastMessageView = scrollView.subviews.first?.subviews.first?.subviews.compactMap({ $0.subviews }).flatMap({ $0 }).first(where: { $0.accessibilityIdentifier == targetId }) {
                    scrollView.scrollRectToVisible(lastMessageView.frame, animated: animated)
                }
            }
        }
        
        // Execute the scroll action
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollAction()
            }
        } else {
            scrollAction()
        }
        
        // Update scroll position state
        scrollPosition = targetId == "bottomSpacer" ? nil : targetId
    }
    
    @ViewBuilder
    private func noPermissionMessageView() -> some View {
                        let isDm = self.viewModel.channel.isDM
                        
                        HStack(spacing: .padding8) {
                            PeptideIcon(iconName: .peptideInfo,
                                        size: .size24,
                                        color: .iconGray04)
                            
                            PeptideText(
                                text: isDm ?
                    "You don't have permission to send message in this DM." :
                                    "You don't have permission to send messages in this channel.",
                                font: .peptideBody2,
                                textColor: .textGray07,
                                alignment: .leading
                            )
                            
                            Spacer(minLength: .zero)
                        }
                        .padding(.padding12)
                        .background(
                            RoundedRectangle(cornerRadius: .size8)
                                .fill(Color.bgGray12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: .size8)
                                .stroke(Color.borderGray11, lineWidth: .size1)
                        )
                        .padding(.horizontal, .padding16)
                        .padding(.top, .padding16)
                        .padding(.bottom, .padding32)
    }
    
    @ViewBuilder
    private func channelHeaderView() -> some View {
        VStack(spacing: .zero) {
            HStack(spacing: .zero) {
                        PeptideIconButton(icon: .peptideBack,
                                          color: .iconDefaultGray01,
                                  size: .size24) {
                            viewState.path.removeLast()
                        }.padding(.trailing, .padding16)
                        
                Button {
                            if case .dm_channel(let channel) = self.viewModel.channel {
                        let userId = channel.recipients.first { $0 != self.viewState.currentUser?.id } ?? ""
                                if let user = self.viewState.users[userId] {
                                    self.viewState.openUserSheet(user: user)
                                }
                    } else if self.viewModel.channel.isNotSavedMessages {
                                self.viewState.path.append(NavigationDestination.channel_info(viewModel.channel.id, viewModel.server?.id))
                            }
                        } label: {
                    HStack(spacing: .zero) {
                                ChannelOnlyIcon(channel: viewModel.channel, withUserPresence: true)
                                PeptideText(text: self.viewModel.channel.isNotSavedMessages ? viewModel.channel.getName(viewState) : "Saved Notes",
                                            font: .peptideHeadline,
                                            textColor: .textDefaultGray01,
                                            alignment: .center,
                                            lineLimit: 1)
                                .padding(leading: .spacing4)
                                
                        if self.viewModel.channel.isNotSavedMessages {
                                    PeptideIcon(iconName: .peptideArrowRight,
                                                size: .size20,
                                                color: .iconGray07)
                                }
                            }
                        }
                        
                        Spacer(minLength: .zero)
                        
                        Button {
                            viewState.path.append(NavigationDestination.channel_search(viewModel.channel.id))
                        } label: {
                            PeptideIcon(iconName: .peptideSearch,
                                        size: .size20,
                                        color: .iconDefaultGray01)
                            .frame(width: .size32, height: .size32)
                            .background(Circle().fill(Color.bgGray11))
                        }
                        .padding(.leading, .padding4)
                    }
                    .padding(.horizontal, .padding16)
                    .frame(minHeight: .size56)
                    .background(Color.bgDefaultPurple13)
                    
                    PeptideDivider()
                    
            // New messages indicator
                    if showNewMessage {
                if let last_id = viewState.unreads[viewModel.channel.id]?.last_id, 
                   let last_message_id = viewModel.channel.last_message_id {
                            if last_id < last_message_id {
                        unreadMessagesIndicator(lastId: last_id)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func unreadMessagesIndicator(lastId: String) -> some View {
        HStack(spacing: .spacing12) {
            PeptideText(textVerbatim: "New messages since \(formatRelative(id: lastId))",
                                                font: .peptideBody2,
                                                textColor: .textDefaultGray01)
                                    
                                    Spacer(minLength: .zero)
                                    
                                    PeptideIcon(iconName: .peptideCloseLiner,
                                                size: .size20,
                                                color: .iconDefaultGray01)
                                }
                                .padding(.horizontal, .padding16)
                                .frame(height: .size32)
                                .background(Color.bgPurple07)
                                .onTapGesture {
            // Handle tapping on the new messages indicator
        }
    }
    
    func sendAck(for messageId: String) {
        // Check if auto-acknowledgment is temporarily disabled
        if viewState.shouldDisableAutoAck() {
            print("🚫 SwiftUI: Auto-acknowledgment disabled - skipping sendAck")
            return
        }
        
        if let last_id = viewState.unreads[viewModel.channel.id]?.last_id {
            if last_id < messageId {
                Task {
                    do {
                        _ = try await viewState.http.ackMessage(channel: viewModel.channel.id, message: messageId).get()
                    } catch {
                        // print("Unexpected send ack: \(error)")
                        }
                    }
            }
        }
    }
    
    @ViewBuilder
    private func channelEmptyStateView() -> some View {
        HStack(spacing: .zero) {
            Spacer(minLength: .zero)
            
            VStack(spacing: .zero) {
                Spacer(minLength: .size32)
                
                let channel = viewModel.channel
                
                if channel.isNotSavedMessages {
                    ChannelOnlyIcon(channel: channel,
                                    withUserPresence: false,
                                    initialSize: (50,50),
                                    frameSize: (80,80))
                    .padding(.vertical, .padding16)
                    
                    PeptideText(text: channel.getName(viewState),
                                font: .peptideTitle1,
                                textColor: .textDefaultGray01)
                    .padding(.bottom, .padding8)
                    
                    let title = self.viewModel.channel.isDM ? 
                        "This space is ready for your words. Start the convo!" : 
                        self.viewModel.channel.isTextOrVoiceChannel ? 
                            "Your Channel Awaits. Say hi and break the ice with your first message." :
                            "Your Group Awaits. Say hi and break the ice with your first message."
                    
                    PeptideText(text: title,
                                font: .peptideBody3,
                                textColor: .textGray06,
                                alignment: .center)
                    .padding(.horizontal, .padding16)
                } else {
                    savedNotesEmptyStateView()
                }
                
                VStack {}
                    .frame(height: .size40)
                
                addMembersButtonIfNeeded()
                }
        }
        .padding(.horizontal, .padding16)
    }
    
    @ViewBuilder
    private func savedNotesEmptyStateView() -> some View {
        HStack(spacing: .zero) {
            Spacer(minLength: .zero)
            
            VStack(spacing: .zero) {
                PeptideImage(
                    imageName: .peptideSavedNotes,
                    width: 120,
                    height: 120
                ).padding(.vertical, .padding16)
                
                PeptideText(text: "Saved Notes",
                            font: .peptideTitle1,
                            textColor: .textDefaultGray01)
                .padding(.bottom, .padding8)
                
                PeptideText(text: "Start a message and make this your personal notepad.",
                            font: .peptideBody3,
                            textColor: .textGray06,
                            alignment: .center)
                .padding(.horizontal, .padding16)
            }
            
            Spacer(minLength: .zero)
        }
    }
    
    @ViewBuilder
    private func addMembersButtonIfNeeded() -> some View {
        if let currentUser = viewState.currentUser {
            if viewModel.channel.isGroupDmChannel && 
               resolveChannelPermissions(
                   from: currentUser, 
                   targettingUser: currentUser, 
                   targettingMember: viewModel.server.flatMap { viewState.members[$0.id]?[currentUser.id] }, 
                   channel: viewModel.channel, 
                   server: viewModel.server
               ).contains(.inviteOthers) {
                
                Button {
                    viewState.path.append(NavigationDestination.add_members_to_channel(viewModel.channel.id))
                } label: {
                    PeptideActionButton(icon: .peptideNewUser,
                                       title: "Add Members")
                    .frame(minHeight: .size56)
                    .background {
                        RoundedRectangle(cornerRadius: .radiusMedium).fill(Color.bgGray11)
                            .overlay {
                                RoundedRectangle(cornerRadius: .radiusMedium)
                                    .stroke(.borderGray10, lineWidth: .size1)
                            }
                    }
                }
                .padding(.bottom, .padding40)
            }
        }
    }
    
    @ViewBuilder
    private func messageRow(msgViewModel: MessageContentsViewModel) -> some View {
        // Remove the tracking approach
        VStack(spacing: .zero) {
            if showNewMessage {
                if let last_id = viewState.unreads[viewModel.channel.id]?.last_id, 
                   let bottomMessageId = bottomMessage?.message.id {
                    if (last_id == msgViewModel.message.id) && (last_id != bottomMessageId) {
                        ZStack(alignment: .center) {
                            PeptideDivider(backgrounColor: .bgRed11)
                            PeptideText(text: "NEW MESSAGE", font: .peptideFootnote, textColor: .textRed07)
                                .padding(4)
                                .background(Color.bgDefaultPurple13)
                        }
                        .padding(.vertical, .padding8)
                    }
                }
            }
            
            if msgViewModel.isFirstInGroup {
                MessageView(viewModel: msgViewModel, isStatic: false)
                    .padding(bottom: msgViewModel.isLastInGroup ? .zero : .zero,
                             leading: .padding16,
                             trailing: .zero)
            } else {
                MessageContentsView(viewModel: msgViewModel, isStatic: false)
                    .padding(bottom: msgViewModel.isLastInGroup ? .zero : .zero,
                             leading: .padding16 + .padding40 + .padding16,
                             trailing: .padding16)
            }
        }
        .background(
            // Add highlighting background when message is highlighted
            highlighted == msgViewModel.message.id ? 
            Color.yellow.opacity(0.3) : Color.clear
        )
        .animation(.easeInOut(duration: 0.3), value: highlighted)
        .onChange(of: highlighted) { oldValue, newValue in
            if newValue == msgViewModel.message.id {
                // print("🎯 Message \(msgViewModel.message.id) is now highlighted")
            } else if oldValue == msgViewModel.message.id {
                // print("🎯 Message \(msgViewModel.message.id) highlight cleared")
            }
        }
        .id(msgViewModel.message.id)
        .tag(msgViewModel.message.id)
        .accessibilityIdentifier(msgViewModel.message.id)
        .task {
            if msgViewModel.message.id == topMessage?.message.id && !isLoadingMore {
                Task {
                    isLoadingMore = true
                    await loadMoreMessages(before: msgViewModel.message.id)
                }
            }
            
            if msgViewModel.message.id == bottomMessage?.message.id {
                Task {
                    sendAck(for: msgViewModel.message.id)
                }
            }
        }
    }
    
    @ViewBuilder
    private func typingIndicator(users: [(User, Member?)]) -> some View {
        HStack(spacing: .padding4) {
            PeptideLoading(dotSize: .size2,
                           dotSpacing: .size2,
                           activeColor: Color.textGray04,
                           offset: -4)
            .frame(width: 30, height: 15)
            .background {
                Color.bgGray12
                    .clipShape(
                        .rect(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 4,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 4
                        )
                    )
            }
            
            PeptideText(text: formatTypingIndicatorText(withUsers: users),
                        font: .peptideCallout,
                        textColor: Color.textGray04,
                        lineLimit: 1)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: .size40)
        .padding(.horizontal, .padding16)
        .background(Color.bgDefaultPurple13)
    }
    
    private func handleMessagesChange(proxy: ScrollViewProxy) {
        let allMessages = getMessages(scrollProxy: nil)

        if messages.isEmpty {
            messages.append(contentsOf: allMessages)
            DispatchQueue.main.async {
                scrollPosition = messages.last?.message.id
                scrollToLastMessage(proxy: proxy, animated: true)
            }
            isLoadingMore = false
            return
        }

        let existingIDs = Set(messages.map { $0.message.id })
        let newIDs = Set(allMessages.map { $0.message.id })
        let commonIDs = existingIDs.intersection(newIDs)

        let upperMessages = allMessages.filter {
            !commonIDs.contains($0.message.id) &&
            $0.message.id < messages.first!.message.id
        }

        let lowerMessages = allMessages.filter {
            !commonIDs.contains($0.message.id) &&
            $0.message.id > messages.last!.message.id
        }

        if allMessages.count < messages.count {
            messages.removeAll { msg in
                !newIDs.contains(msg.message.id)
            }
        }
        
        if !lowerMessages.isEmpty {
            showNewMessage = false
        }

        if !upperMessages.isEmpty || !lowerMessages.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let prevPosition = messages.first?.message.id
                
                messages.insert(contentsOf: upperMessages, at: 0)
                messages.append(contentsOf: lowerMessages)
                
                if !lowerMessages.isEmpty {
                    DispatchQueue.main.async {
                        showNewMessage = false
                        scrollPosition = messages.last?.message.id
                        
                        // Scroll to bottom with new messages only once
                        scrollToLastMessage(proxy: proxy, animated: false)
                    }
                } else if !upperMessages.isEmpty {
                    DispatchQueue.main.async {
                        scrollPosition = prevPosition
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isLoadingMore = false
                }
            }
        }
    }

    // 3. Add this function to adjust scroll based on distance
    private func adjustScroll(proxy: ScrollViewProxy?) {
        if inputTopPosition > 0 && lastMessageBottomPosition > 0 {
            let currentGap = inputTopPosition - lastMessageBottomPosition
            
            // If the distance is too small or keyboard is showing, scroll to show the last message
            if (currentGap < safeSpacing || keyboardHeight > 0) && !isScrolling {
                isScrolling = true
                
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let lastMessageId = messages.last?.message.id {
                        proxy?.scrollTo(lastMessageId, anchor: .bottom)
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isScrolling = false
                }
            }
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState = ViewState.preview().applySystemScheme(theme: .dark)
    let messages = Binding($viewState.channelMessages["0"])!
    
    return MessageableChannelView(viewModel: .init(viewState: viewState, channel: viewState.channels["0"]!, server: viewState.servers[""], messages: messages), toggleSidebar: {})
        .applyPreviewModifiers(withState: viewState)
}

// Assuming this is where the SwiftUI view was being used
func presentMessageableChannelViewController(from parentViewController: UIViewController, viewModel: MessageableChannelViewModel) {
    let messageableChannelVC = MessageableChannelViewController(viewModel: viewModel)
    parentViewController.present(messageableChannelVC, animated: true, completion: nil)
}

// Example usage
// let viewModel = MessageableChannelViewModel(viewState: viewState, channel: channel, server: server, messages: messages)
// presentMessageableChannelViewController(from: self, viewModel: viewModel)



