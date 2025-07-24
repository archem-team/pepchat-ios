//
//  DiscoverScrollView.swift
//  Revolt
//
//

import Foundation
import SwiftUI
import Alamofire
import SwiftCSV

struct DiscoverScrollView: View {
    
    @EnvironmentObject private var viewState : ViewState
    
    
    @State private var discoverItems: [DiscoverItem] = []
    @State private var isLoading : Bool = false
    @State private var inviteCache: [String: String] = [:] // Cache for invite code -> server ID mapping
    @State private var membershipCache: [String: Bool] = [:] // Cache for server ID -> membership status
    @State private var checkingInvites: Set<String> = [] // Track ongoing invite checks
    
    
    var body: some View {
        content
            .background(backgroundView)
            .onAppear(perform: loadData)
    }
    
    // MARK: - View Components
    
    private var content: some View {
        VStack(spacing: .zero){
            headerView
            PeptideDivider(backgrounColor: .borderGray11)
            discoverList
            Spacer()
        }
    }
    
    private var headerView: some View {
            HStack {
                PeptideText(text: "Discover Servers", font: .peptideHeadline)
                    .padding(top: .padding24, bottom: .padding16)
                
                Spacer(minLength: .zero)
            }
            .padding(.horizontal, .padding16)
    }
    
