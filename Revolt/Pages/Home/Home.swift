//
//  HomeRewritten.swift
//  Revolt
//
//  Created by Angelo on 25/11/2023.
//
import SwiftUI
import Types

struct MaybeChannelView: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var currentChannel: ChannelSelection
    @Binding var currentSelection: MainSelection
    var toggleSidebar: () -> ()
    
    var body: some View {
        switch currentChannel {
        case .channel(let channelId):
            if let channel = viewState.channels[channelId] {
                //let messages = Binding($viewState.channelMessages[channelId])!
                let messages = viewState.getChannelChannelMessage(channelId: channelId)
                
                // Use the UIKit implementation wrapped in SwiftUI
                MessageableChannelViewControllerRepresentable(
                    viewModel: MessageableChannelViewModel(
                        viewState: viewState,
                        channel: channel,
                        server: currentSelection.id.flatMap { viewState.servers[$0] },
                        messages: messages
                    ),
                    toggleSidebar: toggleSidebar,
                    targetMessageId: {
                        // print("🎯 HOME: Computing targetMessageId for channel \(channelId)")
                        // print("🎯 HOME: viewState.currentTargetMessageId = \(viewState.currentTargetMessageId ?? "nil")")
                        
                        // Pass targetMessageId if it exists - don't check if message is loaded yet
                        // The MessageableChannelViewController will handle loading the message if needed
                        if let targetId = viewState.currentTargetMessageId {
                            // print("🎯 HOME: Found targetId: \(targetId)")
                            
                            // Only verify channel if message is already loaded
                            if let targetMessage = viewState.messages[targetId] {
                                // print("🎯 HOME: Message is loaded, channel = \(targetMessage.channel)")
                                // Message is loaded, check if it belongs to this channel
                                if targetMessage.channel == channelId {
                                    // print("✅ HOME: Returning targetId \(targetId) for channel \(channelId)")
                                    return targetId
                                } else {
                                    // Message belongs to different channel, clear it
                                    // print("🚫 HOME: Target message belongs to different channel \(targetMessage.channel) vs \(channelId), clearing targetMessageId")
                                    viewState.currentTargetMessageId = nil
                                    return nil
                                }
                            } else {
                                // Message not loaded yet, but pass the ID anyway for loading
                                // print("🔄 HOME: Target message not loaded yet, passing ID for loading: \(targetId)")
                                return targetId
                            }
                        } else {
                            // print("ℹ️ HOME: No targetMessageId found")
                        }
                        return nil
                    }()
                )
                .ignoresSafeArea(.all)
                .edgesIgnoringSafeArea(.all)
                .statusBar(hidden: true)
                .onAppear {
                    // Only clear target message ID if we're sure it belongs to a different channel
                    if let targetId = viewState.currentTargetMessageId {
                        // Only check if the message is already loaded
                        if let targetMessage = viewState.messages[targetId] {
                            if targetMessage.channel != channelId {
                                // print("🚫 Target message is for different channel, clearing targetMessageId")
                                viewState.currentTargetMessageId = nil
                            }
                        } else {
                            // Message not loaded yet, don't clear - let MessageableChannelViewController handle it
                            // print("🔄 Target message not loaded yet in onAppear, keeping targetMessageId: \(targetId)")
                        }
                    }
                }
                
            } else {
                EmptyView()
                //Text("Unknown Channel :(")
            }
        case .home:
            HomeWelcome(toggleSidebar: toggleSidebar)
        case .friends:
            NewMessageFriendsList()
        case .noChannel:
            Text("Looks a bit empty in here.")
        }
    }
}

struct HomeRewritten: View {
    @EnvironmentObject var viewState: ViewState
    
    @Binding var currentSelection: MainSelection
    @Binding var currentChannel: ChannelSelection
    
    @State var offset = CGFloat.zero
    @State var forceOpen: Bool = false
    @State var calculatedSize = CGFloat.zero
    
    @State private var homeTab : HomeTab = .home
        
    
    func toggleSidebar() {
        
    }
    
    var body: some View {
        
        VStack(spacing: .zero){
            
            ZStack(alignment: .bottomTrailing){
                
                TabView(selection: $homeTab) {
                    
                    
                    
                    Tab(value: HomeTab.home) {
                            
                            ZStack(alignment: .bottomTrailing) {
                                HStack(spacing: 0) {
                                    ServerScrollView()
                                        .frame(width: .size64)
                                    
                                    switch currentSelection {
                                    case .server(_):
                                        ServerChannelScrollView(currentSelection: $currentSelection, currentChannel: $currentChannel, toggleSidebar: toggleSidebar)
                                        
                                    case .dms:
                                        DMScrollView(currentChannel: $currentChannel, toggleSidebar: toggleSidebar)
                                        
                                    case .discover:
                                        DiscoverScrollView()

                                    }
                                    
                                    Spacer(minLength: .zero)
                                }
                                
                            }
                            .background(Color.bgDefaultPurple13)
                            .toolbar(.hidden, for: .tabBar)
                            .ignoresSafeArea(.container, edges: .bottom)
                            .fillMaxSize()
                        
                    }


                    Tab(value: HomeTab.friends) {
                        FriendsList()
                            .toolbar(.hidden, for: .tabBar)
                    }


                    Tab(value: HomeTab.you) {
                        YouView()
                            .toolbar(.hidden, for: .tabBar)
                    }
                }
                
                if homeTab == .home {
                    
                    Button{
                        
                        switch homeTab {
                            case .home:
                                toggleSidebar()
                                viewState.currentChannel = .friends
                                viewState.path.append(NavigationDestination.maybeChannelView)
                            case .friends:
                                print("friends")
                            case .you:
                                print("you")
                        }
                        
                        
                    } label: {
                        
                        PeptideIcon(iconName:  homeTab == .home ? .peptideNewMessage : .peptideAdd,
                                    size: .size24,
                                    color: .iconInverseGray13)
                        .frame(width: .size48, height: .size48)
                        .background{
                            Circle().fill(Color.bgYellow07)
                        }
                    }
                    .padding(.padding16)
                    
                }
                
               
            }
            
            
            HomeBottomNavigation(homeTab: $homeTab)
            
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            if let channelId = viewState.launchNotificationChannelId,
               !viewState.launchNotificationHandled {
                
                // CRITICAL FIX: Clear channel messages before navigating to ensure full message history is loaded
                // This prevents the issue where only new WebSocket messages are shown
                print("🔄 Home: Clearing channel messages for notification channel \(channelId) to ensure full history loads")
                viewState.channelMessages[channelId] = []
                viewState.preloadedChannels.remove(channelId)
                
                if let serverId = viewState.launchNotificationServerId {
                    viewState.selectServer(withId: serverId)
                    viewState.selectChannel(inServer: serverId, withId: channelId)
                } else {
                    viewState.selectDm(withId: channelId)
                }

                viewState.path.append(.maybeChannelView)
                viewState.launchNotificationHandled = true 
            }
        }
        .task {
            if case .server(let target) = currentSelection {
                // OPTIMIZED: Use detached task to prevent UI blocking
                Task.detached(priority: .userInitiated) {
                    await self.viewState.getServerMembers(target: target)
                }
            }
        }
        
    }
}

#Preview {
    @Previewable @StateObject var state = ViewState.preview().applySystemScheme(theme: .dark)
    
    return HomeRewritten(currentSelection: $state.currentSelection,
                         currentChannel: $state.currentChannel)
    .environmentObject(state)
    .preferredColorScheme(.dark)
}
