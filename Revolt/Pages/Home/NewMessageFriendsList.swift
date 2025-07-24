import SwiftUI
import Types

struct NewMessageFriendsList: View {
    @EnvironmentObject var viewState: ViewState
    @State var searchQuery: String = ""
    @State var userSort: UserSort = .alphabetical
    @State private var searchTextFieldState: PeptideTextFieldState = .default
    
    var groupedFriends: [String: [User]] {
        let friends = viewState.users.values
            .filter { user in
                user.relationship == .Friend &&
                (searchQuery.isEmpty ||
                 user.username.lowercased().contains(searchQuery.lowercased()) ||
                 (user.display_name?.lowercased().contains(searchQuery.lowercased()) ?? false))
            }
        
        return Dictionary(grouping: friends) { String($0.username.prefix(1)).uppercased() }
            .sorted { $0.key < $1.key }
            .reduce(into: [:]) { initialResult, updatedResult in initialResult[updatedResult.key] = updatedResult.value }
    }
    
    
    var body: some View {
        PeptideTemplateView(toolbarConfig: .init(
            isVisible: true,
            title: "New Message",
            showBackButton: true,
            backButtonIcon: .peptideCloseLiner,
            showBottomLine: true
        )) { _, _ in
            VStack(spacing: .zero) {
                
                let friendsListIsEmpty = groupedFriends.isEmpty && searchQuery.isEmpty
                
                if(!friendsListIsEmpty){
                
                    VStack(spacing: .spacing4) {
                        
                        Button{
                            self.viewState.path.append(NavigationDestination.create_group_name)
                        } label: {
                            PeptideActionButton(icon: .peptideNewGroup,
                                              title: "New Group")
                        }
                        
                        PeptideDivider()
                            .padding(.leading, .padding48)
                        
                        Button{
                            self.viewState.path.append(NavigationDestination.add_friend)
                        } label: {
                            PeptideActionButton(icon: .peptideNewUser,
                                              title: "Add a Friend")
                        }
                    }
                    .backgroundGray11(verticalPadding: .size4)
                    .padding(.horizontal, .padding16)
                    .padding(.top, .padding24)
                    
                }
                
                
                if !(groupedFriends.isEmpty && searchQuery.isEmpty) {
                    HStack(spacing: .spacing8) {
                        PeptideTextField(
                            text: $searchQuery,
                            state: $searchTextFieldState,
                            placeholder: "Search in the friends list",
                            icon: .peptideSearch,
                            cornerRadius: .radiusLarge,
                            height: .size40,
                            keyboardType: .default
                        )
                    }
                    .padding(.vertical, .padding32)
                    .padding(.horizontal, .padding16)
                }
                
                if groupedFriends.isEmpty, searchQuery.isEmpty {
                    // Empty State
                    VStack(spacing: .spacing8) {
                        Spacer()
                        
                        Image(.peptideDmEmpty)
                            .resizable()
                            .frame(width: 200, height: 200)
                        
                        PeptideText(
                            text: "No Connections Yet",
                            font: .peptideHeadline,
                            textColor: .textDefaultGray01
                        )
                        .padding(.top, .padding4)
                        
                        PeptideText(text: "Find friends to message or build a group to get started.",
                                    font: .peptideSubhead,
                                    textColor: .textGray07,
                                    alignment: .center)
                        .padding(.horizontal, .padding24)
                        
                        Spacer(minLength: .zero)
                        
                        PeptideButton(
                            title: "Add Friends",
                            bgColor: .bgYellow07,
                            contentColor: .textInversePurple13
                        ) {
                            viewState.path.append(NavigationDestination.add_friend)
                        }
                        .padding(.bottom, .size24)
                        
                    }
                    .padding()
                } else {
                    // Friends List
                    ScrollView {
                        LazyVStack(spacing: .zero) {
                            ForEach(groupedFriends.keys.sorted(), id: \.self) { key in
                                Section(header: HStack {
                                    PeptideText(
                                        text: key,
                                        font: .peptideHeadline,
                                        textColor: .textDefaultGray01
                                    )
                                    Spacer()
                                }
                                .padding(.horizontal, .padding8)
                                .padding(.vertical, .padding16)) {
                                    ForEach(groupedFriends[key] ?? []) { user in
                                        Button {
                                            Task {
                                                await viewState.openDm(with: user.id)
                                            }
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
                                                
                                                Spacer()
                                                
                                                PeptideIcon(iconName: .peptideArrowRight,
                                                            size: .size24,
                                                            color: .iconGray07)
                                            }
                                            .padding(.padding8)
                                            .background(Color.bgGray11)
                                            .cornerRadius(.radius8)
                                        }
                                        .padding(.bottom, .padding8)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, .padding16)
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @StateObject var viewState: ViewState = .preview()
    
    NewMessageFriendsList()
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
} 

