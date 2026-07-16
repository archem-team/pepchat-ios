//
//  PromosManager.swift
//  Revolt
//
//  Created by Akshat Srivastava on 25/06/26.
//

import Foundation
import Combine
import Alamofire

class PromosManager: ObservableObject {
    @Published var promos: [Promo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var submitState: PromoSubmitState = .idle
    @Published var submitErrorMessage: String?

    private var fetchTask: Task<Void, Never>?

    deinit {
        fetchTask?.cancel()
    }

    @MainActor
    func fetchPromos(sort: PromoSort, http: HTTPClient) {
        fetchTask?.cancel()
        isLoading = promos.isEmpty
        errorMessage = nil

        fetchTask = Task { [weak self] in
            guard let self else { return }

            let query = PromosListQuery(sort: sort.apiValue, pageSize: 100)
            let result: Result<PromosResponse, RevoltError> = await http.req(
                method: .get,
                route: "/promos",
                parameters: query,
                encoder: URLEncodedFormParameterEncoder.default
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.isLoading = false

                switch result {
                case .success(let payload) where payload.success:
                    self.promos = payload.data.items
                    self.errorMessage = nil
                case .success:
                    self.errorMessage = "Failed to load promos."
                case .failure(let error):
                    self.errorMessage = PromosManager.message(for: error, fallback: "Failed to load promos.")
                }
            }
        }
    }

    @MainActor
    func submitPromo(form: PromoSubmitForm, http: HTTPClient) async -> Bool {
        guard !form.serverId.isEmpty else {
            submitErrorMessage = "Select a server."
            submitState = .error
            return false
        }

        guard let sessionToken = http.token, !sessionToken.isEmpty else {
            submitErrorMessage = "No active session."
            submitState = .error
            return false
        }

        guard let url = URL(string: "\(http.baseURL)/promos/submit") else {
            submitErrorMessage = "Invalid submit URL."
            submitState = .error
            return false
        }

        submitState = .saving
        submitErrorMessage = nil

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(sessionToken, forHTTPHeaderField: "x-session-token")
            request.httpBody = try JSONSerialization.data(withJSONObject: form.requestBody())

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200..<300).contains(statusCode) else {
                submitErrorMessage = PromosManager.submitErrorMessage(from: data, statusCode: statusCode)
                submitState = .error
                return false
            }

            let payload = try JSONDecoder().decode(PromoSubmitResponse.self, from: data)
            guard payload.success else {
                submitErrorMessage = payload.errorMessage ?? "Submission failed."
                submitState = .error
                return false
            }

            submitState = .ok
            return true
        } catch {
            submitErrorMessage = error.localizedDescription
            submitState = .error
            return false
        }
    }

    @MainActor
    func uploadPromoImage(data: Data, name: String, http: HTTPClient) async -> String? {
        let result = await http.uploadFile(data: data, name: name, category: .attachment)

        switch result {
        case .success(let file):
            return file.id
        case .failure:
            submitErrorMessage = "Image upload failed."
            submitState = .error
            return nil
        }
    }

    @MainActor
    func resetSubmitState() {
        submitState = .idle
        submitErrorMessage = nil
    }

    private static func message(for error: RevoltError, fallback: String) -> String {
        switch error {
        case .HTTPError(let body, let statusCode):
            if statusCode == 401 {
                return "Sign in again to load promos."
            }

            if let body,
               let data = body.data(using: .utf8),
               let payload = try? JSONDecoder().decode(PromoAPIError.self, from: data),
               let message = payload.error {
                return message
            }

            return fallback
        case .Alamofire(let error):
            return error.localizedDescription
        case .JSONDecoding:
            return "Failed to parse promos."
        }
    }

    private static func submitErrorMessage(from data: Data, statusCode: Int) -> String {
        if statusCode == 401 {
            return "Sign in again to submit promos."
        }

        if statusCode == 403 {
            return "You need to own this community to submit a promo."
        }

        if statusCode == 429 {
            return "Too many submissions. Try again later."
        }

        if let payload = try? JSONDecoder().decode(PromoAPIError.self, from: data),
           let message = payload.error {
            return message
        }

        return "Submission failed."
    }
}

enum PromoSubmitState {
    case idle
    case saving
    case ok
    case error
}

struct PromoSubmitResponse: Decodable {
    let success: Bool
    let data: PromoSubmitData?
    let error: String?
    let type: String?

    var errorMessage: String? {
        error ?? type
    }
}

struct PromoSubmitData: Decodable {
    let id: String
    let approval: String
}

struct PromoAPIError: Decodable {
    let type: String?
    let error: String?
}

private struct PromosListQuery: Encodable {
    let sort: String
    let pageSize: Int
}

struct PromoSubmitItemForm: Identifiable, Equatable {
    let id = UUID()
    var product = ""
    var dosage = ""
    var price = ""
    var unit = "kit"
    var moqKits = ""
    var moqTotal = ""
    var note = ""

