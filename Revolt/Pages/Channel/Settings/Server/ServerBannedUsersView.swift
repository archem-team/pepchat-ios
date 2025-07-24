import SwiftUI
import Types

struct ServerBannedUsersView: View {
    @EnvironmentObject var viewState: ViewState
    var serverId: String
    
    @State private var users: [User] = []
    @State private var bans: [Ban] = []
    @State private var isLoading: Bool = false
    @State private var deletingId: String?
    @State private var searchQuery: String = ""
    @State private var searchTextFieldState: PeptideTextFieldState = .default
    
    var filteredUsers: [User] {
        if searchQuery.isEmpty {
            return users
        }
        
        return users.filter { user in
            return user.username.lowercased().contains(searchQuery.lowercased()) ||
            (user.display_name?.lowercased().contains(searchQuery.lowercased()) ?? false)
        }
    }
    
    private let toolbarConfig = ToolbarConfig(
        isVisible: true,
        title: "Banned Users",
        showBackButton: true,
        showBottomLine: true
    )
    
    var body: some View {
        PeptideTemplateView(toolbarConfig: toolbarConfig) { _, _ in
            VStack(spacing: .zero) {
                if isLoading {
                    ProgressView()
                } else {
                    
                    if(!filteredUsers.isEmpty || !searchQuery.isEmpty){
                        
                        HStack(spacing: .spacing8) {
                            PeptideTextField(
                                text: $searchQuery,
                                state: $searchTextFieldState,
                                placeholder: "Search in banned list",
                                icon: .peptideSearch,
                                cornerRadius: .radiusLarge,
                                height: .size40,
                                keyboardType: .default
                            )
                        }
                        .padding(.top, .padding24)
                        .padding(.horizontal, .size16)
                        
                    }
                    
                    if filteredUsers.isEmpty {
                        
                        let searchQueryIsEmpty = searchQuery.isEmpty
                        
                        VStack(spacing: .spacing4){
                            
                            Image(searchQueryIsEmpty ? .peptidePlane : .peptideNotFound)
                                .resizable()
                                .frame(width: .size100, height: .size100)
                            
                            PeptideText(text: searchQueryIsEmpty ? "The Ban List is Empty" : "Nothing Matches Your Search",
                                        font: .peptideHeadline,
                                        textColor: .textDefaultGray01)
                            .padding(.horizontal, .padding24)
                            
                            PeptideText(text: searchQueryIsEmpty ? "No users have been banned from this server yet." : "Make sure the text is correct or try other terms.",
                                        font: .peptideSubhead,
                                        textColor: .textGray07,
                                        alignment: .center)
                            .padding(.horizontal, .padding24)
                            
                        }
                        .padding(.horizontal, .padding16)
                        .padding(.bottom, .padding16)
                        .padding(.top, .padding24)
                        
                    } else {
                        ScrollView {
                            
                            LazyVStack(spacing: .spacing4) {
                                
                                ForEach(Array(filteredUsers.enumerated()), id: \.element.id) { index, user in
                                    
                                    
                                    HStack(alignment: .top, spacing: .spacing12) {
                                        
                                        VStack(alignment: .leading, spacing: .spacing4) {
                                            HStack(spacing: 4){
                                                
                                                Avatar(
                                                    user: user,
                                                    width: .size32,
                                                    height: .size32
                                                )
                                                .padding(.trailing, 8)
                                                
                                                PeptideText(
                                                    text: user.displayName(),
                                                    font: .peptideHeadline,
                                                    textColor: .textGray07
                                                )
                                            }
                                            .padding(.bottom, 16)
                                            
                                            if let banReason = (bans.first { $0.id.user == user.id }?.reason) {
                                                
                                                PeptideText(
                                                    text: "Ban reason:",
                                                    font: .peptideSubhead,
                                                    textColor: .textGray07
                                                )
                                                .padding(.trailing, 4)
                                                
                                                PeptideText(
                                                    text: banReason,
                                                    font: .peptideBody4
                                                )
                                                
                                            }
                                            
                                        }
                                        
                                        Spacer()
                                        
                                        if(deletingId == user.id){
                                            
                                            ProgressView()
                                            
                                        }else{
                                            Button {
                                                unBan(userId: user.id)
                                            } label: {
                                                PeptideIcon(
                                                    iconName: .peptideCancelFriendRequest,
                                                    size: .size24,
                                                    color: .iconRed07
                                                )
                                                .padding(.top, 4)
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
                    
                    Spacer(minLength: .zero)
                }
            }
            
        }
        .task {
            await fetchBans()
        }
    }
    
    private func fetchBans() async {
        isLoading = true
        let response = await viewState.http.fetchBans(server: serverId)
        switch response {
        case .success(let bansResponse):
            self.users = bansResponse.users
            self.bans = bansResponse.bans
        case .failure(_):
            viewState.showAlert(message: "Failed to load", icon: .peptideInfo)
        }
        isLoading = false
    }
    
    private func unBan(userId: String) {
        
        
        
        Task {
            
            deletingId = userId
            
            let response = await viewState.http.deleteBan(server: serverId, userId: userId)
            
            switch response {
            case .success(_):
                await fetchBans()
            case .failure(_):
                self.viewState.showAlert(message: "Something went wronge!", icon: .peptideInfo)
            }
            
            deletingId = nil
            
            
        }
        
        
        
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    ServerBannedUsersView(serverId: viewState.servers["0"]!.id)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
