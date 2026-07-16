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
    @State private var hasLoadedData: Bool = false
    @State private var inviteCache: [String: String] = [:] // Cache for invite code -> server ID mapping
    @State private var membershipCache: [String: Bool] = [:] // Cache for server ID -> membership status
    @State private var checkingInvites: Set<String> = [] // Track ongoing invite checks
    @State private var searchQuery: String = "" // For search text
    @State private var searchTextFieldState : PeptideTextFieldState = .default
    @State private var selectedTab: DiscoverHomeTab = .home

    private var filteredDiscoverItems: [DiscoverItem] {
        let query = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return discoverItems
        }

        return discoverItems.filter { item in
            item.title.lowercased().contains(query) ||
            item.description.lowercased().contains(query)
        }
    }


    var body: some View {
        content
            .background(backgroundView)
            .onAppear {
                selectedTab = viewState.selectedDiscoverTab
                // Sync from persisted cache for instant UI before any async work
                membershipCache = viewState.discoverMembershipCache
                guard !hasLoadedData else { return }
                hasLoadedData = true
                loadData()
            }
            .onChange(of: viewState.discoverMembershipCache) { newValue in
                membershipCache = newValue
            }
            .onChange(of: viewState.selectedDiscoverTab) { newValue in
                withAnimation(.bouncy(duration: 0.35, extraBounce: 0.18)) {
                    selectedTab = newValue
                }
            }
            .onChange(of: selectedTab) { newValue in
                viewState.selectedDiscoverTab = newValue
            }
    }
    
    // MARK: - View Components
    
    private var content: some View {
        VStack(spacing: .zero){
            headerView
            PeptideDivider(backgrounColor: .borderGray11)

            TabView(selection: $selectedTab) {
                discoverList
                    .tag(DiscoverHomeTab.home)

                PromosView()
                    .tag(DiscoverHomeTab.promos)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.bouncy(duration: 0.35, extraBounce: 0.18), value: selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var headerView: some View {
            HStack {
                Button {
                    withAnimation(.bouncy(duration: 0.35, extraBounce: 0.18)) {
                        viewState.selectedDiscoverTab = .home
                        selectedTab = .home
                    }
                } label: {
                    headerTab(title: "Home", isSelected: selectedTab == .home)
                }
                
                
                Button {
                    withAnimation(.bouncy(duration: 0.35, extraBounce: 0.18)) {
                        viewState.selectedDiscoverTab = .promos
                        selectedTab = .promos
                    }
                } label: {
                    headerTab(title: "Promos", isSelected: selectedTab == .promos, showsNewBadge: true)
                }
                
                Spacer(minLength: .zero)
            }
            .padding(.horizontal, .padding16)
    }

    private func headerTab(title: String, isSelected: Bool, showsNewBadge: Bool = false) -> some View {
        VStack(spacing: .zero) {
            HStack(spacing: .spacing8) {
                PeptideText(text: title, font: .peptideHeadline)

                if showsNewBadge {
                    Text("NEW")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.textDefaultGray01)
                        .padding(.horizontal, .padding4)
                        .padding(.vertical, .padding4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.red)
                        )
                }
            }
                .padding(top: .padding24, bottom: .padding16)

            Capsule()
                .fill(isSelected ? Color.bgRed07 : Color.clear)
                .frame(height: .size4)
        }
        .padding(.horizontal, .size20)
        .contentShape(Rectangle())
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
//            bannerSection
            
            searchSection
            
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
    
    private var searchSection: some View {
        Section {
            
            PeptideTextField(text: $searchQuery,
                             state: $searchTextFieldState,
                             placeholder: "Search communities...",
                             icon: .peptideSearch,
                             cornerRadius: .radiusLarge,
                             height: .size40,
                             keyboardType: .default)
        }
        .listRowSeparator(.hidden)
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
                    if filteredDiscoverItems.isEmpty && !isLoading {
                        HStack {
                            Spacer(minLength: .zero)
                            PeptideText(
                                text: "No communities found.",
                                font: .peptideSubhead,
                                textColor: .textGray07
                            )
                            Spacer(minLength: .zero)
                        }
                        .padding(.vertical, .padding24)
                    } else {
                        ForEach(filteredDiscoverItems, id: \.id) { item in
                            discoverItemRow(for: item)
                        }
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
        .onAppear {
            Task {
                await checkAndCacheMembership(for: item)
            }
        }
    }
    
    private func handleItemClick(item: DiscoverItem, isMember: Bool) {
        if isMember {
            navigateToServer(item: item)
        } else if item.disabled == false, item.code.map({ !$0.isEmpty }) == true {
            navigateToInvite(item: item)
        }
    }
    
    private func navigateToServer(item: DiscoverItem) {
        // print("✅ [DiscoverScrollView] User is already a member of \(item.title), navigating to server")

        if viewState.servers[item.id] != nil {
            viewState.selectServer(withId: item.id)

            if !viewState.path.isEmpty {
                viewState.path.removeAll()
            }

            return
        }
        
        // First try to find server by cached invite code -> server ID mapping
        if let inviteCode = item.code, let serverId = inviteCache[inviteCode] {
            if viewState.servers[serverId] != nil {
                viewState.selectServer(withId: serverId)
                
                // Close the discover view and return to main screen
                if !viewState.path.isEmpty {
                    viewState.path.removeAll()
                }
                
                // print("📋 [DiscoverScrollView] Selected server \(server.name) via invite cache")
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
            
            // print("📋 [DiscoverScrollView] Selected server \(matchingServer.name) via name matching")
        } else {
            // Couldn't find server, show invite screen
            // print("⚠️ [DiscoverScrollView] Couldn't find matching server, showing invite screen")
            navigateToInvite(item: item)
        }
    }
    
    private func navigateToInvite(item: DiscoverItem) {
        guard item.disabled == false, let inviteCode = item.code, !inviteCode.isEmpty else {
            return
        }

        // print("🔗 [DiscoverScrollView] User is not a member of \(item.title), showing invite screen")
        viewState.path.append(NavigationDestination.invite(inviteCode))
    }
    
    private func loadData() {
        // Check if we're on peptide.chat domain before loading
        let baseURL = viewState.baseURL ?? viewState.defaultBaseURL
        if !baseURL.contains("peptide.chat") {
            // print("🌐 [DiscoverScrollView] Not on peptide.chat domain, skipping Discover server API loading")
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
                                        color: $0.color,
                                        logo: $0.logo) }
                DispatchQueue.main.async {
                    // print("📥 Using cached discover: \(items.count) items, updated \(cached.timestamp)")
                    self.discoverItems = items
                }
            }
        }
        self.isLoading = discoverItems.isEmpty
        // print("🌐 [DiscoverScrollView] Loading server list from public servers API...")
        
        ServerChatDataFetcher.shared.fetchData(http: viewState.http) { result in
                DispatchQueue.main.async {
                    
                    self.isLoading = false

                    
                    switch result {
                    case .success(let fetchedServerChats):
                    
                    // print("✅ [DiscoverScrollView] Successfully fetched \(fetchedServerChats.count) servers from public servers API")
                        
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
                                             color: $0.color,
                                             logo: $0.logo)
                            }
                        let cache = ServerChatCache(timestamp: Date(), items: fetchedServerChats)
                        ServerChatDataFetcher.shared.saveCache(cache)
                    
                    // Membership checks happen lazily per-row via .onAppear

                        
                    case .failure(let error):
                    // print("❌ [DiscoverScrollView] Failed to fetch servers: \(error.localizedDescription)")
                        debugPrint("error: \(error.localizedDescription)")
                    }
                }
            }
        }
    
    // MARK: - Lazy Membership Checking

    /// Checks and caches membership for a specific discover item (called per-row on appear)
    private func checkAndCacheMembership(for item: DiscoverItem) async {
        guard let inviteCode = item.code, !inviteCode.isEmpty else {
            return
        }

        // Skip if already checking this invite
        if checkingInvites.contains(inviteCode) {
            print("🔍 [Discover] SKIP (in-flight): \(item.title) [\(inviteCode)]")
            return
        }

        // Skip if ViewState already has membership cached by server ID (from API item.id); seed inviteCache so UI uses fast path
        if let cached = viewState.discoverMembershipCache[item.id] {
            print("🔍 [Discover] CACHE HIT: \(item.title) [\(inviteCode)]")
            await MainActor.run {
                inviteCache[inviteCode] = item.id
                membershipCache[item.id] = cached
            }
            return
        }

        // Skip if we already have cached membership info (from inviteCache + membershipCache)
        if let serverId = inviteCache[inviteCode],
           membershipCache[serverId] != nil {
            print("🔍 [Discover] CACHE HIT (invite): \(item.title) [\(inviteCode)]")
            return
        }

        await MainActor.run {
            checkingInvites.insert(inviteCode)
        }

        print("🌐 [Discover] FETCHING: \(item.title) [\(inviteCode)]")
        do {
            let inviteResponse = try await viewState.http.fetchInvite(code: inviteCode).get()
            let extractedServerId = inviteResponse.getServerID()

            if let serverId = extractedServerId {
                await MainActor.run {
                    inviteCache[inviteCode] = serverId
                }

                guard let currentUser = viewState.currentUser else {
                    await MainActor.run {
                        membershipCache[serverId] = false
                        checkingInvites.remove(inviteCode)
                    }
                    return
                }

                let isMember = viewState.getMember(byServerId: serverId, userId: currentUser.id) != nil

                await MainActor.run {
                    membershipCache[serverId] = isMember
                    viewState.updateMembershipCache(serverId: serverId, isMember: isMember, persist: false)
                    checkingInvites.remove(inviteCode)
                }
            } else {
                await MainActor.run {
                    membershipCache[inviteCode] = false
                    checkingInvites.remove(inviteCode)
                }
            }
        } catch {
            // print("❌ [DiscoverScrollView] Failed to fetch invite \(inviteCode): \(error)")

            // Fallback to name-based matching
            let nameMembership = viewState.servers.values.contains { server in
                server.name.lowercased() == item.title.lowercased()
            }

            await MainActor.run {
                membershipCache[inviteCode] = nameMembership
                checkingInvites.remove(inviteCode)
            }
        }
    }
        
    // Enhanced membership check: ViewState servers first, then persisted cache, then local/API.
    // Uses inviteCache[item.code] ?? item.id so persisted cache is used on launch (inviteCache empty).
    private func checkIfUserIsMember(item: DiscoverItem) -> Bool {
        let serverId = item.code.flatMap { inviteCache[$0] } ?? item.id
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
        if let inviteCode = item.code, let cached = membershipCache[inviteCode] {
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
    let inviteCode: String?
    let disabled: Bool
    let isNew: Bool
    let sortOrder: Int?
    let color: String?
    let logo: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case inviteCode
        case disabled
        case isNew = "new"
        case sortOrder = "sortorder"
        case color = "showcolor"
        case logo
    }
}

