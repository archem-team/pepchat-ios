# Server Channels Cache – Implementation Plan

This document describes how **server channels** are currently loaded, and the plan to add a **channel list cache** so that channel lists (and category names) are persisted per server, **with the goal of** restored on launch when a read path (Option B or load-at-launch) is implemented; **with Option A the cache is write-only and is not restored on launch.** The cache is kept in sync in real time and cleared on logout or invalid session. The design does **not** change any message cache or core messaging functionality.

**Before implementation:** If **launch restore** (channels restored on app launch) is required for the current release, **lock in Option B** (or another concrete read path) and implement it; Option A alone will **not** restore channels on launch. See **Pre-implementation decision** below and §7.

Use **AGENTS.md** for codebase navigation (ViewState extensions, storage, WebSocket events, etc.).

---

## Pre-implementation decision

**Requirements covered by this plan (non-blockers):**

1. **Identity-safe cache load** — No load before authoritative user/session (§0.1); with Option B, load only inside processReadyData after identity from Ready.
2. **Guaranteed cleanup on invalid session/signOut** — Clear at very start of signOut/destroyCache; async write race prevention via session token and cancel (§0.2, §0.3).
3. **Authoritative Ready reconciliation** — Replace per-server channel sets from Ready; never merge stale (§0.10, §7).
4. **Full topology sync coverage** — server_create/delete, join/leave, create-channel (local API) paths in addition to channel WebSocket events (§0.35, §0.36, §6 items 4–9).
5. **Consistency** — allEventChannels + servers[].channels/categories + persisted caches updated and saved together (§0.4, §0.5, §0.26).
6. **No duplicate channel IDs or stale delayed-delete writes** — Duplicate guard on all appends (§0.37); sync removal from allEventChannels/server graph/channelMessages/unreads/preloadedChannels on single-channel delete; delayed removal only for channels/dms/path (UI) (§0.33, §0.34).

**Critical blocker (read path):**

- **Option A is explicitly write-only:** the cache is never read, so channels are **not** restored on launch. If **launch restore** is required now (per the original goal), **lock in Option B** (load in processReadyData after identity, then replace with Ready) or another concrete read path **before** implementation; do not implement Option A only and assume restore will work.

---

## 0. Critical Issues and Mitigations

The following issues must be addressed so the channel cache does not leak data, corrupt state, or diverge from the UI.

### 0.1 Identity before Ready (no load at launch by identity)

**Issue:** At ViewState init we only have persisted state (e.g. `currentUser` from UserDefaults, `currentSessionId`). That identity can be stale or from a different account if the user switched accounts or re-installed. Loading channel cache at launch using “current” identity can load **another account’s channels** into `allEventChannels` pre-Ready.

**Mitigation:** **Do not load channel cache in ViewState init.** **With Option A** (current plan), **do not read** channel cache anywhere—not in init, not in processReadyData (§0.32). The cache is write-only; "restored on launch" is not satisfied until Option B or another read path exists. **With Option B** (when implemented): load channel cache only inside `processReadyData`, after authoritative identity from Ready; then (1) establish identity, (2) load cache for that identity, (3) **filter** per §0.6 (only add channels for serverIds in current `servers` and ids in `servers[serverId].channels`), (4) **replace** (never merge) with Ready channel data so Ready is authoritative.

### 0.2 Invalid-session cleanup (clear must not depend on signOut succeeding)

**Issue:** `.invalid_session` triggers `signOut()`. `signOut()` does a network call first and can return `.failure(.signOutError)` before any state/cache cleanup. If we only clear channel cache inside `signOut()` after the network call, a failed signOut leaves the cache intact and the “invalid session” path is unreliable.

**Mitigation:** Clear channel cache **unconditionally at the very start of `signOut()`**, before any `await` or network call—so even if `signOut()` returns failure, the channel cache is already cleared. Also clear at the start of `destroyCache()`. If identity is missing (e.g. already nil), clear all channel cache files in Application Support (or the single shared file) so no stale file remains (see 0.7).

### 0.3 Serialized writer / generation guard (no race or stale overwrite)

**Issue:** Frequent real-time saves (async or debounced) can reorder; an older snapshot can overwrite a newer one, or a write can complete after logout and overwrite the clear.

**Mitigation:** Use a **single serialized write path** for the channel cache: one queue or one `DispatchWorkItem` so only one save runs at a time and they run in order. Maintain a **session/generation token** (e.g. current `userId` + `baseURL` or a monotonic generation). When enqueueing a save, capture the token; when the save runs, if the token no longer matches the current session (e.g. after logout/invalidate), **skip the write**. When clearing cache, cancel any pending save work item and invalidate the session so in-flight or queued writes become no-ops. Do not rely on “last writer wins” without ordering and invalidation.

### 0.4 Server cache and channel cache updated together (dual-write)

**Issue:** UI ordering and render depend on `server.channels` and `server.categories`. If only channel objects are persisted in the channel cache and the servers cache is not updated on channel create/delete, then after relaunch `server.channels` and the channel cache can diverge.

**Mitigation:** On every in-memory change that affects the channel graph (channel_create, channel_delete, channel_update, server_create, server_delete, server_update when `channels`/categories change, joinServer, removeServer): (1) update **both** in-memory `allEventChannels` / `servers[serverId].channels` and `servers[serverId].categories`, and (2) persist **both** the channel cache and the servers cache (`saveServersCacheAsync()`). So server cache and channel cache are always written together and stay in sync.

### 0.5 Realtime coverage (server topology and join/leave)

**Issue:** server_create, server_delete, server_update (e.g. `e.data?.channels` / categories), joinServer, and removeServer change which servers exist and which channels they have. Excluding them causes cache drift and orphaned or missing entries.

**Mitigation:** Include in the plan:
- **server_create**: Add server and its channels to in-memory state; add to channel cache for that server; call `saveServersCacheAsync()` and channel cache save.
- **server_delete**: Remove server from `servers`, remove that server’s channels from `allEventChannels`, remove that server’s entry from channel cache, clear `loadedServerChannels` for that server; call `saveServersCacheAsync()` and channel cache save.
- **server_update**: When `e.data?.channels` or `e.data?.categories` are present, update `servers[e.id]` and sync `allEventChannels` (remove channel IDs no longer in server.channels); then save both caches.
- **joinServer**: After adding `response.server` and `response.channels`, call `saveServersCacheAsync()` and channel cache save for the new server.
- **removeServer** (removeServer(with:)): Remove server from `servers`, remove its channels from `allEventChannels`, remove from channel cache, remove from `loadedServerChannels`; then save both caches.

### 0.6 Cache load filtered by current servers and channel IDs

**Issue:** Loading all cached server channels into `allEventChannels` without filtering can resurrect channels for servers the user has left or channel IDs that are no longer in `server.channels`, affecting badges/unreads.

**Mitigation:** When a read path exists (Option B or load-at-launch) and we load from channel cache: only add a cached channel to `allEventChannels` if (1) its `serverId` is in the current `servers` dictionary, and (2) the channel’s id is in `servers[serverId].channels`. So we never add channels for servers no longer in membership or channel IDs not in the authoritative server.channels list. After that, **replace** with Ready channel data—**never merge** (§0.10).

### 0.7 Safe cache filename (no raw baseURL)

**Issue:** Using `channels_cache_\(userId)_\(baseURL).json` with raw `baseURL` (e.g. `https://peptide.chat/api`) introduces `/`, `:`, etc., which are path-unsafe and can cause invalid paths or inconsistent clear/load.

**Mitigation:** **Sanitize** the baseURL for use in a filename (after canonicalization per §0.31): e.g. replace `/` and `:` with a safe character, or use a stable hash. Use a filename such as `channels_cache_\(userId)_\(sanitizedCanonicalBaseURL).json`. **Single shared file** (e.g. `channels_cache.json`): high-risk for account switches—without strict write-cancellation and session/generation checks, async writes from User A can race and overwrite after logout, leaking into User B startup. If using a single file, **mandatory**: cancel all pending writes on clear, session token check before every write, and prefer clearing the file at start of signOut/destroyCache so no write runs after identity is gone. **Prefer user-keyed files** for account switches.

### 0.8 Delete flows: mutation before save (no delayed-only mutation)

**Issue:** `deleteChannel(channelId:)` and `removeChannel(with:initPath:)` use `DispatchQueue.main.asyncAfter(deadline: .now() + 0.75)` (or 1.5s) to remove from `channels` and `dms`. If we trigger channel cache save immediately in the delete handler, the save runs **before** the delayed mutation, so the deleted channel remains in the persisted cache.

**Mitigation:** Apply **synchronous** updates for cache-relevant state: in `deleteChannel` / `removeChannel`, **immediately** (no delay) remove the channel from `allEventChannels` and remove its id from `servers[serverId].channels` and from `servers[serverId].categories?[].channels`. Then enqueue the channel cache save (and server cache save). Keep the existing **delayed** block only for UI-facing updates (`channels`, `dms`, `path`, `selectDms()`). So cache sees the deletion before any save runs.

### 0.9 Lazy-load state reset on clear

**Issue:** After `destroyCache()` or when reinitializing for a new user, `loadedServerChannels` is not cleared in the current code. That can make the next session think some servers’ channels are already loaded when they are not, or leave stale server ids.

**Mitigation:** In `destroyCache()`, clear **allEventChannels** and **loadedServerChannels** explicitly (in addition to `channels`, `channelMessages`, etc.). So after clear, lazy-load state is reset and the next Ready or cache load starts from a clean state.

### 0.10 Ready merge rule: replace only

**Issue:** A “replace or merge” rule is unsafe: merging can preserve deleted or removed channel IDs indefinitely.

**Mitigation:** **Replace only.** For each server in the Ready payload, **replace** its channel list in `allEventChannels` and in `servers[serverId]` (`.channels` and `.categories`) with the Ready data. Do not merge old + new; Ready is the single source of truth.

### 0.11 Clear when identity is missing

**Issue:** Clearing “for the current account” only works when we have valid `userId` and `baseURL`. If they are already nil (e.g. after partial teardown), we might skip clear and leave old cache files, risking cross-account leakage.

