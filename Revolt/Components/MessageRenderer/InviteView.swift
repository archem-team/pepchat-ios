import SwiftUI
import Types

struct InviteView: View {
    @EnvironmentObject var viewState: ViewState
    let inviteCode: String
    let invite: InviteInfoResponse?
    

    var body: some View {
        VStack(alignment: .leading, spacing: .size12) {
            
            if let invite{
            
                switch invite {
                case .server(_):
                    PeptideText(
                        text: "You've been invited to join a server",
                        font: .peptideCallout,
                        textColor: .textGray06
                    )
                case .group(_):
                    PeptideText(
                        text: "You've been invited to join a group",
                        font: .peptideCallout,
                        textColor: .textGray06
                    )
                }
                
                HStack(spacing: .spacing8) {
                    switch invite {
                    case .server(let serverInfoResponse):
                        
                        if let icon = serverInfoResponse.server_icon {
                            LazyImage(source: .file(icon), height: 40, width: 40, clipTo: Circle())
                        } else {
                            FallbackServerIcon(name: serverInfoResponse.server_name, width: 40, height: 40, clipTo: Circle())
                        }
                        
                        VStack(spacing: .zero) {
                            
                            PeptideText(
                                text: serverInfoResponse.server_name,
                                font: .peptideHeadline,
                                textColor: .textDefaultGray01
                            )
                            
                            PeptideText(
                                text: "\(serverInfoResponse.member_count) members",
                                font: .peptideBody3,
                                textColor: .textGray07
                            )
                        }
                        
                    case .group(_):
                        PeptideIcon(
                            iconName: .peptideUsers,
                            size: .size48,
                            color: .iconDefaultGray01
                        )
                        
                        VStack(alignment: .leading, spacing: .spacing4) {
                            PeptideText(
                                text: "Group DM",
                                font: .peptideHeadline,
                                textColor: .textDefaultGray01
                            )
                        }
                        
                    }
                   
                }
                
                PeptideButton(
                    buttonType: .small(),
                    title: "Join",
                    bgColor: .bgYellow07,
                    contentColor: .textInversePurple13
                ) {
                    
                    self.viewState.path.append(NavigationDestination.invite(self.inviteCode))
    
                }
                
            }
            else{
                
                HStack(spacing: .size8){
                    
                    Circle()
                        .fill(Color.bgGray11)
                        .frame(width: 40, height: 40)
                    
                    PeptideText(
                        text: "Invalid invite!",
                        font: .peptideCallout                        
                    )
                    
                    Spacer(minLength: .zero)
                }

            }
            
        }
        .padding(.horizontal, .padding12)
        .padding(.vertical, .padding8)
        .background(Color.bgGray12)
        .cornerRadius(.radius8)
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    let invite : InviteInfoResponse = .server(.init(
        code: "X9atcKxZ",
        server_id: "01JMY5NWR3607DNDNV7MF2FZ1T",
        server_name: "Server A",
        channel_id: "01JN355Q01JH25WFZMEKR6MGTF",
        channel_name: "ch1",
        user_name: "labron",
        member_count: 2
    ))
    
    InviteView(
        inviteCode:"X9atcKxZ",
        invite: nil
    )
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
} 
