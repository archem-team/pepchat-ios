# Test Cases Guide for AI Agents — Revolt (pepchat-ios)

This document defines how AI agents must derive and write test cases for the Revolt iOS app (pepchat-ios). When the user instructs you to prepare test cases (for a feature, flow, or area), **use this file as the rules and template** for generating those test cases.

Use **AGENTS.md** at the repo root to navigate the codebase (project structure, architecture, state management, testing guidelines, and code organization).

---

## Purpose

- **For:** AI agents generating manual or automated test cases for Revolt (pepchat-ios).
- **Goal:** Produce test cases that are user-centric, step-by-step, and include expected outcomes and edge-case coverage aligned with the app’s features and architecture.

---

## Project Context

- **App:** Revolt — iOS chat app (Swift/SwiftUI + UIKit where needed). Main code: `Revolt/`, shared types: `Types/`, tests: `RevoltTests/`, `RevoltUITests/`, `Tests/`.
- **Testing:** XCTest. Unit/UI tests live in `RevoltTests/`, `RevoltUITests/`, and `Tests/`. Name tests descriptively (e.g. `testLoginSucceedsWithValidCredentials`). Prefer adding or updating tests alongside behavioral changes to networking and view models (see AGENTS.md → Testing Guidelines).
- **Key flows to consider:** Auth (login, MFA, sign-out), channel/DM messaging (composer, replies, reactions, attachments), draft persistence per channel, message cache load/send/delete, Discover servers (join/leave, membership cache), server/channel settings, profile/settings, push and deep links. See **AGENTS.md** (Project Structure, Architecture, State Management) and **FEATURES.md** for full feature list and locations.

---

## Rules for Test Cases

1. **User point of view (POV)**  
   Every test case must be written as if a real user is performing the action. Describe **step-by-step how the user navigates through the app** (taps, scrolls, enters text, waits) — no implementation jargon unless necessary.

2. **Step-by-step navigation**  
   Each test case must have clear, ordered steps. Each step should be a single, concrete user action (e.g. “Tap the Login button”, “Enter email in the Email field”). Number the steps.

3. **Expected outcome and result**  
   Every test case must explicitly state:
   - **Expected outcome:** What the user should see or experience after completing the steps (e.g. screen shown, message displayed, state change).
   - **Expected result:** Pass/fail criterion in one sentence (e.g. “User is on the home screen and session is persisted” or “Error alert is shown and user remains on Login screen”).

4. **Edge cases**  
   When deriving test cases, consider and include edge cases relevant to Revolt, such as:
   - **Input:** Empty or invalid input (empty fields, wrong format, min/max length, special characters).
   - **Network:** Offline, slow, or timeout; queued messages and retry behavior.
   - **Auth/session:** Expired session, sign-out then reopen, multiple rapid taps, session bound to cache/drafts (sign-out clears drafts and flushes message cache with bounded timeout).
   - **Realtime:** Messages from another device (WebSocket), local delete vs server reconciliation, new messages appearing in the current channel without leaving.
   - **Drafts:** Per-channel draft save/restore; no draft cleared when returning to same channel with empty stored draft; draft cleared at send (offline and online) and on sign-out.
   - **Cache:** Opening channel shows cached messages first; first API page reconciles deleted messages (e.g. deleted while app was closed); sign-out flushes pending cache writes then clears caches.
   - **Discover:** Join/leave server; membership cache so Discover UI reflects state on launch and after WebSocket events.
   - **Lifecycle:** Background/foreground, rotation, navigate away during load; scroll/navigation safety (e.g. no scroll to invalid index when leaving channel).
   - **Conflicting actions:** Double submit, navigate away during send, repeated join/leave.

5. **Scope**  
   Only include test cases for the scope the user asked for (e.g. “login flow”, “draft persistence”, “channel messaging”). If the user does not specify, cover the main flows and their obvious edge cases for that area.

---

## Test Case Structure

Use the following structure for **each** test case. Add optional fields (e.g. Preconditions, Test data) when useful.

```markdown
### TC-XXX: [Short descriptive title]

**Preconditions (optional):**  
- [App state or setup required before steps]

**Steps:**  
1. [First user action — e.g. Open the app.]
2. [Second user action — e.g. On the Login screen, tap the Email field.]
3. [Continue until the scenario is complete.]

**Expected outcome:**  
[What the user should see or experience after the steps — screen, message, behavior.]

**Expected result:**  
[One-sentence pass/fail criterion — e.g. "User is taken to the home screen and remains logged in."]
```

