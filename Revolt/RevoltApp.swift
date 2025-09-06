import SwiftUI
import Sentry
import Types
import Foundation

/// The main entry point for the Revolt iOS/macOS SwiftUI app.
///
/// The app manages the app lifecycle, handles URLs, and initializes error tracking using the Sentry SDK.
/// It also handles platform-specific behaviors (iOS/macOS).
@main
struct RevoltApp: App {
    // Conditional compilation for iOS and macOS to set up platform-specific app delegate behavior.
#if os(iOS)
    /// AppDelegate setup for iOS-specific behavior.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#elseif os(macOS)
    /// AppDelegate setup for macOS-specific behavior.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    
    // Fetches the system's locale to adjust the app's content accordingly.
    @Environment(\.locale) var systemLocale: Locale
    
    // Holds a shared state object for managing the view's global state.
    @StateObject var state = ViewState.shared ?? ViewState()
    
    /// Initializer to configure the app. Initializes Sentry error tracking if not in preview mode.
    init() {
        if !isPreview {
            // Start Sentry for error tracking and performance monitoring.
            SentrySDK.start { options in
                 options.dsn = "https://e0f9413527668131e00a5292b3327a3e@o4508001912487936.ingest.us.sentry.io/4509111269195776"  // DSN for Sentry project
                 options.tracesSampleRate = 0.1  // Reduced sample rate for performance traces (10% instead of 100%)
                 options.profilesSampleRate = 0.1  // Reduced sampling rate for profiling (10% instead of 100%)
                 options.attachViewHierarchy = true  // Attach view hierarchy for better debugging
                 options.enableAppLaunchProfiling = false  // Disable launch profiling to prevent timeout issues
                 options.debug = false  // Disable debug mode to reduce network requests
                 options.enableNetworkTracking = false  // Disable network tracking to prevent timeout conflicts
             }
             RealmManager.configure()
        }
    }
    