**Mitigation:** `clearChannelCacheFile(userId:baseURL:)` (or equivalent) must support being called with **nil** identity: when nil, clear **all** channel cache files in the Application Support directory (e.g. all files matching `channels_cache*.json`), or clear the single shared file. Call this from both `signOut()` (with current identity if available, otherwise nil) and from the start of `destroyCache()` (with current identity if available, otherwise nil).

### 0.12 Integrity: no duplicate channel IDs

**Issue:** Repeated create/update flows could duplicate channel IDs in `server.channels` or `categories[].channels`, polluting persisted snapshots.

**Mitigation:** On channel_create, append to `servers[serverId].channels` only if the id is not already present. On channel_delete / removeChannel, remove the id from `server.channels` and from each category’s `channels` **once** (e.g. `removeAll(where:)` or single remove). Document in the implementation checklist.

### 0.13 loadedServerChannels gate can block authoritative Ready refresh

**Issue:** If a server was loaded from cache (or from a previous Ready) before the current Ready, `loadedServerChannels` contains that serverId. After Ready, `allEventChannels` is replaced with fresh data, but `loadServerChannels(serverId:)` early-returns when `loadedServerChannels.contains(serverId)`, so the **loaded** `channels` dictionary still holds the old channel objects and is never refreshed from the new `allEventChannels`.

**Mitigation:** In **processReadyData**, after applying Ready (replacing server channel lists in `allEventChannels` and `servers`), **reset `loadedServerChannels`** (clear it entirely). Then, if the user’s current selection is a server, call `loadServerChannels(serverId:)` for that server so `channels` is repopulated from the authoritative `allEventChannels`. So: clear `loadedServerChannels` after applying Ready (replace); then re-load the currently selected server’s channels so no stale channel objects remain active.

### 0.14 Logout cache reset must include lazy-load trackers

**Issue:** If `destroyCache()` clears `channels` but does **not** clear `allEventChannels` and `loadedServerChannels`, stale channel graph state can leak across relogin in the same app run (e.g. User B sees User A’s channel list in memory until Ready overwrites it, or `loadedServerChannels` causes wrong early-returns).

**Mitigation:** In **destroyCache()**, explicitly clear **allEventChannels** and **loadedServerChannels** in addition to `channels`, `channelMessages`, `servers`, etc. Document this in the code checklist so it is not missed. Same for any path that tears down the session (e.g. invalid session before signOut completes).

### 0.15 channel_create must not duplicate channel IDs

**Issue:** The current flow appends to `servers[serverId].channels` blindly; repeated or replayed channel_create events can create duplicate entries, causing duplicated rows in the UI and polluted persisted server/channel graphs.

**Mitigation:** Before appending the new channel id to `servers[serverId].channels` (and to any category’s `channels` if the create payload specifies a category), **check that the id is not already present**. If already present, treat as idempotent (e.g. update `allEventChannels[id]` with the new channel object but do not append again). Document in the channel_create handler.

### 0.16 channel_update must cover all server channel branches for cache correctness

**Issue:** Current channel_update logic updates only loaded entries and text/group-DM branches. Voice channels and **unloaded** server channels (only in `allEventChannels`) are not consistently updated, so persisted channel snapshots can drift from reality.

**Mitigation:** For **every** channel type we store in `allEventChannels` (text and voice server channels): (1) **Always** update `allEventChannels[e.id]` with the updated channel (apply the same field updates as for `channels`/`dms`). (2) If the channel is also in `channels` (because that server is loaded), update `channels[e.id]` and `dms` as today. So both loaded and unloaded server channels get the update in `allEventChannels`; then persist (channel cache + server cache if server metadata changed). Handle voice channel updates in the same switch/branch as text channel (name, icon, description, permissions, etc. as applicable).

### 0.17 Ready pipeline conflict: cache load vs extractNeededDataFromReadyEvent

**Issue:** The plan says “load channel cache in processReadyData, then replace with Ready”. But **extractNeededDataFromReadyEvent** currently **clears** `allEventChannels` and **repopulates** it from `event.channels` (for every channel in the event). So when processReadyData runs, extract is called first and has already set `allEventChannels` from the event. Any “load cache then replace” step that runs **after** extract would either clobber Ready data with cache (wrong) or be a no-op if we then “replace with Ready” again. So the insertion point is conflicting with the current pipeline.

**Mitigation:** Choose one of:

- **Option A (no pre-Ready restore this run):** Do **not** load channel cache inside processReadyData for pre-fill. Use the current pipeline as-is: extract sets `allEventChannels` from the event; processReadyData processes the rest. At the **end** of processReadyData, **save** channel cache (and server cache) so the **next** launch has data. Then implement **Option B** for the next launch (load at init with stored identity) only if/when identity at init is deemed safe (e.g. after we have a reliable “last connected user” that is cleared on logout).
- **Option B (pipeline reorder):** Change the Ready flow so that (1) we obtain `servers` and `users` (hence identity) from the event **without** calling extractNeededDataFromReadyEvent in a way that clears `allEventChannels`. (2) Load channel cache for that identity and pre-fill `allEventChannels` for server channels (filtered by current `servers` and `servers[serverId].channels`). (3) Then apply Ready’s channel list: for each server, **replace** `allEventChannels` entries and `servers[serverId].channels`/`.categories` with the event’s data. This requires refactoring: e.g. extract returns raw event.channels or we iterate the event again in processReadyData, and we do **not** clear `allEventChannels` in extract for server channels until after we’ve done the cache load + replace step.

Document the chosen option in the plan. Until Option B is implemented, **do not** load channel cache inside processReadyData for pre-fill (only save at end); this avoids the no-op/clobber hazard.

### 0.18 channel_delete: resolve server/category before removing channel state

**Issue:** The channel_delete event carries only the channel id. If we remove the channel from `allEventChannels` (and `channels`/`dms`) **before** we know which server and which category it belonged to, we lose the ability to clean `servers[serverId].channels` and `server.categories[x].channels` correctly.

**Mitigation:** In the channel_delete handler and in `deleteChannel(channelId:)`: **first** resolve the channel from `allEventChannels[id]` or `channels[id]` and read `serverId` and category membership. **Then** synchronously: remove id from `servers[serverId].channels` and from `servers[serverId].categories?[].channels`; remove from **allEventChannels**; remove from **channelMessages**, **unreads**, and **preloadedChannels**. **Do not** synchronously remove from **channels**/ **dms**—keep the delayed block for those (UI only; §0.33). Never remove the channel object before capturing server/category membership.

### 0.19 Category and server cache persistence must be reliable

**Issue:** Runtime category changes (and server.channels reordering) are not persist-stable today: server/category mutations outside Ready may not be persisted immediately (e.g. saveServersCacheAsync is detached/debounced), so channel cache and server cache can diverge between launches.

**Mitigation:** After **every** in-memory change to `servers[serverId].channels` or `servers[serverId].categories`, trigger **saveServersCacheAsync()** (and channel cache save) in the same way as channel cache—ideally through a serialized, session-guarded path (see §0.20) so the write is ordered and not dropped after logout. Document that category metadata is part of the server cache and must be written on every mutation that affects it (channel_create, channel_delete, server_update with categories, etc.).

### 0.20 Servers cache is global and not session-safe

**Issue:** The servers cache file is still **global** (one file, not user-keyed) and is **not** cleared in `destroyCache()`. So even with channel-cache clearing, **server topology** (server list, `server.channels`, `server.categories`) can leak across accounts at startup: User B may see User A’s servers and channel order until Ready overwrites.

**Mitigation:** (1) **Clear the servers cache file** on logout: in `signOut()` (at start) and in `destroyCache()`, remove or truncate the servers cache file (e.g. `ViewState.clearServersCacheFile()` or equivalent), so the next account does not load the previous account’s server list. (2) Optionally user-key the servers cache (e.g. `servers_cache_\(sanitizedUserId)_\(sanitizedBaseURL).json`) and clear only the current account’s file when that account signs out. (3) Apply the same **session guard and cancel** to **saveServersCacheAsync()** as for channel cache (see §0.21): pending server cache writes must be cancelled on clear and must not run after session invalidation.

### 0.21 Server and channel cache writes: session guard and atomicity risk

**Issue:** saveServersCacheAsync() is currently detached, unordered, and not session-guarded, so stale writes can land after sign-out/destroy and resurrect old state. Writing servers cache and channel cache as two independent files has no atomic/version coupling, so an app kill or crash can leave mismatched snapshots (e.g. server cache has a channel id that channel cache doesn’t, or the opposite).

**Mitigation:** (1) **Session-guard server cache saves:** Use a session token (or the same token as channel cache) for `saveServersCacheAsync()`; when enqueueing, capture the token; when the write runs, if the session no longer matches, skip the write. Cancel any pending server cache save work item when clearing (signOut/destroyCache). (2) **Dual-file consistency is mandatory** (see §0.26): use a **shared generation or version** (e.g. `cacheGeneration` or `savedAt`) written into **both** channel and server cache payloads; on load, if the two files have different generations or one is missing, treat as inconsistent and discard both (rely on Ready). Do not treat shared version as optional.

### 0.22 Cache schema version and corruption handling

**Issue:** The revised plan loads channel cache only inside processReadyData and then replaces with Ready, which removes most launch-time benefit (no pre-Ready restore unless Option B is implemented). There is also no explicit schema/version migration or corruption handling; cache payload evolution (e.g. new Channel fields, new file format) can cause decode failures or undefined behaviour.

**Mitigation:** (1) **Explicit scope:** Document that with Option A, the channel cache provides **no** pre-Ready restore in the same session—it is written at the end of Ready for use on a **future** launch (and only if we later add safe load-at-launch or load in processReadyData with pipeline reorder). (2) **Schema version:** Add a **version** field (e.g. `cacheSchemaVersion: Int`) at the top level of the channel cache file. On load, if version is missing or greater than supported, treat as empty and optionally delete the file. (3) **Corruption:** If decoding the channel cache throws or returns invalid data, catch, log, **clear or remove the file**, and continue without cache (Ready will repopulate). Do not leave a half-decoded state.

### 0.23 Ready reconciliation is not authoritative for loaded server channels

**Issue:** READY intentionally does not clear `channels`; only `channelMessages` and `messages` are cleared. **processChannelsFromData** is called with **neededChannels** (DMs only), so it only overwrites/merges DMs into `channels`. Server channels that were previously loaded remain in `channels` and are never replaced or pruned, so stale server channel objects can survive reconnect and be treated as valid.

