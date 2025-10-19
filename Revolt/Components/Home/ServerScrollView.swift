//
//  ServerScrollView.swift
//  Revolt
//
//  Created by Angelo Manca on 2023-11-25.
//

import SwiftUI
import Types
import OrderedCollections
import UniformTypeIdentifiers

/// A view that displays a scrollable list of servers with options to add a new server,
/// access discovery, and settings. It also shows the user's avatar for direct messages (DMs).
struct ServerScrollView: View {
    let buttonSize = 48.0  // Size of the buttons in the scroll view
    
    @EnvironmentObject var viewState: ViewState  // Environment object for managing the application's state
    @State var showAddServerSheet = false  // State to control the presentation of the Add Server sheet
    
    @State var showServerSheet: Bool = false
    @State private var isPresentedNotificationSetting : Bool = false
    
    @State private var selectedServer : Server? = nil
    @State private var draggedServer: Server? = nil
    
    @State private var didDrop: Bool = false

    
    var filteredChannelsWithUnread: [(channel: Channel, unreadCount: UnreadCount)] {
        viewState.dms.compactMap { channel in
            guard case .saved_messages = channel else {
                if let unread = viewState.getUnreadCountFor(channel: channel) {
                    return (channel, unread)
                }
                return nil
            }
            return nil
        }
    }
    
