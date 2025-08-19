//
//  MutualConnectionsSheet.swift
//  Revolt
//
//  Created by Mehdi on 2/9/25.
//

import SwiftUI
import Types


enum MutualConnection : CaseIterable, Hashable{
    case friends;
    case groups;
    case servers;
    
    func getTitle(count: Int) -> String {
        switch self {
        case .friends: return count == 0 ? "No Friends" : "\(count) Friend\(count > 1 ? "s" : "")"
        case .groups: return count == 0 ? "No Groups" : "\(count) Group\(count > 1 ? "s" : "")"
        case .servers: return  count == 0 ? "No Servers" :  "\(count) Server\(count > 1 ? "s" : "")"
        }
    }
}

struct MutualConnectionsSheet: View {

    @EnvironmentObject var viewState: ViewState
    @Binding var isPresented: Bool
    var user: User
    @State var mutualServers: [Server] = []
    @State var mutualFriends: [User] = []
    @State var mutualChannels: [GroupDMChannel] = []

    @State var selectedTab = MutualConnection.servers
    
    var body: some View {
        VStack{
            PeptideSheet(isPresented: $isPresented, horizontalPadding: .zero, maxHeight: 600){
                
                ZStack(alignment: .center) {
                    PeptideText(
                        text: "Mutual Connections",
                        font: .peptideHeadline,
                        textColor: .textDefaultGray01
                    )
                    HStack {
                        PeptideIconButton(icon: .peptideBack, color: .iconDefaultGray01, size: .size24) {
                            isPresented.toggle()
                        }
                        Spacer()
                    }
                }
                .padding(.bottom, .padding24)
                .padding(.horizontal, .padding16)
                
                HStack(spacing: .zero){
                    
                    ForEach(MutualConnection.allCases, id: \.self) { tab in
                        
                        let label = tab.getTitle(count: tab == .friends ? mutualFriends.count : tab == .servers ? mutualServers.count : mutualChannels.count)
                        
                        PeptideTabItemIndicator(isSelected: selectedTab == tab, label: label){
                            self.selectedTab = tab
                        }
                        
                    }
                }
                .padding(.bottom, .size24)
                
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        if(selectedTab == .friends){
                            
                            if mutualFriends.isEmpty {
                                PeptideText(text: "No mutual friends found", 
                                          font: .peptideBody4, 
                                          textColor: .textGray07)
                                    .padding(.all, .padding24)
                            } else {
                                let firstUserId = self.mutualFriends.first?.id
                                let lastUserId = self.mutualFriends.last?.id
                            
                            ForEach(self.mutualFriends, id: \.self){ friend in
                                
                                let userId = friend.id
                                
                                HStack(spacing: .zero){
                                
                                    Avatar(user: friend, withPresence: false)
                                        .padding(.trailing, .size12)
                                    
                                    PeptideText(text: friend.username)
                                    
                                    Spacer(minLength: .zero)
                                    
                                }
                                .padding(.all, .size12)
                                .background{
                                    
                                    UnevenRoundedRectangle(topLeadingRadius: userId == firstUserId ? .radiusMedium : .zero,
                                                           bottomLeadingRadius: userId == lastUserId ? .radiusMedium : .zero,
                                                           bottomTrailingRadius: userId == lastUserId ? .radiusMedium : .zero,
                                                           topTrailingRadius: userId == firstUserId ? .radiusMedium : .zero)
                                    .fill(Color.bgGray11)
                                    
                                }
                                .padding(.horizontal, .size16)
                                
                                if userId != lastUserId {
                                    PeptideDivider(backgrounColor: .borderGray10)
                                        .padding(.leading, .size48)
                                        .background(Color.bgGray11)
                                        .padding(.horizontal, .size16)
                                    
                                }
                                
                            }
                            
                            }
                        }
                        else if(selectedTab == .groups){
                            
                            if mutualChannels.isEmpty {
                                PeptideText(text: "No mutual groups found", 
                                          font: .peptideBody4, 
                                          textColor: .textGray07)
                                    .padding(.all, .padding24)
                            } else {
                                let firstItemId = self.mutualChannels.first?.id
                                let lastItemId = self.mutualChannels.last?.id
                                
                                ForEach(self.mutualChannels, id: \.id){ item in
                                
                                let itemId = item.id
                                
                                HStack(spacing: .zero){
                                    
                                    
                                    if let icon = item.icon {
                                        LazyImage(source: .file(icon), height: 32, width: 32, clipTo: Circle()) .padding(.trailing, .size12)
                                    } else {

                                        PeptideText(text: item.name.first?.description ?? "")
                                            .frame(width: 32, height: 32, alignment: .center)
                                            .background(.bgGray12, in: .circle)
                                            .padding(.trailing, .size12)

                                    }
                                    

                                    
                                    PeptideText(text: item.name)
                                    
                                    Spacer(minLength: .zero)
                                    
                                }
                                .padding(.all, .size12)
                                .background{
                                    
                                    UnevenRoundedRectangle(topLeadingRadius: itemId == firstItemId ? .radiusMedium : .zero,
                                                           bottomLeadingRadius: itemId == lastItemId ? .radiusMedium : .zero,
                                                           bottomTrailingRadius: itemId == lastItemId ? .radiusMedium : .zero,
                                                           topTrailingRadius: itemId == firstItemId ? .radiusMedium : .zero)
                                    .fill(Color.bgGray11)
                                    
                                }
                                .padding(.horizontal, .size16)
                                
                                if itemId != lastItemId {
                                    PeptideDivider(backgrounColor: .borderGray10)
                                        .padding(.leading, .size48)
                                        .background(Color.bgGray11)
                                        .padding(.horizontal, .size16)
                                    
                                }
                                
                            }
                            
                            }
                        }
                        else if(selectedTab == .servers){
                            
                            if mutualServers.isEmpty {
                                PeptideText(text: "No mutual servers found", 
                                          font: .peptideBody4, 
                                          textColor: .textGray07)
                                    .padding(.all, .padding24)
                            } else {
                                let firstItemId = self.mutualServers.first?.id
                                let lastItemId = self.mutualServers.last?.id
                                
                                ForEach(self.mutualServers, id: \.id){ item in
                                
                                let itemId = item.id
                                
                                HStack(spacing: .zero){
                                    
                                    
                                    if let icon = item.icon {
                                        LazyImage(source: .file(icon), height: 32, width: 32, clipTo: Circle()) .padding(.trailing, .size12)
                                    } else {

                                        PeptideText(text: item.name.first?.description ?? "")
                                            .frame(width: 32, height: 32, alignment: .center)
                                            .background(.bgGray12, in: .circle)
                                            .padding(.trailing, .size12)

                                    }
                                    

                                    
                                    PeptideText(text: item.name)
                                    
                                    Spacer(minLength: .zero)
                                    
                                }
                                .padding(.all, .size12)
                                .background{
                                    
                                    UnevenRoundedRectangle(topLeadingRadius: itemId == firstItemId ? .radiusMedium : .zero,
                                                           bottomLeadingRadius: itemId == lastItemId ? .radiusMedium : .zero,
                                                           bottomTrailingRadius: itemId == lastItemId ? .radiusMedium : .zero,
                                                           topTrailingRadius: itemId == firstItemId ? .radiusMedium : .zero)
                                    .fill(Color.bgGray11)
                                    
                                }
                                .padding(.horizontal, .size16)
                                
                                if itemId != lastItemId {
                                    PeptideDivider(backgrounColor: .borderGray10)
                                        .padding(.leading, .size48)
                                        .background(Color.bgGray11)
                                        .padding(.horizontal, .size16)
                                    
                                }
                                
                            }
                            
                            }
                        }
                    }
                    .padding(.bottom, .padding16)
                }
                .frame(minHeight: 100)
                
            }
        }
        .task {
            // Fetch mutual friends and servers if user is not the current user
            if user.id != viewState.currentUser!.id,
               let mutuals = try? await viewState.http.fetchMutuals(user: user.id).get()
            {
                let serverIds = mutuals.servers
                let userIds = mutuals.users
                self.mutualFriends = userIds.compactMap { self.viewState.users[$0] }
                self.mutualServers = serverIds.compactMap { self.viewState.servers[$0] }

                
            }
        }
        .task {
            
            mutualChannels = findCommonGroupDMChannel(channels: viewState.dms,
                                                        currentUserId: viewState.currentUser?.id,
                                                        otherUserId: user.id)
            
            
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
}


struct MutualConnectionsSheetPreview: PreviewProvider {
    @StateObject static var viewState: ViewState = ViewState.preview().applySystemScheme(theme: .dark)
    
    static var previews: some View {
        Text("foo")
            .sheet(isPresented: .constant(true)) {
                MutualConnectionsSheet(isPresented: .constant(true), user: viewState.users["0"]!)
            }
            .applyPreviewModifiers(withState: viewState)
            .preferredColorScheme(.dark)
    }
}
