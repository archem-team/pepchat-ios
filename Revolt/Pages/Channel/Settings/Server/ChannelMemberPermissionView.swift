import SwiftUI
import Types

struct ChannelMemberPermissionView: View {
    @EnvironmentObject var viewState: ViewState
    var serverId: String
    var member: Member
    
    @State private var roles: [Role] = []
    @State private var isLoading: Bool = false
    @State private var showSaveButton: Bool = false
    
    @State private var checkedRoles: Set<String> = Set()
    @State private var saveBtnState : ComponentState = .default
    
    private var user: User? {
        viewState.users[member.id.user]
    }
    
    private var saveBtnView : AnyView {
        AnyView(
            
            Button {
                updateRoles()
            } label: {
                
                if saveBtnState == .loading {
                    
                    ProgressView()
                    
                } else {
                    
                    PeptideText(text: "Save",
                                font: .peptideButton,
                                textColor: .textYellow07,
                                alignment: .center)
                    
                }
            }
                .opacity(showSaveButton ? 1 : 0)
                .disabled(!showSaveButton)
            
            
        )
    }
    
    func updateRoles(){
        
        Task{
            
            self.saveBtnState = .loading
            
            let response  = await self.viewState.http.editMember(server: self.serverId, memberId: member.id.user, edits: .init(roles: Array(self.checkedRoles)))
            
            switch response{
            case .success(_):
                self.viewState.path.removeLast()
            case .failure(_):
                self.viewState.showAlert(message: "Something went wronge!", icon: .peptideInfo)
            }
            
            self.saveBtnState = .default
        }
        
    }
    
    var body: some View {
        
        let server  = self.viewState.servers[serverId]!
        
        PeptideTemplateView(toolbarConfig: ToolbarConfig(
            isVisible: true,
            title: "Edit \(member.nickname ?? "")",
            showBackButton: true,
            backButtonIcon: .peptideCloseLiner,
            customToolbarView: saveBtnView,
            showBottomLine: true
        )) { _, _ in
            VStack(alignment: .leading, spacing: .zero) {
                if isLoading {
                    PeptideLoading()
                } else {
                    // Member Info Header
                    if let user = user {
                        HStack(spacing: .spacing12) {
                            Avatar(
                                user: user,
                                member: member,
                                width: .size32,
                                height: .size32,
                                withPresence: false
                            )
                            
                            PeptideText(
                                text: user.display_name ?? user.username,
                                font: .peptideButton,
                                textColor: .textDefaultGray01
                            )
                            
                            Spacer(minLength: .zero)
                        }
                        .padding(.all, .padding12)
                        .background(
                            RoundedRectangle(cornerRadius: .radiusXSmall)
                                .fill(Color.bgGray12)
                        )
                        .padding(.vertical, 24)
                        .padding(.horizontal, .padding16)
                    }
                    
                    HStack{
                        
                        Spacer(minLength: .zero)
                        
                        PeptideText(
                            text: "Assign roles to define this member's permissions and responsibilities.",
                            font: .peptideFootnote,
                            textColor: .textGray06,
                            alignment: .center
                        )
                        .padding(.horizontal, .padding16)
                        .padding(.bottom, .padding24)
                        
                        Spacer(minLength: .zero)
                        
                    }
                    
                    if server.roles?.isEmpty == false {
                        
                        let roleCount = server.roles?.count ?? 0
                        
                        PeptideText(textVerbatim: "Role - \(roleCount)",
                                    font: .peptideHeadline)
                        .padding(top: .padding24, bottom: .padding8)
                        .padding(.horizontal, .size32)
                        
                        
                        LazyVStack(alignment: .leading, spacing: .spacing4) {
                            let sortedRoles = Array(server.roles ?? [:]).sorted(by: { a, b in a.value.rank < b.value.rank })
                            
                            let lastRoleId = sortedRoles.last?.key
                            
                            
                            ForEach(sortedRoles, id: \.key) { pair in
                                PeptideActionButton(
                                    icon: .peptideShieldUserRole,
                                    iconColor: Color(hex: pair.value.colour ?? "#FFFFFD") ?? .iconDefaultGray01,
                                    iconSize: .size32,
                                    title: pair.value.name,
                                    hasArrow: false,
                                    hasToggle: true,
                                    toggleChecked: checkedRoles.contains(pair.key)
                                ) { checked in
                                    self.showSaveButton = true
                                    if checked {
                                        checkedRoles.insert(pair.key)
                                    } else {
                                        checkedRoles.remove(pair.key)
                                    }
                                }
                                
                                if pair.key != lastRoleId {
                                    PeptideDivider()
                                        .padding(.leading, .padding48)
                                }
                            }
                        }
                        .backgroundGray11(verticalPadding: .padding4)
                        .padding(.bottom, .padding24)
                        .padding(.horizontal, .size16)
                        
                    }
                    
                    // Roles List
//                    ScrollView {
//                        LazyVStack(spacing: .spacing4) {
//                            ForEach((member.roles ?? []), id: \.id) { role in
//                                HStack(spacing: .spacing12) {
//                                    // Role Icon
//                                    PeptideIcon(
//                                        iconName: .peptideRoleIdCard,
//                                        size: .size24,
//                                        color: role.colour.map { Color(hex: $0) } ?? .iconGray07
//                                    )
//                                    
//                                    // Role Name
//                                    PeptideText(
//                                        text: role.name,
//                                        font: .peptideCallout,
//                                        textColor: .textDefaultGray01
//                                    )
//                                    
//                                    Spacer()
//                                    
//                                    // Toggle
//                                    Toggle("", isOn: toggleBinding(for: role.id))
//                                        .toggleStyle(PeptideCircleCheckToggleStyle())
//                                }
//                                .padding(.horizontal, .padding16)
//                                .padding(.vertical, .padding12)
//                                .background(Color.bgGray11)
//                                .cornerRadius(.radius8)
//                            }
//                        }
//                        .padding(.horizontal, .padding16)
//                    }
              
                    Spacer()
                    
                }
            }
        }
        .task {
            // Initialize checkedRoles with member's current roles
            if let memberRoles = member.roles {
                checkedRoles = Set(memberRoles)
            }
        }
    }
    