**Mitigation:** After applying Ready (allEventChannels and servers updated from the event), perform an **authoritative prune** of loaded runtime state: remove from **channels**, **channelMessages**, **unreads**, and **preloadedChannels** any channel id that is a **server** channel (text/voice) and is **not** in the authoritative set (not in `allEventChannels` or not in `servers[serverId].channels` for any server). Then reset `loadedServerChannels` and, if the current selection is a server, call `loadServerChannels(serverId:)` so `channels` is repopulated only from the fresh `allEventChannels`. (§0.34: clearing unreads and preloadedChannels avoids stale badge/unread artifacts.)

### 0.24 currentChannel can stay invalid after Ready or server_update

**Issue:** If stale channel objects remain in `channels` or if the current channel was deleted/unauthorized, **currentChannel** may still point at a channel id that is no longer valid. Integrity checks (e.g. navigating to that channel) may not redirect away, so the user can be left on a deleted or unauthorized channel.

**Mitigation:** After Ready (and after any server_update that removes channels), **validate currentChannel**: if `currentChannel` is `.channel(id)` and that id is no longer in `allEventChannels` or no longer in any `server.channels`, clear navigation (e.g. `path = []`) and set `currentChannel` to a safe value (e.g. first channel of current server, or `.noChannel`/`.home`). Apply the same check after the authoritative prune (see §0.23).

### 0.25 Message events must update allEventChannels for unread/badge correctness

**Issue:** For unloaded server channels, unread and badge logic use **allEventChannels** (e.g. to resolve channel and last_message_id). Message events (new message, etc.) update **channels** and message state but do **not** update `allEventChannels[channelId].last_message_id`, so the lazy store can go stale and unread/badge counts can drift; stale last_message_id may also be persisted in the channel cache.

**Mitigation:** When processing **message** events (e.g. new message, message update that affects last message), if the channel is a server channel (text/voice), **also** update `allEventChannels[channelId]` with the new `last_message_id` (or updated channel metadata) so unread logic and any subsequent cache save see the correct state. Apply the same for any event that updates channel metadata used by unreads/badges.

### 0.26 Dual-file consistency: shared version is mandatory

**Issue:** Channel cache and server cache are two independent files with no atomic commit or version tie. A crash between writes can leave mismatched snapshots (server.channels/categories vs cached channel objects), breaking deterministic channel list restore. Treating shared version as “optional” leaves partial-write mismatches as a critical corruption risk.

**Mitigation:** **Mandatory** shared generation or version coupling: (1) Use a single **cache generation** (e.g. monotonic counter or timestamp) or **version** written into **both** files (e.g. top-level `cacheGeneration` or `savedAt`). (2) When **writing**, update the generation, then write both files (order: e.g. channel cache then server cache, or both with same generation in payload). (3) When **loading**, read both; if generations differ or one file is missing, treat as inconsistent and **discard both** (use empty state and rely on Ready). Do not use one file without the other when generations do not match. This makes dual-file consistency a requirement, not optional.

### 0.27 Cache shape integrity constraints

**Issue:** The shape `[serverId: [Channel]]` without validation allows corrupted states: a channel under the wrong server key, or duplicate channel IDs across server arrays, which can cause cross-server contamination when hydrating.

**Mitigation:** (1) **On write:** When building the channel cache map, only include a channel under the key that matches its **serverId** (for text/voice: `channel.server` must equal the map key). Reject or skip channels whose `server` does not match the key. (2) **On read:** When loading from cache, validate each entry: for each channel in `serverId -> [Channel]`, assert `channel.server == serverId` (or equivalent); if not, skip or drop that channel. (3) **Uniqueness:** Ensure no channel id appears under more than one server key; within a server’s array, ensure no duplicate channel ids. Document these as integrity constraints in the implementation.

### 0.28 Schema/versioning strategy for channel cache

**Issue:** No schema/versioning strategy is defined; a model evolution or enum-tag change (e.g. in `Channel`) can make decode fail or partially invalidate behaviour with no controlled migration path.

**Mitigation:** (1) **Define a version constant** (e.g. `ChannelCacheSchemaVersion = 1`) and include it in every channel cache payload. (2) **On load:** If `version < minimumSupported` or `version > currentVersion`, treat as unsupported: clear/remove file and continue without cache. (3) **Migration path:** For future bumps, implement a small migration (e.g. `migrate(from: Int)`) that upgrades old payloads to the current shape before use; if migration fails, treat as corrupt and remove file. Document the strategy in code and in this plan.

### 0.29 Cached pre-Ready channel list and permission revalidation

**Issue:** If channel list is ever shown from cache before Ready (Option B or load-at-launch), server channel UI renders from cached `server.channels` + channel objects without a permission revalidation gate. Role/permission changes from another device can leak outdated visibility (e.g. channel names or presence) until Ready syncs.

**Mitigation:** (1) **Document:** Until Ready (or a dedicated permission sync) has run, treat any cached channel list as **potentially stale** for visibility/permissions; the UI may show channel names the user no longer has access to. (2) **After Ready:** Use Ready as the authority for which channels exist and which the user can see; the authoritative prune (§0.23) and currentChannel validation (§0.24) keep runtime state consistent. (3) If Option B is implemented, consider a short “stale cache” indicator or avoid showing sensitive channel names until Ready has been applied.

### 0.30 server_delete / removeServer must purge all runtime state for that server

**Issue:** server_delete and removeServer cleanup is incomplete: the plan mentions removing from `servers`, `allEventChannels`, channel cache, and `loadedServerChannels`, but does not explicitly require purging that server’s channels from **channels**, **channelMessages**, **unreads**, and **preloadedChannels**. Stale entries can remain and cause incorrect UI or leaks.

**Mitigation:** When removing a server (server_delete or removeServer(with:)), **fully purge** that server’s runtime state: (1) Remove the server from `servers`. (2) For every channel id in that server’s `server.channels`, remove from **channels**, **channelMessages**, **unreads**, and **preloadedChannels**. (3) Remove those channel ids from **allEventChannels**. (4) Remove the server from channel cache and from **loadedServerChannels**. (5) Then save both caches. Do not leave orphaned channel ids in channels/channelMessages/unreads/preloadedChannels.

### 0.31 baseURL canonicalization before sanitization

**Issue:** Sanitizing baseURL for use in filenames is not enough without **canonicalization**: equivalent URLs (e.g. with/without trailing slash, different scheme, different case) can map to different sanitized strings and thus different files, breaking deterministic clear/load behaviour.

**Mitigation:** Before sanitizing, **canonicalize** baseURL: e.g. lowercase the host, strip trailing slash, use a single consistent scheme (e.g. `https`), remove default port. Then apply the same sanitization (replace `/`, `:` with `_` or hash) to the canonical form. Use the canonicalized-and-sanitized value for both cache file path and session token so that equivalent URLs always map to the same file and same session.

### 0.32 Option A is write-only without a read path

**Issue:** With Option A only, the plan explicitly does not load channel cache in processReadyData (to avoid pipeline conflict). So the channel cache is **never read** in the current design—only written at the end of Ready. The feature does not actually restore channels from cache until Option B (or another read path) is implemented.

**Mitigation:** **Document explicitly:** With Option A alone, the channel cache is **write-only** for the foreseeable future. Restore from cache (e.g. pre-Ready channel list or faster post-launch UI) **requires** implementing Option B (load in processReadyData with pipeline reorder) or a safe load-at-launch path (e.g. with canonicalized identity and integrity checks). Until then, the cache only prepares data for a future read path and for consistency with the rest of the plan.

### 0.33 Delete flow: synchronous vs delayed removal (no contradiction)

**Issue:** The plan asks for synchronous removal from allEventChannels and servers[].channels, and also keeps a delayed removal from channels/dms, which can be read as a contradiction or as reintroducing race/snapshot inconsistency.

**Mitigation:** **Clarify intent:** (1) **Synchronous** removal from **allEventChannels**, **servers[serverId].channels**, and **servers[serverId].categories** (and from **channelMessages**, **unreads**, **preloadedChannels** per §0.34) is required so that persisted state and server graph are correct. (2) **Do not** synchronously remove from **channels**/ **dms**—keep the **delayed** block for channels, dms, path (UI only). During the delay the channel is still in `channels` but is already removed from the server graph and allEventChannels, so any new save will not persist it. Implementations must be consistent: sync = allEventChannels + server graph + channelMessages + unreads + preloadedChannels; delayed = channels + dms + path only.

### 0.34 Channel-level purge: channelMessages, unreads, and preloadedChannels

**Issue:** channel_delete and the Ready authoritative prune remove channels from `channels` and `channelMessages` but do not consistently clear **channelMessages**, **unreads**, and **preloadedChannels** (and other per-channel runtime state) for those channel ids. Leaving **channelMessages[channelId]** in place leaves orphaned message state; stale unread/badge artifacts can remain after deletion or reconciliation.

**Mitigation:** On **channel_delete** (and in `deleteChannel`/`removeChannel`): after resolving serverId and removing from allEventChannels and server graph, **also** remove the channel id from **channelMessages**, **unreads**, and **preloadedChannels** synchronously. On **Ready authoritative prune**: when removing a server channel id from `channels` and `channelMessages`, **also** remove it from **unreads** and **preloadedChannels** (channelMessages is already pruned with channels). Document this in the checklist so both delete and prune paths clear per-channel state and no orphaned channelMessages remain.

### 0.35 server_create / joinServer / local create-server must populate allEventChannels

**Issue:** server_create (WebSocket), joinServer (API), and local create-server/join-invite flows add a server and its channels to `servers` and sometimes to `channels`, but **do not** populate **allEventChannels**. Lazy-loading depends on allEventChannels; if those channels are ever unloaded, they cannot be reloaded correctly, and a cache derived from allEventChannels will miss them.

