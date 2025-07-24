//
//  SystemMessageSheet.swift
//  Revolt
//
//

import SwiftUI
import Types

struct SystemMessageSheet: View {
    
    @EnvironmentObject var viewState : ViewState
    
    var systemMessage : SystemMessageType
    var server : Server
    
    @State  var selectedChannelId: String? = nil
    
    var onSelected : (_ selectedChannelId : String?, _ systemMessage : SystemMessageType) -> Void
    
    
    private var channels : [TextChannel] {
       server.channels
            .compactMap({
                switch viewState.channels[$0] {
                    case .text_channel(let c):
                    return .some(c)
                    default:
                        return .none
                }
            })
        
    }

    var title : String {
        switch systemMessage {
            case .userJoined:
                "User Joined"
            case .userLeft:
                "User Left"
            case .userKicked:
                "User Kicked"
            case .userBanned:
                "User Banned"
            default:
                ""
        }
    }
    
    var body: some View {
        VStack(spacing: .zero){
            
            PeptideText(text: title,
                        font: .peptideButton,
                        textColor: .textDefaultGray01)
            .padding(.top, .padding24)
            
            
            PeptideText(text: "Choose a channel to show these messages.",
                        font: .peptideSubhead,
                        textColor: .textGray06)
            .padding(.top, .padding4)
            .padding(.bottom, .padding24)
            
            
            ScrollView(.vertical) {
                
                LazyVStack(spacing: .zero){
                    let lastChannelId = channels.last?.id
                    
                    item(channelName: "None",
                         channelId: nil,
                         lastChannelId: lastChannelId)
                    
                    PeptideDivider(backgrounColor: .borderGray11)
                        .padding(.leading, .size48)
                        .padding(.vertical, .padding4)
                        .background(Color.bgGray12)
                    
                    ForEach(channels) { channel in
                        item(channelName: "\(channel.name)",
                             channelId: channel.id,
                             lastChannelId: lastChannelId)
                        
                        if channel.id != lastChannelId {
                            PeptideDivider(backgrounColor: .borderGray11)
                                .padding(.leading, .size48)
                                .padding(.vertical, .padding4)
                                .background(Color.bgGray12)
                            
                        }
                    }
                }
                
                
            }
            .scrollBounceBehavior(.basedOnSize)
            
        }
        .padding(.horizontal, .padding16)
        .background(Color.bgDefaultPurple13)
    
    }
    
  
    
    
    private func currentChannelForSystemMessage() -> String? {
            guard let systemMessages = server.system_messages else {
                return nil
            }
            
            switch systemMessage {
                case .userJoined:
                    return systemMessages.user_joined
                case .userLeft:
                    return systemMessages.user_left
                case .userKicked:
                    return systemMessages.user_kicked
                case .userBanned:
                    return systemMessages.user_banned
            default:
                return nil
           
            }
    }
    
    
    private func toggleBinding(for channelId: String?) -> Binding<Bool> {
        Binding(
            get: {
                self.selectedChannelId == channelId
            },
            set: { isSelected in
                if isSelected {
                    self.selectedChannelId = channelId
                    onSelected(self.selectedChannelId, systemMessage)
                }
            }
        )
    }
    
    
    func item(channelName : String,
              channelId : String?,
              lastChannelId : String?) -> some View {
                
        HStack(spacing: .spacing12){
            
            PeptideIcon(iconName: .peptideTag,
                        color: .iconGray07)
            
            PeptideText(text: channelName,
                        font: .peptideButton,
                        alignment: .leading)
            Spacer(minLength: .zero)
            
            Toggle("", isOn: toggleBinding(for: channelId))
                .toggleStyle(PeptideCircleCheckToggleStyle())
        }
        .padding(.horizontal, .padding12)
        .frame(height: .size48)
        .padding(.top, channelId == nil ? .padding4 : .zero)
        .padding(.bottom, channelId == lastChannelId ? .padding4 : .zero)
        .background{
            
            UnevenRoundedRectangle(topLeadingRadius: channelId == nil ? .radiusMedium : .zero,
                                   bottomLeadingRadius: channelId == lastChannelId ? .radiusMedium : .zero,
                                   bottomTrailingRadius: channelId == lastChannelId ? .radiusMedium : .zero,
                                   topTrailingRadius: channelId == nil ? .radiusMedium : .zero)
            .fill(Color.bgGray12)
            
        }
       
    }
    
    

}


struct SystemChannelSelector: View {
    @EnvironmentObject var viewState: ViewState
    
    var title: String
    var server: Server
    
    @Binding var selection: String?
    
    var body: some View {
        Picker(title, selection: $selection) {
            
            
//            ForEach(server.channels
//                .compactMap({
//                    switch viewState.channels[$0] {
//                        case .text_channel(let c):
//                            return .some(c)
//                        default:
//                            return .none
//                    }
//                })
//            ) { channel in
//                Text("#\(channel.name)")
//                    .tag(channel.id as String?)
//            }
        }
    }
}

#Preview {
    
    @Previewable @StateObject var viewState = ViewState.preview()
    
    SystemMessageSheet(systemMessage: .userBanned,
                       server: viewState.servers["0"]!, onSelected: {_,_ in
        
    })
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
