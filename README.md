<div align="center">
<h1>
  Zeko Chat
  
  [![Stars](https://img.shields.io/github/stars/archem-team/pepchat-ios?style=flat-square&logoColor=white)](https://github.com/archem-team/pepchat-ios/stargazers)
  [![Forks](https://img.shields.io/github/forks/archem-team/pepchat-ios?style=flat-square&logoColor=white)](https://github.com/archem-team/pepchat-ios/network/members)
  [![Pull Requests](https://img.shields.io/github/issues-pr/archem-team/pepchat-ios?style=flat-square&logoColor=white)](https://github.com/archem-team/pepchat-ios/pulls)
  [![Issues](https://img.shields.io/github/issues/archem-team/pepchat-ios?style=flat-square&logoColor=white)](https://github.com/archem-team/pepchat-ios/issues)
  [![Contributors](https://img.shields.io/github/contributors/archem-team/pepchat-ios?style=flat-square&logoColor=white)](https://github.com/archem-team/pepchat-ios/graphs/contributors)
  [![License](https://img.shields.io/github/license/archem-team/pepchat-ios?style=flat-square&logoColor=white)](https://github.com/archem-team/pepchat-ios/blob/main/LICENSE)
</h1>
Native iOS app for Zeko Chat
</div>
<br/>

This repository contains the source code for the Zeko Chat iOS app.

> [!IMPORTANT]
> The app is now live in production.

- **[Join the TestFlight beta](https://testflight.apple.com/join/cdQYYD3C)** to try the app.
- **[Zeko Chat on the App Store](https://apps.apple.com/in/app/zeko-chat/id6756353165)** — download the release version.

## Development

### Getting Started

Follow these instructions to get a copy of the project up and running on your local machine for development and testing purposes.

#### Prerequisites

- macOS with Xcode installed.

#### Installation

1. **Clone the repository:** \
   `git clone https://github.com/archem-team/pepchat-ios.git`

2. **Open the project in Xcode:** \
   Open `Revolt.xcworkspace` in Xcode.

3. **Build and run the app:** \
   Select your target device or simulator and hit the run button.

## License

All content contained within this repository is licensed under the [GNU Affero General Public License v3.0](https://github.com/archem-team/pepchat-ios/blob/main/LICENSE). Dependencies may be licensed differently.

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