**Mitigation:** **Every** path that adds a server or its channels must **add those channels to allEventChannels** and trigger cache save: (1) **server_create** (WebSocket): add each channel in the event to allEventChannels. (2) **joinServer(code:)** (API): after adding `response.server` and `response.channels`, add each response channel to allEventChannels. (3) **Create server** (e.g. AddServerSheet) and **join via invite** (e.g. ViewInvite): when the API returns server + channels, add those channels to allEventChannels and update servers; then trigger saveChannelCacheAsync and saveServersCacheAsync. (4) **Create channel** (e.g. ChannelCategoryCreateView): when the API returns the new channel, add it to allEventChannels and append to servers[serverId].channels (with duplicate guard per §0.37); then trigger save.

### 0.36 Local API-success paths must trigger cache write

**Issue:** The plan focuses Ready and WebSocket channel events for cache writes. API-success paths (create channel, create server, join server via invite) also mutate topology; if the app exits before the corresponding WebSocket events arrive, the cache can be stale or missing the new channels.

**Mitigation:** **Every** local mutation that changes server/channel topology must trigger **saveChannelCacheAsync()** and **saveServersCacheAsync()** (with shared generation and session guard): WebSocket events (channel_create, channel_delete, server_create, server_delete, server_update, etc.), **and** API-success paths such as joinServer, create server (AddServerSheet), join via invite (ViewInvite), create channel (ChannelCategoryCreateView). Document these in the checklist.

### 0.37 Channel ID duplication guard on all append paths

**Issue:** Append-only behaviour can create duplicate channel IDs in server.channels (and category.channels); persisted cache and UI can then show duplicate channels and unstable ordering. Duplicate guard is required on **all** paths that append to server.channels, not only WebSocket channel_create.

