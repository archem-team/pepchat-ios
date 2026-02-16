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
            .onAppear {
                // Sync from persisted cache for instant UI before any async work
                membershipCache = viewState.discoverMembershipCache
                loadData()
            }
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
        // Check if we're on peptide.chat domain before loading
        let baseURL = viewState.baseURL ?? viewState.defaultBaseURL
        if !baseURL.contains("peptide.chat") {
            print("🌐 [DiscoverScrollView] Not on peptide.chat domain, skipping CSV loading")
            self.isLoading = false
            self.discoverItems = [] // Empty list for non-peptide domains
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            if let cached = ServerChatDataFetcher.shared.loadCache() {
                let items = cached.items
                    .map { DiscoverItem(id: $0.id,
                                        code: $0.inviteCode,
                                        title: $0.name,
                                        description: $0.description,
                                        isNew: $0.isNew,
                                        sortOrder: $0.sortOrder,
                                        disabled: $0.disabled,
                                        color: $0.color) }
                    .sorted(by: { $0.sortOrder < $1.sortOrder })
                DispatchQueue.main.async {
                    print("📥 Using cached discover: \(items.count) items, updated \(cached.timestamp)")
                    self.discoverItems = items
                }
            }
        }
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
                                             disabled: $0.disabled,
                                             color: $0.color)
                            }
                            .sorted(by: { $0.sortOrder < $1.sortOrder })
                        let cache = ServerChatCache(timestamp: Date(), items: fetchedServerChats)
                        ServerChatDataFetcher.shared.saveCache(cache)
                    
                    // Log all discovered servers and their invite codes
                    print("📋 [DiscoverScrollView] Displaying \(self.discoverItems.count) servers:")
                    for (index, item) in self.discoverItems.enumerated() {
                        print("  [\(index + 1)] \(item.title)")
                        print("      📎 Invite code: \(item.code)")
                        print("      📝 Description: \(item.description)")
                        print("      🆕 New: \(item.isNew)")
                        print("      🔒 Disabled: \(item.disabled)")
                        print("      🎨 Color: \(item.color ?? "none")")
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
        print("🔍 [checkAndCacheMembership] START - Item: \(item.title), Code: \(item.code)")
        print("   📊 Current checkingInvites: \(checkingInvites)")
        print("   📊 Current inviteCache: \(inviteCache)")
        print("   📊 Current membershipCache: \(membershipCache)")
        
        // Skip if already checking this invite
        let isAlreadyChecking = checkingInvites.contains(item.code)
        print("   🔎 Checking if already in progress: \(isAlreadyChecking)")
        if isAlreadyChecking {
            print("   ⏭️ [checkAndCacheMembership] SKIP - Already checking invite: \(item.code)")
            return
        }
        
        // Skip if we already have membership cached by server ID (from CSV item.id); seed inviteCache so UI uses fast path
        if viewState.discoverMembershipCache[item.id] != nil || membershipCache[item.id] != nil {
            let cached = viewState.discoverMembershipCache[item.id] ?? membershipCache[item.id]!
            await MainActor.run {
                inviteCache[item.code] = item.id
                membershipCache[item.id] = cached
            }
            print("   ⏭️ [checkAndCacheMembership] SKIP - Already cached for serverId (item.id): \(item.id)")
            return
        }
        
        // Skip if we already have cached membership info (from inviteCache + membershipCache)
        let cachedServerId = inviteCache[item.code]
        let cachedMembership = cachedServerId != nil ? membershipCache[cachedServerId!] : nil
        print("   🔎 Checking cache - ServerId: \(cachedServerId ?? "nil"), CachedMembership: \(cachedMembership?.description ?? "nil")")
        if let serverId = cachedServerId,
           membershipCache[serverId] != nil {
            print("   ⏭️ [checkAndCacheMembership] SKIP - Already cached for serverId: \(serverId)")
            return
        }
        
        await MainActor.run {
            checkingInvites.insert(item.code)
        }
        print("   ✅ Added to checkingInvites. Updated set: \(checkingInvites)")
        
        do {
            // Fetch invite information
            print("   🌐 [checkAndCacheMembership] Fetching invite for code: \(item.code)")
            let inviteResponse = try await viewState.http.fetchInvite(code: item.code).get()
            print("   ✅ [checkAndCacheMembership] Invite response received")
            print("   📦 InviteResponse type: \(type(of: inviteResponse))")
            
            let extractedServerId = inviteResponse.getServerID()
            print("   🔎 Extracted serverId from invite: \(extractedServerId ?? "nil")")
            
            if let serverId = extractedServerId {
                // Cache the invite code -> server ID mapping
                await MainActor.run {
                    inviteCache[item.code] = serverId
                }
                print("   💾 [checkAndCacheMembership] Cached invite code -> serverId mapping")
                print("   📊 Updated inviteCache[\(item.code)] = \(serverId)")
                print("   📊 Full inviteCache after update: \(inviteCache)")
                
                // Check if user is a member of this server
                let currentUser = viewState.currentUser
                print("   👤 [checkAndCacheMembership] Current user: \(currentUser?.id ?? "nil")")
                guard let currentUser = currentUser else {
                    print("   ⚠️ [checkAndCacheMembership] No current user found, setting membership to false")
                    await MainActor.run {
                        membershipCache[serverId] = false
                        checkingInvites.remove(item.code)
                    }
                    print("   💾 [checkAndCacheMembership] Updated membershipCache[\(serverId)] = false")
                    print("   📊 Updated membershipCache: \(membershipCache)")
                    print("   🗑️ Removed from checkingInvites. Updated set: \(checkingInvites)")
                    return
                }
                
                print("   🔍 [checkAndCacheMembership] Checking membership for userId: \(currentUser.id), serverId: \(serverId)")
                let member = viewState.getMember(byServerId: serverId, userId: currentUser.id)
                print("   📋 [checkAndCacheMembership] Member lookup result: \(member != nil ? "FOUND" : "NOT FOUND")")
                if let member = member {
                    print("   📋 Member details: id.server=\(member.id.server), id.user=\(member.id.user)")
                }
                let isMember = member != nil
                print("   ✅ [checkAndCacheMembership] isMember calculated: \(isMember)")
                
                await MainActor.run {
                    membershipCache[serverId] = isMember
                    viewState.updateMembershipCache(serverId: serverId, isMember: isMember, persist: false)
                    checkingInvites.remove(item.code)
                }
                print("   💾 [checkAndCacheMembership] Updated membershipCache[\(serverId)] = \(isMember)")
                print("   📊 Updated membershipCache: \(membershipCache)")
                print("   🗑️ Removed from checkingInvites. Updated set: \(checkingInvites)")
                
                print("✅ [DiscoverScrollView] \(item.title): Member = \(isMember)")
            } else {
                // Group invite or other type - not a server
                print("   ⚠️ [checkAndCacheMembership] No serverId found in invite response (group invite or other type)")
                await MainActor.run {
                    membershipCache[item.code] = false
                    checkingInvites.remove(item.code)
                }
                print("   💾 [checkAndCacheMembership] Updated membershipCache[\(item.code)] = false (using invite code as key)")
                print("   📊 Updated membershipCache: \(membershipCache)")
                print("   🗑️ Removed from checkingInvites. Updated set: \(checkingInvites)")
            }
        } catch {
            print("❌ [DiscoverScrollView] Failed to fetch invite \(item.code): \(error)")
            print("   🔄 [checkAndCacheMembership] Attempting fallback name-based matching")
            
            // Fallback to name-based matching
            let nameMembership = viewState.servers.values.contains { server in
                server.name.lowercased() == item.title.lowercased()
            }
            print("   🔍 [checkAndCacheMembership] Name-based match result: \(nameMembership)")
            print("   📋 Comparing: '\(item.title.lowercased())' with server names")
            let matchingServers = viewState.servers.values.filter { $0.name.lowercased() == item.title.lowercased() }
            print("   📋 Found \(matchingServers.count) matching servers: \(matchingServers.map { $0.name })")
            
            await MainActor.run {
                membershipCache[item.code] = nameMembership
                checkingInvites.remove(item.code)
            }
            print("   💾 [checkAndCacheMembership] Updated membershipCache[\(item.code)] = \(nameMembership) (fallback)")
            print("   📊 Updated membershipCache: \(membershipCache)")
            print("   🗑️ Removed from checkingInvites. Updated set: \(checkingInvites)")
        }
        
        print("🏁 [checkAndCacheMembership] END - Item: \(item.title), Code: \(item.code)")
    }
        
    // Enhanced membership check: ViewState servers first, then persisted cache, then local/API.
    // Uses inviteCache[item.code] ?? item.id so persisted cache is used on launch (inviteCache empty).
    private func checkIfUserIsMember(item: DiscoverItem) -> Bool {
        let serverId = inviteCache[item.code] ?? item.id
        // 1) Server in joined list => member (source of truth; stays in sync with web/Android via WebSocket)
        if viewState.servers[serverId] != nil {
            return true
        }
        // 2) Persisted membership cache (instant on launch; updated when user joins/leaves)
        if let cached = viewState.discoverMembershipCache[serverId] {
            return cached
        }
        // 3) Local in-memory cache (from this session)
        if let cached = membershipCache[serverId] {
            return cached
        }
        // 4) Members dictionary (may be unloaded for server)
        if let currentUser = viewState.currentUser {
            let isMember = viewState.getMember(byServerId: serverId, userId: currentUser.id) != nil
            DispatchQueue.main.async {
                self.membershipCache[serverId] = isMember
            }
            return isMember
        }
        // Fallbacks when serverId from item.id had no cache and no currentUser
        if let cached = membershipCache[item.code] {
            return cached
        }
        return viewState.servers.values.contains { server in
            server.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
            item.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
    let color: String?
}

struct ServerChatCache: Codable {
    let timestamp: Date
    let items: [ServerChat]
}

class ServerChatDataFetcher {
    static let shared = ServerChatDataFetcher()
    
    let csvUrl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRY41D-NgTE6bC3kTN3dRpisI-DoeHG8Eg7n31xb1CdydWjOLaphqYckkTiaG9oIQSWP92h3NE-7cpF/pub?gid=0&single=true&output=csv"
    
    private let cacheFileName = "discover_server_cache.json"
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
    }
    
    func loadCache() -> ServerChatCache? {
        if let data = try? Data(contentsOf: cacheURL) {
            return try? JSONDecoder().decode(ServerChatCache.self, from: data)
        }
        return nil
    }
    
    func saveCache(_ cache: ServerChatCache) {
        DispatchQueue.global(qos: .background).async {
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: self.cacheURL, options: .atomic)
            }
        }
    }
    
    func fetchData(completion: @escaping (Result<[ServerChat], Error>) -> Void) {
        print("🌐 [ServerChatDataFetcher] Fetching CSV from URL: \(csvUrl)")
        AF.request(csvUrl).responseString { response in
            switch response.result {
            case .success(let csvString):
                print("✅ [ServerChatDataFetcher] CSV downloaded successfully")
                do {
                    let csv = try CSV<Named>(string: csvString)
                    
                    let checkForIDHeader = csv.header.contains("id")
                    
                    if !checkForIDHeader {
                        print("⚠️ [ServerChatDataFetcher] 'id' header missing, using empty string key")
                    }
                    
                    print("📊 [ServerChatDataFetcher] Parsing CSV with \(csv.rows.count) rows")
                    print("📊 This is the CSV data: \(csv)")
                    
                    let serverChats = csv.rows.compactMap { row -> ServerChat? in
                        guard let id = row["id"] ?? row[""],
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
                            price2: row[""],
                            color: row["showcolor"]
                        )
                    }
                    let cache = ServerChatCache(timestamp: Date(), items: serverChats)
                    self.saveCache(cache)
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
