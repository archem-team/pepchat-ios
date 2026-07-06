# Discover Server API

## Overview

The Discover server list now loads from the public PepChat directory API instead of the previous Google Sheets CSV feed.

Endpoint:

```text
GET https://manageapi.peptide.chat/api/directory/servers
```

The endpoint is public and returns a standard response envelope with the server list in `data`. The server applies `Cache-Control: public, max-age=300`, so clients should not poll faster than five minutes.

If this API fails, the app falls back to the previous published Google Sheets CSV URL:

```text
https://docs.google.com/spreadsheets/d/e/2PACX-1vRY41D-NgTE6bC3kTN3dRpisI-DoeHG8Eg7n31xb1CdydWjOLaphqYckkTiaG9oIQSWP92h3NE-7cpF/pub?gid=0&single=true&output=csv
```

## App Integration

The integration remains local to `Revolt/Components/Home/Discover/DiscoverScrollView.swift`.

- `DiscoverScrollView.loadData()` still owns loading cached data first, showing the list, then refreshing from the network.
- `ServerChatDataFetcher` now calls the public JSON API with Alamofire `responseDecodable` instead of downloading and parsing CSV.
- If the API request fails, returns `success=false`, or cannot decode, `ServerChatDataFetcher` downloads and parses the legacy CSV fallback.
- The decoded API rows are cached to `discover_server_cache.json` in the user caches directory.
- Discover is still only loaded for `peptide.chat` base URLs, preserving the old domain guard.
- `DiscoverScrollView` observes `ViewState.discoverMembershipCache` and mirrors it into local row state so join/leave events update already-mounted Discover rows.

## Field Mapping

| API field | App field | Notes |
| --- | --- | --- |
| `id` | `DiscoverItem.id` | Stable server id and list key. Used for direct membership lookup. |
| `name` | `DiscoverItem.title` | May be empty, UI should tolerate it. |
| `description` | `DiscoverItem.description` | May be empty, UI should tolerate it. |
| `inviteCode` | `DiscoverItem.code` | Nullable. `nil` means the server is not joinable. |
| `disabled` | `DiscoverItem.disabled` | Locked rows are greyed out and do not navigate to invite. |
| `new` | `DiscoverItem.isNew` | Decoded with custom coding key because `new` is not the Swift property name. |
| `showcolor` | `DiscoverItem.color` | Optional accent hex color. |
| `sortorder` | `DiscoverItem.sortOrder` | Optional. The API response is already sorted, so the app preserves response order. |

The old CSV-only fields (`chronological`, donation columns, notes, `dateAdded`) are not used by the Discover UI and are not required by the API-backed implementation.

When the CSV fallback is used, rows are sorted locally by `sortorder` to preserve the previous CSV behavior.

## Membership Behavior

Membership checks are intentionally unchanged:

1. `checkIfUserIsMember(item:)` checks `viewState.servers` by API server id first.
2. It then checks the persisted Discover membership cache.
3. Visible rows lazily call `checkAndCacheMembership(for:)` to resolve invite metadata when an invite code exists.

Disabled rows or rows with no invite code skip invite fetching and do not navigate to `NavigationDestination.invite`.

Local row cache is not treated as authoritative for server-id membership hits. This matters after leave events: `ViewState.updateMembershipCache(serverId:isMember:)` persists the false value, and the Discover view receives the updated dictionary through `onChange` instead of continuing to show stale local state.

On app launch, Ready reconciliation snapshots cached membership keys before marking servers absent from the Ready payload as non-member. This avoids mutating the membership dictionary while iterating it and keeps terminated-state reopen behavior deterministic.

## Failure And Cache Behavior

The app still shows the last cached Discover response when available. If the API refresh fails, the current cached or already-loaded list remains visible and the error is logged with `debugPrint`.

Network fallback order:

1. Load `discover_server_cache.json` if available.
2. Fetch the public JSON API.
3. If the API path fails or returns an empty `data` array, fetch and parse the legacy CSV.
4. Save whichever fresh network source succeeds back into `discover_server_cache.json`.

Empty network responses are not cacheable. If the API returns an empty list, the app tries the CSV fallback. If the CSV fallback also returns no rows, the fetch fails without overwriting the previous cache.

The previous CSV cache format may fail to decode after this migration because the API model uses API field names (`new`, `sortorder`, `showcolor`). That is acceptable: the next successful API fetch repopulates the cache in the new format.

## Manual Test Cases

1. Open Discover on `peptide.chat`; the server list loads from cache first if present, then refreshes from the public API.
2. Verify rows appear in the same order returned by the API.
3. Tap a server where the current user is already a member; the app should select that server directly by id.
4. Tap a joinable server where the current user is not a member; the app should navigate to the invite flow.
5. Tap a disabled server or a server with `inviteCode == nil`; the row should remain non-joinable and should not navigate to an empty invite.
6. Relaunch the app and verify cached Discover membership state still appears immediately.
7. Leave a server from this device, return to Discover without killing the app, and verify that server no longer shows as joined.
8. Leave a server, terminate the app, reopen it, and verify Discover applies the persisted non-member cache state before any row-level invite checks finish.
