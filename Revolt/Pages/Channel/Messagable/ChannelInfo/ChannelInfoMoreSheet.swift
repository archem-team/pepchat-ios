//
//  ChannelInfoMoreSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct ChannelInfoMoreSheet: View {
    
    @EnvironmentObject var viewState : ViewState
    
    @Binding var isPresented : Bool
    @State private var sheetHeight: CGFloat = .zero
    var channel: Channel
    var server : Server?
    
    
    @Binding var isPresentedNotificationSetting : Bool
    @Binding var isPresentedLeaveChannel : Bool
    
    
    private var channelPermission: Permissions {
        guard let currentUser = viewState.currentUser else {
            return .none
        }
        
        return resolveChannelPermissions(
            from: currentUser,
            targettingUser: currentUser,
            targettingMember: server.flatMap { viewState.members[$0.id]?[currentUser.id] },
            channel: channel,
            server: server
        )
    }
    
    var body: some View {
        
        VStack(spacing: .spacing24){
            
            if !self.channel.isDM {
            
                Button {
                    viewState.showAlert(message: "Group ID Copied!", icon: .peptideCopy)
                    copyText(text: self.channel.id)
                    isPresented.toggle()
                } label: {
                    
                    PeptideActionButton(icon: .peptideCopy,
                                        title: "Copy Group ID",
                                        hasArrow: false)
                    .backgroundGray11(verticalPadding: .padding4)
                    
                }
                
            }
            
            VStack(spacing: .spacing4){
                
                Button {
                    self.isPresentedNotificationSetting.toggle()
                    self.isPresented.toggle()
                } label: {
                    
                    PeptideActionButton(icon: .peptideNotificationOn,
                                        title: "Notification Options",
                                        hasArrow: false)
                }
                
                
                if self.channel.isRelevantChannel && channelPermission.contains(.manageChannel) {
                    PeptideDivider()
                        .padding(.leading, .padding48)
                    
                    Button {
                        
                        self.viewState.path.append(NavigationDestination.channel_settings(self.channel.id))
                        
                        self.isPresented.toggle()
                        
                    } label: {
                        PeptideActionButton(icon: .peptideSetting,
                                            title: "Group Setting",
                                            hasArrow: false)
                    }
                }
                
                
                
            }
            .backgroundGray11(verticalPadding: .padding4)
            
            if !self.channel.isDM {
            
                Button {
                    self.isPresentedLeaveChannel.toggle()
                    self.isPresented.toggle()
                } label: {
                    
                    PeptideActionButton(icon: .peptideSignOutLeave,
                                        iconColor: .iconRed07,
                                        title: "Leave Group",
                                        titleColor: .textRed07,
                                        hasArrow: false)
                    .backgroundGray11(verticalPadding: .padding4)
                    
                }
                
            }
            
        }
        .padding(top: .padding32,
                 bottom: .padding8,
                 leading: .padding16,
                 trailing: .padding16)
        .overlay {
            GeometryReader { geometry in
                Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
            sheetHeight = newHeight
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.bgGray12)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.bottom)
        
    }
}

#Preview {
    
    @Previewable @StateObject var viewState : ViewState = ViewState.preview()
    ChannelInfoMoreSheet(isPresented: .constant(false), channel: (viewState.channels["0"]!),
                         server: viewState.servers["0"]!,
                         isPresentedNotificationSetting: .constant(false), isPresentedLeaveChannel: .constant(false))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