struct PublicServersResponse: Decodable {
    let success: Bool
    let data: [ServerChat]?
    let error: PublicServersError?
}

struct PublicServersError: Decodable, Error {
    let message: String?
}

struct ServerChatCache: Codable {
    let timestamp: Date
    let items: [ServerChat]
}

class ServerChatDataFetcher {
    static let shared = ServerChatDataFetcher()

    let csvFallbackUrl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRY41D-NgTE6bC3kTN3dRpisI-DoeHG8Eg7n31xb1CdydWjOLaphqYckkTiaG9oIQSWP92h3NE-7cpF/pub?gid=0&single=true&output=csv"
    
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
    
    func fetchData(http: HTTPClient, completion: @escaping (Result<[ServerChat], Error>) -> Void) {
        Task {
            let result: Result<PublicServersResponse, RevoltError> = await http.req(
                method: .get,
                route: "/directory/servers"
            )

            switch result {
            case .success(let publicServersResponse):
                guard publicServersResponse.success, let serverChats = publicServersResponse.data else {
                    self.fetchCSVFallback(completion: completion)
                    return
                }

                guard !serverChats.isEmpty else {
                    self.fetchCSVFallback(completion: completion)
                    return
                }

                let cache = ServerChatCache(timestamp: Date(), items: serverChats)
                self.saveCache(cache)
                completion(.success(serverChats))

            case .failure(let error):
                debugPrint("directory servers fetch failed: \(error)")
                if case .HTTPError(_, 401) = error {
                    completion(.failure(PublicServersError(message: "Sign in again to load Discover servers.")))
                    return
                }
                self.fetchCSVFallback(completion: completion)
            }
        }
    }

