import SwiftUI
import Types
import ULID

struct ServerMembersView: View {
    @EnvironmentObject var viewState: ViewState
    var serverId: String
    
    @State private var searchQuery: String = ""
    @State private var searchTextFieldState: PeptideTextFieldState = .default
    @State private var members: [Member] = []
    @State private var usersById: [String: User] = [:]
    @State private var displayedMembers: [Member] = []
    @State private var isLoading: Bool = true
    @State private var selectedMemberFilter: ServerMemberFilter = .all

    private func makeDisplayedMembers() -> [Member] {
        let trimmedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedSearch.lowercased()

        return members.filter { member in
            guard let user = user(for: member) else { return false }
            let matchesSearch = query.isEmpty || searchableText(member: member, user: user).contains(query)
            return matchesSearch && selectedMemberFilter.matches(member: member, user: user)
        }
        .sorted { lhs, rhs in
            let lhsUser = user(for: lhs)
            let rhsUser = user(for: rhs)
            return displayName(member: lhs, user: lhsUser).localizedCaseInsensitiveCompare(displayName(member: rhs, user: rhsUser)) == .orderedAscending
        }
    }

    private func refreshDisplayedMembers() {
        displayedMembers = makeDisplayedMembers()
    }

    private var memberFilterOptions: [ServerMemberFilter] {
        let roleFilters = hoistedRoles.map { roleId, role in
            ServerMemberFilter.role(id: roleId, name: role.name)
        }

        return [.all, .online, .offline] + roleFilters
    }