    var body: some View {
        VStack(spacing: .zero) {
            
            let _ = selectedServer
            
            ScrollView {
                
                // Section displaying the list of servers
                LazyVStack(spacing: .spacing12) {
                    // Button to select direct messages (DMs)
                    Button {
                        
                        if viewState.currentUser != nil {
                            withAnimation(.easeOut(duration: 1.0)){
                                viewState.selectDms()  // Select direct messages
                            }
                        }
                        
                    } label: {
                        ZStack(alignment: .leading) {
                            
                            PeptideIcon(iconName: .peptideMessage,
                                      color: .iconDefaultGray01)
                            .frame(width: buttonSize, height: buttonSize)
                            .background{
                                RoundedRectangle(cornerRadius: .radius16).fill(.bgPurple07)
                            }
                            .padding(.horizontal, .padding8)
                            .overlay(alignment: .center){
                                if viewState.currentUser == nil {
                                    ProgressView()
                                }
                            }
                            
                            if viewState.currentSelection == .dms {
                                
                                SlideShape(buttonSize: buttonSize)
                                
                            }
                            
                        }
                        
                    }
                    .padding(top: .padding8)
                    
                    PeptideDivider()
                        .frame(width: .size32)
                    
                    
                    ForEach(filteredChannelsWithUnread, id: \.channel.id) { channelsWithUnread in
                        let channel = channelsWithUnread.channel
                        let unreadType = channelsWithUnread.unreadCount
                        
                        HStack(spacing: .zero) {
                            // Display `UnreadView` only for `.unread` or `.unreadWithMentions`
                            
                            if case .unread = unreadType {
                                UnreadView(unreadSize: .size12)
                                    .offset(x: -4)
                            } else if case .unreadWithMentions = unreadType {
                                UnreadView(unreadSize: .size12)
                                    .offset(x: -4)
                            } else {
                                UnreadView(unreadSize: .size12)
                                    .opacity(0)
                            }
                            
                            ZStack(alignment: .bottomTrailing) {
                                Button {
                                    // Select DM and navigate
                                    viewState.selectDm(withId: channel.id)
                                    viewState.path.append(NavigationDestination.maybeChannelView)
                                } label: {
                                    HomeChannelOnlyIcon(channel: channel, frameSize: .size48)
                                }
                                
                                // Display `UnreadMentionsView` only for `.mentions` or `.unreadWithMentions`
                                if case .mentions(let count) = unreadType {
                                    UnreadMentionsView(count: count, mentionSize: .size20)
                                } else if case .unreadWithMentions(let count) = unreadType {
                                    UnreadMentionsView(count: count, mentionSize: .size20)
                                }
                            }
                            .padding(leading: .padding4, trailing: .padding8)
                        }
                    }
                    
                    
                    if !filteredChannelsWithUnread.isEmpty{
                        PeptideDivider()
                            .frame(width: .size32)
                    }
                    
                    Button {
                        withAnimation(.easeOut(duration: 1.0)){
                            viewState.selectDiscover()
                        }
                    } label: {
                        
                        ZStack(alignment: .leading) {
                            
                            PeptideIcon(iconName: .peptideCompass,
                                      color: .iconYellow07)
                            .frame(width: buttonSize, height: buttonSize)
                            .background{
                                if case .discover = viewState.currentSelection {
                                    RoundedRectangle(cornerSize: .init(width: .size16, height: .size16))
                                        .fill(.bgPurple07)
                                }else{
                                    Circle().fill(.bgGray11)
                                }
                                
                            }
                            .padding(.horizontal, .padding8)
                            
                            if viewState.currentSelection == .discover {
                                
                                SlideShape(buttonSize: buttonSize)
                                
                            }
                        }
                        
                    }
                    
                    
                    
                    ForEach(viewState.servers.elements, id: \.key) { elem in
                        ServerItemView(
                            server: elem.value,
                            buttonSize: buttonSize,
                            selectedServer: $selectedServer,
                            showServerSheet: $showServerSheet,
                            isPresentedNotificationSetting: $isPresentedNotificationSetting
                        )
                        .onDrag {
                            draggedServer = elem.value
                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(forTypeIdentifier: UTType.text.identifier, visibility: .all) { completion in
                                let data = Data(elem.key.utf8)
                                completion(data, nil)
                                return nil
                            }
                            return provider
                        }
                        .onDrop(of: [UTType.text], delegate: ServerDropDelegate(
                            currentServer: elem.value,
                            draggedServer: $draggedServer,
                            viewState: viewState,
                            didDrop: $didDrop
                        ))
                    }
                    
                    Button {
                        showAddServerSheet.toggle()  // Toggle the Add Server sheet
                    } label: {
                        
                        PeptideIcon(iconName: .peptideAdd,
                                  color: .iconYellow07)
                        .frame(width: buttonSize, height: buttonSize)
                        .background{
                            Circle().fill(.bgGray11)
                        }
                        
                        
                    }
                    .padding(.bottom, .padding32)
                }
                
                
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .clipped()
            
            Spacer(minLength: .zero)
            
        }
        .frame(width : .size64)
        .background(.bgDefaultPurple13)
        .sheet(isPresented: self.$isPresentedNotificationSetting){
            if let selectedServer {
                NotificationSettingSheet(isPresented: $isPresentedNotificationSetting,
                                      channel: nil,
                                      server: selectedServer)
            }
            
        }
        .sheet(isPresented: $showServerSheet) {
            if let selectedServer {
                ServerInfoSheet(isPresentedServerSheet: $showServerSheet,
                              server: selectedServer,
                              onNavigation: {route, serverId in
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        switch route {
                        case .overview:
                            viewState.path.append(NavigationDestination.server_overview_settings(serverId))
                        case .channels:
                            viewState.path.append(NavigationDestination.server_channels(serverId))
                        default:
                            debugPrint("")
                        }
                    }
                })
            }
        }
        .sheet(isPresented: $showAddServerSheet) {
            AddServerSheet(isPresented: $showAddServerSheet)
        }
        .onChange(of: didDrop) { oldValue, newValue in
            if newValue {
                Task{
                    let orderedIDs = self.viewState.servers.elements.map { $0.key }
                    self.viewState.userSettingsStore.updateServerOrdering(orders: orderedIDs)
                    
                    let timestamp = "\(Int64(Date().timeIntervalSince1970 * 1000))"
                    let orderingKeys = viewState.userSettingsStore.prepareOrderingSettings()
                    _ = await viewState.http.setSettings(timestamp: timestamp, keys: orderingKeys)
                }
                didDrop = false
            }
        }
        .onAppear {
            // DATABASE-FIRST: Trigger background sync for servers and channels
            NetworkSyncService.shared.syncAllServers()
            NetworkSyncService.shared.syncAllChannels()
        }
        // React to DM updates posted by ViewState/WebSocket so the sidebar refreshes immediately
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DMListNeedsUpdate"))) { notification in
            // Force a UI refresh by notifying that ViewState changed
            viewState.objectWillChange.send()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DatabaseChannelsUpdated"))) { _ in
            // Database wrote new/updated channels (including DMs) – refresh sidebar list
            viewState.objectWillChange.send()
        }
    }
}

struct SlideShape: View {
    
    var buttonSize : CGFloat
    
    var body: some View {
        Color.bgGray02
            .frame(width: .size4, height: buttonSize)
            .clipShape(
                .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: .radiusLarge,
                    topTrailingRadius: .radiusLarge
                )
            )
    }
}

struct ServerItemView: View {
    @EnvironmentObject var viewState: ViewState
    let server: Server
    let buttonSize: CGFloat
    @Binding var selectedServer: Server?
    @Binding var showServerSheet: Bool
    @Binding var isPresentedNotificationSetting: Bool
    
