# Verified Badge Feature (Username)

This document captures the full iOS implementation history for username verified badges, including model mapping, UI integration points, debugging journey, and final behavior parity with web.

---

## 1. Goal and Product Expectation

The goal was to show a **verified indicator next to the username** in message rows, matching web behavior as closely as possible.

Expected UX (final):

- Show a verified marker only for users with the verified bit.
- Show it beside username (before timestamp) in chat rows.
- Hide it on continuation rows (same behavior as username/time).
- Keep non-verified users unchanged.
- Use **yellow SF Symbol** `checkmark.seal.fill` (not custom image asset) for consistent visual style.

---

## 2. Data Model and Bitfield Mapping

### 2.1 Existing user badge source

- `Types/User.swift` stores `badges: Int?` (bitfield).
- Badge parsing utilities are in `Types/Badges.swift`.

### 2.2 Bit mapping used

In `Types/Badges.swift`:

- `Badges.responsible_disclosure = 8`
- This is the bit currently used for "verified-like" behavior.

### 2.3 Verified check helper

Added/used helper in `Types/User.swift`:

- `hasVerifiedBadge() -> Bool`
- Logic: `(badges & Badges.responsible_disclosure.rawValue) != 0`

This is the canonical gate for whether username verified UI is shown.

> Note: If backend/web later confirms a different verified bit, update this mapping first.

---

## 3. Implementation Locations

### 3.1 UIKit message list (`MessageCell`)

Files:

- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Setup.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Layout.swift`

What was implemented:

- Added a dedicated badge view beside username:
  - `usernameVerifiedBadgeImageView: UIImageView`
  - width constraint that collapses to `0` when hidden (prevents extra spacing).
- In setup:
  - Positioned badge between `usernameLabel` and `timeLabel`.
  - Set tint to yellow for SF Symbol rendering.
- In configure:
  - `showVerified = author.hasVerifiedBadge()`
  - image set to `UIImage(systemName: "checkmark.seal.fill")`
  - visibility + width (`14` when shown, `0` when hidden).
- In continuation layout:
  - Badge hidden when continuation row is active.

### 3.2 SwiftUI message renderer (`MessageView`)

File:

- `Revolt/Components/MessageRenderer/MessageView.swift`

What was implemented:

- In `nameView`, when `viewModel.author.hasVerifiedBadge()` is true, render:
  - `Image(systemName: "checkmark.seal.fill")`
  - yellow foreground
  - small size (`12`) to match dense message header.

---

## 4. Debugging Timeline and Issues Encountered

This section documents all major implementation pivots and fixes made during development.

### 4.1 "All badges" vs "verified-only" requirement mismatch

Initial direction expanded to render all user badges near username.

Issue:

- Product expectation was web parity: show only verified marker next to username.

Fix:

- Reverted to verified-only logic using `hasVerifiedBadge()`.
- Removed multi-badge username rendering path in message rows.

### 4.2 Broken intermediate state in `MessageCell`

During refactor from multi-badge to verified-only, intermediate code had invalid usage patterns (e.g., array/image mismatches and misplaced verified logic in reuse path).

Fix:

- Replaced with a single `UIImageView` approach.
- Ensured reuse cleanup resets badge image/hidden state.
- Rebound verified state strictly in `configure(...)`.

### 4.3 Layout spacing gap when user is not verified

If badge is hidden but still constrained, there can be unnecessary horizontal gap before time label.

Fix:

- Added `usernameVerifiedBadgeWidthConstraint`.
- Width toggles `14` (visible) / `0` (hidden), so `timeLabel` naturally shifts left for non-verified users.

### 4.4 Asset badge vs SF Symbol

Initial verified rendering used a local badge image (`verified`).

Requirement update:

- Use SF Symbol `checkmark.seal.fill` in yellow.

Fix:

- UIKit switched to `UIImage(systemName: "checkmark.seal.fill")` + yellow tint.
- SwiftUI switched to `Image(systemName: "checkmark.seal.fill")` + yellow foreground style.

### 4.5 Build verification constraints in agent environment

Attempted simulator build via CLI hit environment restrictions:

- CoreSimulator service unavailable / sandbox permission limits for cache/log write.

What was still validated:

- File-level static checks and lints for touched files (no lint errors).
- Diff-level verification for intended behavior in relevant files.

---

## 5. Final Behavior (Current)

### Username verified marker

- A yellow `checkmark.seal.fill` appears next to username only when `hasVerifiedBadge() == true`.
- Marker appears in:
  - UIKit message rows (`MessageCell`)
  - SwiftUI message rows (`MessageView`)
- Marker is hidden for continuation rows.
- Marker is not shown for non-verified users and does not leave residual spacing.

### Non-goals in this implementation

- This work does not change global "all badge" surfaces such as profile/user sheet.
- This work does not redefine backend bit mapping semantics.

---

## 6. Source Reference Map

### Badge model and helper

- `Types/Badges.swift`
- `Types/User.swift`

### UIKit message row

- `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Setup.swift`
- `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Layout.swift`

### SwiftUI message row

- `Revolt/Components/MessageRenderer/MessageView.swift`

---

## 7. Maintenance Notes

- If backend verified bit changes, update `hasVerifiedBadge()` logic and retest both UIKit + SwiftUI rows.
- Keep icon size and spacing synchronized between UIKit and SwiftUI for visual consistency.
- If theme system later defines a specific "verified yellow", switch from system yellow to theme token in both paths.

