import SwiftUI
import Types

struct ServerInvitesView: View {
    @EnvironmentObject var viewState: ViewState
    var serverId: String
    
    @State private var invites: [ServerInvite] = []
    @State private var isLoading: Bool = false
    @State private var deletingId: String?
    
    private let toolbarConfig = ToolbarConfig(
        isVisible: true,
        title: "Invites",
        showBackButton: true,
        showBottomLine: true
    )
    
    var body: some View {
        PeptideTemplateView(toolbarConfig: toolbarConfig) { _, _ in
            VStack(spacing: .zero) {
                if isLoading {
                    ProgressView()
                } else {
                    
                    if invites.isEmpty {
                        
                        VStack(spacing: .spacing8) {
                            
                            Image(.peptidePlane)
                                .resizable()
                                .frame(width: .size100, height: .size100)
                                .padding(.bottom, 4)
                            
                            PeptideText(
                                text: "No invites yet",
                                font: .peptideHeadline,
                                textColor: .textDefaultGray01
                            )
                            
                            PeptideText(
                                text: "No invitations have been sent so far.",
                                font: .peptideBody3,
                                textColor: .textGray07
                            )
                            
                            Spacer()
                            
                        }
                        .padding(.top, 24)
                        
                    } else {
                        ScrollView {
                            
                            LazyVStack(spacing: .spacing4) {
                                
                                ForEach(Array(invites.enumerated()), id: \.element.id) { index, invite in
                                    
                                    
                                    HStack(alignment: .top, spacing: .spacing12) {
                                        
                                        VStack(alignment: .leading, spacing: .spacing4) {
                                            
                                            PeptideText(
                                                text: invite.id,
                                                font: .peptideTitle4
                                            )
                                            
                                            HStack(spacing: .spacing4) {
                                                
                                                PeptideIcon(
                                                    iconName: .peptideTag,
                                                    size: .size12,
                                                    color: .iconGray07
                                                )
                                                .padding(.trailing, 4)
                                                
                                                if let server = viewState.servers[invite.server] {
                                                    PeptideText(
                                                        text: server.name,
                                                        font: .peptideBody4,
                                                        textColor: .textGray07
                                                    )
                                                }
                                                
                                            }
                                            .padding(.top, 16)
                                            .padding(.bottom, 8)
                                            
                                            if let creator = viewState.users[invite.creator] {
                                                
                                                HStack(spacing: 4){
                                                    
                                                    Avatar(
                                                        user: creator,
                                                        width: .size32,
                                                        height: .size32
                                                    )
                                                    .padding(.trailing, 4)
                                                    
                                                    PeptideText(
                                                        text: "Invite by \(creator.displayName())",
                                                        font: .peptideBody4,
                                                        textColor: .textGray07
                                                    )
                                                }
                                                
                                            }
                                            
                                        }
                                        
                                        Spacer()
                                        
                                        if(deletingId == invite.id){
                                            
                                            ProgressView()
                                            
                                        }else{
                                            Button {
                                                deleteInvite(id: invite.id)
                                            } label: {
                                                PeptideIcon(
                                                    iconName: .peptideTrashDelete,
                                                    size: .size24,
                                                    color: .iconRed07
                                                )
                                            }
                                        }
                                        
                                    }
                                    .padding(.all, .padding16)
                                    .backgroundGray12(verticalPadding: .padding4)
                                    .padding(.bottom, .padding16)
                                    
                                    
                                }
                            }
                            .padding(.horizontal, .padding16)
                        }
                        .padding(.top, 24)
                    }
                }
            }
        }
        .task {
            await fetchInvites()
        }
    }
    
    private func fetchInvites() async {
        isLoading = true
        let response = await viewState.http.fetchServerInvites(server: serverId)
        switch response {
        case .success(let fetchedInvites):
            invites = fetchedInvites
        case .failure(_):
            viewState.showAlert(message: "Failed to load invites", icon: .peptideInfo)
        }
        isLoading = false
    }
    
    private func deleteInvite(id: String) {
        
        Task {
            
            deletingId = id
            
            let response = await viewState.http.deleteInvite(code: id)
            
            switch response {
            case .success(_):
                await fetchInvites()
            case .failure(_):
                self.viewState.showAlert(message: "Something went wronge!", icon: .peptideInfo)
            }
            
            deletingId = nil
            
            
        }
        
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    ServerInvitesView(serverId: viewState.servers["0"]!.id)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