    private func fetchRoles() async {
//        isLoading = true
//        // Fetch roles from your API
//        // This is a placeholder - implement actual role fetching
//        let response = await viewState.http.fetchServerRoles(server: serverId)
//        switch response {
//        case .success(let fetchedRoles):
//            roles = fetchedRoles
//        case .failure(_):
//            viewState.showAlert(message: "Failed to load roles", icon: .peptideInfo)
//        }
//        isLoading = false
    }
    
//    private func toggleBinding(for roleId: String) -> Binding<Bool> {
//        Binding(
//            get: { member.roles?.contains(roleId) ?? false },
//            set: { newValue in
//                Task {
//                    if newValue {
//                        // Add role
//                        let _ = try? await viewState.http.addMemberRole(
//                            server: serverId,
//                            user: member.id.user,
//                            role: roleId
//                        ).get()
//                    } else {
//                        // Remove role
//                        let _ = try? await viewState.http.removeMemberRole(
//                            server: serverId,
//                            user: member.id.user,
//                            role: roleId
//                        ).get()
//                    }
//                }
//            }
//        )
//    }
}

//#Preview {
//    @Previewable @StateObject var viewState: ViewState = .preview()
//    let member = Member(id: .init(server: "0", user: "1"))
    
//    ChannelMemberPermissionView(serverId: "0", member: member)
//        .applyPreviewModifiers(withState: viewState)
//        .preferredColorScheme(.dark)
//} 

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    ChannelMemberPermissionView(serverId: viewState.servers["0"]!.id, member: Member(id: MemberId(server: "0", user: "0"), joined_at: ""))
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