    /// Defines the app's main view hierarchy.
    var body: some Scene {
        WindowGroup {
            // Main view of the app
            //SplashScreen()
            ApplicationSwitcher()
                .environmentObject(state)  // Pass the shared state to the environment
                .background(.bgDefaultPurple13)
                .typesettingLanguage((state.currentLocale ?? systemLocale).language)  // Set typesetting language based on current locale
                .onOpenURL { url in
                    print("📱 UNIVERSAL_LINK: Received URL: \(url)")  // Log the opened URL for debugging
                    let components = NSURLComponents(string: url.absoluteString)
                    // Handle different URL schemes and paths
                    switch url.scheme {
                    case "http", "https":
                        switch url.pathComponents[safe: 1] {
                        case "app", "login":
                            state.currentSelection = .dms  // Navigate to direct messages (DMs)
                            state.currentChannel = .home  // Set home as current channel
                        case "channel":
                            // Handle channel links: /channel/CHANNEL_ID or /channel/CHANNEL_ID/MESSAGE_ID
                            if let channelId = url.pathComponents[safe: 2] {
                                print("📱 UNIVERSAL_LINK: Navigating to channel: \(channelId)")
                                
                                if let channel = state.channels[channelId] {
                                    // Clear existing messages for this channel
                                    state.channelMessages[channelId] = []
                                    
                                    // Navigate to the appropriate server or DMs
                                    if let serverId = channel.server {
                                        state.currentSelection = .server(serverId)
                                    } else {
                                        state.currentSelection = .dms
                                    }
                                    state.currentChannel = .channel(channelId)
                                    
                                    // Handle message ID if present
                                    if let messageId = url.pathComponents[safe: 3] {
                                        print("📱 UNIVERSAL_LINK: Message ID found: \(messageId)")
                                        state.currentTargetMessageId = messageId
                                    } else {
                                        state.currentTargetMessageId = nil
                                    }
                                    
                                    // Navigate to the channel view
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                        // This ensures that when user presses back, they go to server list instead of previous channel
                                        print("🔄 RevoltApp: Clearing navigation path to prevent back to previous channel")
                                        state.path = []
                                        state.path.append(NavigationDestination.maybeChannelView)
                                    }
                                } else {
                                    print("📱 UNIVERSAL_LINK: Channel not found: \(channelId)")
                                }
                            }
                        case "server":
                            // Handle server links: /server/SERVER_ID/channel/CHANNEL_ID or /server/SERVER_ID/channel/CHANNEL_ID/MESSAGE_ID
                            if let serverId = url.pathComponents[safe: 2] {
                                print("📱 UNIVERSAL_LINK: Navigating to server: \(serverId)")
                                
                                if state.servers[serverId] != nil {
                                    state.currentSelection = .server(serverId)
                                    
                                    // Check if URL contains "channel" and then channel ID
                                    if url.pathComponents.count > 4 && url.pathComponents[safe: 3] == "channel",
                                       let channelId = url.pathComponents[safe: 4] {
                                        // Clear existing messages for this channel
                                        state.channelMessages[channelId] = []
                                        
                                        state.currentChannel = .channel(channelId)
                                        
                                        // Handle message ID if present (would be at index 5)
                                        if let messageId = url.pathComponents[safe: 5] {
                                            print("📱 UNIVERSAL_LINK: Message ID found: \(messageId)")
                                            state.currentTargetMessageId = messageId
                                        } else {
                                            state.currentTargetMessageId = nil
                                        }
                                        
                                        // Navigate to the channel view
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            // CRITICAL FIX: Clear navigation path to prevent going back to previous channel
                                            // This ensures that when user presses back, they go to server list instead of previous channel
                                            print("🔄 RevoltApp: Clearing navigation path to prevent back to previous channel")
                                            state.path = []
                                            state.path.append(NavigationDestination.maybeChannelView)
                                        }
                                    }
                                } else {
                                    print("📱 UNIVERSAL_LINK: Server not found: \(serverId)")
                                }
                            }
                        case "invite":
                            // Handle invite links: /invite/INVITE_CODE
                            if let inviteCode = url.pathComponents[safe: 2] {
                                print("📱 UNIVERSAL_LINK: Opening invite: \(inviteCode)")
                                
                                // Navigate to invite view directly without clearing path
                                state.path.append(NavigationDestination.invite(inviteCode))
                            }
                        default:
                            print("📱 UNIVERSAL_LINK: Unhandled path: \(url.pathComponents[safe: 1] ?? "nil")")
                        }
                    case "revoltchat":
                        var queryItems: [String: String] = [:]
                        // Parse query items from the URL
                        for item in components?.queryItems ?? [] {
                            queryItems[item.name] = item.value?.removingPercentEncoding
                        }
                        switch url.host() {
                        case "users":
                            if let id = queryItems["user"] {
                                // Open user profile based on the user ID in the URL
                                state.openUserSheet(withId: id, server: queryItems["server"])
                            }
                        case "channels":
                            if let id = queryItems["channel"] {
                                // Navigate to a specific channel by its ID
                                if let channel = state.channels[id] {
                                    if let server = channel.server {
                                        state.currentSelection = .server(server)  // Navigate to server view
                                    } else {
                                        state.currentSelection = .dms  // Default to direct messages
                                    }
                                    state.currentChannel = .channel(id)  // Set the current channel
                                }
                            }
                        default:
                            ()
                        }
                    default:
                        ()
                    }
                }
                .preferredColorScheme(.dark)
            
        }
        
    }
}