    private func fetchCSVFallback(completion: @escaping (Result<[ServerChat], Error>) -> Void) {
        // print("🌐 [ServerChatDataFetcher] Falling back to CSV URL: \(csvFallbackUrl)")
        AF.request(csvFallbackUrl).responseString { response in
            switch response.result {
            case .success(let csvString):
                do {
                    let csv = try CSV<Named>(string: csvString)
                    let serverChats = csv.rows.compactMap { row -> ServerChat? in
                        guard let id = row["id"] ?? row[""],
                              let name = row["name"],
                              let description = row["description"],
                              let disabled = row["disabled"].map({ $0.lowercased() == "true" }),
                              let isNew = row["new"].map({ $0.lowercased() == "true" }) else {
                            return nil
                        }

                        return ServerChat(
                            id: id,
                            name: name,
                            description: description,
                            inviteCode: row["inviteCode"],
                            disabled: disabled,
                            isNew: isNew,
                            sortOrder: row["sortorder"].flatMap(Int.init),
                            color: row["showcolor"],
                            logo: nil
                        )
                    }
                    .sorted { ($0.sortOrder ?? Int.max) < ($1.sortOrder ?? Int.max) }

                    guard !serverChats.isEmpty else {
                        completion(.failure(PublicServersError(message: "CSV fallback returned no discover servers")))
                        return
                    }

                    let cache = ServerChatCache(timestamp: Date(), items: serverChats)
                    self.saveCache(cache)
                    completion(.success(serverChats))
                } catch {
                    completion(.failure(error))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}





//
//#Preview {
//    DiscoverScrollView()
//        .applyPreviewModifiers(withState: ViewState.preview())
//        .preferredColorScheme(.dark)
//}