    private var backgroundView: some View {
        Color.bgGray12
            .clipShape(
                .rect(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
            )
    }
    
    private var discoverList: some View {
        List {
            bannerSection
            
            if isLoading {
                loadingSection
            }
            
            serversSection
        }
        .environment(\.defaultMinListRowHeight, 0)
        .frame(maxWidth: .infinity)
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .background(Color.bgGray12)
        .clipped()
        .scrollBounceBehavior(.basedOnSize)
    }
    
    private var bannerSection: some View {
                Section{
                    HStack(spacing: .zero){
                        Spacer()
                        
                        VStack(spacing: .zero){
                            Image(.peptideDiscover)
                                .padding(.top, .padding24)
                            
                            PeptideText(text: "Discover New Communities",
                                        font: .peptideHeadline,
                                        textColor: .textDefaultGray01)
                            .padding(.vertical, .padding4)
                            
                            PeptideText(text: "Join trending and official groups to be part of something big.",
                                        font: .peptideSubhead,
                                        textColor: .textGray07)
                            .padding(.bottom, .padding24)
                        }
                        .padding(.horizontal, .padding16)
                        
                        Spacer()
                    }
                }
                .listRowInsets(.init())
                .listRowSeparator(.hidden)
                .listRowSpacing(0)
                .listRowBackground(Color.clear)
    }
                
    private var loadingSection: some View {
                    Section {
                        HStack {
                            Spacer(minLength: .zero)
                            ProgressView()
                            Spacer(minLength: .zero)
                        }
                        .padding(.size40)
                    }
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowSpacing(0)
                    .listRowBackground(Color.clear)
                }
                
    private var serversSection: some View {
                Section {
                    ForEach(discoverItems, id: \.id) { item in
                discoverItemRow(for: item)
                    }
                }
                .listRowInsets(.init())
                .listRowSeparator(.hidden)
                .listRowSpacing(0)
                .listRowBackground(Color.clear)
    }
    
    private func discoverItemRow(for item: DiscoverItem) -> some View {
        let isMember = checkIfUserIsMember(item: item)
        
        return DiscoverItemView(
            discoverItem: item,
            onClick: {
                handleItemClick(item: item, isMember: isMember)
            },
            isMember: isMember
        )
        .padding(.horizontal, .padding16)
        .padding(.bottom, .padding8)
    }
    
    private func handleItemClick(item: DiscoverItem, isMember: Bool) {
        if isMember {
            navigateToServer(item: item)
        } else {
            navigateToInvite(item: item)
        }
    }
    
    private func navigateToServer(item: DiscoverItem) {
        print("✅ [DiscoverScrollView] User is already a member of \(item.title), navigating to server")
        
        // First try to find server by cached invite code -> server ID mapping
        if let serverId = inviteCache[item.code] {
            if let server = viewState.servers[serverId] {
                viewState.selectServer(withId: serverId)
                
                // Close the discover view and return to main screen
                if !viewState.path.isEmpty {
                    viewState.path.removeAll()
                }
                
                print("📋 [DiscoverScrollView] Selected server \(server.name) via invite cache")
                return
            }
        }
        
        // Fallback: Find the matching server by name (legacy method)
        if let matchingServer = viewState.servers.values.first(where: { 
            $0.name.lowercased() == item.title.lowercased() 
        }) {
            viewState.selectServer(withId: matchingServer.id)
            
            // Close the discover view and return to main screen
            if !viewState.path.isEmpty {
                viewState.path.removeAll()
            }
            
            print("📋 [DiscoverScrollView] Selected server \(matchingServer.name) via name matching")
        } else {
            // Couldn't find server, show invite screen
            print("⚠️ [DiscoverScrollView] Couldn't find matching server, showing invite screen")
            viewState.path.append(NavigationDestination.invite(item.code))
        }
    }
    
    private func navigateToInvite(item: DiscoverItem) {
        print("🔗 [DiscoverScrollView] User is not a member of \(item.title), showing invite screen")
        viewState.path.append(NavigationDestination.invite(item.code))
    }
    
    private func loadData() {
            self.isLoading = true
        print("🌐 [DiscoverScrollView] Loading server list from CSV...")
            ServerChatDataFetcher.shared.fetchData { result in
                DispatchQueue.main.async {
                    
                    self.isLoading = false

                    
                    switch result {
                    case .success(let fetchedServerChats):
                    
                    print("✅ [DiscoverScrollView] Successfully fetched \(fetchedServerChats.count) servers from CSV")
                        
                        self.discoverItems = fetchedServerChats
                            //.filter { !$0.disabled }
                            .map{
                                DiscoverItem(id: $0.id,
                                             code: $0.inviteCode,
                                             title: $0.name,
                                             description: $0.description,
                                             isNew: $0.isNew,
                                             sortOrder: $0.sortOrder,
                                             disabled: $0.disabled)
                            }
                            .sorted(by: { $0.sortOrder < $1.sortOrder })
                    
                    // Log all discovered servers and their invite codes
                    print("📋 [DiscoverScrollView] Displaying \(self.discoverItems.count) servers:")
                    for (index, item) in self.discoverItems.enumerated() {
                        print("  [\(index + 1)] \(item.title)")
                        print("      📎 Invite code: \(item.code)")
                        print("      📝 Description: \(item.description)")
                        print("      🆕 New: \(item.isNew)")
                        print("      🔒 Disabled: \(item.disabled)")
                    }
                    
                    // Check membership for all items asynchronously
                    Task {
                        await self.checkMembershipForAllItems()
                    }

                        
                    case .failure(let error):
                    print("❌ [DiscoverScrollView] Failed to fetch servers: \(error.localizedDescription)")
                        debugPrint("error: \(error.localizedDescription)")
                    }
                }
            }
        }
    
    // MARK: - Enhanced Membership Checking
    
    /// Checks membership for all discover items asynchronously
    private func checkMembershipForAllItems() async {
        print("🔍 [DiscoverScrollView] Starting membership check for \(discoverItems.count) servers")
        
        // Check membership for each item
        for item in discoverItems {
            await checkAndCacheMembership(for: item)
        }
        
        // Trigger UI update
        await MainActor.run {
            // Force a UI refresh by updating the state
            self.discoverItems = self.discoverItems
        }
        
        print("✅ [DiscoverScrollView] Completed membership check for all servers")
    }
    
    /// Checks and caches membership for a specific discover item
    private func checkAndCacheMembership(for item: DiscoverItem) async {
        // Skip if already checking this invite
        if checkingInvites.contains(item.code) {
            return
        }
        
        // Skip if we already have cached membership info
        if let serverId = inviteCache[item.code],
           membershipCache[serverId] != nil {
            return
        }
        
        await MainActor.run {
            checkingInvites.insert(item.code)
        }
        
        do {
            // Fetch invite information
            let inviteResponse = try await viewState.http.fetchInvite(code: item.code).get()
            
            if let serverId = inviteResponse.getServerID() {
                // Cache the invite code -> server ID mapping
                await MainActor.run {
                    inviteCache[item.code] = serverId
                }
                
                // Check if user is a member of this server
                guard let currentUser = viewState.currentUser else {
                    await MainActor.run {
                        membershipCache[serverId] = false
                        checkingInvites.remove(item.code)
                    }
                    return
                }
                
                let isMember = viewState.getMember(byServerId: serverId, userId: currentUser.id) != nil
                
                await MainActor.run {
                    membershipCache[serverId] = isMember
                    checkingInvites.remove(item.code)
                }
                
                print("✅ [DiscoverScrollView] \(item.title): Member = \(isMember)")
            } else {
                // Group invite or other type - not a server
                await MainActor.run {
                    membershipCache[item.code] = false
                    checkingInvites.remove(item.code)
                }
            }
        } catch {
            print("❌ [DiscoverScrollView] Failed to fetch invite \(item.code): \(error)")
            
            // Fallback to name-based matching
            let nameMembership = viewState.servers.values.contains { server in
                server.name.lowercased() == item.title.lowercased()
            }
            
            await MainActor.run {
                membershipCache[item.code] = nameMembership
                checkingInvites.remove(item.code)
            }
        }
    }
        
    // Enhanced membership check with caching and API verification
    private func checkIfUserIsMember(item: DiscoverItem) -> Bool {
        // First check if we have cached invite -> server ID mapping
        if let serverId = inviteCache[item.code] {
            // Check cached membership status
            if let cachedMembership = membershipCache[serverId] {
                return cachedMembership
            }
            
            // Check membership using the server ID
            guard let currentUser = viewState.currentUser else {
                return false
            }
            
            let isMember = viewState.getMember(byServerId: serverId, userId: currentUser.id) != nil
            
            // Cache the result
            membershipCache[serverId] = isMember
            return isMember
        }
        
        // Check if we have a cached result for this invite code directly
        if let cachedMembership = membershipCache[item.code] {
            return cachedMembership
        }
        
        // Fallback to name-based matching (legacy method)
        let nameMembership = viewState.servers.values.contains { server in
            server.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == 
            item.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nameMembership
    }
}


struct ServerChat: Codable {
    let id: String
    let name: String
    let description: String
    let inviteCode: String
    let disabled: Bool
    let isNew: Bool
    let sortOrder: Int
    let chronological: Int
    let dateAdded: String?
    let price1: String?
    let price2: String?
}


class ServerChatDataFetcher {
    static let shared = ServerChatDataFetcher()
    
    let csvUrl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRY41D-NgTE6bC3kTN3dRpisI-DoeHG8Eg7n31xb1CdydWjOLaphqYckkTiaG9oIQSWP92h3NE-7cpF/pub?gid=0&single=true&output=csv"
    
    func fetchData(completion: @escaping (Result<[ServerChat], Error>) -> Void) {
        print("🌐 [ServerChatDataFetcher] Fetching CSV from URL: \(csvUrl)")
        AF.request(csvUrl).responseString { response in
            switch response.result {
            case .success(let csvString):
                print("✅ [ServerChatDataFetcher] CSV downloaded successfully")
                do {
                    let csv = try CSV<Named>(string: csvString)
                    
                    print("📊 [ServerChatDataFetcher] Parsing CSV with \(csv.rows.count) rows")
                    
                    let serverChats = csv.rows.compactMap { row -> ServerChat? in
                        guard let id = row["id"],
                              let name = row["name"],
                              let description = row["description"],
                              let inviteCode = row["inviteCode"],
                              let disabled = row["disabled"].map({ $0.lowercased() == "true" }),
                              let isNew = row["new"].map({ $0.lowercased() == "true" }),
                              let sortOrder = row["sortorder"].flatMap(Int.init),
                              let chronological = row["chronological"].flatMap(Int.init) else { return nil }
                        
                        return ServerChat(
                            id: id,
                            name: name,
                            description: description,
                            inviteCode: inviteCode,
                            disabled: disabled,
                            isNew: isNew,
                            sortOrder: sortOrder,
                            chronological: chronological,
                            dateAdded: row["dateAdded"],
                            price1: row[""],
                            price2: row[""]
                        )
                    }
                    print("📋 [ServerChatDataFetcher] Parsed \(serverChats.count) valid servers from CSV")
                    completion(.success(serverChats))
                } catch {
                    print("❌ [ServerChatDataFetcher] Failed to parse CSV: \(error.localizedDescription)")
                    completion(.failure(error))
                }
                
            case .failure(let error):
                print("❌ [ServerChatDataFetcher] Failed to download CSV: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
}






#Preview {
    DiscoverScrollView()
        .applyPreviewModifiers(withState: ViewState.preview())
        .preferredColorScheme(.dark)
}
