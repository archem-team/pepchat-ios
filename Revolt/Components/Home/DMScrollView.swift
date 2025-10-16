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
            
            // DATABASE-FIRST: Trigger background sync for channels
            NetworkSyncService.shared.syncAllChannels()
        }
        // CRITICAL FIX: Listen for DM updates from WebSocket
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DMListNeedsUpdate"))) { notification in
            // The view will automatically update due to @EnvironmentObject viewState
            // But we'll ensure the DM list is refreshed
            if let userInfo = notification.userInfo as? [String: Any],
               let channelId = userInfo["channelId"] as? String {
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
						break
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
