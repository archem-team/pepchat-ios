//
//  ViewState+Drafts.swift
//  Revolt
//
//  Draft message storage (composer text per channel). Session-bound; loaded in processReadyData, cleared in signOut/destroyCache.
//

import Foundation

private let draftMaxLength = 2000
private let channelDraftsKeyPrefix = "channelDrafts_"

extension ViewState {

    /// UserDefaults key for current account's drafts. Nil if session not bound.
    private func draftStorageKey() -> String? {
        guard let userId = currentUser?.id, let base = baseURL, !userId.isEmpty, !base.isEmpty else { return nil }
        return "\(channelDraftsKeyPrefix)\(userId)_\(base)"
    }

    /// Load drafts from UserDefaults for the given account into in-memory channelDrafts. Call from processReadyData after setSession.
    func loadDraftsFromUserDefaults(userId: String, baseURL: String) {
        let key = "\(channelDraftsKeyPrefix)\(userId)_\(baseURL)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            channelDrafts = [:]
            return
        }
        channelDrafts = decoded
    }

    /// Save draft for channel. Nil or empty removes the draft. Caps length at 2000. Persists to UserDefaults. No-op if session not bound.
    func saveDraft(channelId: String, text: String?) {
        guard let key = draftStorageKey() else { return }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trimmed, !t.isEmpty {
            let capped = String(t.prefix(draftMaxLength))
            channelDrafts[channelId] = capped
        } else {
            channelDrafts.removeValue(forKey: channelId)
        }
        if let data = try? JSONEncoder().encode(channelDrafts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Load draft for channel. Returns nil if none or session not bound.
    func loadDraft(channelId: String) -> String? {
        guard draftStorageKey() != nil else { return nil }
        return channelDrafts[channelId]
    }

    /// Clear draft for one channel. Persists. No-op if session not bound.
    func clearDraft(channelId: String) {
        guard let key = draftStorageKey() else { return }
        channelDrafts.removeValue(forKey: channelId)
        if let data = try? JSONEncoder().encode(channelDrafts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Clear all drafts for the current account (in-memory and UserDefaults). Call from signOut and at start of destroyCache.
    func clearAllDraftsForCurrentAccount() {
        guard let key = draftStorageKey() else {
            channelDrafts = [:]
            return
        }
        channelDrafts = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }
}