/// A view that manages app navigation and displays the relevant interface based on app state.
struct ApplicationSwitcher: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var viewState: ViewState
    @State var wasSignedOut = false
    //@State var banner: WsState? = nil
    
    @State var isFirstTimeLaunch : Bool = true
    
    var body: some View {
        
        if isFirstTimeLaunch {
            
            PeptideTemplateView{_,_   in
                
                ZStack(alignment: .bottom){
                    
                    Image(.peptideLogo)
                    
                }
                .fillMaxSize()
                .overlay(alignment: .bottom){
                    
                    PeptideText(text: "ZekoChat v\(Bundle.main.releaseVersionNumber)",
                                font: .peptideFootnote,
                                textColor: .textGray06,
                                alignment: .center)
                    .padding(.padding24)
                }
                
            }
            .task {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    
                    withAnimation {
                        self.isFirstTimeLaunch.toggle()
                        
                    }
                    
                }
            }
            
        } else {
            if viewState.state != .signedOut && !viewState.isOnboarding {
                // Main app interface if the user is signed in or not onboarding
                InnerApp()
                    .transition(.opacity)  // Smooth transition between states
                    .task {
                        viewState.setBaseUrlToHttp()
                        // Background WebSocket task to maintain connection
                        await viewState.backgroundWsTask()
                        if viewState.state != .signedOut {
                            withAnimation {
                                viewState.state = .connecting  // Set connecting state with animation
                            }
                        }
                    }
                    .alertPopup(show: viewState.alert.0 != nil){
                        AlertMessagePopup(message: viewState.alert.0 ?? "", icon: viewState.alert.1, iconColor: viewState.alert.2 ?? .iconDefaultGray01)
                    }
                /*.alertPopup(show: banner !=  nil) {
                 if let banner = banner {
                 HStack {
                 switch banner {
                 case .disconnected:
                 Image(systemName: "exclamationmark.triangle.fill")
                 Text("Disconnected")
                 .bold()
                 Text("Tap to reconnect")
                 
                 case .connecting:
                 Image(systemName: "arrow.clockwise")
                 Text("Reconnecting")
                 case .connected:
                 Image(systemName: "checkmark")
                 Text("Connected")
                 }
                 }
                 .padding(8)
                 .foregroundStyle(.black)
                 .background {
                 let colour: Color
                 
                 let _ = switch banner {
                 case .disconnected:
                 colour = Color.red
                 case .connecting:
                 colour = Color.yellow
                 case .connected:
                 colour = Color.green
                 }
                 
                 RoundedRectangle(cornerRadius: 20).foregroundStyle(colour)
                 }
                 .onTapGesture {
                 if case .disconnected = banner {
                 viewState.ws?.forceConnect()
                 }
                 }
                 }
                 }*/
                    .onChange(of: colorScheme) { before, after in
                        // Automatically update color scheme based on system preferences
                        if viewState.theme.shouldFollowiOSTheme {
                            withAnimation {
                                _ = viewState.applySystemScheme(theme: after, followSystem: true)
                            }
                        }
                    }
                /*.onChange(of: viewState.ws?.currentState, { before, after in
                 // Display banner based on WebSocket connection state
                 if case .connected = after {
                 banner = .connected  // Show "Connected" banner
                 DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                 withAnimation {
                 banner = nil  // Dismiss banner after 2 seconds
                 }
                 }
                 } else if before != nil {
                 banner = after  // Update banner for other states
                 }
                 })*/
            } else {
                // Show the Welcome view if user is signed out or onboarding
                Welcome(wasSignedOut: $wasSignedOut)
                    .onAppear {
                        // Clear session token and cache when signed out
                        if viewState.state == .signedOut && viewState.sessionToken != nil {
                            viewState.sessionToken = nil
                            viewState.destroyCache()
                            withAnimation {
                                wasSignedOut = true
                            }
                        }
                    }
            }
        }
        
        
        
    }
}

/// Represents the inner part of the app when the user is signed in.
struct InnerApp: View {
    @EnvironmentObject var viewState: ViewState
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        // Stack-based navigation structure for managing views
        NavigationStack(path: $viewState.path) {
            if viewState.forceMainScreen {
                MainApp()  // Show the main screen
            } else {
                // Handle different app states (signed out, connecting, connected)
                switch viewState.state {
                case .signedOut:
                    PeptideText(text: "Signed out... How did you get here?",
                                font: .peptideBody1)
                case .connecting:
                    VStack {
                        PeptideText(text: "Connecting...",
                                    font: .peptideBody1)
#if DEBUG
                        // Debug button to reset app state
                        /*Button {
                            viewState.destroyCache()
                            viewState.sessionToken = nil
                            viewState.state = .signedOut
                        } label: {
                            
                            PeptideText(text: "Developer: Nuke everything and force welcome screen",
                                        font: .peptideBody1)
                        }*/
#endif
                    }
                case .connected:
                    MainApp()  // Show the main app when connected
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("🔄 SCENE_PHASE: Changed from \(oldPhase) to \(newPhase)")
            
            switch newPhase {
            case .background:
                print("🔄 SCENE_PHASE: App entered background - preserving state")
                // Don't clear anything when going to background
                
            case .inactive:
                print("🔄 SCENE_PHASE: App became inactive")
                // App is transitioning between states, don't clear anything
                
            case .active:
                print("🔄 SCENE_PHASE: App became active")
                // CRITICAL FIX: Don't restart everything when coming back from background
                if viewState.state == .connected {
                    print("🔄 SCENE_PHASE: App was already connected, preserving state")
                    // Just verify WebSocket connection, don't recreate everything
                    Task {
                        if viewState.ws == nil || viewState.wsCurrentState != .connected {
                            print("🔄 SCENE_PHASE: WebSocket disconnected, reconnecting...")
                            await viewState.backgroundWsTask()
                        }
                    }
                } else {
                    print("🔄 SCENE_PHASE: App was not connected, initializing...")
                    Task {
                        await viewState.backgroundWsTask()
                    }
                }
                
            @unknown default:
                break
            }
        }
    }
}

/// Main app content, including home screen and navigation destinations.
struct MainApp: View {
    @EnvironmentObject var viewState: ViewState
    