    var body: some View {
        Button {
            withAnimation {
                viewState.selectServer(withId: server.id)
            }
            
            // OPTIMIZED: Move API call outside animation block to prevent UI freeze
            Task.detached(priority: .userInitiated) {
                await viewState.getServerMembers(target: server.id)
            }
        } label: {
            ZStack(alignment: .leading) {
                let unreadType = viewState.getUnreadCountFor(server: server)
                let isSelected = viewState.currentSelection.id == server.id
                
                ZStack(alignment: .bottomTrailing) {
                    ServerListIcon(
                        server: server,
                        height: buttonSize,
                        width: buttonSize,
                        currentSelection: $viewState.currentSelection
                    )
                    
                    if case .mentions(let count) = unreadType {
                        UnreadMentionsView(count: count, mentionSize: .size20)
                    } else if case .unreadWithMentions(let count) = unreadType {
                        UnreadMentionsView(count: count, mentionSize: .size20)
                    }
                }
                
                switch unreadType {
                case .unread, .unreadWithMentions(_):
                    UnreadView(unreadSize: .size12)
                        .offset(x: -16)
                        .opacity(!isSelected ? 1 : 0)
                default:
                    UnreadView(unreadSize: .size12)
                        .opacity(0)
                }
                
                SlideShape(buttonSize: buttonSize)
                    .offset(x: -8)
                    .opacity(isSelected ? 1 : 0)
                }
                .compositingGroup()
            }
            .contextMenu {
                PeptideText(text: server.name, textColor: .textGray04)
                
                Button {
                    Task {
                        let success = await viewState.markServerAsRead(serverId: server.id)
                        withAnimation {
                            if success {
                                viewState.showAlert(message: "Server marked as read!", icon: .peptideDone)
                            } else {
                                viewState.showAlert(message: "Failed to mark server as read", icon: .peptideWarningCircle)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: .zero) {
                        PeptideText(text: "Mark as Read", textColor: .textGray04)
                        PeptideIcon(iconName: .peptideDone, color: .iconGray04)
                    }
                }
                
                Button {
                    withAnimation {
                        copyText(text: server.id)
                        viewState.showAlert(message: "Server ID Copied!", icon: .peptideCopy)
                    }
                } label: {
                    HStack(spacing: .zero) {
                        PeptideText(text: "Copy Server ID", textColor: .textGray04)
                        PeptideIcon(iconName: .peptideCopy, color: .iconGray04)
                    }
                }
                
                Button {
                    withAnimation {
                        selectedServer = server
                        isPresentedNotificationSetting.toggle()
                    }
                } label: {
                    HStack(spacing: .zero) {
                        PeptideText(text: "Notification Options", textColor: .textGray04)
                        PeptideIcon(iconName: .peptideNotificationOff, color: .iconGray04)
                    }
                }
                
                Button {
                    selectedServer = server
                    showServerSheet.toggle()
                } label: {
                    HStack(spacing: .zero) {
                        PeptideText(text: "More Options", textColor: .textGray04)
                        PeptideIcon(iconName: .peptideSetting, color: .iconGray04)
                    }
                }
            }
        }
    }


struct ServerDropDelegate: DropDelegate {
    let currentServer: Server
    @Binding var draggedServer: Server?
    let viewState: ViewState
    @Binding var didDrop: Bool
    
    func performDrop(info: DropInfo) -> Bool {
            guard let draggedServer = draggedServer else { return false }

            let servers = Array(viewState.servers.elements)
            guard let fromIndex = servers.firstIndex(where: { $0.value.id == draggedServer.id }),
                  let toIndex = servers.firstIndex(where: { $0.value.id == currentServer.id }) else {
                return false
            }

            viewState.reorderServers(from: servers[fromIndex].key, to: servers[toIndex].key)
            self.draggedServer = nil

            // Trigger drop complete flag
            didDrop = true
            return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedServer = draggedServer else { return }
        
        let servers = Array(viewState.servers.elements)
        guard let fromIndex = servers.firstIndex(where: { $0.value.id == draggedServer.id }),
              let toIndex = servers.firstIndex(where: { $0.value.id == currentServer.id }) else {
            return
        }
        
        viewState.reorderServers(from: servers[fromIndex].key, to: servers[toIndex].key)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return draggedServer != nil /*&& draggedServer?.id != currentServer.id*/
    }
}

#Preview(traits: .fixedLayout(width: 60, height: 400)) {
    ServerScrollView()
        .applyPreviewModifiers(withState: ViewState.preview()
            .applySystemScheme(theme: .dark))
}
