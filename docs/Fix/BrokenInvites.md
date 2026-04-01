# Broken Invites Fix

## Context

When a user accepts an invite from the Discover server list, there is an edge case where the app navigates to the Home welcome screen instead of a channel or a clear failure state.

This mostly occurs when:

- Discover incorrectly routes user to invite flow (stale membership state),
- `joinServer(code:)` fails because user is already in the server or invite cannot complete,
- fallback logic cannot resolve a valid channel,
- navigation still pushes `.maybeChannelView`.

In that situation, `currentChannel` can still be `.home` (especially from Discover mode), so `.maybeChannelView` renders `HomeWelcome`.

## Root Cause

The previous fallback in `ViewInvite.handleJoinFailure` always performed:

- `selectServer(...)`,
- optional `selectChannel(...)` only if `server.channels.first` exists,
- `path.removeAll()`,
- `path.append(.maybeChannelView)`.

If no channel was selected, navigation still proceeded, and the UI landed on Home.

## Goals of This Fix

1. Do not navigate to `.maybeChannelView` unless a valid channel is available.
2. Provide explicit UX for unknown invite-join failures.
3. Keep invalid/expired invite handling separate from unknown runtime failures.

## Code Changes

All code changes are in:

- `Revolt/Pages/Home/ViewInvite.swift`

### 1) Added unknown-error state

- Added `@State private var showUnknownJoinError: Bool = false`.

This state controls whether the invite page should show the dedicated fallback error UI.

### 2) Added explicit unknown-error UI branch in `body`

- Wrapped existing `switch info` in an outer conditional:
  - If `showUnknownJoinError == true`, render `UnknownInviteJoinErrorView`.
  - Else, continue existing invite rendering (`loading`, `invalid link`, `group`, `server invite`).

### 3) Added reusable helper

- Added:

```swift
@MainActor
private func presentUnknownJoinError() {
    isProcessingInvite = false
    showUnknownJoinError = true
}
```

This centralizes state mutation for unknown failures.

### 4) Updated `handleAcceptInvite` error catch path

- Replaced alert-based behavior in `catch` with:

```swift
presentUnknownJoinError()
```

This ensures unexpected invite accept errors show a dedicated full-screen explanation.

### 5) Hardened `handleJoinFailure` fallback

`handleJoinFailure` now:

1. Selects server by ID.
2. Verifies server exists in `viewState.servers`.
3. Resolves a valid channel ID using:
   - invite channel first (`inviteServerInfo.channel_id`) if present in server channels,
   - otherwise first available server channel.
4. If channel cannot be resolved, presents unknown error view and returns.
5. Only after channel selection succeeds, clears path and pushes `.maybeChannelView`.

Result: navigation no longer proceeds to channel screen without channel context.

### 6) Added new view component

- Added `UnknownInviteJoinErrorView` in `ViewInvite.swift`.
- Copy and feel matches existing invite error card style:
  - title: `"Something went wrong"`
  - body: `"An unknown error occurred. Please try again in some time."`
  - CTA: `"Got it"` (dismisses by clearing path)

## Behavior Before vs After

### Before

- Invite accept fallback could navigate to `.maybeChannelView` without valid selected channel.
- This rendered Home welcome screen unexpectedly.
- User got no clear explanation.

### After

- Navigation to `.maybeChannelView` is gated by successful channel resolution.
- If unresolved, user sees a clear unknown-error screen and can dismiss.
- No misleading redirect to Home for this failure path.

## Testing Notes

Manual scenarios to validate:

1. Discover invite for server where user is already member but join API fails.
   - Expected: unknown-error screen (not Home redirect) if channel cannot be resolved.
2. Valid invite accept with proper server/channel.
   - Expected: still navigates to target channel via `.maybeChannelView`.
3. Invalid or expired invite link.
   - Expected: existing "Link No Longer Valid" screen (unchanged behavior).
4. Decline invite.
   - Expected: existing dismiss path (clear navigation stack).

## Why this is safe

- Scope is isolated to `ViewInvite`.
- No networking contract changes.
- No cache/model/schema changes.
- Default success path remains intact.

## Future Improvements (Optional)

- Add secondary CTA on unknown-error screen:
  - `Try Again` to retry join flow inline.
- Differentiate known API errors (already member, banned, revoked invite) from unknown errors by parsing server error response and showing specific copy.
