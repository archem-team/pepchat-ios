//
//  PromosView.swift
//  Revolt
//
//  Created by Akshat Srivastava on 24/06/26.
//

import SwiftUI
import Kingfisher

struct PromosView: View {
    @EnvironmentObject private var viewState: ViewState

    @StateObject private var promosManager = PromosManager()
    @State private var searchQuery: String = "" // For search text
    @State private var searchTextFieldState : PeptideTextFieldState = .default
    @State private var selectedPromoFilter: PromoSort = .Newest

    private var filteredPromos: [Promo] {
        let query = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return promosManager.promos
        }

        return promosManager.promos.filter { promo in
            promo.vendor.name.lowercased().contains(query) ||
            promo.title?.lowercased().contains(query) == true ||
            promo.warehouse?.lowercased().contains(query) == true ||
            promo.items.contains { $0.product.lowercased().contains(query) }
        }
    }

    private var canSubmitPromo: Bool {
        guard let currentUserId = viewState.currentUser?.id else { return false }
        return viewState.servers.values.contains { $0.owner == currentUserId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: .spacing12) {
                promoHeaderSection

                if promosManager.isLoading {
                    ProgressView()
                        .padding(.padding40)
                } else if let errorMessage = promosManager.errorMessage {
                    emptyState(message: errorMessage)
                } else if filteredPromos.isEmpty {
                    emptyState(
                        message: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "No live promos right now."
                        : "No promos found."
                    )
                } else {
                    PromoMasonryGrid(promos: filteredPromos) { promo in
                        openCommunity(for: promo)
                    }
                }
            }
            .padding(.padding16)
        }
        .background(Color.bgGray12)
        .onAppear {
            promosManager.fetchPromos(sort: selectedPromoFilter, http: viewState.http)
        }
        .onChange(of: selectedPromoFilter) { newValue in
            promosManager.fetchPromos(sort: newValue, http: viewState.http)
        }
    }

    var promoHeaderSection: some View {
        HStack {
            searchSection
            
            filter
            
//            if canSubmitPromo {
//                submitButton
//            }
        }
    }
    
    var searchSection: some View {
        Section {
            
            PeptideTextField(text: $searchQuery,
                             state: $searchTextFieldState,
                             placeholder: "Search promos...",
                             icon: .peptideSearch,
                             cornerRadius: .radiusLarge,
                             height: .size40,
                             keyboardType: .default)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    var filter: some View {
        Menu {
            Button{
                self.selectedPromoFilter = .Newest
            } label: {
                HStack{
                    PeptideText(text: "Newest")
                    
                    if(self.selectedPromoFilter == .Newest){
                        PeptideIcon(iconName: .peptideDoneCircle,
                                    size: .size20,
                                    color: .iconYellow07)
                    }
                    
                }
            }
            Button{
                self.selectedPromoFilter = .EndingSoon
            } label: {
                
                HStack{
                    PeptideText(text: "Ending Soon")
                    
                    if(self.selectedPromoFilter == .EndingSoon){
                        PeptideIcon(iconName: .peptideDoneCircle,
                                    size: .size20,
                                    color: .iconYellow07)
                    }
                    
                }
            }
            
        } label: {
            PeptideIcon(iconName: .peptideSort)
                .frame(width: .size40, height: .size40)
                .background{
                    Circle().fill(Color.bgGray11)
                }
        }
    }
    
    var submitButton: some View {
        PeptideButton(title: "Submit", isFullWidth: false) {
            viewState.path.append(.promos_submit)
        }
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: .spacing8) {
            PeptideText(
                text: message,
                font: .peptideSubhead,
                textColor: .textGray07,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.padding32)
    }

    private func openCommunity(for promo: Promo) {
        if let serverId = promo.vendor.serverId,
           viewState.servers[serverId] != nil {
            viewState.selectServer(withId: serverId)

            if !viewState.path.isEmpty {
                viewState.path.removeAll()
            }

            return
        }

        if let matchingServer = viewState.servers.values.first(where: {
            $0.name.lowercased() == promo.vendor.name.lowercased()
        }) {
            viewState.selectServer(withId: matchingServer.id)

            if !viewState.path.isEmpty {
                viewState.path.removeAll()
            }

            return
        }

        guard let inviteCode = inviteCode(from: promo.vendor.inviteLink) else {
            return
        }

        viewState.path.append(NavigationDestination.invite(inviteCode))
    }

    private func inviteCode(from link: String?) -> String? {
        guard let link, !link.isEmpty else { return nil }

        if let range = link.range(of: "/invite/") {
            let suffix = link[range.upperBound...]
            return suffix
                .split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
                .first
                .map(String.init)
        }

        return link
            .split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
            .last
            .map(String.init)
    }
}

enum PromoSort: String {
    case Newest
    case EndingSoon

    var apiValue: String {
        switch self {
        case .Newest:
            return "newest"
        case .EndingSoon:
            return "endingSoon"
        }
    }
}

private struct PromoCardView: View {
    let promo: Promo
    let onOpenCommunity: () -> Void

    @EnvironmentObject private var viewState: ViewState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var expanded = false
    @State private var selectedImageIndex = 0
    @State private var imageTransitionDirection: PromoImageTransitionDirection = .forward
    @State private var previewImage: PromoImagePreview?

    private let collapseThreshold = 5

    private var autumnBaseURL: String {
        (viewState.apiInfo?.features.autumn.url ?? "https://peptide.chat/autumn")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var logoURL: URL? {
        guard let logo = promo.vendor.logo, !logo.isEmpty else { return nil }
        return URL(string: "\(autumnBaseURL)/icons/\(logo)?max_side=256")
    }

    private var imageRefs: [String] {
        promo.images?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private var imageURLs: [URL] {
        imageRefs.compactMap { imageURL(for: $0) }
    }

    private var isCollapsible: Bool {
        promo.items.count > collapseThreshold
    }

    private var isJoinedCommunity: Bool {
        if let serverId = promo.vendor.serverId,
           viewState.servers[serverId] != nil {
            return true
        }

        return viewState.servers.values.contains {
            $0.name.lowercased() == promo.vendor.name.lowercased()
        }
    }

    private var compoundSummaries: [CompoundSummary] {
        var summaries: [CompoundSummary] = []
        var indexes: [String: Int] = [:]

        for item in promo.items {
            let name = item.product
            if let index = indexes[name] {
                summaries[index].count += 1
            } else {
                indexes[name] = summaries.count
                summaries.append(CompoundSummary(name: name, count: 1))
            }
        }

        return summaries
    }

    private var collapsedSummaryLimit: Int {
        horizontalSizeClass == .compact ? 6 : 10
    }

    private var collapsedCompoundSummaries: [CompoundSummary] {
        Array(compoundSummaries.prefix(collapsedSummaryLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing8) {
            header

            if !promo.items.isEmpty {
                if isCollapsible && !expanded {
                    productSummary
                } else {
                    itemTable
                }
            }

            chips

            if let noteText {
                PeptideText(
                    text: noteText,
                    font: .peptideCaption1,
                    textColor: .textGray07,
                    alignment: .leading
                )
            }

            if !imageRefs.isEmpty {
                promoGallery
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: .radius8)
                .fill(Color.bgGray11)
        }
    }

    private var promoGallery: some View {
        VStack(alignment: .leading, spacing: .spacing8) {
            ZStack {
                PromoRemoteImage(
                    url: imageURL(for: selectedImageRef),
                    height: galleryHeroHeight,
                    cornerRadius: .radius8
                )
                .id(selectedImageRef)
                .transition(imageTransitionDirection.transition)
            }
            .frame(height: galleryHeroHeight)
            .clipShape(RoundedRectangle(cornerRadius: .radius8))
            .contentShape(RoundedRectangle(cornerRadius: .radius8))
            .onTapGesture {
                let urls = imageURLs
                guard !urls.isEmpty else { return }

                previewImage = PromoImagePreview(
                    urls: urls,
                    startIndex: min(selectedImageIndex, urls.count - 1)
                )
            }
            .gesture(gallerySwipeGesture)

            if imageRefs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .size6) {
                        ForEach(Array(imageRefs.enumerated()), id: \.offset) { index, ref in
                            Button {
                                selectImage(at: index)
                            } label: {
                                PromoRemoteImage(
                                    url: imageURL(for: ref),
                                    width: 52,
                                    height: 52,
                                    cornerRadius: 6
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            selectedImageIndex == index ? Color.borderDefaultGray09 : Color.clear,
                                            lineWidth: .size2
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onChange(of: promo.id) { _ in
            selectedImageIndex = 0
            previewImage = nil
        }
        .fullScreenCover(item: $previewImage) { preview in
            PromoImageViewer(urls: preview.urls, startIndex: preview.startIndex) {
                previewImage = nil
            }
        }
    }

    private var gallerySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard imageRefs.count > 1 else { return }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > vertical, abs(horizontal) > 44 else { return }

                if horizontal < 0 {
                    selectImage(at: selectedImageIndex + 1)
                } else {
                    selectImage(at: selectedImageIndex - 1)
                }
            }
    }

    private func selectImage(at index: Int) {
        guard imageRefs.indices.contains(index), index != selectedImageIndex else { return }

        imageTransitionDirection = index > selectedImageIndex ? .forward : .backward

        withAnimation(.easeInOut(duration: 0.24)) {
            selectedImageIndex = index
        }
    }

    private var galleryHeroHeight: CGFloat {
        horizontalSizeClass == .compact ? 180 : 220
    }

    private var selectedImageRef: String {
        guard imageRefs.indices.contains(selectedImageIndex) else {
            return imageRefs[0]
        }

        return imageRefs[selectedImageIndex]
    }

    private func imageURL(for ref: String) -> URL? {
        if ref.lowercased().hasPrefix("http://") || ref.lowercased().hasPrefix("https://") {
            return URL(string: ref)
        }

        return URL(string: "\(autumnBaseURL)/attachments/\(ref)")
    }

    private var header: some View {
        HStack(spacing: .spacing8) {
            if let logoURL {
                KFImage(logoURL)
                    .cacheOriginalImage()
                    .placeholder { fallbackLogo }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: .size40, height: .size40)
                    .clipShape(Circle())
            } else {
                fallbackLogo
            }

            VStack(alignment: .leading, spacing: .spacing2) {
                PeptideText(
                    text: promo.vendor.name,
                    font: .peptideCallout,
                    textColor: .textDefaultGray01,
                    alignment: .leading
                )

                if let title = promo.title, !title.isEmpty {
                    PeptideText(
                        text: title,
                        font: .peptideCaption1,
                        textColor: .textGray07,
                        alignment: .leading,
                        lineLimit: 1
                    )
                }
            }

            Spacer(minLength: .zero)

            Button {
                onOpenCommunity()
            } label: {
                PeptideIcon(
                    iconName: isJoinedCommunity ? .peptideArrowRight : .peptideAdd,
                    size: .size20,
                    color: .bgYellow07
                )
                .frame(width: .size36, height: .size36)
                .background {
                    Circle().fill(Color.bgPurple07)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var fallbackLogo: some View {
        Circle()
            .fill(Color.bgGray12)
            .frame(width: .size40, height: .size40)
            .overlay {
                PeptideIcon(
                    iconName: .peptideTeamUsers,
                    size: .size20,
                    color: .iconGray07
                )
            }
    }

    private var productSummary: some View {
        VStack(alignment: .leading, spacing: .spacing8) {
            FlowLayout(spacing: .size6, minimumItemWidth: 88) {
                ForEach(collapsedCompoundSummaries) { summary in
                    compoundChip(summary)
                }
            }

            Button {
                withAnimation {
                    expanded = true
                }
            } label: {
                HStack(spacing: .spacing4) {
                    PeptideText(
                        text: "Show all \(promo.items.count) prices",
                        font: .peptideButton,
                        textColor: .textYellow07,
                        alignment: .leading
                    )

                    PeptideIcon(
                        iconName: .peptideArrowRight,
                        size: .size16,
                        color: .iconYellow07
                    )
                    .rotationEffect(.degrees(90))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var itemTable: some View {
        VStack(spacing: .zero) {
            ForEach(Array(promo.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: .spacing4) {
                    HStack(alignment: .firstTextBaseline, spacing: .spacing8) {
                        PeptideText(
                            text: item.product,
                            font: .peptideSubhead,
                            textColor: .textDefaultGray01,
                            alignment: .leading
                        )

                        if let dosage = item.dosage, !dosage.isEmpty {
                            PeptideText(
                                text: dosage,
                                font: .peptideCaption1,
                                textColor: .textGray07
                            )
                        }

                        Spacer(minLength: .spacing8)

                        HStack(spacing: .spacing2) {
                            PeptideText(
                                text: money(item.price) ?? "$0",
                                font: .peptideSubhead,
                                textColor: .textDefaultGray01
                            )

                            PeptideText(
                                text: "/ \(item.unit ?? "kit")",
                                font: .peptideCaption1,
                                textColor: .textGray07
                            )
                        }
                    }

                    if let moq = moqText(for: item) {
                        PeptideText(
                            text: moq,
                            font: .peptideCaption1,
                            textColor: .textGray07,
                            alignment: .leading
                        )
                    }

                    if let note = item.note, !note.isEmpty {
                        PeptideText(
                            text: note,
                            font: .peptideCaption1,
                            textColor: .textGray07,
                            alignment: .leading
                        )
                    }
                }
                .padding(10)

                if index < promo.items.count - 1 || isCollapsible {
                    PeptideDivider(backgrounColor: .borderGray11)
                }
            }

            if isCollapsible {
                Button {
                    withAnimation {
                        expanded.toggle()
                    }
                } label: {
                    PeptideText(
                        text: expanded ? "Show less" : "Show all \(promo.items.count) products",
                        font: .peptideButton,
                        textColor: .textYellow07,
                        alignment: .center
                    )
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: .radius8)
                .fill(Color.bgGray12)
        }
    }

    private var chips: some View {
        FlowLayout(spacing: .spacing8) {
            if let warehouse = promo.warehouse, !warehouse.isEmpty {
                chip(warehouse)
            }

            if let shippingFee = promo.shippingFee {
                chip(shippingFee == 0 ? "Free shipping" : "Shipping \(money(shippingFee) ?? "$0")")
            }

            if let freeShippingThreshold = promo.freeShippingThreshold {
                chip("Free over \(money(freeShippingThreshold) ?? "$0")")
            }

            if let purityPct = promo.guarantee?.purityPct {
                chip("\(percent(purityPct)) purity")
            }

            if let volumePct = promo.guarantee?.volumePct {
                chip("\(percent(volumePct)) volume")
            }

            if promo.guarantee?.customsReship == true {
                chip("Customs reship")
            }

            if let timelineText {
                chip(timelineText)
            }
        }
    }

    private var noteText: String? {
        let notes = [
            promo.discountNote,
            promo.shippingNote,
            promo.moqNote,
            promo.guarantee?.text
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !notes.isEmpty else { return nil }
        return notes.joined(separator: " · ")
    }

    private var timelineText: String? {
        if promo.untilSoldOut == true {
            return "Until sold out"
        }

        if let endDate = promo.endDate,
           let date = parsedDate(from: endDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "Ends \(formatter.string(from: date))"
        }

        if let timelineText = promo.timelineText, !timelineText.isEmpty {
            return timelineText
        }

        return nil
    }

    private func chip(_ title: String) -> some View {
        PeptideText(
            text: title,
            font: .peptideCaption1,
            textColor: .textDefaultGray01
        )
        .padding(.horizontal, .padding8)
        .padding(.vertical, .padding4)
        .background {
            RoundedRectangle(cornerRadius: .radiusXSmall)
                .fill(Color.bgGray12)
        }
    }

    private func compoundChip(_ summary: CompoundSummary) -> some View {
        HStack(spacing: .spacing4) {
            PeptideText(
                text: summary.name,
                font: .peptideCaption1,
                textColor: .textDefaultGray01
            )

            if summary.count > 1 {
                PeptideText(
                    text: "×\(summary.count)",
                    font: .peptideCaption1,
                    textColor: .textGray07
                )
            }
        }
        .padding(.horizontal, .padding8)
        .padding(.vertical, .padding8)
        .background {
            RoundedRectangle(cornerRadius: .radius8)
                .fill(Color.bgGray12)
        }
    }

    private func moqText(for item: PromoItem) -> String? {
        var parts: [String] = []

        if let moqKits = item.moqKits {
            parts.append("\(number(moqKits)) kits")
        }

        if let moqTotal = item.moqTotal,
           let amount = money(moqTotal) {
            parts.append(amount)
        }

        guard !parts.isEmpty else { return nil }
        return "MOQ \(parts.joined(separator: " / "))"
    }

    private func money(_ value: Double?) -> String? {
        guard let value else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value))
    }

    private func percent(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))%" : "\(value)%"
    }

    private func number(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : "\(value)"
    }

    private func parsedDate(from value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }
}

private struct PromoRemoteImage: View {
    let url: URL?
    var width: CGFloat? = nil
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var didFail = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.bgGray12)

            if let url, !didFail {
                KFImage(url)
                    .cacheOriginalImage()
                    .onSuccess { _ in
                        didFail = false
                    }
                    .onFailure { _ in
                        didFail = true
                    }
                    .placeholder {
                        ProgressView()
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: width == nil ? .infinity : width)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                brokenImagePlaceholder
            }
        }
        .frame(maxWidth: width == nil ? .infinity : width)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.borderDefaultGray09.opacity(0.7), lineWidth: 1)
        }
        .onChange(of: url) { _ in
            didFail = false
        }
    }

    private var brokenImagePlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.12))

            Image(systemName: "photo.trianglebadge.exclamationmark")
                .font(.system(size: min(height * 0.22, 34), weight: .regular))
                .foregroundStyle(Color.textGray07)
        }
    }
}

private struct PromoImagePreview: Identifiable {
    let urls: [URL]
    let startIndex: Int

    var id: String {
        "\(urls.map(\.absoluteString).joined(separator: "|"))-\(startIndex)"
    }
}

private enum PromoImageTransitionDirection {
    case forward
    case backward

    var transition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var insertionEdge: Edge {
        self == .forward ? .trailing : .leading
    }

    private var removalEdge: Edge {
        self == .forward ? .leading : .trailing
    }
}

private struct PromoImageViewer: View {
    let urls: [URL]
    let startIndex: Int
    let onClose: () -> Void

    @State private var selectedIndex: Int
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var didFail = false
    @State private var pagingDragOffset: CGFloat = 0

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    init(urls: [URL], startIndex: Int, onClose: @escaping () -> Void) {
        self.urls = urls
        self.startIndex = startIndex
        self.onClose = onClose
        _selectedIndex = State(initialValue: min(max(startIndex, 0), max(urls.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    ForEach(urls.indices, id: \.self) { index in
                        pageImage(at: index, size: proxy.size)
                            .offset(x: CGFloat(index - selectedIndex) * proxy.size.width + pagingDragOffset)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(pageSwipeGesture)
            }
            .ignoresSafeArea()

            topControls

            bottomCounter
        }
        .onChange(of: selectedIndex) { _ in
            resetZoom()
            didFail = false
        }
    }

    @ViewBuilder
    private func pageImage(at index: Int, size: CGSize) -> some View {
        if index == selectedIndex, urls.indices.contains(index), !didFail {
            KFImage(urls[index])
                .cacheOriginalImage()
                .onSuccess { _ in
                    didFail = false
                }
                .onFailure { _ in
                    didFail = true
                }
                .placeholder {
                    ProgressView()
                        .tint(.white)
                }
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(zoomGesture(in: size))
                .simultaneousGesture(doubleTapGesture(in: size))
        } else if index == selectedIndex {
            brokenImage
                .frame(width: size.width, height: size.height)
        } else if urls.indices.contains(index) {
            KFImage(urls[index])
                .cacheOriginalImage()
                .placeholder {
                    ProgressView()
                        .tint(.white)
                }
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
        }
    }

    private var topControls: some View {
        VStack {
            HStack {
                Spacer(minLength: .zero)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)

            Spacer(minLength: .zero)
        }
    }

    private var bottomCounter: some View {
        VStack {
            Spacer(minLength: .zero)

            if urls.count > 1 {
                Text("\(selectedIndex + 1)/\(urls.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.58), in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onChanged { value in
                guard scale <= minScale, urls.count > 1 else { return }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > vertical else { return }

                let isAtFirst = selectedIndex == 0 && horizontal > 0
                let isAtLast = selectedIndex == urls.count - 1 && horizontal < 0
                pagingDragOffset = isAtFirst || isAtLast ? horizontal * 0.18 : horizontal
            }
            .onEnded { value in
                guard scale <= minScale else { return }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > vertical, abs(horizontal) > 60 else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        pagingDragOffset = 0
                    }
                    return
                }

                withAnimation(.easeInOut(duration: 0.24)) {
                    if horizontal < 0 {
                        showNextImage()
                    } else {
                        showPreviousImage()
                    }
                    pagingDragOffset = 0
                }
            }
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = clampedScale(lastScale * value)
                    offset = clampedOffset(lastOffset, in: size)
                }
                .onEnded { _ in
                    scale = clampedScale(scale)
                    if scale <= minScale {
                        resetZoom()
                    } else {
                        offset = clampedOffset(offset, in: size)
                        lastScale = scale
                        lastOffset = offset
                    }
                },
            DragGesture()
                .onChanged { value in
                    guard scale > minScale else { return }
                    let proposed = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    offset = clampedOffset(proposed, in: size)
                }
                .onEnded { _ in
                    lastOffset = clampedOffset(offset, in: size)
                    offset = lastOffset
                }
        )
    }

    private func doubleTapGesture(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    if scale > minScale {
                        resetZoom()
                    } else {
                        scale = 2.5
                        lastScale = scale
                        offset = clampedOffset(offset, in: size)
                        lastOffset = offset
                    }
                }
            }
    }

    private func showNextImage() {
        guard selectedIndex < urls.count - 1 else { return }
        selectedIndex += 1
    }

    private func showPreviousImage() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
    }

    private var brokenImage: some View {
        VStack(spacing: .spacing8) {
            Image(systemName: "photo.trianglebadge.exclamationmark")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.textGray07)

            PeptideText(
                text: "Image unavailable",
                font: .peptideSubhead,
                textColor: .textGray07,
                alignment: .center
            )
        }
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private func clampedOffset(_ proposed: CGSize, in size: CGSize) -> CGSize {
        guard scale > minScale else { return .zero }

        let horizontalLimit = size.width * (scale - minScale) / 2
        let verticalLimit = size.height * (scale - minScale) / 2

        return CGSize(
            width: min(max(proposed.width, -horizontalLimit), horizontalLimit),
            height: min(max(proposed.height, -verticalLimit), verticalLimit)
        )
    }

    private func resetZoom() {
        scale = minScale
        lastScale = minScale
        offset = .zero
        lastOffset = .zero
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let minimumItemWidth: CGFloat
    let content: () -> Content

    init(
        spacing: CGFloat,
        minimumItemWidth: CGFloat = 116,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.spacing = spacing
        self.minimumItemWidth = minimumItemWidth
        self.content = content
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumItemWidth), spacing: spacing, alignment: .leading)],
            alignment: .leading,
            spacing: spacing
        ) {
            content()
        }
    }
}

private struct PromoMasonryGrid: View {
    let promos: [Promo]
    let onOpenCommunity: (Promo) -> Void

    var body: some View {
        let columns = distributedPromos(columnCount: columnCount)

        HStack(alignment: .top, spacing: .spacing12) {
            ForEach(columns.indices, id: \.self) { columnIndex in
                LazyVStack(spacing: .spacing12) {
                    ForEach(columns[columnIndex]) { promo in
                        PromoCardView(
                            promo: promo,
                            onOpenCommunity: {
                                onOpenCommunity(promo)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var columnCount: Int {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return 1
        }

        return UIScreen.main.bounds.width >= 1000 ? 3 : 2
    }

    private func distributedPromos(columnCount: Int) -> [[Promo]] {
        var columns = Array(repeating: [Promo](), count: max(columnCount, 1))

        for (index, promo) in promos.enumerated() {
            columns[index % columns.count].append(promo)
        }

        return columns
    }
}

private struct CompoundSummary: Identifiable {
    var id: String { name }
    let name: String
    var count: Int
}

//#Preview {
//    PromosView()
//}
