# Mention Indicator

## Goal

Change mention rendering in the message composer so selected mentions are visually distinct while drafting.  
Requested behavior: mentioned usernames should appear in **yellow** inside the `UITextView` before the message is sent.

## Scope

- Composer mention rendering in `MessageInputView`
- Mention conversion pipeline before send (`@username` -> `<@userId>`)
- Real-time text updates while typing/deleting
- Draft-restore styling pass

## Files Changed

- `Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift`
- `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TextView.swift`

## Implementation Details

### 1) Mention token tracking (range-based)

Added a private token model in `MessageInputView`:

- `MentionToken { userId, displayText, range }`

Added storage and styling state:

- `mentionTokens: [MentionToken]`
- `mentionTextColor = .systemYellow`
- `isApplyingMentionStyle` guard flag to avoid recursive attributed updates

Why:

- String-only replacement is ambiguous and can replace plain text accidentally.
- Range tokens make conversion and styling deterministic for exact mention segments.

### 2) Attributed styling for mentions in composer

Added two methods in `MessageInputView`:

- `refreshMentionStylingAfterTextChange()`
  - Validates tokens against current text
  - Removes invalid/broken tokens when user edits/deletes mention text
  - Calls `applyMentionStyling()`

- `applyMentionStyling()`
  - Builds `NSMutableAttributedString` with base text color
  - Applies `.foregroundColor = .systemYellow` on mention token ranges
  - Preserves cursor (`selectedRange`)
  - Restores `typingAttributes` so normal typing keeps default text color

### 3) Hook styling into typing flow

In `MessageableChannelViewController+TextView.swift`:

- After forwarding `textViewDidChange` to `MessageInputView`, now also calls:
  - `messageInputView.refreshMentionStylingAfterTextChange()`

Why:

- Ensures mention color updates on each keystroke and after deletions.

### 4) Hook styling into mention insertion

In `mentionInputView(_:didSelectUser:member:)`:

- Existing behavior (`@username ` insertion + mention data storage) is preserved.
- Added range capture for inserted mention:
  - Finds inserted `@username` range from the resulting text
  - Appends a `MentionToken`
- Calls `applyMentionStyling()` immediately after insertion.

Result:

- Mention turns yellow as soon as user selects from mention list.

### 5) Draft restore styling pass

In `setText(_:)`:

- Added `refreshMentionStylingAfterTextChange()` before posting text change notification.

Why:

- Re-applies mention styling logic whenever draft text is restored into composer.
- Invalid tokens are naturally dropped if text no longer matches.

### 6) Safer mention conversion before send

Updated `convertTextForSending()` in `MessageInputView`:

- Primary path: converts mentions using `mentionTokens` in reverse order by range.
- Fallback path: preserves existing string-based behavior using `MentionData` if no tokens exist.

Why:

- Reverse-range replacement avoids range shift issues.
- Token path converts only selected mentions, not random `@text` fragments.
- Fallback keeps compatibility with older behavior.

### 7) Cleanup synchronization

Mention token storage is now cleared when mention data is cleared:

- `cleanup()`
- `clearMentionData()`

Why:

- Avoid stale styling state across composer lifecycle.

## Behavior Summary

- Type `@` + query -> mention popup works as before.
- Select user -> inserted `@username` is colored yellow in composer.
- Continue typing -> non-mention text remains default color.
- Edit/delete mention text -> invalid mention token is removed and yellow highlight disappears for broken mention.
- Send message -> conversion uses precise mention token ranges whenever available.

## Notes

- Color is currently `UIColor.systemYellow`.  
  If design needs theme asset color instead, switch `mentionTextColor` to a named color token.
- Draft persistence still stores plain text only. Token metadata is in-memory, so restored drafts are styled only when mention tokens can be revalidated from current session input changes.

## Exact Code Added

### 1) Added in `MessageInputView` (class scope)

```swift
private struct MentionToken {
    let userId: String
    let displayText: String
    var range: NSRange
}
```

```swift
private var mentionTokens: [MentionToken] = []
private let mentionTextColor = UIColor.systemYellow
private var isApplyingMentionStyle = false
```

### 2) Added in `MessageInputView` (methods)

```swift
func refreshMentionStylingAfterTextChange() {
    let text = textView.text ?? ""
    let nsText = text as NSString

    mentionTokens = mentionTokens.filter { token in
        guard token.range.location >= 0,
              token.range.location + token.range.length <= nsText.length else { return false }
        return nsText.substring(with: token.range) == token.displayText
    }

    applyMentionStyling()
}
```

```swift
private func applyMentionStyling() {
    guard !isApplyingMentionStyle else { return }
    isApplyingMentionStyle = true
    defer { isApplyingMentionStyle = false }

    let raw = textView.text ?? ""
    let selected = textView.selectedRange
    let baseAttrs: [NSAttributedString.Key: Any] = [
        .font: textView.font ?? UIFont.systemFont(ofSize: 16),
        .foregroundColor: UIColor(named: "textDefaultGray01") ?? UIColor.label
    ]

    let attributed = NSMutableAttributedString(string: raw, attributes: baseAttrs)
    for token in mentionTokens {
        guard token.range.location >= 0,
              token.range.location + token.range.length <= (raw as NSString).length else { continue }
        attributed.addAttribute(.foregroundColor, value: mentionTextColor, range: token.range)
    }

    textView.attributedText = attributed
    textView.selectedRange = selected
    textView.typingAttributes = baseAttrs
}
```

### 3) Added in mention selection flow

In `mentionInputView(_:didSelectUser:member:)`:

```swift
let nsText = newText as NSString
let insertedRange = nsText.range(of: displayText, options: .backwards)
if insertedRange.location != NSNotFound {
    mentionTokens.append(
        MentionToken(userId: user.id, displayText: displayText, range: insertedRange)
    )
}
```

```swift
applyMentionStyling()
```

### 4) Added in typing flow hook

In `MessageableChannelViewController+TextView.swift` inside `textViewDidChange`:

```swift
messageInputView.refreshMentionStylingAfterTextChange()
```

### 5) Added in draft restore flow

In `setText(_:)`:

```swift
refreshMentionStylingAfterTextChange()
```

### 6) Added in cleanup points

In `cleanup()`:

```swift
mentionTokens.removeAll()
```

In `clearMentionData()`:

```swift
mentionTokens.removeAll()
```

### 7) Added in send-conversion flow

In `convertTextForSending()`:

```swift
let mutable = NSMutableString(string: originalText)
let validTokens = mentionTokens
    .filter { token in
        token.range.location >= 0
            && token.range.location + token.range.length <= mutable.length
            && mutable.substring(with: token.range) == token.displayText
    }
    .sorted { $0.range.location > $1.range.location }

if !validTokens.isEmpty {
    for token in validTokens {
        mutable.replaceCharacters(in: token.range, with: "<@\(token.userId)>")
    }
    return mutable as String
}
```

Fallback logic retained for compatibility:

```swift
var convertedText = originalText
let mentionDataList = getMentionDataList()
for mentionData in mentionDataList {
    convertedText = convertedText.replacingOccurrences(
        of: mentionData.displayText,
        with: "<@\(mentionData.userId)>"
    )
}
```