**Mitigation:** Before **any** append of a channel id to `servers[serverId].channels` (or to a category's channels), **check that the id is not already present**; if present, do not append (treat as idempotent or update the channel object only). This applies to: WebSocket **channel_create**, **joinServer** (when merging response.channels into server), **create server** / **join invite** (when adding response channels), and **create channel** API success (ChannelCategoryCreateView etc.). Document in the implementation checklist.

---

## 1. Current Behaviour: How Channels Load in a Server

### 1.1 Source of truth

- **Ready event** (WebSocket): On connect, the backend sends a single `ReadyEvent` containing `servers`, `channels`, `users`, `members`, `emojis`.
- **Servers**: Each `Server` has `channels: [String]` (ordered channel IDs) and `categories: [Category]?` (each `Category` has `id`, `title`, `channels: [String]`).
- **Channels**: The event includes a flat list of `Channel` (DM, group DM, text, voice, etc.). Text/voice channels reference a server via `server` (server ID).

**Relevant files:**

| Location | Purpose |
|----------|--------|
| `Revolt/ViewState+Extensions/ViewState+ReadyEvent.swift` | `extractNeededDataFromReadyEvent`, `processReadyData` – process Ready and populate servers + channels. |
| `Revolt/ViewState.swift` | `allEventChannels`, `loadedServerChannels`, `loadServerChannels(serverId:)`, `unloadServerChannels(serverId:)`. |
| `Types/Server.swift` | `Server` (`.channels`, `.categories`), `Category`. |

### 1.2 Lazy loading of server channels

- **allEventChannels** (`ViewState`): Holds *all* channels from the Ready event. DMs and group DMs are also pushed into `channels` and `channelMessages` immediately; **server** (text/voice) channels are only stored in `allEventChannels`.
- When the user **selects a server**, `selectServer(withId:)` (in `ViewState+Navigation.swift`) calls `loadServerChannels(serverId:)`, which:
  - Filters `allEventChannels` for that server’s text/voice channels.
  - Adds them to `channels` and creates `channelMessages[channel.id] = []` for text channels.
  - Marks the server in `loadedServerChannels`.
- When the user **leaves the server** (e.g. switches to DMs or Discover), `unloadServerChannels(serverId:)` removes that server’s channels from `channels` and `channelMessages` and from `loadedServerChannels`.

So: **channel list for a server** comes from `allEventChannels` (and ordering/categories from `servers[serverId]`). There is **no disk cache** for this today; it is refetched on every new session via the Ready event.

### 1.3 Where the channel list is shown

- **ServerChannelScrollView** and related UI use `server.channels` and `server.categories` plus `viewState.channels[id]` (or `allEventChannels[id]`) to resolve channel details.
- **MessageBox**, **Contents**, **RevoltApp** navigation, etc. resolve channels via `viewState.channels` or `viewState.allEventChannels`.

### 1.4 Real-time updates today

- **channel_create** (ViewState+WebSocketEvents): Adds the channel to `allEventChannels`; for server channels, appends to `servers[serverId]?.channels` and, if that server is selected, adds to `channels` and `channelMessages`.
- **channel_update**: Updates channel in `channels` / `dms` where present; **allEventChannels** is not updated in the current code (gap to fix for consistency).
- **channel_delete**: Calls `deleteChannel(channelId:)`. That only removes from `channels` and `dms`; it does **not** remove from `allEventChannels` or from `servers[serverId].channels` (gap to fix so UI and cache stay consistent).

### 1.5 Boot and persistence today

- **ViewState init** (`Revolt/ViewState.swift`): Loads **servers** from disk via `ViewState.loadServersCacheSync()` into `servers` (so at launch we have `Server` objects with `.channels` and `.categories`). Channels and `allEventChannels` are **not** loaded from disk; they are empty until the Ready event.
- **After Ready**: `processReadyData` updates servers, saves them with `saveServersCacheAsync()` (ViewState+ServerCache), and fills `allEventChannels` from the event (then DMs are also put into `channels`). **extractNeededDataFromReadyEvent** clears `allEventChannels` and repopulates it from `event.channels` (see §0.17).
- **destroyCache()** (ViewState+Auth): Clears in-memory state (including `servers`, `channels`, etc.) and clears the **membership** cache file. It does **not** currently clear **allEventChannels** or **loadedServerChannels** (gap; see §0.9, §0.14), and it does **not** delete the **servers** cache file, so server topology can leak across accounts (see §0.20).

---

## 2. What Must Not Change (Message Cache and Core Messaging)

- **Message cache**: No changes to `MessageCacheManager`, `MessageCacheWriter`, or any SQLite message/channel_info tables. Channel list cache is **separate** from message cache.
- **Message loading**: How messages are loaded (cache, API, ViewState) is unchanged.
- **DMs and messageable channels**: All existing behaviour for DMs and server channels regarding message loading, drafts, replies, and WebSocket message events remains as-is.
- **Core flows**: Send message, queue message, offline/online behaviour, and message UI stay unchanged.

Only **channel list** data (which channels exist in each server and their categories) is cached and cleared as described below; **message content** continues to use the existing message cache only.

---

## 3. Goals for the Channel Cache

1. **When the user “joins” a server** (i.e. when we have authoritative channel data for that server – from Ready or from real-time events): persist that server’s **channel list** (Channel objects for text/voice) and **category names** (already on `Server.categories`) so we can show the list from cache next time.
2. **Real-time**: When the server owner (or anyone with permission) adds, updates, or deletes a channel, the UI and the **in-memory** state (e.g. `allEventChannels`, `servers[serverId].channels`) stay in sync, and the **channel cache** is updated so the persisted snapshot is up to date.
3. **User-specific and safe**: On **logout** or **invalid session**, clear the channel cache so the next user (or same user on a new session) does not see the previous user’s channel list. Prefer one cache file per account (e.g. keyed by `userId` + `baseURL`) so that on a single device, User A’s cache is cleared on sign-out and User B’s cache is written when they connect.
4. **Already logged-in user**: If the app has a valid session but the channel cache is missing or empty (e.g. first time after this feature, or cache was cleared), populate the cache as soon as we have channel data (Ready or after loading a server’s channels).

---

## 4. Scope and Constraints

### 4.1 What we are caching

- **Per server**: The list of **Channel** objects that belong to that server (text and voice channels only; not DMs). Plus category information: this is already part of `Server` (`.categories`), and the servers cache already persists `Server` (including categories). The **new** persistence is the **Channel** objects per server so that **when a read path exists** (Option B or load-at-launch) we can restore `allEventChannels` for server channels on launch; with Option A the cache is only written, not read (§0.1, §0.32).
- **Categories**: Category names and structure live on `Server.categories`. They are already persisted with the servers cache. When we add a channel cache, we will persist channel lists per server; we do **not** need a separate “categories only” cache – we rely on `Server` in the servers cache and merge with the channel cache as below.

### 4.2 When we write the cache

- **After Ready**: For each server in the Ready payload, we have its channels in `allEventChannels`. Persist per-server channel lists and call `saveServersCacheAsync()` so server cache (including `.channels` and `.categories`) is persisted too.
- **After real-time events**: After applying channel_create, channel_update, channel_delete, server_create, server_delete, server_update (when channels/categories change), joinServer, or removeServer to in-memory state, update the channel cache and call `saveServersCacheAsync()` (see §0.4, §0.5). Writes go through a single serialized path with session guard (see §0.3).

### 4.3 When we read the cache

- **Option A (current plan):** With Option A, **do not read** channel cache anywhere: not at init, not in processReadyData (§0.1, §0.17, §0.32). The channel cache is **write-only** until Option B or another read path is implemented. At the **end** of processReadyData we only **save** channel cache (and server cache) so a future read path can use it.
- **Avoid contradiction:** Do **not** state “read in processReadyData” when Option A is in effect. Any “load channel cache” step applies **only** when Option B (or load-at-launch) is implemented.
- **If Option B is implemented:** Load channel cache inside processReadyData only after we have `servers` and identity, pre-fill `allEventChannels` (filtered by §0.6, with integrity checks per §0.27), then replace with Ready channel data and save.
- **Already logged-in user**: After Ready, save so future launches can use the cache (schema version, corruption handling §0.22; dual-file version §0.26).

### 4.4 When we clear the cache

- **signOut()**: Clear the channel cache **at the very start** of `signOut()`, **before** any `await` or network call, so cleanup runs even if signOut returns failure (e.g. invalid_session path). Use current `userId` and `baseURL` if available; if nil, clear all channel cache files (see §0.2, §0.11).
- **destroyCache()**: At the start of `destroyCache()`, clear the channel cache (same as above). **Explicitly** clear in-memory **allEventChannels** and **loadedServerChannels** so no lazy-load state leaks across relogin (see §0.9, §0.14). Clear the **servers** cache file (or current account’s file if user-keyed) so server topology does not leak (see §0.20). Cancel pending server and channel cache saves and invalidate session (see §0.21).
- **Invalid session**: Relies on signOut() being called; because clear runs at the start of signOut(), invalid session still clears the cache even when the signOut network call fails.

---

## 5. Storage Design

### 5.1 Where to store

- **Separate from message cache**: No SQLite, no MessageCacheManager/MessageCacheWriter. Use a **file** (e.g. JSON) in Application Support, similar to `ViewState+ServerCache.swift` and `ViewState+MembershipCache.swift`.
- **User-specific or single file**: Either:
  - **User-keyed file**: Use a **canonicalized then sanitized** key. **Canonicalize** baseURL first (e.g. lowercase host, strip trailing slash, single scheme) so equivalent URLs map to the same file (§0.31). Then **sanitize** for path safety: do not use raw baseURL (§0.7). Use e.g. `channels_cache_\(userId)_\(sanitizedCanonicalBaseURL).json`.
  - **Single file** (e.g. `channels_cache.json`): **High-risk for account switches** (§0.7): strict write-cancellation and session/generation checks are **mandatory**; otherwise async writes from User A can overwrite after logout and leak into User B. Prefer user-keyed files. If using a single file, clear it at start of signOut/destroyCache and cancel all pending writes.

### 5.2 Shape of data

- **Per server**: Store the list of `Channel` (text/voice) for that server. Categories are already on `Server` in the servers cache. Shape: a wrapper with **cacheSchemaVersion** (see §0.22, §0.28) and **shared generation** (see §0.26); plus `[String: [Channel]]` — `serverId -> [Channel]` (only text/voice; each channel’s `server` must equal the key per §0.27).
- **Integrity (§0.27):** On write, only put a channel under the key matching its `serverId`. On read, validate `channel.server == serverId` for each entry; reject duplicates across servers and within a server’s array.
- **Encoding**: Reuse existing `Channel` Codable. Ensure only encodable channel types are stored (text, voice); exclude DM and group DM.
- **Version and corruption (§0.22, §0.28):** Define a version constant; on load, if version missing/unsupported or decode throws, clear/remove file and continue without cache.

### 5.3 Who owns the API

- **ViewState** is the single source of truth for app state and already has server cache and membership cache in extensions. Add a **ViewState+ChannelCache.swift** (or similar) with:
  - `static func channelCacheURL(userId: String?, baseURL: String?) -> URL?` — if using user-keyed files, **canonicalize** then sanitize baseURL (§0.31, §0.7); if either is nil, return nil or use “clear all” convention.
  - `static func loadChannelCacheSync(userId: String, baseURL: String) -> [String: [Channel]]` — returns serverId → list of Channel; validate integrity per §0.27. **With Option A** this is not called; only used when Option B or another read path is implemented.
  - **Serialized save**: `func saveChannelCacheAsync()` — enqueue a single save on a serialized queue/work item. Before writing, check a **session token** (e.g. current userId + baseURL); if it no longer matches (e.g. after logout), skip the write. Cancel pending save when clearing (see §0.3).
  - `static func clearChannelCacheFile(userId: String?, baseURL: String?)` — if both are non-nil, remove the file for that account; if either is nil, remove **all** channel cache files in Application Support (e.g. all `channels_cache*.json`) so no stale file remains (see §0.11).

---

## 6. Real-Time Consistency (In-Memory and Cache)

All of the following must also call **saveServersCacheAsync()** after updating in-memory state so server cache and channel cache stay in sync (see §0.4). Use a **serialized** channel cache save with **session guard** (see §0.3).

1. **channel_create**: Add to `allEventChannels`. Append to `servers[serverId].channels` (and to category if applicable) **only if the id is not already present** to avoid duplicates (see §0.12, §0.15). Then enqueue channel cache save and saveServersCacheAsync().
2. **channel_update**: Update **allEventChannels**[e.id] for **all** server channel types (text and voice); if the channel is also in `channels` (loaded), update there and in `dms` as today. Apply the same field updates for voice channels as for text where applicable (see §0.16). Then enqueue channel cache save (and saveServersCacheAsync() if server metadata changed).
3. **channel_delete** / **deleteChannel(channelId:)**: **First** resolve the channel from `allEventChannels[id]` or `channels[id]` and read **serverId** and category membership. **Then** synchronously: remove id from **servers[serverId].channels** and **servers[serverId].categories?[].channels**; remove from **allEventChannels**; remove from **channelMessages**, **unreads**, and **preloadedChannels** (§0.34). **Do not** sync-remove from **channels**/ **dms**—keep the **delayed** block for channels, dms, path (UI only) (§0.33). Enqueue channel cache save and saveServersCacheAsync(). Never remove the channel object before capturing server/category membership (§0.18).
4. **server_create**: Add **each** channel in the event to **allEventChannels** (§0.35); add server to `servers`; guard duplicate ids (§0.37); then save channel cache and server cache (§0.5).
5. **server_delete**: **Full purge** (§0.30): remove that server's channel ids from **channels**, **channelMessages**, **unreads**, **preloadedChannels**, **allEventChannels**; remove server from `servers`, channel cache, **loadedServerChannels**; validate currentChannel; then save both caches.
6. **server_update**: When `e.data?.channels` or `e.data?.categories` are present, update `servers[e.id]`; remove from **allEventChannels** any channel ids no longer in `server.channels`; **prune** those ids from **channels**, **channelMessages**, **unreads**, **preloadedChannels**; validate currentChannel; then save both caches.
7. **joinServer**: After adding `response.server` and `response.channels`, add **each** response channel to **allEventChannels** (§0.35); append to server.channels only if id not already present (§0.37); then save channel cache and server cache (§0.36).
8. **removeServer(with:)**: **Full purge** (§0.30): remove that server's channel ids from **channels**, **channelMessages**, **unreads**, **preloadedChannels**, **allEventChannels**; remove server from `servers`, channel cache, **loadedServerChannels**; validate currentChannel; then save both caches.
9. **Local API-success paths** (§0.35, §0.36): When **create server** (AddServerSheet), **join via invite** (ViewInvite), or **create channel** (ChannelCategoryCreateView) succeeds, add the new channel(s) to **allEventChannels**, update **servers** (append only if id not present; §0.37), and call **saveChannelCacheAsync()** and **saveServersCacheAsync()**.

10. **Message events** (e.g. new message): When a message event updates channel state (e.g. last_message_id), if the channel is a server channel, **also** update **allEventChannels**[channelId] with the new metadata (§0.25).

**Dual-file writes:** Use a **shared generation/version** in both channel and server cache payloads; on load, if generations differ or one file missing, discard both (§0.26). No change to core message handling (send, queue, display).

---

## 7. Load and Merge Strategy

### 7.1 No load at init; save at end of Ready (Option A)

**Decision:** Option A = write-only; **no** restore on launch. If launch restore is required, use Option B (or another concrete read path) and implement it; see Pre-implementation decision above.

1. **Do not** load channel cache in ViewState init; with Option A, **do not read** channel cache anywhere (§0.1, §0.32)—cache is write-only until Option B or another read path exists.
2. **Current pipeline (§0.17):** extractNeededDataFromReadyEvent clears and repopulates `allEventChannels` from the event; processChannelsFromData is called with **neededChannels** (DMs only), so **server** channels in `channels` are never replaced and can stay stale (§0.23). At the **end** of **processReadyData**:
   - **Authoritative prune (§0.23, §0.34):** Remove from **channels**, **channelMessages**, **unreads**, and **preloadedChannels** any server channel id not in the authoritative set (not in `allEventChannels` or not in any `servers[serverId].channels`). This makes Ready truly authoritative and clears stale badge/unread state.
   - **Validate currentChannel (§0.24):** If `currentChannel` is `.channel(id)` and that id is no longer in `allEventChannels` or in any server.channels, clear path and set currentChannel to a safe value (e.g. first channel of current server or `.noChannel`/`.home`).
   - **Reset loadedServerChannels** and, if current selection is a server, call **loadServerChannels(serverId:)** so `channels` is repopulated from fresh `allEventChannels`.
   - Call **saveChannelCacheAsync()** and **saveServersCacheAsync()** with **shared generation** (session-guarded) per §0.26.
3. **If Option B is later implemented:** Reorder so we have `servers` and identity first, load channel cache (filtered and validated per §0.6, §0.27), replace with Ready channel data, then prune, validate currentChannel, reset loadedServerChannels, re-load current server, then save.

### 7.2 Cache scope, Option A write-only, and corruption

- With Option A, the channel cache is **write-only**: we do not read it anywhere; it is written at the end of Ready for a **future** read path (Option B or load-at-launch) only (§0.32).
- On load (when a read path exists), validate integrity (§0.27); if channel and server cache generations differ or one file is missing, discard both (§0.26). If decode fails or version is unsupported, clear/remove file(s) and continue without cache (§0.22, §0.28).

---

## 8. Clear on Logout / Invalid Session

- **signOut()** (ViewState+Auth): Clear the channel cache **at the very start** of `signOut()`, **before** any `await` or network call. Call `ViewState.clearChannelCacheFile(userId: currentUser?.id, baseURL: baseURL)`; if either is nil, call with nil so **all** channel cache files are removed (see §0.2, §0.11). Cancel any pending channel cache save work item and invalidate the session token so no write runs after clear. Then run the rest of signOut (network, clearAllDraftsForCurrentAccount, state = .signedOut). This way invalid_session → signOut() still clears cache even when signOut returns .failure.
- **destroyCache()**: At the start of `destroyCache()`, clear the channel cache (same API: current identity or nil). Explicitly clear **allEventChannels** and **loadedServerChannels** (see §0.9, §0.14). Clear the servers cache file (§0.20). Cancel pending channel and server cache saves and invalidate session (§0.21). Then proceed with the rest of destroyCache.

---

## 9. Documented Code Changes (Checklist)

### 9.1 New file

| File | Purpose |
|------|--------|
| `Revolt/ViewState+Extensions/ViewState+ChannelCache.swift` | Channel cache URL (sanitize baseURL or single file), `loadChannelCacheSync`, serialized `saveChannelCacheAsync` with session token check and cancel support, `clearChannelCacheFile(userId:baseURL:)` with nil = clear all. Include **cacheSchemaVersion** in payload; on load, if version missing/unsupported or decode fails, clear/remove file and continue (§0.22). |

### 9.2 ViewState.swift

| Change | Purpose |
|--------|--------|
| Add `channelCacheSaveWorkItem` (or single queue) and a session token (e.g. `channelCacheSessionToken: (userId, baseURL)?`). When enqueueing save, capture token; when save runs, if token != current session, skip write. Cancel work item and set token to nil when clearing (§0.3). | Serialized writer; no stale overwrite or write after logout. |
| In **destroyCache()** (or ViewState+Auth): explicitly clear **allEventChannels** and **loadedServerChannels** so no lazy-load state leaks across relogin (§0.9, §0.14). | Lazy-load state reset. |

### 9.3 ViewState+ReadyEvent.swift

| Change | Purpose |
|--------|--------|
| **Do not** load channel cache in ViewState init or in processReadyData when using Option A (§0.1, §0.17, §0.32). | Cache is write-only with Option A. |
| At **end** of **processReadyData**: (1) **Authoritative prune (§0.23, §0.34):** Remove from **channels**, **channelMessages**, **unreads**, **preloadedChannels** any server channel id not in authoritative set. (2) **Validate currentChannel (§0.24).** (3) **Reset loadedServerChannels**; if current selection is a server, call **loadServerChannels(serverId:)**. (4) Call **saveChannelCacheAsync()** and **saveServersCacheAsync()** with **shared generation** (session-guarded) (§0.26). | Ready authoritative; no stale refs or badge state; cache saved. |

### 9.4 ViewState+Auth.swift

| Change | Purpose |
|--------|--------|
| At the **very start** of **signOut()**, before any `await`: call `ViewState.clearChannelCacheFile(userId: currentUser?.id, baseURL: baseURL)` (nil = clear all). Cancel pending channel cache save and invalidate session token (§0.2). | Cache cleared even when signOut fails. |
| At the start of **destroyCache()**: same clear (identity or nil). Explicitly clear **allEventChannels** and **loadedServerChannels** (§0.14). **Clear the servers cache file** (e.g. `ViewState.clearServersCacheFile()`) so server topology does not leak (§0.20). Cancel pending **channel and server** cache saves and invalidate session (§0.21). | Full clear; no cross-account server/channel leak. |

### 9.5 ViewState init (ViewState.swift)

| Change | Purpose |
|--------|--------|
| **Do not** load channel cache in init. With **Option A**, channel cache is not read anywhere (§0.1, §0.32). | No load with stale identity; Option A = write-only. |

### 9.6 ViewState+WebSocketEvents.swift

| Change | Purpose |
|--------|--------|
| **channel_create**: Append to `servers[serverId].channels` (and category if applicable) **only if id not already present** (§0.12, §0.15). Enqueue channel cache save and saveServersCacheAsync(). | No duplicate ids. |
| **channel_update**: Update **allEventChannels**[e.id] for **all** server channel types (text and voice); if in `channels`, update there and `dms`. Apply same field updates for voice as for text where applicable (§0.16). Enqueue channel cache save (and saveServersCacheAsync() if needed). | Cache correctness for unloaded and voice. |
| **channel_delete**: **First** resolve channel to get **serverId** and category. **Then** synchronously: remove id from **servers[serverId].channels** and categories; remove from **allEventChannels**; remove from **channelMessages**, **unreads**, and **preloadedChannels** (§0.34). **Do not** sync-remove from **channels**/ **dms**—keep the existing **delayed** block for channels, dms, path (UI only) (§0.18, §0.33). Enqueue save. | Cache/server graph and per-channel state correct; no orphaned channelMessages; UI delay only for channels/dms. |
| **server_create**: Add **each** channel in the event to **allEventChannels** (§0.35); guard duplicate ids in server.channels (§0.37); save channel cache and server cache (§0.5). | Lazy-load and cache have new channels. |
| **server_delete**: **Full purge (§0.30):** For every channel id in that server’s `server.channels`, remove from **channels**, **channelMessages**, **unreads**, **preloadedChannels**, and **allEventChannels**. Remove server from `servers`, channel cache, **loadedServerChannels**. Validate **currentChannel** (redirect if on a removed channel). Save both caches. | No orphaned cache or runtime state. |
| **server_update**: When `e.data?.channels` or `e.data?.categories` are present, update server; remove from **allEventChannels** any channel ids no longer in `server.channels`; **prune** those ids from **channels**, **channelMessages**, **unreads**, **preloadedChannels**; validate **currentChannel** (§0.24, §0.34). Save both caches. | Category/channel reorder; no stale loaded or badge state. |
| **Message events**: When a message event updates channel metadata (e.g. last_message_id), update **allEventChannels**[channelId] for server channels so unread/badge and cache stay correct (§0.25). | Unread/badge and persisted cache correctness. |

### 9.7 ViewState.swift – deleteChannel(channelId:)

| Change | Purpose |
|--------|--------|
| **First** resolve channel to get **serverId** and category. **Then** synchronously: remove id from `servers[serverId]?.channels` and categories; remove from **allEventChannels**; remove from **channelMessages**, **unreads**, and **preloadedChannels** (§0.34). Enqueue save. Keep **delayed** block for **channels**, **dms**, **path** only (UI; do not sync-remove from channels/dms) (§0.8, §0.18, §0.33). | Cache and per-channel state correct; no orphaned channelMessages; UI delay only for channels/dms. |

### 9.8 ViewState+DMChannel.swift – removeChannel(with:initPath:)

| Change | Purpose |
|--------|--------|
| If server channel: **first** resolve serverId/category; **then** synchronously remove id from **servers[serverId].channels** and categories, from **allEventChannels**, and from **channelMessages**, **unreads**, and **preloadedChannels** (§0.34). Enqueue save. Keep delayed block for **channels**, **dms**, **path**, **selectDms()** (UI only) (§0.8, §0.18, §0.33). | Same as deleteChannel; no orphaned channelMessages. |

### 9.9 ViewState.swift – joinServer(code:)

| Change | Purpose |
|--------|--------|
| After adding `response.server` and `response.channels`, add **each** response channel to **allEventChannels** (§0.35); append to server.channels only if id not already present (§0.37). Call save (§0.5, §0.36). | New server cached; lazy-load and cache correct. |

### 9.10 ViewState+DMChannel.swift – removeServer(with:)

| Change | Purpose |
|--------|--------|
| **Full purge (§0.30):** For every channel id in that server’s channels, remove from **channels**, **channelMessages**, **unreads**, **preloadedChannels**, **allEventChannels**. Remove server from `servers`, channel cache, **loadedServerChannels**. Validate **currentChannel**. Call save (§0.5). | Leave server = full runtime cleanup. |

### 9.11 Local API-success paths (ViewInvite, AddServerSheet, ChannelCategoryCreateView)

| Change | Purpose |
|--------|--------|
| When **create server** (AddServerSheet) or **join via invite** (ViewInvite) succeeds: add returned channel(s) to **allEventChannels**; update **servers**; append to server.channels **only if id not already present** (§0.37). Call **saveChannelCacheAsync()** and **saveServersCacheAsync()** (§0.35, §0.36). | Cache and lazy-load get new channels; no stale cache if app exits before WebSocket. |
| When **create channel** (ChannelCategoryCreateView) succeeds: add new channel to **allEventChannels**; append to servers[serverId].channels **only if id not already present** (§0.37). Call save (§0.35, §0.36). | Same. |

### 9.12 Servers cache (ViewState+ServerCache or ViewState+Auth)

| Change | Purpose |
|--------|--------|
| Add **clearServersCacheFile()** (or equivalent). Call from **signOut()** (at start) and **destroyCache()** so server topology does not leak across accounts (§0.20). | User B does not see User A’s servers at startup. |
| Apply **session guard and cancel** to **saveServersCacheAsync()**: same pattern as channel cache—session token, skip write if session invalid, cancel pending save on clear (§0.21). | No stale server cache write after logout. |

### 9.13 No changes to

- `Revolt/1Storage/MessageCacheManager.swift`
- `Revolt/1Storage/MessageCacheWriter.swift`
- Message send/queue flow, MessageInputHandler, RepliesManager, MessageContentsView
- Draft storage (ViewState+Drafts) other than ensuring clear order in destroyCache/signOut

---

## 10. Summary Table

| Topic | What | Why |
|-------|------|-----|
| **What we cache** | Per-server list of Channel (text/voice); server cache holds Server.channels and .categories. Both caches written together. | Show channel list + category names; UI uses server.channels/categories. |
| **When we write** | After Ready; after channel_* / server_* / joinServer / removeServer. Serialized save with session guard. | Keep cache in sync; no race or write after logout (§0.3, §0.4, §0.5). |
| **When we read** | **Option A:** Do **not** read channel cache anywhere; cache is write-only (§0.32). **Option B:** Read in processReadyData after identity/servers, with filter and integrity (§0.6, §0.27). | No wrong-user load; no spec contradiction. |
| **When we clear** | At **start** of signOut() (before await) and at start of destroyCache(); clear channel **and servers** cache files; support nil identity = clear all (§0.2, §0.11, §0.20). Explicitly clear allEventChannels and loadedServerChannels (§0.14). | No cross-user leakage; no lazy-load state leak. |
| **Real-time** | Update allEventChannels + servers[].channels/categories; **message events** update allEventChannels for server channels (§0.25); resolve server/category **before** removing channel on delete (§0.18); no duplicate ids (§0.15); channel_update all types (§0.16); save both caches with session guard and **shared generation** (§0.8, §0.21, §0.26). Delete: sync removal for cache correctness; delayed removal for UI only (§0.33). | Unread/badge and cache correct; dual-file consistent. |
| **Ready** | **Authoritative prune** of channels/channelMessages for server channels not in Ready (§0.23); **validate currentChannel** (§0.24); reset loadedServerChannels and re-load current server; save with shared generation (§0.13, §0.17, §0.26). | Ready truly authoritative; no stale loaded state. |
| **Cache file** | **Mandatory** shared generation in both files (§0.26); schema version and migration strategy (§0.22, §0.28); integrity constraints on write/read (§0.27); baseURL **canonicalize** then sanitize (§0.31); servers cache cleared and session-guarded (§0.20, §0.21). | Deterministic restore; no partial-write or cross-server corruption. |
| **server_delete / removeServer** | **Full purge:** channels, channelMessages, unreads, preloadedChannels, allEventChannels for that server; then servers, cache, loadedServerChannels; validate currentChannel (§0.30). | No orphaned runtime state. |
| **Message cache** | No changes | Channels and DMs keep using existing message cache only. |

This plan keeps all core functionality and messaging behaviour unchanged and adds a dedicated, user-scoped channel list cache that is updated in real time and cleared on logout or invalid session. All critical issues in §0 (including §0.13–§0.37) are addressed. With Option A, the cache is write-only and **not** restored on launch until Option B or another read path is implemented (§0.32). **If launch restore is required for the current release, lock in Option B (or another concrete read path) before implementation** (Pre-implementation decision). Delete semantics are consistent: sync removal from allEventChannels, server graph, unreads, preloadedChannels; delayed removal only for channels, dms, path (UI) (§0.33, §0.34).

---

## 11. Implementation Log

This section documents the code changes made to implement the plan (Option A: write-only cache). All references are to Channel.md sections.

### 11.1 New file: `Revolt/ViewState+Extensions/ViewState+ChannelCache.swift`

| What | Details |
|------|--------|
| **channelCacheURL(userId:baseURL:)** | Returns file URL for user-keyed cache; canonicalizes then sanitizes baseURL (§0.7, §0.31). Nil if identity incomplete. |
| **loadChannelCacheSync(userId:baseURL:)** | Decodes payload; validates schema version; filters by channel.server == serverId (§0.27). Not called with Option A (§0.32). |
| **saveChannelCacheAsync()** | Captures session token and snapshots on main; work item runs after 0.5s, checks token, builds payload from allEventChannels (per server), encodes and writes on background queue. Single work item; cancel on clear (§0.3). |
| **clearChannelCacheFile(userId:baseURL:)** | Removes file for (userId, baseURL); if either nil, removes all `channels_cache_*.json` in Application Support (§0.11). |
| **Payload** | `ChannelCachePayload`: cacheSchemaVersion = 2, generation string, `[String: [Channel]]` (serverId → text/voice channels only). |

### 11.2 `Revolt/ViewState.swift`

| Change | Purpose |
|--------|--------|
| **channelCacheSaveWorkItem**, **channelCacheSessionToken** | Serialized save and session guard (§0.3). Token is computed from currentUser?.id and baseURL. |
| **deleteChannel(channelId:)** | Resolve channel from allEventChannels/channels for serverId; sync-remove from servers[serverId].channels and categories, allEventChannels, channelMessages, unreads, preloadedChannels; call saveChannelCacheAsync + saveServersCacheAsync; keep delayed block (0.75s) for channels, dms, path only (§0.8, §0.18, §0.33, §0.34, §9.7). |
| **joinServer(code:)** | Add each response channel to allEventChannels; set servers[response.server.id] = response.server; call saveChannelCacheAsync + saveServersCacheAsync (§0.35, §0.36, §9.9). |

### 11.3 `Revolt/ViewState+Extensions/ViewState+Auth.swift`

| Change | Purpose |
|--------|--------|
| **signOut()** | At the very start (before any await): ViewState.clearChannelCacheFile(userId: currentUser?.id, baseURL: baseURL); channelCacheSaveWorkItem?.cancel(); channelCacheSaveWorkItem = nil (§0.2, §9.4). |
| **destroyCache()** | At start: clearChannelCacheFile (identity or nil); cancel channelCacheSaveWorkItem; ViewState.clearServersCacheFile(); then existing clears; explicitly allEventChannels.removeAll(), loadedServerChannels.removeAll() (§0.9, §0.14, §0.20, §9.4). |

### 11.4 `Revolt/ViewState+Extensions/ViewState+ServerCache.swift`

| Change | Purpose |
|--------|--------|
| **clearServersCacheFile()** | Static; removes servers_cache.json. Called from destroyCache and (if desired) signOut (§0.20, §9.12). |

### 11.5 `Revolt/ViewState+Extensions/ViewState+ReadyEvent.swift`

| Change | Purpose |
|--------|--------|
| **End of processReadyData** | After processReadySpan.finish: (1) Authoritative prune: build authoritativeServerChannelIds from servers.values.flatMap(\.channels); remove from channels, channelMessages, unreads, preloadedChannels any server channel id not in that set. (2) Validate currentChannel: if .channel(id) and id not in authoritative set, clear path and set currentChannel to .home or first channel of current server. (3) loadedServerChannels.removeAll(); if current selection is server, loadServerChannels(serverId:). (4) saveChannelCacheAsync(); saveServersCacheAsync() (§0.23, §0.24, §0.34, §7.1, §9.3). |

### 11.6 `Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift`

| Event | Change |
|-------|--------|
| **server_create** | Add each channel to allEventChannels, channels, channelMessages; build server with duplicate guard on channels; saveChannelCacheAsync + saveServersCacheAsync (§0.35, §0.37, §9.6). |
| **server_delete** | Full purge: for each channel id in server.channels remove from channels, channelMessages, unreads, preloadedChannels, allEventChannels; remove loadedServerChannels[e.id]; validate currentChannel; remove server; updateMembershipCache; save both caches; then path/selectDms if selection was that server (§0.30, §9.6). |
| **server_update** | When updating server: compute removedIds = oldChannelIds - newChannelIds; prune those from channels, channelMessages, unreads, preloadedChannels, allEventChannels; validate currentChannel; if e.data?.channels or categories present, save both caches (§0.24, §0.34, §9.6). |
| **channel_create** | allEventChannels[channel.id] = channel (existing). For text/voice: append to servers[serverId].channels only if !server.channels.contains(channel.id) (§0.37). After switch: if channel.server != nil, saveChannelCacheAsync + saveServersCacheAsync. |
| **channel_update** | After updating channels[e.id] (and dms): if channel is server type, set allEventChannels[e.id] = updated channel; save both caches. Added voice_channel branch for updates (§0.16, §9.6). |
| **channel_delete** | Still calls deleteChannel(channelId:) which now does sync purge + save (§9.6). |
| **message** | After updating channels[m.channel] with last_message_id: if allEventChannels[m.channel] is text_channel, update its last_message_id and saveChannelCacheAsync (§0.25). |

### 11.7 `Revolt/ViewState+Extensions/ViewState+DMChannel.swift`

| Change | Purpose |
|--------|--------|
| **removeServer(with:)** | Full purge: for each channel id in server.channels remove from channels, channelMessages, unreads, preloadedChannels, allEventChannels; loadedServerChannels.remove(serverID); validate currentChannel; servers.removeValue; updateMembershipCache; saveChannelCacheAsync + saveServersCacheAsync; selectDms (§0.30, §9.10). |
| **removeChannel(with:initPath:)** | If server channel: resolve serverId from channel; sync-remove from servers[serverId].channels and categories, allEventChannels, channelMessages, unreads, preloadedChannels; saveChannelCacheAsync + saveServersCacheAsync. Keep delayed block (1.5s) for channels, dms; initPath still clears path and selectDms (§0.34, §9.8). |

### 11.8 Local API-success paths

| File | Change |
|------|--------|
| **ViewInvite.swift** | updateServerAndChannels: add each join.channels to allEventChannels, channels, channelMessages; set servers; saveChannelCacheAsync + saveServersCacheAsync. fetchAndProcessMembers: same allEventChannels + servers + save (§0.35, §0.36, §9.11). |
| **AddServerSheet.swift** | On create server success: add each serverChannel.channels to allEventChannels and channels; set servers; saveChannelCacheAsync + saveServersCacheAsync (§9.11). |
| **ChannelCategoryCreateView.swift** | On create channel success: allEventChannels[success.id] = success; channels[success.id] = success; append to servers[server.id].channels only if !contains(success.id); saveChannelCacheAsync + saveServersCacheAsync (§0.37, §9.11). |

### 11.9 Not implemented (optional / follow-up)

- **saveServersCacheAsync()** session guard and cancel (§0.21, §9.12): Plan suggests same pattern as channel cache (session token, skip write if invalid, cancel on clear). Left as fire-and-forget for this pass; clearServersCacheFile() is called so file is removed on logout.
- **Option B (read path)**: loadChannelCacheSync and load in processReadyData are not used; cache remains write-only until Option B or another read path is implemented.

---

## 12. Fixes

### 12.1 Cached channels not shown when opening app from terminated state (launch / offline)

**What really was the issue**

- When the user opens the app from a **terminated state**, the app loads servers from the **servers cache** (e.g. `loadServersCacheSync()`) so the server list appears. Channel list data, however, was **not** read from the channel cache at launch (Option A was write-only). So:
  - **allEventChannels** stayed empty until the **Ready** WebSocket event was received and processed.
  - **loadServerChannels(serverId:)** gets channels by filtering **allEventChannels** for that server. With allEventChannels empty, tapping a server before Ready showed **no channels** even if they had been cached previously.
- In the time between app launch and Ready (fetching/connecting), the user could tap a server and see an empty channel list. With slow or no internet, channels would never appear because Ready never arrives.
- So: **cached channels were not shown** before Ready, and there was **no offline fallback** for the channel list even though the channel cache file existed and was written at the end of Ready.

**What can be fixed**

- **Read the channel cache at launch** when we already have identity (currentUser, baseURL) and servers (from servers cache), and **populate allEventChannels** with cached server channels (filtered by current servers and by server.channels so we only show channels that belong to servers the user is still in). Then:
  - As soon as the user taps a server, **loadServerChannels(serverId:)** will find channels in allEventChannels and show them (from cache).
  - When **Ready** arrives, **extractNeededDataFromReadyEvent** and **processReadyData** clear and repopulate allEventChannels from the event, so the UI is updated with the **latest** data. Fetching and updating remain the source of truth; cache is for instant/offline display.
- **Priority**: Fetching and applying the latest data (Ready) stays the priority; in parallel, showing cached data gives something to show immediately and when offline.

**What was actually done to fix it**

- A **launch-time read path** was added so the channel cache is used for display before Ready (and when offline), while Ready still replaces data authoritatively.

**Code changed**

1. **`Revolt/ViewState.swift` (init)**

   After applying server ordering and before loading emojis, the channel cache is loaded when identity and servers are present, and **allEventChannels** is filled only for channels that belong to a cached server and whose id is in that server’s **channels** array (filter per §0.6):

   ```swift
   // Load channel cache at launch so cached server channels show before Ready (and when offline). Filter by current servers (§0.6); Ready will replace authoritatively.
   if let userId = self.currentUser?.id, let base = self.baseURL, !self.servers.isEmpty {
       let cached = ViewState.loadChannelCacheSync(userId: userId, baseURL: base)
       for (serverId, channelList) in cached {
           guard self.servers[serverId] != nil else { continue }
           let allowedIds = Set(self.servers[serverId]?.channels ?? [])
           for ch in channelList where allowedIds.contains(ch.id) {
               self.allEventChannels[ch.id] = ch
           }
       }
   }
   ```

   - **When**: Only when `currentUser`, `baseURL`, and `servers` are all present (e.g. returning user with servers cache).
   - **Filter**: Only servers that exist in **servers** and only channel IDs that are in **servers[serverId].channels** are added to allEventChannels, so we don’t show channels for left servers or stale IDs.
   - **After Ready**: Existing behaviour unchanged: Ready clears and repopulates allEventChannels (and processReadyData prunes, validates currentChannel, resets loadedServerChannels, and saves caches). So latest data from the server always overwrites the cache-backed pre-fill.

2. **No change** to:
   - **ViewState+ChannelCache.swift**: `loadChannelCacheSync` was already implemented for Option B; it is now used at init when identity and servers are available.
   - **ViewState+ReadyEvent.swift**: Ready still replaces allEventChannels and runs authoritative prune and save; no change.
   - **loadServerChannels(serverId:)**: Still reads from allEventChannels; it now sees cache-backed data when the user taps a server before Ready or when offline.

**Result**

- Opening the app from a terminated state: if the user has cached servers and channel cache, tapping a server **shows cached channels** immediately while the app fetches data. When Ready is processed, channel lists are updated with the latest data.
- Offline (or before Ready): Cached channels for cached servers are shown so the user has something to see instead of an empty list.

### 12.2 Memory limit crash (EXC_RESOURCE RESOURCE_TYPE_MEMORY) when offline in cached channel

**What really was the issue**

- With **internet off**, the user could open a **cached server** → open the **last cached server** → open a **channel** and see **cached messages**. After **scrolling a bit**, the app crashed with:
  - `EXC_RESOURCE (RESOURCE_TYPE_MEMORY: high watermark memory limit exceeded) (limit=3072 MB)`
  - Crash location: `ViewState.cleanupUnusedUsersInstant(excludingChannelId:)` at ViewState.swift (e.g. around the loop that removes users).
- **Cause**: When leaving the channel (or when `forceMemoryCleanup()` ran), `cleanupUnusedUsersInstant` was used to drop users that are not needed. It iterated over **every** entry in **channelMessages** (all channels from all servers ever loaded from cache) and for **every** message ID in each channel did a `messages[messageId]` lookup to collect authors/mentions into `usersToKeep`. With many cached servers and large message lists, this meant tens of thousands of iterations and a large temporary working set (big `usersToKeep`, `users.keys.filter` array, and many dictionary mutations). Under already-high memory (cached messages + UI), that pushed the process over the 3 GB limit and the OS killed it.

**What can be fixed**

- **Reduce the scope and size of work** in `cleanupUnusedUsersInstant` so it does not scan the entire cached state in one go:
  - **Scope channels**: When the current selection is a server, only consider channels that belong to **that server** (and the channel being left), not every channel in `channelMessages` (which can include all servers opened from cache).
  - **Cap message scan per channel**: When building `usersToKeep`, only look at the last N message IDs per channel (e.g. 300) so we don’t touch every cached message. That keeps authors for recent messages without scanning the full history.

**What was actually done to fix it**

- **Scoped channels**: If `currentSelection == .server(serverId)`, we only consider channel IDs in `servers[serverId].channels` plus the `excludingChannelId`. Otherwise (e.g. DMs / discover) we still consider all keys in `channelMessages` but the per-channel cap limits total work.
- **Per-channel message cap**: Introduced `cleanupUnusedUsersMessageCapPerChannel = 300`. For each channel we only consider `messageIds.suffix(300)` when collecting authors/mentions into `usersToKeep`.
- This keeps cleanup correct for the current server/channel and recent messages while avoiding the huge scan that caused the memory spike and crash.

**Code changed**

1. **`Revolt/ViewState.swift` – `cleanupUnusedUsersInstant(excludingChannelId:)`**

   - **New constant**: `private static let cleanupUnusedUsersMessageCapPerChannel = 300`.
   - **Channel set**:  
     - If `currentSelection == .server(serverId)` and `servers[serverId]` exists:  
       `channelIdsToConsider = Set(server.channels).union([excludingChannelId])`.  
     - Else:  
       `channelIdsToConsider = Set(channelMessages.keys)` (unchanged for DM/discover).
   - **Iteration**: Loop over `channelIdsToConsider` instead of `channelMessages` directly. For each channel, get `messageIds` from `channelMessages[otherChannelId]`, then use only:
     - `let cappedIds = messageIds.suffix(Self.cleanupUnusedUsersMessageCapPerChannel)`
     - and iterate over `cappedIds` when adding authors/mentions to `usersToKeep`.
   - Rest of the function (servers, members, dms, `usersToRemove`, removal loop, logging) is unchanged.

**Result**

- Under the same scenario (offline → cached server → last cached server → channel → scroll then leave or when force cleanup runs), cleanup runs with bounded work (current server’s channels only when in server view, and at most 300 message IDs per channel). Memory no longer spikes past the limit and the app no longer crashes with `EXC_RESOURCE (RESOURCE_TYPE_MEMORY)` in `cleanupUnusedUsersInstant`.

**Follow-up (crash still seen when leaving channel after scrolling cached messages)**

- Console showed cleanup starting (`VIEWSTATE_INSTANT_CLEANUP: Starting`) then the process was killed with no further logs (no `USER_INSTANT_CLEANUP` / `Completed`), so the crash occurred during `cleanupChannelFromMemory` (either step 2 or step 4).
- **Two additional changes** were made:
  1. **Message removal without full scan** (`ViewState+Memory.swift` – `cleanupChannelFromMemory`): Step 2 no longer uses `messages.keys.filter { message.channel == channelId }`, which iterated the entire `messages` dictionary (thousands of keys) and could allocate a large temporary. It now uses the channel’s own message ID list: `let messageIdsToRemove = channelMessages[channelId] ?? []`, then removes that key from `channelMessages`, then removes each id from `messages`. Work is O(channel size) instead of O(total messages), with a single small array.
  2. **Skip user cleanup when already heavy** (`ViewState+Memory.swift` – `cleanupChannelFromMemory`): Step 4 now calls `cleanupUnusedUsersInstant` only when `initialMessageCount <= 1500`. When we’re already in a heavy state (e.g. many cached messages), the extra scan in `cleanupUnusedUsersInstant` is skipped to avoid pushing the process over the memory limit; unused users are left for a later cleanup or next launch.
- **Result**: Leaving the channel after scrolling cached messages (Server A → Channel A → scroll → back) should no longer trigger an OOM kill during cleanup; message removal is cheap and the heavy user cleanup is skipped when message count is high.

**Follow-up: OOM still on real device when user count is very high**

- **Observed**: On a real iPhone, after scrolling a cached channel and tapping back, the app was still terminated for memory (“Terminated due to memory issue”). Logs showed `VIEWSTATE_INSTANT_CLEANUP: Step0 counts messages=0 users=17474 channelMsg=0` then `Step4 calling cleanupUnusedUsersInstant` with no subsequent “returned” or “Completed” — i.e. the process was killed **inside** `cleanupUnusedUsersInstant`.
- **Cause**: With ~17k users already in memory, `cleanupUnusedUsersInstant` builds large temporaries (`usersToKeep`, `usersToRemove` from `users.keys.filter`) and does heavy work; that allocation spike pushes the process over the device limit and triggers jetsam.
- **Fix**: In `cleanupChannelFromMemory`, step 4 now also requires `initialUserCount <= 2000` before calling `cleanupUnusedUsersInstant`. When user count is already very high (e.g. 17474), we skip the user cleanup entirely on leave; message/channel cleanup still runs. Unused users are left for later cleanup or next launch.
- **Result**: Back navigation after scrolling a cached channel should no longer be killed by the OS when the app is already holding many users.

**Follow-up: OOM in deferred block (ViewState.forceMemoryCleanup + VC forceImmediateMemoryCleanup)**

- **Observed**: After the above fix, logs showed `VIEWSTATE_INSTANT_CLEANUP: Step4 skipping ... initialUsers=17474` and `Completed`, then `FORCE_IMMEDIATE_CLEANUP: Completed` (VC path), then the deferred block ran (`VIEWSTATE_INSTANT_CLEANUP` again, completed), then `FORCE_INSTANT_CLEANUP: Starting` (ViewState.forceMemoryCleanup) and the process was killed with no “Completed”. So the crash moved to **ViewState.forceMemoryCleanup()**, which calls `cleanupUnusedUsersInstant("")` when `users.count > maxUsersInMemory` (step 2). The VC’s **forceImmediateMemoryCleanup()** also does heavy user iteration (building `usersToKeep` from all channelMessages/messages); with 17k users both paths can spike memory.
- **Fix**:
  1. **ViewState+Memory.swift – forceMemoryCleanup()**: Step 2 now calls `cleanupUnusedUsersInstant(excludingChannelId: "")` only when `users.count > maxUsersInMemory` **and** `users.count <= 2000`. When user count is already very high, user-limit enforcement is skipped.
  2. **MessageableChannelViewController+Extensions.swift – forceImmediateMemoryCleanup()**: At the start, after clearing the image cache, if `viewModel.viewState.users.count > 2000` we log and return immediately, skipping the entire “INSTANT_USER_CLEANUP” block (usersToKeep iteration, DM cleanup, etc.). Image cache is still cleared.
- **Result**: Both the synchronous VC cleanup and the deferred ViewState cleanup avoid heavy user work when the app is already holding >2000 users, so back navigation after scrolling a cached channel (offline) should no longer be terminated by the OS.
