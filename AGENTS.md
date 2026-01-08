# Repository Guidelines

## Project Structure & Module Organization
- `Revolt/` contains the main iOS app (Swift/SwiftUI views, networking, and app entry points).
- `notificationservice/` is the Notification Service Extension.
- `Types/` holds shared model types.
- `RevoltTests/`, `RevoltUITests/`, and `Tests/` contain unit/UI tests (XCTest).
- `Revolt/Resources/` stores assets, xcassets catalogs, and localized strings (`Localizable.xcstrings`).
- `Package.swift` and `Revolt.xcworkspace` define SwiftPM and Xcode workspace configuration.

## Architecture Overview
- UI is primarily SwiftUI, with UIKit used where needed (e.g., complex channel/message views).
- Feature screens live under `Revolt/Pages/`, while reusable UI is under `Revolt/Components/`.
- Networking and realtime behavior live in `Revolt/Api/` (HTTP + websocket).
- Shared domain models live in `Types/` and are used across UI and networking layers.
- Key flows: auth screens under `Revolt/Pages/Login/`, channel + message UI under `Revolt/Pages/Channel/`, and settings under `Revolt/Pages/Settings/`.
- Data flow: `Revolt/Api/` → `Types/` → view models (ex: `Revolt/Pages/.../*ViewModel.swift`) → views (`Revolt/Pages/`, `Revolt/Components/`).

## Build, Test, and Development Commands
- Open the workspace: `open Revolt.xcworkspace` (recommended for local dev).
- Resolve SwiftPM packages: `xcodebuild -resolvePackageDependencies`.
- Build from CLI (example): `xcodebuild -scheme Revolt -destination 'platform=iOS Simulator,name=iPhone 15' build`.
- Run tests (example): `xcodebuild -scheme Revolt -destination 'platform=iOS Simulator,name=iPhone 15' test`.

## Coding Style & Naming Conventions
- Use Swift standard formatting with 4-space indentation.
- Types and files: `UpperCamelCase` (e.g., `MessageableChannelViewModel.swift`).
- Properties, functions, and locals: `lowerCamelCase`.
- Keep SwiftUI view files scoped to their feature folders under `Revolt/Pages/`.
- No repo-wide formatter is configured; keep diffs minimal and consistent with nearby code.

## Testing Guidelines
- Tests use XCTest and live in `RevoltTests/`, `RevoltUITests/`, and `Tests/`.
- Name tests descriptively (e.g., `testLoginSucceedsWithValidCredentials`).
- Prefer updating/adding tests alongside behavioral changes to networking and view models.

## Commit & Pull Request Guidelines
- Commit messages in history are short, sentence-style summaries (no conventional prefix); follow that pattern.
- PRs should include: a brief summary, testing performed, and screenshots or recordings for UI changes.
- Link related issues or tickets when applicable.

## Security & Configuration Tips
- Avoid committing secrets (tokens, API keys). Use environment variables or Xcode build settings for local overrides.
- When modifying entitlements or provisioning (`Revolt/Revolt.entitlements`), document the reason in the PR.