    func requestBody() -> [String: Any]? {
        let trimmedProduct = product.trimmed
        guard !trimmedProduct.isEmpty else { return nil }

        var body: [String: Any] = [
            "product": trimmedProduct,
            "price": price.numberValue ?? 0,
            "unit": unit.trimmed.isEmpty ? "kit" : unit.trimmed
        ]

        body.setIfPresent("dosage", dosage.trimmed.nilIfEmpty)
        body.setIfPresent("moqKits", moqKits.numberValue)
        body.setIfPresent("moqTotal", moqTotal.numberValue)
        body.setIfPresent("note", note.trimmed.nilIfEmpty)
        return body
    }
}

struct PromoSubmitForm {
    var serverId: String
    var title = ""
    var items: [PromoSubmitItemForm] = [PromoSubmitItemForm()]
    var warehouse = ""
    var shippingFee = ""
    var freeShippingThreshold = ""
    var shippingNote = ""
    var purityPct = ""
    var volumePct = ""
    var customsReship = false
    var guaranteeText = ""
    var discountNote = ""
    var moqNote = ""
    var startDate = ""
    var endDate = ""
    var untilSoldOut = false
    var timelineText = ""
    var images: [String] = []
    var submitterContact = ""
    var submitterNote = ""

    func requestBody() -> [String: Any] {
        let cleanItems = items.compactMap { $0.requestBody() }

        var body: [String: Any] = ["serverId": serverId]
        body.setIfPresent("title", title.trimmed.nilIfEmpty)
        body.setIfPresent("items", cleanItems.isEmpty ? nil : cleanItems)
        body.setIfPresent("images", images.isEmpty ? nil : images)
        body.setIfPresent("shippingFee", shippingFee.numberValue)
        body.setIfPresent("freeShippingThreshold", freeShippingThreshold.numberValue)
        body.setIfPresent("shippingNote", shippingNote.trimmed.nilIfEmpty)
        body.setIfPresent("guarantee", guaranteeBody)
        body.setIfPresent("discountNote", discountNote.trimmed.nilIfEmpty)
        body.setIfPresent("warehouse", warehouse.trimmed.nilIfEmpty)
        body.setIfPresent("moqNote", moqNote.trimmed.nilIfEmpty)
        body.setIfPresent("startDate", startDate.nilIfEmpty)
        body.setIfPresent("endDate", endDate.nilIfEmpty)
        body.setIfPresent("untilSoldOut", untilSoldOut ? true : nil)
        body.setIfPresent("timelineText", timelineText.trimmed.nilIfEmpty)
        body.setIfPresent("submitterContact", submitterContact.trimmed.nilIfEmpty)
        body.setIfPresent("submitterNote", submitterNote.trimmed.nilIfEmpty)
        return body
    }

    private var guaranteeBody: [String: Any]? {
        let hasGuarantee =
            purityPct.numberValue != nil ||
            volumePct.numberValue != nil ||
            customsReship ||
            !guaranteeText.trimmed.isEmpty

        guard hasGuarantee else { return nil }

        var body: [String: Any] = [:]
        body.setIfPresent("purityPct", purityPct.numberValue)
        body.setIfPresent("volumePct", volumePct.numberValue)
        body.setIfPresent("customsReship", customsReship ? true : nil)
        body.setIfPresent("text", guaranteeText.trimmed.nilIfEmpty)
        return body
    }
}

struct PromosResponse: Decodable {
    let success: Bool
    let data: PromosResponseData
}

struct PromosResponseData: Decodable {
    let items: [Promo]
}

struct Promo: Identifiable, Decodable {
    let id: String
    let vendor: PromoVendor
    let title: String?
    let items: [PromoItem]
    let images: [String]?
    let shippingFee: Double?
    let freeShippingThreshold: Double?
    let shippingNote: String?
    let guarantee: PromoGuarantee?
    let discountNote: String?
    let warehouse: String?
    let moqNote: String?
    let startDate: String?
    let endDate: String?
    let untilSoldOut: Bool?
    let timelineText: String?
    let status: String?
    let createdAt: String?
    let updatedAt: String?
}

struct PromoVendor: Decodable {
    let serverId: String?
    let name: String
    let logo: String?
    let inviteLink: String?
}

struct PromoItem: Decodable, Identifiable {
    var id: String {
        [
            product,
            dosage ?? "",
            price.map { String($0) } ?? "",
            unit ?? ""
        ].joined(separator: "-")
    }

    let product: String
    let dosage: String?
    let price: Double?
    let unit: String?
    let moqKits: Double?
    let moqTotal: Double?
    let note: String?
}

struct PromoGuarantee: Decodable {
    let purityPct: Double?
    let volumePct: Double?
    let customsReship: Bool?
    let text: String?
}

private extension Dictionary where Key == String, Value == Any {
    mutating func setIfPresent(_ key: String, _ value: Any?) {
        guard let value else { return }
        self[key] = value
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var numberValue: Double? {
        let value = trimmed
        guard !value.isEmpty else { return nil }
        return Double(value)
    }
}