---

## Example Test Case (format only)

### TC-001: Login with valid email and password

**Preconditions:**  
- App is installed and opened; user is on the Login screen.  
- User has an existing account with known email and password.

**Steps:**  
1. Open the Revolt app and wait for any splash or intro to finish.  
2. On the Login screen, tap the Email field and enter a valid email (e.g. `user@example.com`).  
3. Tap the Password field and enter the correct password.  
4. Tap the “Login” button.  
5. Wait for any loading indicator to disappear.

**Expected outcome:**  
- A loading overlay may appear briefly.  
- User is taken to the main home screen (server list / DMs / Discover).  
- No error alert is shown.  
- Session is persisted (e.g. closing and reopening the app keeps the user on the main screen).

**Expected result:**  
User successfully logs in and lands on the main screen; session is valid and persisted.

---

## Feature Areas for Test Case Derivation

When the user asks for test cases “for the app” or for a broad area, derive cases for the relevant feature areas below. Use **AGENTS.md** and **FEATURES.md** to locate code and behavior.

| Area | Description | Key paths / behaviors |
|------|-------------|----------------------|
| **Auth** | Login, MFA, sign-out, session | `Revolt/Pages/Login/`, `ViewState+Auth.swift`; sign-out clears drafts and flushes message cache. |
| **Channel / Messaging** | Composer, send, replies, reactions, attachments, typing | `Revolt/Pages/Channel/Messagable/`, managers (RepliesManager, etc.); local delete refreshes table; new messages via WebSocket refresh current channel. |
| **Drafts** | Per-channel draft save, restore, clear on send/sign-out | `ViewState+Drafts.swift`; restore in viewWillAppear when non-empty; do not clear composer when stored draft is nil/empty. |
| **Message cache** | Load from cache, send/edit/delete, reconciliation | `Revolt/1Storage/MessageCacheManager.swift`, `MessageCacheWriter.swift`; first API page reconciles deletes; session-scoped writes. |
| **Discover** | Server list, join/leave, membership cache | `Revolt/Components/Home/Discover/`, `ViewState+MembershipCache.swift`. |
| **Servers / Channels** | Navigation, settings, invites | `Revolt/Pages/Channel/Settings/`, `Revolt/Pages/Home/ViewInvite.swift`. |
| **Settings / Profile** | Profile, notifications, sessions, security | `Revolt/Pages/Settings/`. |
| **Notifications / Links** | Push, universal links, deep link to message | `notificationservice/`, `Revolt/RevoltApp.swift`. |

---

## Instructions for AI Agents

When the user says things like:
- “Prepare test cases for [feature/flow]”
- “Write test cases for [X]”
- “Derive test cases for [Y]”

you must:

1. **Use this document** (`docs/TestCases.md`) as the rule set for format, user POV, steps, expected outcome/result, and edge-case coverage.  
2. **Use AGENTS.md** to navigate the codebase (structure, state, caching, managers, testing guidelines).  
3. **Generate test cases** that follow the structure above and the rules in the “Rules for Test Cases” section.  
4. **Include edge cases** relevant to the requested scope (input, network, auth/session, realtime, drafts, cache, Discover, lifecycle, conflicting actions — see Edge cases).  
5. **Write steps and expectations** from the user’s perspective only; no internal APIs or variable names unless necessary for clarity.  
6. **Number test cases** (e.g. TC-001, TC-002) and give each a short, descriptive title.  
7. **Output** the test cases in Markdown (in the user’s chosen place: this file, a new file, or the chat), using the template and example above as reference.  
8. **If generating XCTest code:** Place unit tests in `RevoltTests/` or `Tests/`, UI tests in `RevoltUITests/`; name tests descriptively (e.g. `testLoginSucceedsWithValidCredentials`).

---

## Where to Add or Reference Test Cases

- The user may ask you to **append test cases** to this file (e.g. under a “Test cases by feature” section).  
- Or to **create a separate file** (e.g. `docs/TestCases-Auth.md`) and keep this file as the rules-only guide.  
- Or to **output test cases in the chat** for copy-paste.  
Follow the user’s instruction; in all cases, the **format and rules** from this document apply.

---

*This file is the single source of rules for how AI agents must derive and write test cases for Revolt (pepchat-ios). Update this file only when the test-case rules or structure need to change. For project structure, architecture, and testing setup, see **AGENTS.md**.*
