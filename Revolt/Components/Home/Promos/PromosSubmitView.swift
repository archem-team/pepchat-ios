//
//  PromosSubmitView.swift
//  Revolt
//
//  Created by Akshat Srivastava on 25/06/26.
//

import SwiftUI
import PhotosUI
import Kingfisher
import Types

struct PromosSubmitView: View {
    @EnvironmentObject private var viewState: ViewState

    @StateObject private var promosManager = PromosManager()
    @State private var form = PromoSubmitForm(serverId: "")
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var uploadingImages = false
    @State private var validationAlert: PromoFormAlert?
    @State private var usesStartDate = false
    @State private var usesEndDate = false
    @State private var startDate = Date()
    @State private var endDate = Date()

    private let maxImages = 12

    private var ownedServers: [Server] {
        guard let currentUserId = viewState.currentUser?.id else { return [] }
        return viewState.servers.values
            .filter { $0.owner == currentUserId }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var autumnBaseURL: String {
        (viewState.apiInfo?.features.autumn.url ?? "https://peptide.chat/autumn")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var body: some View {
        
        PeptideTemplateView(toolbarConfig: .init(isVisible: true, title: "Submit a promo")){_,_ in
            Group {
                if promosManager.submitState == .ok {
                    successView
                } else {
                    formView
                }
            }
            .navigationBarBackButtonHidden(true)
            .onAppear {
                if form.serverId.isEmpty {
                    form.serverId = ownedServers.first?.id ?? ""
                }
                promosManager.resetSubmitState()
            }
            .onChange(of: selectedPhotos) { newValue in
                Task {
                    await uploadPhotos(newValue)
                }
            }
            .alert(item: $validationAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .zero) {
                SettingAttentionView(items: [
                    "Promos are reviewed by an admin before going live. Vendor identity and the join link come from the community you select."
                ])

                if ownedServers.isEmpty {
                    emptyOwnersView
                } else {
                    communitySection
                    fieldSection(title: "Title") {
                        promoField(label: "Title", placeholder: "e.g. US Warehouse Promo", text: $form.title)
                    }

                    divider
                        
                    productsSection

                    divider
                    shippingSection

                    divider
                    guaranteeSection

                    divider
                    offerDetailsSection

                    divider
                    timelineSection

                    divider
                    imagesSection

                    divider
                    reviewerSection

                    actions
                }
            }
            .padding(.horizontal, .padding16)
        }
    }

    private var emptyOwnersView: some View {
        VStack(spacing: .spacing8) {
            PeptideText(
                text: "You need to own a community before submitting a promo.",
                font: .peptideSubhead,
                textColor: .textGray07,
                alignment: .center
            )

            PeptideButton(title: "Back to promos", isFullWidth: false) {
                close()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .padding32)
    }

    private var communitySection: some View {
        fieldSection(title: "Community") {
            VStack(alignment: .leading, spacing: .size4) {
                PeptideText(
                    text: "Community",
                    font: .peptideBody,
                    textColor: .textGray06,
                    alignment: .leading
                )
                .padding(.horizontal, .size4)

                Picker("Community", selection: $form.serverId) {
                    ForEach(ownedServers) { server in
                        Text(server.name).tag(server.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.textDefaultGray01)
                .frame(maxWidth: .infinity, minHeight: .size40, alignment: .leading)
                .padding(.horizontal, .padding12)
                .background {
                    RoundedRectangle(cornerRadius: .radiusXSmall)
                        .stroke(Color.bgGray11, lineWidth: .size2)
                        .background(Color.bgGray11)
                        .cornerRadius(.radius8)
                }
            }
        }
    }

    private var productsSection: some View {
        fieldSection(title: "Products") {
            VStack(spacing: .spacing8) {
                ForEach($form.items) { $item in
                    productCard(item: $item)
                }

                Button {
                    form.items.append(PromoSubmitItemForm())
                } label: {
                    HStack(spacing: .spacing8) {
                        PeptideIcon(
                            iconName: .peptideAdd,
                            size: .size20,
                            color: .iconYellow07
                        )
                        PeptideText(
                            text: "Add product",
                            font: .peptideButton,
                            textColor: .textYellow07
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: .size40)
                    .background {
                        RoundedRectangle(cornerRadius: .radius8)
                            .fill(Color.bgGray11.opacity(0.65))
                    }
                }
            }
        }
    }

    private func productCard(item: Binding<PromoSubmitItemForm>) -> some View {
        VStack(alignment: .leading, spacing: .spacing8) {
            HStack {
                PeptideText(
                    text: "Item \(itemIndex(for: item.wrappedValue) + 1)",
                    font: .peptideCaption1,
                    textColor: .textGray07,
                    alignment: .leading
                )

                Spacer(minLength: .zero)

                if form.items.count > 1 {
                    Button {
                        removeItem(item.wrappedValue)
                    } label: {
                        PeptideIcon(
                            iconName: .peptideClose,
                            size: .size20,
                            color: .iconRed07
                        )
                    }
                }
            }

            twoColumn {
                promoField(label: "Product", placeholder: "Reta", text: item.product)
                promoField(label: "Dosage", placeholder: "10mg", text: item.dosage)
                promoField(label: "Price", placeholder: "USD", text: item.price, keyboardType: .decimalPad)
                promoField(label: "Unit", placeholder: "kit", text: item.unit)
                promoField(label: "MOQ Kits", placeholder: "MOQ Kits", text: item.moqKits, keyboardType: .decimalPad)
                promoField(label: "MOQ Total", placeholder: "$ total", text: item.moqTotal, keyboardType: .decimalPad)
            }

            promoField(label: "Note", placeholder: "Optional", text: item.note)
        }
        .padding(.padding12)
        .background {
            RoundedRectangle(cornerRadius: .radius8)
                .fill(Color.bgGray11.opacity(0.65))
        }
    }

    private var shippingSection: some View {
        fieldSection(title: "Shipping") {
            VStack(spacing: .spacing8) {
                twoColumn {
                    promoField(label: "Shipping Fee", placeholder: "USD", text: $form.shippingFee, keyboardType: .decimalPad)
                    promoField(label: "Free Shipping Over", placeholder: "USD", text: $form.freeShippingThreshold, keyboardType: .decimalPad)
                }
                promoField(label: "Shipping Note", placeholder: "Optional", text: $form.shippingNote)
                promoField(label: "Warehouse", placeholder: "US, EU", text: $form.warehouse)
            }
        }
    }

    private var guaranteeSection: some View {
        fieldSection(title: "Guarantee") {
            VStack(spacing: .spacing8) {
                twoColumn {
                    promoField(label: "Purity", placeholder: "%", text: $form.purityPct, keyboardType: .decimalPad)
                    promoField(label: "Volume", placeholder: "%", text: $form.volumePct, keyboardType: .decimalPad)
                }
                toggleRow(title: "Customs reship guarantee", isOn: $form.customsReship)
                promoField(label: "Guarantee Note", placeholder: "Optional", text: $form.guaranteeText)
            }
        }
    }

    private var offerDetailsSection: some View {
        fieldSection(title: "Offer details") {
            VStack(spacing: .spacing8) {
                promoField(label: "Discount Note", placeholder: "e.g. 5% off over $1,000", text: $form.discountNote)
                promoField(label: "MOQ Note", placeholder: "Optional", text: $form.moqNote)
            }
        }
    }

    private var timelineSection: some View {
        fieldSection(title: "Timeline") {
            VStack(spacing: .spacing8) {
                optionalDatePicker(
                    title: "Start Date",
                    isEnabled: $usesStartDate,
                    date: $startDate,
                    isDisabled: false
                )

                optionalDatePicker(
                    title: "End Date",
                    isEnabled: $usesEndDate,
                    date: $endDate,
                    isDisabled: form.untilSoldOut
                )

                toggleRow(title: "Until sold out (no fixed end date)", isOn: $form.untilSoldOut)
                promoField(label: "Timeline Note", placeholder: "Optional", text: $form.timelineText)
            }
            .onChange(of: usesStartDate) { isEnabled in
                form.startDate = isEnabled ? apiDateFormatter.string(from: startDate) : ""
            }
            .onChange(of: startDate) { newValue in
                if usesStartDate {
                    form.startDate = apiDateFormatter.string(from: newValue)
                }
            }
            .onChange(of: usesEndDate) { isEnabled in
                form.endDate = isEnabled && !form.untilSoldOut ? apiDateFormatter.string(from: endDate) : ""
            }
            .onChange(of: endDate) { newValue in
                if usesEndDate && !form.untilSoldOut {
                    form.endDate = apiDateFormatter.string(from: newValue)
                }
            }
            .onChange(of: form.untilSoldOut) { isUntilSoldOut in
                if isUntilSoldOut {
                    usesEndDate = false
                    form.endDate = ""
                } else if usesEndDate {
                    form.endDate = apiDateFormatter.string(from: endDate)
                }
            }
        }
    }

    private var imagesSection: some View {
        fieldSection(title: "Images (\(form.images.count)/\(maxImages))") {
            VStack(alignment: .leading, spacing: .spacing8) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: .size72), spacing: .spacing8)],
                    alignment: .leading,
                    spacing: .spacing8
                ) {
                    ForEach(Array(form.images.enumerated()), id: \.element) { index, id in
                        imageThumb(id: id, index: index)
                    }

                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: max(0, maxImages - form.images.count),
                        matching: .images
                    ) {
                        ZStack {
                            RoundedRectangle(cornerRadius: .radius8)
                                .strokeBorder(Color.borderDefaultGray09, style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .frame(width: .size72, height: .size72)

                            if uploadingImages {
                                ProgressView()
                            } else {
                                PeptideIcon(
                                    iconName: .peptideAdd,
                                    size: .size24,
                                    color: .iconGray07
                                )
                            }
                        }
                    }
                    .disabled(uploadingImages || form.images.count >= maxImages)
                }

                if uploadingImages {
                    PeptideText(
                        text: "Uploading images...",
                        font: .peptideCaption1,
                        textColor: .textGray07,
                        alignment: .leading
                    )
                }
            }
        }
    }

    private func imageThumb(id: String, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            KFImage(URL(string: "\(autumnBaseURL)/attachments/\(id)"))
                .cacheOriginalImage()
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: .size72, height: .size72)
                .clipShape(RoundedRectangle(cornerRadius: .radius8))

            Button {
                form.images.remove(at: index)
            } label: {
                PeptideIcon(
                    iconName: .peptideClose,
                    size: .size12,
                    color: .iconDefaultGray01
                )
                .frame(width: .size24, height: .size24)
                .background {
                    Circle().fill(Color.black.opacity(0.65))
                }
            }
            .offset(x: .size6, y: -1 * .size6)
        }
        .frame(width: .size72, height: .size72)
    }

    private var reviewerSection: some View {
        fieldSection(title: "For the reviewer (not shown publicly)") {
            VStack(spacing: .spacing8) {
                promoField(label: "Your Contact", placeholder: "e.g. @telegram_handle", text: $form.submitterContact)
                promoEditor(label: "Note To The Admin", placeholder: "Optional", text: $form.submitterNote)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .center, spacing: .spacing12) {
            PeptideButton(
                title: promosManager.submitState == .saving ? "Submitting..." : "Submit for review",
                buttonState: promosManager.submitState == .saving || uploadingImages ? .loading : .default
            ) {
                Task {
                    await submit()
                }
            }

            Button {
                close()
            } label: {
                PeptideText(
                    text: "Cancel",
                    font: .peptideButton,
                    textColor: .textGray07
                )
            }

            if promosManager.submitState == .error,
               let message = promosManager.submitErrorMessage {
                PeptideText(
                    text: message,
                    font: .peptideCaption1,
                    textColor: .textRed07,
                    alignment: .center
                )
            }
        }
        .padding(.top, .padding24)
        .padding(.bottom, .padding24)
    }

    private var successView: some View {
        VStack(spacing: .spacing12) {
            Spacer(minLength: .zero)

            PeptideText(
                text: "Promo submitted",
                font: .peptideHeadline,
                textColor: .textDefaultGray01
            )

            PeptideText(
                text: "Your promo is pending review by an admin and will appear here once approved.",
                font: .peptideSubhead,
                textColor: .textGray07,
                alignment: .center
            )

            PeptideButton(title: "Back to promos", isFullWidth: false) {
                close()
            }

            Spacer(minLength: .zero)
        }
        .padding(.padding24)
    }

    private var divider: some View {
        PeptideDivider(backgrounColor: .borderGray11)
            .padding(.top, .size12)
    }

    private func fieldSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacing12) {
            PeptideText(
                text: title,
                font: .peptideHeadline,
                textColor: .textDefaultGray01,
                alignment: .leading
            )

            content()
        }
        .padding(.top, .padding24)
    }

    private func promoField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        PeptideTextField(
            text: text,
            state: .constant(.default),
            label: label,
            placeholder: placeholder,
            hasClearBtn: false,
            cornerRadius: .radius8,
            height: .size40,
            keyboardType: keyboardType
        )
    }

    private func promoEditor(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: .size4) {
            PeptideText(
                text: label,
                font: .peptideBody,
                textColor: .textGray06,
                alignment: .leading
            )
            .padding(.horizontal, .size4)

            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: .size100)
                    .padding(.padding8)
                    .font(.peptideBodyFont)
                    .foregroundStyle(Color.textDefaultGray01)
                    .tint(.textDefaultGray01)

                if text.wrappedValue.isEmpty {
                    PeptideText(
                        text: placeholder,
                        font: .peptideBody,
                        textColor: .textGray07,
                        alignment: .leading
                    )
                    .padding(.padding16)
                    .allowsHitTesting(false)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: .radiusXSmall)
                    .stroke(Color.bgGray11, lineWidth: .size2)
                    .background(Color.bgGray11)
                    .cornerRadius(.radius8)
            }
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: .spacing8) {
            Toggle("", isOn: isOn)
                .toggleStyle(PeptideCheckToggleStyle())

            PeptideText(
                text: title,
                font: .peptideBody,
                textColor: .textDefaultGray01,
                alignment: .leading
            )

            Spacer(minLength: .zero)
        }
        .padding(.vertical, .padding4)
    }

    private func optionalDatePicker(
        title: String,
        isEnabled: Binding<Bool>,
        date: Binding<Date>,
        isDisabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: .size4) {
            PeptideText(
                text: title,
                font: .peptideBody,
                textColor: isDisabled ? .textGray07 : .textGray06,
                alignment: .leading
            )
            .padding(.horizontal, .size4)

            HStack(spacing: .spacing8) {
                Toggle("", isOn: isEnabled)
                    .toggleStyle(PeptideCheckToggleStyle())
                    .disabled(isDisabled)

                DatePicker(
                    "",
                    selection: date,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .disabled(isDisabled || !isEnabled.wrappedValue)
                .opacity(isDisabled || !isEnabled.wrappedValue ? 0.55 : 1)

                Spacer(minLength: .zero)
            }
            .frame(maxWidth: .infinity, minHeight: .size40, alignment: .leading)
            .padding(.horizontal, .padding12)
            .background {
                RoundedRectangle(cornerRadius: .radiusXSmall)
                    .stroke(Color.bgGray11, lineWidth: .size2)
                    .background(isDisabled ? Color.bgGray11.opacity(0.45) : Color.bgGray11)
                    .cornerRadius(.radius8)
            }
        }
        .opacity(isDisabled ? 0.7 : 1)
    }

    private func twoColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: .spacing8), GridItem(.flexible(), spacing: .spacing8)],
            spacing: .spacing12
        ) {
            content()
        }
    }

    private var apiDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func uploadPhotos(_ photos: [PhotosPickerItem]) async {
        guard !photos.isEmpty, form.images.count < maxImages else { return }

        uploadingImages = true
        defer {
            uploadingImages = false
            selectedPhotos = []
        }

        let room = maxImages - form.images.count

        for (index, photo) in photos.prefix(room).enumerated() {
            guard let data = try? await photo.loadTransferable(type: Data.self) else {
                continue
            }

            let id = await promosManager.uploadPromoImage(
                data: data,
                name: "promo-\(Date().timeIntervalSince1970)-\(index).jpg",
                http: viewState.http
            )

            if let id {
                form.images.append(id)
            }
        }
    }

    private func submit() async {
        guard promosManager.submitState != .saving, !uploadingImages else { return }

        if let message = validateForm() {
            validationAlert = PromoFormAlert(title: "Check promo details", message: message)
            return
        }

        let submitted = await promosManager.submitPromo(
            form: form,
            sessionToken: viewState.sessionToken
        )

        if submitted {
            viewState.showAlert(message: "Promo submitted!", icon: .peptideDoneCircle, color: .iconGreen07)
        } else if let message = promosManager.submitErrorMessage {
            validationAlert = PromoFormAlert(title: "Submission failed", message: message)
        }
    }

    private func validateForm() -> String? {
        if form.serverId.trimmed.isEmpty {
            return "Select a community before submitting."
        }

        if uploadingImages {
            return "Please wait until image uploads finish."
        }

        if form.images.count > maxImages {
            return "You can attach up to \(maxImages) images."
        }

        if form.title.trimmed.isEmpty {
            return "Enter a promo title."
        }

        if form.title.count > 120 {
            return "Title must be 120 characters or less."
        }

        if form.items.count > 200 {
            return "You can add up to 200 products."
        }

        let productValidation = validateProducts()
        if let productValidation {
            return productValidation
        }

        if let message = validateRequiredNumber(form.shippingFee, label: "Shipping fee", minimum: 0) {
            return message
        }

        if let message = validateRequiredNumber(form.freeShippingThreshold, label: "Free shipping amount", minimum: 0) {
            return message
        }

        if form.warehouse.trimmed.isEmpty {
            return "Enter a warehouse, for example US or EU."
        }

        if let message = validateRequiredNumber(form.purityPct, label: "Purity", minimum: 0, maximum: 100) {
            return message
        }

        if let message = validateRequiredNumber(form.volumePct, label: "Volume", minimum: 0, maximum: 100) {
            return message
        }

        if form.discountNote.trimmed.isEmpty {
            return "Enter a discount note."
        }

        if !usesStartDate {
            return "Select a start date."
        }

        if !form.untilSoldOut && !usesEndDate {
            return "Select an end date or choose Until sold out."
        }

        if form.submitterContact.trimmed.isEmpty {
            return "Enter your reviewer contact."
        }

        if let message = validateOptionalNumber(form.shippingFee, label: "Shipping fee", minimum: 0) {
            return message
        }

        if let message = validateOptionalNumber(form.freeShippingThreshold, label: "Free shipping amount", minimum: 0) {
            return message
        }

        if let message = validateOptionalNumber(form.purityPct, label: "Purity", minimum: 0, maximum: 100) {
            return message
        }

        if let message = validateOptionalNumber(form.volumePct, label: "Volume", minimum: 0, maximum: 100) {
            return message
        }

        if form.shippingNote.count > 300 {
            return "Shipping note must be 300 characters or less."
        }

        if form.discountNote.count > 300 {
            return "Discount note must be 300 characters or less."
        }

        if form.warehouse.count > 60 {
            return "Warehouse must be 60 characters or less."
        }

        if form.moqNote.count > 120 {
            return "MOQ note must be 120 characters or less."
        }

        if form.timelineText.count > 200 {
            return "Timeline note must be 200 characters or less."
        }

        if form.submitterContact.count > 120 {
            return "Reviewer contact must be 120 characters or less."
        }

        if form.submitterNote.count > 1000 {
            return "Admin note must be 1000 characters or less."
        }

        if form.untilSoldOut && usesEndDate {
            return "End date must be disabled when Until sold out is selected."
        }

        if usesStartDate && usesEndDate && !form.untilSoldOut {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: endDate)

            if start > end {
                return "End date cannot be before start date."
            }
        }

        if usesEndDate && !form.untilSoldOut {
            let today = Calendar.current.startOfDay(for: Date())
            if Calendar.current.startOfDay(for: endDate) < today {
                return "End date cannot be in the past."
            }
        }

        return nil
    }

    private var hasPromoContent: Bool {
        !form.title.trimmed.isEmpty ||
        form.items.contains { !$0.isEmptyProductRow } ||
        !form.images.isEmpty ||
        !form.shippingFee.trimmed.isEmpty ||
        !form.freeShippingThreshold.trimmed.isEmpty ||
        !form.shippingNote.trimmed.isEmpty ||
        !form.warehouse.trimmed.isEmpty ||
        !form.purityPct.trimmed.isEmpty ||
        !form.volumePct.trimmed.isEmpty ||
        form.customsReship ||
        !form.guaranteeText.trimmed.isEmpty ||
        !form.discountNote.trimmed.isEmpty ||
        !form.moqNote.trimmed.isEmpty ||
        usesStartDate ||
        usesEndDate ||
        form.untilSoldOut ||
        !form.timelineText.trimmed.isEmpty
    }

    private func validateProducts() -> String? {
        for (index, item) in form.items.enumerated() {
            if item.product.trimmed.isEmpty {
                return "Product \(index + 1): enter a product name."
            }

            if item.dosage.trimmed.isEmpty {
                return "Product \(index + 1): enter a dosage."
            }

            guard let price = item.price.numberValue, price > 0 else {
                return "Product \(index + 1): enter a valid price greater than 0."
            }

            if item.unit.trimmed.isEmpty {
                return "Product \(index + 1): enter a unit, for example kit."
            }

            if let message = validateRequiredNumber(item.moqKits, label: "Product \(index + 1) MOQ kits", minimum: 0) {
                return message
            }

            if let message = validateRequiredNumber(item.moqTotal, label: "Product \(index + 1) MOQ total", minimum: 0) {
                return message
            }

            if item.note.count > 300 {
                return "Product \(index + 1): note must be 300 characters or less."
            }
        }

        return nil
    }

    private func validateRequiredNumber(
        _ value: String,
        label: String,
        minimum: Double,
        maximum: Double? = nil
    ) -> String? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else {
            return "\(label) is required."
        }

        return validateOptionalNumber(value, label: label, minimum: minimum, maximum: maximum)
    }

    private func validateOptionalNumber(
        _ value: String,
        label: String,
        minimum: Double,
        maximum: Double? = nil
    ) -> String? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return nil }

        guard let number = trimmed.numberValue else {
            return "\(label) must be a valid number."
        }

        if number < minimum {
            return "\(label) cannot be negative."
        }

        if let maximum, number > maximum {
            return "\(label) must be \(Int(minimum))-\(Int(maximum))."
        }

        return nil
    }

    private func itemIndex(for item: PromoSubmitItemForm) -> Int {
        form.items.firstIndex(where: { $0.id == item.id }) ?? 0
    }

    private func removeItem(_ item: PromoSubmitItemForm) {
        form.items.removeAll { $0.id == item.id }
    }

    private func close() {
        if !viewState.path.isEmpty {
            viewState.path.removeLast()
        }
    }
}

private struct PromoFormAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private extension PromoSubmitItemForm {
    var isEmptyProductRow: Bool {
        product.trimmed.isEmpty &&
        dosage.trimmed.isEmpty &&
        price.trimmed.isEmpty &&
        moqKits.trimmed.isEmpty &&
        moqTotal.trimmed.isEmpty &&
        note.trimmed.isEmpty &&
        (unit.trimmed.isEmpty || unit.trimmed.lowercased() == "kit")
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var numberValue: Double? {
        let value = trimmed
        guard !value.isEmpty else { return nil }
        return Double(value)
    }
}

//#Preview {
//    PromosSubmitView()
//}