    private var hoistedRoles: [(String, Role)] {
        guard let roles = viewState.servers[serverId]?.roles else { return [] }

        return roles
            .filter { $0.value.hoist == true }
            .sorted { lhs, rhs in lhs.value.rank < rhs.value.rank }
            .map { ($0.key, $0.value) }
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
                    VStack {
                        Spacer(minLength: .zero)
                        PeptideLoading(
                            dotSize: .size6,
                            dotSpacing: .size6,
                            activeColor: .iconDefaultGray01
                        )
                        Spacer(minLength: .zero)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    let currentDisplayedMembers = displayedMembers
                    let displayedMembersCount = currentDisplayedMembers.count
                    let canAssignRoles = serverPermissions.contains(.assignRoles)

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

                        memberFilterMenu
                    }
                    .padding(.top, .padding24)
                    .padding(.horizontal, .size16)

                    if !currentDisplayedMembers.isEmpty
                    {
                    
                        HStack {
                            PeptideText(
                                text: "\(selectedMemberFilter.title) - \(displayedMembersCount)",
                                font: .peptideHeadline,
                                textColor: .textDefaultGray01
                            )
                            .padding(.horizontal, 32)
                            .padding(.top, .padding24)
                            .padding(.bottom, .padding8)
                            
                            Spacer()
                        }
                        
                    }else{
                        
                        let searchQueryIsEmpty = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        let hasActiveFilter = selectedMemberFilter != .all
                        
                        VStack(spacing: .spacing4){
                            
                            Image((searchQueryIsEmpty && !hasActiveFilter) ? .peptideDmEmpty : .peptideNotFound)
                                .resizable()
                                .frame(width: .size100, height: .size100)
                            
                            PeptideText(text: (searchQueryIsEmpty && !hasActiveFilter) ? "No Members Yet" : "Nothing Matches Your Search",
                                        font: .peptideHeadline,
                                        textColor: .textDefaultGray01)
                            .padding(.horizontal, .padding24)
                            
                            PeptideText(text: (searchQueryIsEmpty && !hasActiveFilter) ? "Add members to channel to see the filled list." : "Try a different member filter or search term.",
                                        font: .peptideSubhead,
                                        textColor: .textGray07,
                                        alignment: .center)
                            .padding(.horizontal, .padding24)

                        }
                        .padding(.horizontal, .padding16)
                        .padding(.bottom, .padding16)
                        .padding(.top, .padding24)
                        
                    }
                    
                    if !currentDisplayedMembers.isEmpty {
                     
                        LazyVStack(spacing: .spacing8) {
                            ForEach(Array(currentDisplayedMembers.enumerated()), id: \.element.id.user) { index, member in
                                if let user = user(for: member) {
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
                                                HStack(spacing: .spacing4) {
                                                    PeptideText(
                                                        text: user.display_name ?? user.username,
                                                        font: .peptideCallout,
                                                        textColor: .textDefaultGray01,
                                                        lineLimit: 1
                                                    )

                                                    if let badge = accountBadge(for: user) {
                                                        MessageBadge(text: badge.text, color: badge.color)
                                                    }
                                                }
                                                
                                                UserBadgesView(badges: user.getAllBadgesSortedForDisplay(), badgeSize: 12, spacing: 2)
                                                
                                                let isOnline = user.online == true
                                                PeptideText(
                                                    text: isOnline ? (user.status?.presence?.rawValue ?? Presence.Online.rawValue) : "Offline",
                                                    font: .peptideCaption1,
                                                    textColor: .textGray07
                                                )
                                            }
                                            
                                            Spacer(minLength: .zero)
                                            
                                            if canAssignRoles {
                                                
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
                                        if canAssignRoles {
                                            Button {
                                                viewState.path.append(NavigationDestination.member_permissions(serverId, member))
                                            } label: {
                                                Label("Manage Roles", systemImage: "person.badge.shield.checkmark")
                                            }
                                        }
                                    }
                                    
                                    if index != displayedMembersCount - 1 {
                                        PeptideDivider()
                                            .padding(.horizontal, .padding24)
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
        .onChange(of: searchQuery) { _, _ in
            refreshDisplayedMembers()
        }
        .onChange(of: selectedMemberFilter) { _, _ in
            refreshDisplayedMembers()
        }
    }

    private var memberFilterMenu: some View {
        Menu {
            ForEach(memberFilterOptions, id: \.id) { filter in
                Button {
                    selectedMemberFilter = filter
                } label: {
                    HStack {
                        PeptideText(text: filter.menuTitle)

                        if selectedMemberFilter == filter {
                            PeptideIcon(
                                iconName: .peptideDoneCircle,
                                size: .size20,
                                color: .iconYellow07
                            )
                        }
                    }
                }
            }
        } label: {
            PeptideIcon(iconName: .peptideSort)
                .frame(width: .size40, height: .size40)
                .background {
                    Circle().fill(Color.bgGray11)
                }
        }
    }
    
    private func fetchMembers() async {
        isLoading = true
        let response = await viewState.http.fetchServerMembers(target: serverId)
        
        switch response {
        case .success(let fetchedMembers):
            members = fetchedMembers.members
            usersById = Dictionary(uniqueKeysWithValues: fetchedMembers.users.map { ($0.id, $0) })
            viewState.serverMembersCounts[serverId] = fetchedMembers.members.count
            refreshDisplayedMembers()
        case .failure(_):
            viewState.showAlert(message: "Failed to load members", icon: .peptideInfo)
        }
        isLoading = false
    }

    private func user(for member: Member) -> User? {
        usersById[member.id.user] ?? viewState.users[member.id.user]
    }

    private func searchableText(member: Member, user: User) -> String {
        [
            user.username,
            user.display_name,
            member.nickname,
            user.usernameWithDiscriminator()
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func displayName(member: Member, user: User?) -> String {
        member.nickname ?? user?.display_name ?? user?.username ?? ""
    }

    private func accountBadge(for user: User) -> (text: String, color: Color)? {
        if user.bot != nil {
            return (String(localized: "BOT"), .bgPurple10)
        }

        if isNewAccount(user) {
            return (String(localized: "NEW"), .bgGreen07)
        }

        return nil
    }

    private func isNewAccount(_ user: User) -> Bool {
        guard user.id != String(repeating: "0", count: 26),
              let ulid = ULID(ulidString: user.id) else {
            return false
        }

        let accountAge = Calendar.current.dateComponents([.day], from: ulid.timestamp, to: Date()).day ?? Int.max
        return accountAge <= 14
    }

}

private enum ServerMemberFilter: Equatable {
    case all
    case online
    case offline
    case role(id: String, name: String)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .online:
            return "online"
        case .offline:
            return "offline"
        case .role(let id, _):
            return "role-\(id)"
        }
    }

    var title: String {
        switch self {
        case .all:
            return "Members"
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .role(_, let name):
            return name.capitalized
        }
    }

    var menuTitle: String {
        switch self {
        case .all:
            return "All"
        default:
            return title
        }
    }

    func matches(member: Member, user: User) -> Bool {
        switch self {
        case .all:
            return true
        case .online:
            return user.online == true && user.status?.presence != .Invisible
        case .offline:
            return user.online != true || user.status?.presence == .Invisible
        case .role(let id, _):
            return member.roles?.contains(id) == true
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    ServerMembersView(serverId: viewState.servers["0"]!.id)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
} 
