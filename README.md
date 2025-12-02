<div align="center">
<h1>
  Revolt iOS
  
  [![Stars](https://img.shields.io/github/stars/revoltchat/ios?style=flat-square&logoColor=white)](https://github.com/revoltchat/ios/stargazers)
  [![Forks](https://img.shields.io/github/forks/revoltchat/ios?style=flat-square&logoColor=white)](https://github.com/revoltchat/ios/network/members)
  [![Pull Requests](https://img.shields.io/github/issues-pr/revoltchat/ios?style=flat-square&logoColor=white)](https://github.com/revoltchat/ios/pulls)
  [![Issues](https://img.shields.io/github/issues/revoltchat/ios?style=flat-square&logoColor=white)](https://github.com/revoltchat/ios/issues)
  [![Contributors](https://img.shields.io/github/contributors/revoltchat/ios?style=flat-square&logoColor=white)](https://github.com/revoltchat/ios/graphs/contributors)
  [![License](https://img.shields.io/github/license/revoltchat/ios?style=flat-square&logoColor=white)](https://github.com/revoltchat/ios/blob/main/LICENSE)
</h1>
Native iOS app for Revolt
</div>
<br/>

This repository contains the source code for the native iOS application.

> [!IMPORTANT]
> This app is still in early stages, and not yet ready for production.

[Join the Testflight](https://testflight.apple.com/join/mGSCJe13) to try the app.

## Development

### Getting Started

Follow these instructions to get a copy of the project up and running on your local machine for development and testing purposes.

#### Prerequisites

- macOS with Xcode installed.

#### Installation

1. **Clone the repository:** \
   `git clone https://github.com/revoltchat/ios.git`

2. **Open the project in Xcode:** \
   Open `ZekoChat.xcworkspace` in Xcode (or `ZekoChat.xcodeproj` if not using CocoaPods).

3. **Build and run the app:** \
   Select your target device or simulator and hit the run button.

## License

All content contained within this repository is licensed under the [GNU Affero General Public License v3.0](https://github.com/revoltchat/ios/blob/main/LICENSE). Dependencies may be licensed differently._

# Message Link Navigation Fix

This document explains the changes made to fix the issue where clicking on a channel link with a message ID opens the channel but doesn't display any messages, despite logs showing messages were successfully loaded.

## Problem

When navigating to a message link (e.g., `https://peptide.chat/channels/01JSZ6NR0K99GTAHNJTBRESAFE?01JSZ6NR0K99GTAHNJTBRESAFE`), the app would:
1. Successfully load the channel
2. Attempt to load messages around the target message ID
3. Log that messages were successfully loaded
4. But fail to display any messages in the UI

## Solution

We made the following changes to fix this issue:

### 1. Enhanced `fetchHistory` in `Http.swift`

- Updated the `fetchHistory` function to properly support the `nearby` parameter
- Improved parameter handling using a dictionary instead of string concatenation
- Added proper URL encoding for parameters
- Fixed server parameter handling

```swift
func fetchHistory(
    channel: String,
    limit: Int = 100,
    before: String? = nil,
    after: String? = nil,
    nearby: String? = nil,
    sort: String = "Latest",
    server: String? = nil,
    messages: [String] = [],
    include_users: Bool = true
) async -> Result<FetchHistory, RevoltError> {
    // Implementation details
}
```

### 2. Added `fetchMessage` in `Http.swift`

- Added a function to fetch a specific message by ID

```swift
func fetchMessage(channel: String, message: String) async -> Result<Message, RevoltError> {
    await req(method: .get, route: "/channels/\(channel)/messages/\(message)")
}
```

### 3. Improved `loadMessagesNearby` in `MessageableChannelViewController.swift`

- Enhanced message sorting to ensure chronological order
- Added better error handling and debugging information
- Improved UI updates after loading messages

### 4. Updated `refreshWithTargetMessage` in `MessageableChannelViewController.swift`

- Improved the flow for handling target message loading
- Added fallback to fetch just the target message if loading nearby messages fails
- Enhanced error handling and logging

## Testing

To test this fix, navigate to a message link (e.g., `https://peptide.chat/channels/01JSZ6NR0K99GTAHNJTBRESAFE?01JSZ6NR0K99GTAHNJTBRESAFE`) and verify that:

1. The channel opens
2. Messages around the target message are loaded and displayed
3. The view scrolls to the target message
4. The target message is highlighted

If only the target message is displayed without surrounding context, check the logs for any errors in the message loading process.
