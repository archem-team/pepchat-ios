import SwiftUI
import Types
import OSLog

struct ServerMembersView: View {
    @EnvironmentObject var viewState: ViewState
    var serverId: String
    
    @State private var searchQuery: String = ""
    @State private var searchTextFieldState: PeptideTextFieldState = .default
    @State private var members: [Member] = []
    @State private var isLoading: Bool = true
    
    private let logger = Logger(subsystem: "chat.revolt.app", category: "ServerMembersView")
    
    
    var filteredMembers: [Member] {
        if searchQuery.isEmpty {
            return members
        }
        
        return members.filter { member in
            if let user = viewState.users[member.id.user] {
                return user.username.lowercased().contains(searchQuery.lowercased()) ||
                       (user.display_name?.lowercased().contains(searchQuery.lowercased()) ?? false)
            }
            return false
        }
    }
    
    private let toolbarConfig = ToolbarConfig(
        isVisible: true,
        title: "Members",
        showBackButton: true,
        showBottomLine: true
    )
    
    
    var serverPermissions: Permissions{
        
        if let server = viewState.servers[serverId]{
            
            if let currentUser = viewState.currentUser{
                
                if let member =  viewState.members[server.id]?[currentUser.id] {
                    return resolveServerPermissions(user: currentUser, member: member, server: server)
                } else if currentUser.id == server.owner {
                    return .all
                }
            }
            
        }
                
        return .none
    }
    
    var body: some View {
        PeptideTemplateView(toolbarConfig: toolbarConfig) { _, _ in
            VStack(spacing: .zero) {
                if isLoading {
                    // Show loading state
                    PeptideLoading()
                } else {
                    // Search Bar
                    
                        HStack(spacing: .spacing8) {
                            PeptideTextField(
                                text: $searchQuery,
                                state: $searchTextFieldState,
                                placeholder: "Search in members",
                                icon: .peptideSearch,
                                cornerRadius: .radiusLarge,
                                height: .size40,
                                keyboardType: .default
                            )
                        }
                        .padding(.top, .padding24)
                        .padding(.horizontal, .size16)
                    
                    
                    if(!self.filteredMembers.isEmpty)
                    {
                    
                        HStack {
                            PeptideText(
                                text: "Members - \(filteredMembers.count)",
                                font: .peptideHeadline,
                                textColor: .textDefaultGray01
                            )
                            .padding(.horizontal, 32)
                            .padding(.top, .padding24)
                            .padding(.bottom, .padding8)
                            
                            Spacer()
                        }
                        
                    }else{
                        
                        let searchQueryIsEmpty = searchQuery.isEmpty
                        
                        VStack(spacing: .spacing4){
                            
                            Image(searchQueryIsEmpty ? .peptideDmEmpty : .peptideNotFound)
                                .resizable()
                                .frame(width: .size100, height: .size100)
                            
                            PeptideText(text: searchQueryIsEmpty ? "No Members Yet" : "Nothing Matches Your Search",
                                        font: .peptideHeadline,
                                        textColor: .textDefaultGray01)
                            .padding(.horizontal, .padding24)
                            
                            PeptideText(text: searchQueryIsEmpty ? "Add members to channel to see the filled list." : "Make sure the text is correct or try other terms.",
                                        font: .peptideSubhead,
                                        textColor: .textGray07,
                                        alignment: .center)
                            .padding(.horizontal, .padding24)

                        }
                        .padding(.horizontal, .padding16)
                        .padding(.bottom, .padding16)
                        .padding(.top, .padding24)
                        
                    }
                    
                    if(!self.filteredMembers.isEmpty){
                     
                        LazyVStack(spacing: .spacing8) {
                            ForEach(Array(filteredMembers.enumerated()), id: \.offset) { index, member in
                                if let user = viewState.users[member.id.user] {
                                    Button {
                                        // Open user sheet when tapping on any user
                                        viewState.openUserSheet(user: user, member: member)
                                    } label: {
                                        HStack(spacing: .spacing8) {
                                            Avatar(
                                                user: user,
                                                width: .size40,
                                                height: .size40,
                                                withPresence: false
                                            )
                                            
                                            VStack(alignment: .leading, spacing: .zero) {
                                                PeptideText(
                                                    text: user.display_name ?? user.username,
                                                    font: .peptideCallout,
                                                    textColor: .textDefaultGray01
                                                )
                                                
                                                let isOnline = user.online == true
                                                PeptideText(
                                                    text: isOnline ? (user.status?.presence?.rawValue ?? Presence.Online.rawValue) : "Offline",
                                                    font: .peptideCaption1,
                                                    textColor: .textGray07
                                                )
                                            }
                                            
                                            Spacer(minLength: .zero)
                                            
                                            if serverPermissions.contains(.assignRoles){
                                                
                                                PeptideIcon(
                                                    iconName: .peptideArrowRight,
                                                    size: .size20,
                                                    color: .iconGray07
                                                )
                                                
                                            }
                                            
                                        }
                                        .padding(.padding8)                                
                                        .cornerRadius(.radius8)
                                    }
                                    .contextMenu {
                                        // Add context menu for role management (for users with permission)
                                        if serverPermissions.contains(.assignRoles) {
                                            Button {
                                                viewState.path.append(NavigationDestination.member_permissions(serverId, member))
                                            } label: {
                                                Label("Manage Roles", systemImage: "person.badge.shield.checkmark")
                                            }
                                        }
                                    }
                                    
                                    if index != filteredMembers.count - 1 {
                                        PeptideDivider()
                                            .padding(.leading, .padding48)
                                    }
                                }
                            }
                        }
                        .backgroundGray12(verticalPadding: .padding4)
                        .padding(.horizontal, 16)
                        
                    }
                }
                
                Spacer(minLength: .zero)
            }
        }
        .task {
            await fetchMembers()
        }
    }
    
    // MARK: - Database-First Data Loading
    
    private func fetchMembers() async {
        logger.info("🔄 Loading members for server \(serverId) from database")
        isLoading = true
        
        // 1. Load from database first
        let dbMembers = await MemberRepository.shared.fetchMembers(forServer: serverId)
        
        await MainActor.run {
            self.members = dbMembers
            self.isLoading = false
        }
        
        logger.info("✅ Loaded \(dbMembers.count) members from database")
        
        // 2. Trigger background sync for fresh data
        NetworkSyncService.shared.syncServerMembers(serverId: serverId)
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    ServerMembersView(serverId: viewState.servers["0"]!.id)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
} 
