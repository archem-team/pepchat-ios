//
//  DMScrollView.swift
//  Revolt
//
//  Created by Angelo on 27/11/2023.
//

import Foundation
import SwiftUI
import Types

/// A view representing a scrollable list of direct messages (DMs) within the application.
struct DMScrollView: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var currentChannel: ChannelSelection  // Binding to the currently selected channel
    var toggleSidebar: () -> ()  // Closure to toggle the visibility of the sidebar
    
    @State private var isPresentedChannelOption : Bool = false
    @State private var isPresentedNotificationSetting : Bool = false
    @State private var delletingGroupDM : GroupDMChannel? = nil
    @State private var isPresentedDelletGroupDmSheet : Bool = false
    @State private var isLoadingDeleteGroupDM : Bool = false
    @State private var selectedChannel : Channel? = nil
    @State private var wsState : WsState = .connecting
    
    // Function to check and fix missing DMs
    private func checkAndFixMissingDMs() {
        // print("🔄 DMScrollView: Checking for missing DMs...")
        
        let totalDmChannels = viewState.allDmChannelIds.count
        let currentlyVisibleDms = viewState.dms.count
        
        // print("🔄 DMScrollView: Total DM channels: \(totalDmChannels), Currently visible: \(currentlyVisibleDms)")
        // print("🔄 DMScrollView: Loaded batches: \(viewState.loadedDmBatches)")
        
        // Use the new validation function
        viewState.validateAndFixDmListConsistency()
        
        // If we still have fewer visible DMs than we should, fix it
        if totalDmChannels > 0 && currentlyVisibleDms < min(totalDmChannels, viewState.dmBatchSize * 2) {
            // print("🔄 DMScrollView: Missing DMs detected, reinitializing...")
            viewState.reinitializeDmListFromCache()
            
            // Also ensure the first few batches are loaded
            let totalBatches = (totalDmChannels + viewState.dmBatchSize - 1) / viewState.dmBatchSize
            let batchesToLoad = min(3, totalBatches)
            for batchIndex in 0..<batchesToLoad {
                if !viewState.loadedDmBatches.contains(batchIndex) {
                    // print("🔄 DMScrollView: Loading missing batch \(batchIndex)")
                    viewState.loadDmBatch(batchIndex)
                }
            }
        }
        
        // Ensure no gaps in loaded batches
        viewState.ensureNoBatchGaps()
        
        // print("🔄 DMScrollView: After fix - Visible DMs: \(viewState.dms.count), Loaded batches: \(viewState.loadedDmBatches)")
    }
    
    var body: some View {
        
        let _ = self.delletingGroupDM

        
        VStack(alignment: .leading, spacing: .zero){
            
            VStack(alignment: .leading, spacing: .spacing8){
                
                PeptideText(text: "Direct Messages", font: .peptideHeadline)
                   
                                                
                    switch wsState {
                        case .disconnected:
                        
                                HStack(spacing: .size2){
                                    
                                    PeptideIcon(iconName: .peptideDisconnect,
                                                size: .size20,
                                                color: .iconRed07)
                                    
                                    PeptideText(text: "Disconnected",
                                                font: .peptideFootnote,
                                                textColor: .textRed07)
                                    
                                    Spacer(minLength: .zero)
                                    
                    
                                    PeptideIconButton(icon: .peptideRefresh,
                                                      color: .iconDefaultGray01,
                                                      size: .size20){
                                        viewState.ws?.forceConnect()
                                    }
                                    
                                    
                                }
                                .padding(.horizontal, .padding12)
                                .frame(height: .size36)
                                .background(RoundedRectangle(cornerRadius: .radiusXSmall).fill(Color.bgRed11))
                        
                        case .connected:
                            EmptyView()
                        
                        case .connecting:
                            HStack(spacing: .spacing4){
                                
                                Spacer(minLength: .zero)
                                
                                let retryCount = viewState.ws?.retryCount ?? 0
                                
                                PeptideText(text: retryCount == 0 ? "Connecting" : "Reconnecting",
                                            font: .peptideFootnote,
                                            textColor: .textDefaultGray01)
                                
                                PeptideLoading(dotSize: .size2,
                                               dotSpacing: .size2,
                                               activeColor: Color.iconDefaultGray01,
                                               offset: -4)

                                
                                Spacer(minLength: .zero)

                            }
                            .frame(height: .size36)
                            .background(RoundedRectangle(cornerRadius: .radiusXSmall).fill(Color.bgGray11))
                    
                    
                }
                
            }
            .padding(top: .padding24, bottom: .padding16)
            .padding(.horizontal, .padding16)
            
                
            
            PeptideDivider(backgrounColor: .borderGray11)
            
            
            Button {
                Task { @MainActor in
                    do {
                        // Open the direct message channel for the current user
                        guard let currentUser = viewState.currentUser else {
                            print("Error: currentUser is nil")
                            return
                        }
                        let channel = try await viewState.http.openDm(user: currentUser.id).get()
                        toggleSidebar() // Toggle the sidebar
                        
                        // Use selectDm to properly set the current channel
                        viewState.channels[channel.id] = channel
                        viewState.selectDm(withId: channel.id)
                        viewState.path.append(NavigationDestination.maybeChannelView)
                    } catch let error {
                        // Handle error here
                        print("error \(error)")
                    }
                }
            } label: {
                HStack(spacing: .padding8){
                    
                    
                    PeptideIcon(iconName: .peptideBookmark,
                                size: .size20,
                                color: .iconDefaultGray01)
                    .frame(width: .size32, height: .size32)
                    .background(Circle().fill(Color.bgGray10))
                    
                    VStack(alignment: .leading, spacing: .spacing2){
                        
                        PeptideText(text: "Saved Notes",
                                    font: .peptideCallout,
                                    textColor: .textDefaultGray01)
                        
                        PeptideText(text: "Personal",
                                    font: .peptideCaption1,
                                    textColor: .textGray07)
                    }
                    
                    Spacer(minLength: .zero)
                    
                    PeptideIcon(iconName: .peptideArrowRight,
                                size: .size20,
                                color: .iconGray07)
                    
                }
                .padding(.horizontal, .padding16)
                
            }
            .frame(minHeight: .size58)
            
            
            PeptideDivider(backgrounColor: .borderGray11)
            
            
            ScrollView {
                
                LazyVStack(spacing: .zero) {
                    
                    let dmsList = viewState.dms.filter { channel in
                        switch channel {
                        case .saved_messages:
                            return false
                        case .dm_channel(let dmChannel):
                            return dmChannel.active
                        default:
                            return true
                        }
                    }
                    
                
                    if dmsList.isEmpty {
                        
                        DMEmptyView()
                            .padding(top: .padding24,
                                     bottom: .padding24,
                                     leading: .padding16,
                                     trailing: .padding16)
                        
                    } else {
                        ForEach(Array(dmsList.enumerated()), id: \.element.id) { index, channel in
                            Button {
                                toggleSidebar()
                                // CRITICAL FIX: Clear channel messages before navigating to ensure full message history is loaded
                                // This prevents the issue where only new WebSocket messages are shown
                                print("🔄 DMScrollView: Clearing channel messages for DM \(channel.id) to ensure full history loads")
                                viewState.channelMessages[channel.id] = []
                                viewState.preloadedChannels.remove(channel.id)
                                viewState.selectDm(withId: channel.id)
                                viewState.path.append(NavigationDestination.maybeChannelView)
                            } label: {
                                
                                ZStack(alignment: .leading){
                                    
                                    
                                    HStack(spacing: .zero) {
                                        ChannelIconDM(channel: channel,
                                                    withUserPresence: true)
                                        .onLongPressGesture {
                                            self.selectedChannel = channel
                                            self.isPresentedChannelOption.toggle()
                                        }
                                        .onTapGesture{
                                            toggleSidebar()
                                            // CRITICAL FIX: Clear channel messages before navigating to ensure full message history is loaded
                                            // This prevents the issue where only new WebSocket messages are shown
                                            print("🔄 DMScrollView: Clearing channel messages for DM \(channel.id) to ensure full history loads")
                                            viewState.channelMessages[channel.id] = []
                                            viewState.preloadedChannels.remove(channel.id)
                                            viewState.selectDm(withId: channel.id)
                                            viewState.path.append(NavigationDestination.maybeChannelView)
                                        }
                                        
                                        Spacer(minLength: .zero)
                                        // Show unread message count if applicable
                                        
                                    }
                                    
                                    
                                }
                                
                            }
                            .onAppear {
                                // IMPROVED LAZY LOADING: Load batches based on actual visible index
                                viewState.loadDmBatchesIfNeeded(visibleIndex: index)
                                
                                // Also load more when near the end
                                if index >= dmsList.count - 5 && viewState.hasMoreDmsToLoad {
                                    viewState.loadMoreDmsIfNeeded()
                                }
                            }
                            .onDisappear {
                                // CRITICAL FIX: When item disappears, check if we need to reload missing batches
                                // This happens when user scrolls up after scrolling down
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    // Check if this item should still be visible based on its index
                                    if index < viewState.dms.count {
                                        // If the item should be visible but disappeared, reload its batch
                                        let batchIndex = index / viewState.dmBatchSize
                                        if !viewState.loadedDmBatches.contains(batchIndex) {
                                            // print("🔄 LAZY_DM: Item \(index) disappeared but should be visible, reloading batch \(batchIndex)")
                                            viewState.loadDmBatch(batchIndex)
                                        }
                                    }
                                }
                            }
                        }
                        
                        RoundedRectangle(cornerRadius: .zero)
                            .fill(Color.bgGray12)
                            .frame(height: .size64)
                    }
                    
                    
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.bgGray12)

            Spacer(minLength: .zero)
            
        }
        .background{
            Color.bgGray12
                .clipShape(
                    .rect(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
            
        }
        .onChange(of: self.viewState.wsCurrentState){o, n in
            self.wsState = n
        }
        .onAppear{
            self.wsState = self.viewState.wsCurrentState
            
            // CRITICAL FIX: Check for missing DMs when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.checkAndFixMissingDMs()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Also check when app becomes active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkAndFixMissingDMs()
            }
        }
        // CRITICAL FIX: Listen for DM updates from WebSocket
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DMListNeedsUpdate"))) { notification in
            // print("📱 DMScrollView: Received WebSocket update notification")
            // The view will automatically update due to @EnvironmentObject viewState
            // But we'll ensure the DM list is refreshed
            if let userInfo = notification.userInfo as? [String: Any],
               let channelId = userInfo["channelId"] as? String {
                // print("📱 DMScrollView: New message in channel \(channelId)")
                // Force a UI refresh by triggering viewState update
                viewState.objectWillChange.send()
            }
        }
        .sheet(isPresented: $isPresentedChannelOption){
            
            if let selectedChannel = self.selectedChannel {
                ChannelOptionsSheet(isPresented: $isPresentedChannelOption,
                                    channel: selectedChannel){ option in
                switch option {
                   case .viewProfile(let user, let member):
                        viewState.openUserSheet(user: user, member: member)
                   case .message(let user):
                        Task { @MainActor in
                            toggleSidebar()
                            await viewState.openDm(with: user.id)
                            self.isPresentedChannelOption.toggle()
                            viewState.path.append(NavigationDestination.maybeChannelView)
                        }
                   case .notificationOptions:
                        self.isPresentedChannelOption.toggle()
                        self.isPresentedNotificationSetting.toggle()
                   case .copyDirectMessageId(let channelId):
                        copyText(text: channelId)
                    self.viewState.showAlert(message: "Direct Message ID Copied!", icon: .peptideDoneCircle)
                   case .closeDM(let channelId):
                        Task { @MainActor in
                            await self.viewState.closeDMGroup(channelId: channelId)
                        }
                case .closeDMGroup(let channel):
                    self.delletingGroupDM = channel
                    self.isPresentedDelletGroupDmSheet.toggle()
                    self.isPresentedChannelOption.toggle()
                   case .reportUser(let user):
                    viewState.path.append(NavigationDestination.report(user, nil, nil))
                    
                   case .copyGroupId(let channelId):
                        copyText(text: channelId)
                        self.viewState.showAlert(message: "Group ID Copied!", icon: .peptideDoneCircle)
                    
                    case .groupSetting(let channelId) :
                        self.viewState.path.append(NavigationDestination.channel_settings(channelId))
                    default:
                        print("---")
                    
                   }
                
                }
            }
        }
        .sheet(isPresented: self.$isPresentedNotificationSetting){
            if let selectedChannel = self.selectedChannel {
                NotificationSettingSheet(isPresented: $isPresentedNotificationSetting, channel: selectedChannel)
            }
        }
        .popup(isPresented: $isPresentedDelletGroupDmSheet, view: {
            
            if let delletingGroupDM = self.delletingGroupDM{
                
                DeleteGroupSheet(
                    isPresented: $isPresentedDelletGroupDmSheet,
                    channel: .group_dm_channel(delletingGroupDM)
                )
                
            }
            
        }, customize: {
            $0.type(.default)
              .isOpaque(true)
              .appearFrom(.bottomSlide)
              .backgroundColor(Color.bgDefaultPurple13.opacity(0.9))
              .closeOnTap(false)
              .closeOnTapOutside(false)
        })
        
        
    }
}

/// Preview provider for the DMScrollView.
struct DMScrollView_Previews: PreviewProvider {
    @StateObject static var viewState = ViewState.preview()  // Create a preview instance of ViewState
    
    static var previews: some View {
        DMScrollView(currentChannel: $viewState.currentChannel, toggleSidebar: {})
            .applyPreviewModifiers(withState: viewState)  // Apply preview modifiers
    }
}