    var body: some View {
        HomeRewritten(
            currentSelection: $viewState.currentSelection,  // Bind the current selection
            currentChannel: $viewState.currentChannel  // Bind the current channel
        )
        // Navigation destinations for various app screens
        .navigationDestination(for: NavigationDestination.self) { dest in
            switch dest {
                
            case .channel_info(let channelId, let serverId):
                if let channelValue = viewState.channels[channelId] {
                    let channelBinding = Binding(
                        get: { viewState.channels[channelId] ?? channelValue },
                        set: { newValue in viewState.channels[channelId] = newValue }
                    )
                    
                    let serverBinding = channelBinding.wrappedValue.server.map { id in
                        Binding(
                            get: { viewState.servers[id] },
                            set: { newValue in viewState.servers[id] = newValue }
                        )
                    } ?? .constant(nil)
                    
                    ChannelInfo(channel: channelBinding, server: serverBinding)
                } else {
                    PeptideWarningTemplateView()
                }
                
                
                
            case .add_members_to_channel(let id):
                if let channelValue = viewState.channels[id] {
                    let channelBinding = Binding(
                        get: { viewState.channels[id] ?? channelValue },
                        set: { newValue in viewState.channels[id] = newValue }
                    )
                    AddMembersToChannelView(channel: channelBinding)
                } else {
                    PeptideWarningTemplateView()
                }
                
                
                
                
            case .channel_settings(let id):
                if let channelValue = viewState.channels[id] {
                    let channelBinding = Binding(
                        get: { viewState.channels[id] ?? channelValue },
                        set: { newValue in viewState.channels[id] = newValue }
                    )
                    let serverBinding = channelBinding.wrappedValue.server.map { id in
                        Binding(
                            get: { viewState.servers[id] },
                            set: { newValue in viewState.servers[id] = newValue }
                        )
                    } ?? .constant(nil)
                    ChannelSettings(server: serverBinding, channel: channelBinding)
                } else {
                    PeptideWarningTemplateView()
                }
                
                
            case .discover:
                Discovery()  // Discovery screen
                
            case .server_settings(let id):
                if let serverValue = viewState.servers[id] {
                    let serverBinding = Binding(
                        get: { viewState.servers[id] ?? serverValue },
                        set: { newValue in viewState.servers[id] = newValue }
                    )
                    ServerSettings(server: serverBinding)
                } else {
                    PeptideWarningTemplateView()
                }
                
                
            case .settings:
                Settings()  // App settings
                
            case .add_friend:
                AddFriend()  // Add friend screen
                
            case .create_group(let initial_users):
                CreateGroup(selectedUsers: Set(initial_users.compactMap { viewState.users[$0] }))
                
            case .channel_search(let id):
                if let channelValue = viewState.channels[id] {
                    let channelBinding = Binding(
                        get: { viewState.channels[id] ?? channelValue },
                        set: { newValue in viewState.channels[id] = newValue }
                    )
                    ChannelSearch(channel: channelBinding)
                } else {
                    PeptideWarningTemplateView()
                }
                
                
            case .invite(let code):
                ViewInvite(code: code)  // Invite view
            case .maybeChannelView :
                MaybeChannelView(
                    currentChannel: $viewState.currentChannel,
                    currentSelection: $viewState.currentSelection,
                    toggleSidebar: {
                        //TODO
                    })
                
            case .create_group_name:
                CreateGroupName()
                
            case .create_group_add_memebers(let groupName):
                CreateGroupAddMembders(groupName: groupName)
                
            case .report(let user, let serverId, let messageId):
                if let serverId {
                    ReportView(user: nil, server: viewState.servers[serverId], reportType : .Server)
                } else if let user {
                    ReportView(user: user, reportType : .User)
                } else if let messageId {
                    ReportView(message : viewState.messages[messageId], reportType : .Message)
                }
                
            case .channel_overview_setting(let channelId, _):
                if let channelValue = viewState.channels[channelId] {
                    let channelBinding = Binding(
                        get: { viewState.channels[channelId] ?? channelValue },
                        set: { newValue in viewState.channels[channelId] = newValue }
                    )
                    ChannelOverviewSettings.fromState(viewState: viewState, channel: channelBinding)
                } else {
                    PeptideWarningTemplateView()
                }
                
            case .server_channel_overview_setting(let channelId, let serverId):
                if let  channel = viewState.channels[channelId] , let server = Binding($viewState.servers[serverId]) {
                    ServerChannelOverviewSettings(viewState: viewState, channel: channel, server: server)
                } else {
                    PeptideWarningTemplateView()
                }
                
            case .server_role_setting(let serverId):
                
                if let serverValue = viewState.servers[serverId] {
                    let serverBinding = Binding(
                        get: { viewState.servers[serverId] ?? serverValue },
                        set: { newValue in viewState.servers[serverId] = newValue }
                    )
                    
                    ServerRolesSettings(server: serverBinding)
                    
                } else {
                    PeptideWarningTemplateView()
                }
                
            case .server_overview_settings(let serverId):
                
                if let serverValue = viewState.servers[serverId] {
                    let serverBinding = Binding(
                        get: { viewState.servers[serverId] ?? serverValue },
                        set: { newValue in viewState.servers[serverId] = newValue }
                    )
                    
                    ServerOverviewSettings(server: serverBinding)
                    
                } else {
                    PeptideWarningTemplateView()
                }
                
                
            case .server_channels(let serverId):
                
                if let server = viewState.servers[serverId]{
                    ServerChannelsView(server: server)
                } else {
                    PeptideWarningTemplateView()
                }
                
            case .server_category(let serverId, let categoryId):
                if let server = viewState.servers[serverId], let category = server.categories?.first(where: { $0.id == categoryId }){
                    ServerCategoryView(server: server, category: category)
                } else {
                    PeptideWarningTemplateView()
                }
                
            case .channel_category_create(let serverId, let type):
                if let server = viewState.servers[serverId]{
                    ChannelCategoryCreateView(server:server, type: type)
                }
                
            case .profile_setting :
                if let currentUser = viewState.currentUser {
                    ProfileSettings.fromState(currentUser: currentUser)
                }
                
            case .server_emoji_settings(let serverId):
                
                if let _ = viewState.servers[serverId]{
                    ServerEmojiSettings(server: Binding($viewState.servers[serverId])!)
                }
                
            case .show_recovery_codes(let token, let isGenerate):
                ShowRecoveryCodesView(token: token, isGenerate: isGenerate)
            case .enable_authenticator_app(let token):
                EnableAuthenticatorAppView(token: token)
            case .validate_password_view(let reason):
                ValidatePasswordView(validatePasswordReason: reason)
            case .server_members_view(let serverId):
                ServerMembersView(serverId: serverId)
            case .blocked_users_view:
                BlockedUsersView()
            case .user_settings:
                UserSettings()
            case .role_setting(let serverId, let channelId, let roleId, let roleTitle, let value):
                if let serverValue = viewState.servers[serverId], let channelValue = viewState.channels[channelId] {
                    let serverBinding = Binding(
                        get: { viewState.servers[serverId] ?? serverValue },
                        set: { newValue in viewState.servers[serverId] = newValue }
                    )
                    let channelBinding = Binding(
                        get: { viewState.channels[channelId] ?? channelValue },
                        set: { newValue in viewState.channels[channelId] = newValue }
                    )
                    ChannelRolePermissionsSettings(server: serverBinding, channel: channelBinding, roleId: roleId, roleTitle: roleTitle, permissions: value)
                } else {
                    PeptideWarningTemplateView()
                }
                
                
            case .member_permissions(let serverId, let member):
                ChannelMemberPermissionView(serverId: serverId, member: member)
            case .server_invites(let serverId):
                ServerInvitesView(serverId: serverId)
            case .server_banned_users(let serverId):
                ServerBannedUsersView(serverId: serverId)
            case .create_server_role(let serverId):
                if let serverValue = viewState.servers[serverId] {
                    let serverBinding = Binding(
                        get: { viewState.servers[serverId] ?? serverValue },
                        set: { newValue in viewState.servers[serverId] = newValue }
                    )
                    CreateServerRoleView(server: serverBinding)
                } else {
                    PeptideWarningTemplateView()
                }
                
            case .default_role_settings(let serverId):
                if let serverValue = viewState.servers[serverId] {
                    let serverBinding = Binding(
                        get: { viewState.servers[serverId] ?? serverValue },
                        set: { newValue in viewState.servers[serverId] = newValue }
                    )
                    DefaultRoleSettings(server: serverBinding, permissions: serverValue.default_permissions)
                } else {
                    PeptideWarningTemplateView()
                }
                
                
            case .sessions_settings:
                SessionsSettings()
            case .username_view:
                UserNameView()
            case .change_email_view:
                ChangeEmailView()
            case .change_password_view:
                ChangePasswordView()
            case .role_settings(let serverId, let roleId):
                if let serverValue = viewState.servers[serverId], let role = serverValue.roles?[roleId] {
                    let serverBinding = Binding(
                        get: { viewState.servers[serverId] ?? serverValue },
                        set: { newValue in viewState.servers[serverId] = newValue }
                    )
                    RoleSettings(server: serverBinding, roleId: roleId, role: role)
                } else {
                    PeptideWarningTemplateView()
                }
                
            case .channel_permissions_settings(let serverId, let channelId):
                if let channelValue = viewState.channels[channelId] {
                    let channelBinding = Binding(
                        get: { viewState.channels[channelId] ?? channelValue },
                        set: { newValue in viewState.channels[channelId] = newValue }
                    )
                    let serverBinding = serverId.map { id in
                        Binding(
                            get: { viewState.servers[id] },
                            set: { newValue in viewState.servers[id] = newValue }
                        )
                    } ?? .constant(nil)
                    ChannelPermissionsSettings(server: serverBinding, channel: channelBinding)
                } else {
                    PeptideWarningTemplateView()
                }
                
            case .developer_settings:
                DeveloperSettings()
                
            case .about_settings:
                About()
                
            }
        }
        // Show user profile sheet
        .environment(\.currentServer, viewState.currentSelection.id.flatMap { viewState.servers[$0] })
        .environment(\.currentChannel, viewState.currentChannel.id.flatMap { viewState.channels[$0] })
        .sheet(item: $viewState.currentUserSheet) { (v) in
            UserSheet(user: v.user, member: v.member)
        }.sheet(item: $viewState.currentUserOptionsSheet) { (v) in
            FriendOptionsSheet(user: v.user)
        }
    }
}



// Temporary settings for compact mode (to be replaced later)
let TEMP_IS_COMPACT_MODE: (Bool, Bool) = (false, true)

// Device detection code to handle platform-specific behavior
#if targetEnvironment(macCatalyst)
let isIPad = UIDevice.current.userInterfaceIdiom == .pad
let isIPhone = UIDevice.current.userInterfaceIdiom == .phone
let isMac = true
#elseif os(iOS)
let isIPad = UIDevice.current.userInterfaceIdiom == .pad
let isIPhone = UIDevice.current.userInterfaceIdiom == .phone
let isMac = false
#else
let isIPad = false
let isIPhone = false
let isMac = true
#endif

/// Checks if the app is running in preview mode (for Xcode Previews).
var isPreview: Bool {
#if DEBUG
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
#else
    false
#endif
}

/// Copies text to the clipboard based on the platform.
func copyText(text: String) {
#if os(macOS)
    NSPasteboard.general.setString(text, forType: .string)
#else
    UIPasteboard.general.string = text
#endif
}

/// Copies a URL to the clipboard based on the platform.
func copyUrl(url: URL) {
#if os(macOS)
    NSPasteboard.general.setString(url.absoluteString, forType: .URL)
#else
    UIPasteboard.general.url = url
#endif
}

