# Implementation Stack Map

Auto-generated per-file map of implementation style across code files in this repository.

**How stack share is measured**: percentages are estimated from non-empty, non-comment lines in each file, split into `Swift`, `SwiftUI`, and `UIKit` buckets using keyword-based detection.

**Total code files documented**: 357

## bin

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `bin/run_maestro_tests.sh` | `100% / 0% / 0%` (n=103) | Provides source code supporting this module. |
| `bin/run_on_clean_emulator.sh` | `100% / 0% / 0%` (n=308) | Provides source code supporting this module. |

## ci_scripts

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `ci_scripts/ci_post_clone.sh` | `100% / 0% / 0%` (n=4) | Provides source code supporting this module. |
| `ci_scripts/ci_post_xcodebuild.sh` | `100% / 0% / 0%` (n=14) | Provides source code supporting this module. |

## notificationservice

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `notificationservice/NotificationService.swift` | `100% / 0% / 0%` (n=122) | Provides service-layer logic used by higher-level features. |

## Revolt

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `Revolt/1Storage/MessageCacheManager.swift` | `100% / 0% / 0%` (n=660) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/1Storage/MessageCacheWriter.swift` | `100% / 0% / 0%` (n=102) | Defines `MessageCacheWriter` (class) for this module feature. |
| `Revolt/Api/Http.swift` | `100% / 0% / 0%` (n=640) | Defines API request/response models and networking helpers. |
| `Revolt/Api/Payloads.swift` | `100% / 0% / 0%` (n=450) | Defines API request/response models and networking helpers. |
| `Revolt/Api/PermissionsCalculator.swift` | `99% / 1% / 0%` (n=122) | Defines API request/response models and networking helpers. |
| `Revolt/Api/Responses.swift` | `100% / 0% / 0%` (n=163) | Defines API request/response models and networking helpers. |
| `Revolt/Api/UserSettingsStore.swift` | `99% / 1% / 0%` (n=476) | Defines API request/response models and networking helpers. |
| `Revolt/Api/Utils.swift` | `100% / 0% / 0%` (n=60) | Defines API request/response models and networking helpers. |
| `Revolt/Api/Websocket.swift` | `100% / 0% / 0%` (n=721) | Defines API request/response models and networking helpers. |
| `Revolt/Components/1Loading/1ChannelLoadingView.swift` | `81% / 19% / 0%` (n=64) | Defines a reusable UI component used across the app. |
| `Revolt/Components/1Loading/MessageSkeletonView.swift` | `84% / 16% / 0%` (n=122) | Defines a reusable UI component used across the app. |
| `Revolt/Components/1Loading/SkeletonHostingController.swift` | `61% / 36% / 3%` (n=69) | Defines a reusable UI component used across the app. |
| `Revolt/Components/AccountManagement/BlockUserPopup.swift` | `88% / 12% / 0%` (n=81) | Defines a reusable UI component used across the app. |
| `Revolt/Components/AccountManagement/HCaptchaView.swift` | `67% / 20% / 12%` (n=49) | Defines a reusable UI component used across the app. |
| `Revolt/Components/AccountManagement/RemoveFriendShipPopup.swift` | `89% / 11% / 0%` (n=87) | Defines a reusable UI component used across the app. |
| `Revolt/Components/AlertPopup.swift` | `85% / 15% / 0%` (n=46) | Defines a reusable UI component used across the app. |
| `Revolt/Components/AudioPlayer/AudioPlayerManager.swift` | `99% / 1% / 0%` (n=659) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Components/AudioPlayer/AudioPlayerView.swift` | `86% / 11% / 3%` (n=741) | Defines a reusable UI component used across the app. |
| `Revolt/Components/AudioPlayer/AudioSessionManager.swift` | `99% / 0% / 1%` (n=94) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Components/AudioPlayer/DownloadProgressView.swift` | `82% / 13% / 5%` (n=83) | Defines a reusable UI component used across the app. |
| `Revolt/Components/AudioPlayer/VideoPlayerView.swift` | `81% / 16% / 4%` (n=483) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Avatar.swift` | `90% / 10% / 0%` (n=79) | Defines a reusable UI component used across the app. |
| `Revolt/Components/ChannelIcon.swift` | `90% / 10% / 0%` (n=425) | Defines a reusable UI component used across the app. |
| `Revolt/Components/CommonElements/CheckboxStyle.swift` | `79% / 21% / 0%` (n=19) | Defines a reusable UI component used across the app. |
| `Revolt/Components/CommonElements/LoadingSpinnerView.swift` | `79% / 21% / 0%` (n=77) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Contents.swift` | `89% / 8% / 3%` (n=876) | Defines a reusable UI component used across the app. |
| `Revolt/Components/EmojiPicker.swift` | `91% / 9% / 0%` (n=171) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Home/Discover/DiscoverItem.swift` | `100% / 0% / 0%` (n=11) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Home/Discover/DiscoverItemView.swift` | `90% / 10% / 0%` (n=70) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Home/Discover/DiscoverScrollView.swift` | `92% / 8% / 0%` (n=387) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Home/DMEmptyView.swift` | `77% / 23% / 0%` (n=35) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Home/DMScrollView.swift` | `89% / 11% / 0%` (n=287) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Home/PageToolbar.swift` | `82% / 18% / 0%` (n=60) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Home/ServerChannelScrollView.swift` | `88% / 12% / 0%` (n=398) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Home/ServerScrollView.swift` | `86% / 14% / 0%` (n=353) | Defines a reusable UI component used across the app. |
| `Revolt/Components/LazyImage.swift` | `88% / 12% / 0%` (n=42) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Loading/ChannelLoadingView.swift` | `81% / 19% / 0%` (n=64) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Markdown.swift` | `52% / 22% / 26%` (n=23) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageBox.swift` | `85% / 14% / 0%` (n=754) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/DeleteMessageView.swift` | `38% / 62% / 0%` (n=8) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/InviteView.swift` | `89% / 11% / 0%` (n=103) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageAttachment.swift` | `77% / 19% / 3%` (n=177) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageBadge.swift` | `84% / 16% / 0%` (n=19) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageContentsView.swift` | `87% / 12% / 1%` (n=453) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageEmbed.swift` | `86% / 12% / 1%` (n=210) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageEmojisReact.swift` | `79% / 21% / 0%` (n=33) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageOptionSheet.swift` | `94% / 6% / 0%` (n=143) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageReactions.swift` | `88% / 12% / 0%` (n=146) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageReactionsSheet.swift` | `77% / 23% / 0%` (n=70) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageReactionsSheetUIKit.swift` | `82% / 18% / 0%` (n=78) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageReply.swift` | `82% / 18% / 0%` (n=99) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/MessageView.swift` | `79% / 21% / 0%` (n=213) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/ReportMessageSheetView.swift` | `84% / 16% / 0%` (n=102) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/SwipeToReplyView.swift` | `83% / 17% / 0%` (n=96) | Defines a reusable UI component used across the app. |
| `Revolt/Components/MessageRenderer/SystemMessageView.swift` | `89% / 11% / 0%` (n=261) | Defines a reusable UI component used across the app. |
| `Revolt/Components/PeptidePagination.swift` | `100% / 0% / 0%` (n=20) | Defines a reusable UI component used across the app. |
| `Revolt/Components/PeptideSectionHeader.swift` | `75% / 25% / 0%` (n=16) | Defines a reusable UI component used across the app. |
| `Revolt/Components/PresenceIndicator.swift` | `89% / 11% / 0%` (n=35) | Defines a reusable UI component used across the app. |
| `Revolt/Components/RemoteImageTextAttachment.swift` | `97% / 0% / 3%` (n=30) | Defines a reusable UI component used across the app. |
| `Revolt/Components/ReversedScrollView.swift` | `76% / 24% / 0%` (n=29) | Defines a reusable UI component used across the app. |
| `Revolt/Components/ReversedSrollView.swift` | `77% / 23% / 0%` (n=30) | Defines a reusable UI component used across the app. |
| `Revolt/Components/ServerBadges.swift` | `84% / 16% / 0%` (n=25) | Defines a reusable UI component used across the app. |
| `Revolt/Components/ServerIcon.swift` | `80% / 20% / 0%` (n=66) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Settings/AllPermissionsSettings.swift` | `89% / 11% / 0%` (n=93) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Settings/PermissionToggle.swift` | `86% / 14% / 0%` (n=91) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/AddServerSheet.swift` | `87% / 13% / 0%` (n=101) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/ConfirmationSheet.swift` | `90% / 10% / 0%` (n=98) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/DeleteChannelSheet.swift` | `86% / 14% / 0%` (n=81) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/DeleteDmGroupSheet.swift` | `86% / 14% / 0%` (n=81) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/DeleteGrouSheet.swift` | `87% / 13% / 0%` (n=83) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/DeleteServerSheet.swift` | `86% / 14% / 0%` (n=93) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/MutualConnectionsSheet.swift` | `89% / 11% / 0%` (n=219) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/ServerInfoSheet.swift` | `89% / 11% / 0%` (n=373) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/ShareInviteSheet.swift` | `81% / 19% / 0%` (n=70) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/UserSheet.swift` | `91% / 9% / 0%` (n=467) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Sheets/UserSheetViewController.swift` | `61% / 32% / 7%` (n=390) | Defines a reusable UI component used across the app. |
| `Revolt/Components/Tile.swift` | `77% / 23% / 0%` (n=56) | Defines a reusable UI component used across the app. |
| `Revolt/Components/UnreadCounter.swift` | `73% / 27% / 0%` (n=52) | Defines a reusable UI component used across the app. |
| `Revolt/Components/User/1BadgeView.swift` | `72% / 28% / 0%` (n=43) | Defines a reusable UI component used across the app. |
| `Revolt/Components/User/BadgeView.swift` | `81% / 19% / 0%` (n=63) | Defines a reusable UI component used across the app. |
| `Revolt/Components/User/PeptideUserAvatar.swift` | `85% / 15% / 0%` (n=33) | Defines a reusable UI component used across the app. |
| `Revolt/Components/VideoPlayer.swift` | `0% / 0% / 0%` (n=0) | Defines a reusable UI component used across the app. |
| `Revolt/Delegates/AppDelegate.swift` | `93% / 7% / 0%` (n=251) | Defines `declareNotificationCategoryTypes` (func) for this module feature. |
| `Revolt/Extensions/1EmojiParser.swift` | `100% / 0% / 0%` (n=487) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/AnyTransition.swift` | `93% / 7% / 0%` (n=15) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/Binding.swift` | `95% / 5% / 0%` (n=22) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/Bundle.swift` | `89% / 11% / 0%` (n=9) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/CGFloat.swift` | `100% / 0% / 0%` (n=57) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/Collection.swift` | `100% / 0% / 0%` (n=13) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/Color.swift` | `93% / 7% / 0%` (n=14) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/EmojiParser.swift` | `100% / 0% / 0%` (n=1649) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/EnvironmentValues.swift` | `71% / 29% / 0%` (n=7) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/Image.swift` | `85% / 15% / 0%` (n=20) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/ImageResource+Extensions.swift` | `92% / 8% / 0%` (n=13) | Extends `ImageResource` with extensions behavior. |
| `Revolt/Extensions/ImageResource+PeptideExtensions.swift` | `94% / 6% / 0%` (n=18) | Extends `ImageResource` with peptideextensions behavior. |
| `Revolt/Extensions/Int.swift` | `100% / 0% / 0%` (n=9) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/IteratorProtocol.swift` | `100% / 0% / 0%` (n=24) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/Member.swift` | `93% / 7% / 0%` (n=15) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/MessageBoxExtensions.swift` | `79% / 21% / 0%` (n=108) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/Optional.swift` | `100% / 0% / 0%` (n=9) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/OptionSet.swift` | `100% / 0% / 0%` (n=39) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/Section.swift` | `67% / 33% / 0%` (n=6) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/String.swift` | `100% / 0% / 0%` (n=25) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/StringExtensions.swift` | `97% / 3% / 0%` (n=36) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/SwiftUIExtensions.swift` | `73% / 27% / 0%` (n=52) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/UIFont.swift` | `88% / 0% / 12%` (n=8) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/UIImage.swift` | `98% / 0% / 2%` (n=57) | Adds convenience extension methods to existing types. |
| `Revolt/Extensions/View+Introspect.swift` | `67% / 28% / 4%` (n=116) | Extends `View` with introspect behavior. |
| `Revolt/Extensions/View.swift` | `84% / 16% / 0%` (n=108) | Adds convenience extension methods to existing types. |
| `Revolt/Pages/Channel/Messagable/Attachments/AttachmentsSheet.swift` | `90% / 10% / 0%` (n=59) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/ChannelInfo/AddMembersToChannelView.swift` | `87% / 13% / 0%` (n=199) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/ChannelInfo/ChannelInfo.swift` | `91% / 9% / 0%` (n=660) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/ChannelInfo/ChannelInfoMoreSheet.swift` | `89% / 11% / 0%` (n=100) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/ChannelInfo/ChannelSearch.swift` | `90% / 10% / 0%` (n=283) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/ChannelInfo/ChannelUserOptionSheet.swift` | `93% / 7% / 0%` (n=175) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/ChannelInfo/PinnedMessagesView.swift` | `90% / 10% / 0%` (n=206) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Controllers/FullScreenImageViewController.swift` | `61% / 32% / 7%` (n=264) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/DataSources/MessageTableViewDataSource.swift` | `83% / 8% / 9%` (n=168) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+EmptyState.swift` | `57% / 38% / 5%` (n=133) | Extends `MessageableChannelViewController` with emptystate behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Extensions.swift` | `88% / 10% / 2%` (n=218) | Extends `MessageableChannelViewController` with extensions behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+GlobalFix.swift` | `81% / 18% / 1%` (n=72) | Extends `MessageableChannelViewController` with globalfix behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Keyboard.swift` | `75% / 17% / 8%` (n=65) | Extends `MessageableChannelViewController` with keyboard behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Lifecycle.swift` | `86% / 13% / 1%` (n=217) | Extends `MessageableChannelViewController` with lifecycle behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MarkUnread.swift` | `98% / 1% / 1%` (n=169) | Extends `MessageableChannelViewController` with markunread behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageCell.swift` | `89% / 3% / 8%` (n=61) | Extends `MessageableChannelViewController` with messagecell behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+MessageLoading.swift` | `91% / 9% / 0%` (n=1215) | Extends `MessageableChannelViewController` with messageloading behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Notifications.swift` | `94% / 6% / 1%` (n=156) | Extends `MessageableChannelViewController` with notifications behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+NSFW.swift` | `75% / 12% / 12%` (n=8) | Extends `MessageableChannelViewController` with nsfw behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Permissions.swift` | `88% / 6% / 6%` (n=16) | Extends `MessageableChannelViewController` with permissions behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Replies.swift` | `89% / 10% / 2%` (n=210) | Extends `MessageableChannelViewController` with replies behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+ScrollPosition.swift` | `80% / 20% / 1%` (n=133) | Extends `MessageableChannelViewController` with scrollposition behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+ScrollView.swift` | `77% / 20% / 3%` (n=213) | Extends `MessageableChannelViewController` with scrollview behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Setup.swift` | `68% / 28% / 4%` (n=363) | Extends `MessageableChannelViewController` with setup behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+Skeleton.swift` | `58% / 34% / 8%` (n=38) | Extends `MessageableChannelViewController` with skeleton behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TableBouncing.swift` | `49% / 49% / 2%` (n=94) | Extends `MessageableChannelViewController` with tablebouncing behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TableView.swift` | `79% / 13% / 8%` (n=85) | Extends `MessageableChannelViewController` with tableview behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TargetMessage.swift` | `88% / 11% / 1%` (n=559) | Extends `MessageableChannelViewController` with targetmessage behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/MessageableChannelViewController+TextView.swift` | `89% / 8% / 3%` (n=180) | Extends `MessageableChannelViewController` with textview behavior. |
| `Revolt/Pages/Channel/Messagable/Extensions/NSLockExtensions.swift` | `100% / 0% / 0%` (n=8) | Adds convenience extension methods to existing types. |
| `Revolt/Pages/Channel/Messagable/Extensions/UIViewExtensions.swift` | `79% / 0% / 21%` (n=24) | Adds convenience extension methods to existing types. |
| `Revolt/Pages/Channel/Messagable/Managers/1PendingAttachmentsManager.swift` | `99% / 0% / 1%` (n=70) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Pages/Channel/Messagable/Managers/CellHeightCache.swift` | `96% / 0% / 4%` (n=26) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Pages/Channel/Messagable/Managers/MessageGroupingManager.swift` | `0% / 0% / 0%` (n=0) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Pages/Channel/Messagable/Managers/MessageLoader.swift` | `0% / 0% / 0%` (n=0) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Pages/Channel/Messagable/Managers/PermissionsManager.swift` | `70% / 26% / 4%` (n=134) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Pages/Channel/Messagable/Managers/RepliesManager.swift` | `85% / 14% / 1%` (n=477) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Pages/Channel/Messagable/Managers/ScrollPositionManager.swift` | `85% / 14% / 1%` (n=173) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Pages/Channel/Messagable/Managers/TypingIndicatorManager.swift` | `85% / 14% / 1%` (n=81) | Encapsulates reusable manager logic for this feature flow. |
| `Revolt/Pages/Channel/Messagable/Mention/MentionInputView.swift` | `75% / 19% / 6%` (n=650) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/MessageableChannel.swift` | `84% / 16% / 0%` (n=1067) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/MessageableChannelViewController+NotificationBanner.swift` | `75% / 12% / 12%` (n=8) | Extends `MessageableChannelViewController` with notificationbanner behavior. |
| `Revolt/Pages/Channel/Messagable/MessageableChannelViewController.swift` | `89% / 9% / 2%` (n=1935) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/MessageableChannelViewControllerRepresentable.swift` | `70% / 21% / 9%` (n=53) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/MessageableChannelViewModel.swift` | `97% / 2% / 0%` (n=207) | Implements view-model state and actions for its feature screen. |
| `Revolt/Pages/Channel/Messagable/MessageSkeletonView.swift` | `45% / 43% / 12%` (n=76) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Models/HTTPError.swift` | `100% / 0% / 0%` (n=10) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Models/MessageableChannelConstants.swift` | `94% / 0% / 6%` (n=18) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Models/MessageableChannelErrors.swift` | `100% / 0% / 0%` (n=32) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Models/MessagesReply.swift` | `100% / 0% / 0%` (n=10) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Models/ReplyMessage.swift` | `100% / 0% / 0%` (n=13) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/NSFWConfirmationSheet.swift` | `88% / 12% / 0%` (n=93) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/NSFWOverlayView.swift` | `66% / 25% / 9%` (n=137) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/RepliesContainerView.swift` | `63% / 31% / 6%` (n=164) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Utils/MarkdownProcessor.swift` | `100% / 0% / 0%` (n=441) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Utils/MessageInputHandler.swift` | `92% / 7% / 1%` (n=557) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Utils/ULID.swift` | `100% / 0% / 0%` (n=28) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Utils/URLDetector.swift` | `100% / 0% / 0%` (n=143) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/1AttachmentPreviewView.swift` | `69% / 23% / 8%` (n=253) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/1LinkPreviewView.swift` | `65% / 32% / 4%` (n=279) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/AttachmentPreviewView.swift` | `69% / 23% / 8%` (n=264) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/LinkPreviewView.swift` | `66% / 30% / 4%` (n=301) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Attachments.swift` | `74% / 24% / 2%` (n=344) | Extends `MessageCell` with attachments behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+AVPlayer.swift` | `78% / 17% / 4%` (n=46) | Extends `MessageCell` with avplayer behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Content.swift` | `95% / 3% / 2%` (n=121) | Extends `MessageCell` with content behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+ContextMenu.swift` | `88% / 10% / 2%` (n=141) | Extends `MessageCell` with contextmenu behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+GestureRecognizer.swift` | `88% / 6% / 6%` (n=50) | Extends `MessageCell` with gesturerecognizer behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Layout.swift` | `79% / 17% / 4%` (n=111) | Extends `MessageCell` with layout behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Reactions.swift` | `68% / 26% / 7%` (n=176) | Extends `MessageCell` with reactions behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Reply.swift` | `90% / 7% / 3%` (n=112) | Extends `MessageCell` with reply behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Setup.swift` | `55% / 43% / 2%` (n=223) | Extends `MessageCell` with setup behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+Swipe.swift` | `85% / 13% / 2%` (n=106) | Extends `MessageCell` with swipe behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell+Extensions/MessageCell+TextViewDelegate.swift` | `95% / 4% / 1%` (n=302) | Extends `MessageCell` with textviewdelegate behavior. |
| `Revolt/Pages/Channel/Messagable/Views/MessageCell.swift` | `75% / 19% / 6%` (n=1347) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/MessageInputView.swift` | `78% / 19% / 3%` (n=793) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/MessageOptionViewController.swift` | `70% / 22% / 8%` (n=410) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/NSFWOverlayView.swift` | `65% / 26% / 10%` (n=125) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/RepliesContainerView.swift` | `70% / 24% / 5%` (n=203) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/SystemMessageCell.swift` | `81% / 15% / 4%` (n=167) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/ToastView.swift` | `53% / 37% / 10%` (n=49) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Messagable/Views/TypingIndicatorView.swift` | `81% / 5% / 14%` (n=42) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Channel/ChannelOverviewSettings.swift` | `88% / 12% / 0%` (n=214) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Channel/ChannelPermissionsSettings/ChannelPermissionsSettings.swift` | `86% / 14% / 0%` (n=147) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Channel/ChannelPermissionsSettings/ChannelRolePermissionsSettings.swift` | `87% / 13% / 0%` (n=106) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Channel/ChannelSettings.swift` | `90% / 10% / 0%` (n=104) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Channel/ServerChannel/ServerCategorySheet.swift` | `86% / 14% / 0%` (n=96) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Channel/ServerChannel/ServerChannelOverviewSettings.swift` | `90% / 10% / 0%` (n=211) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/Categories/ChannelCategoryCreateSheet.swift` | `88% / 12% / 0%` (n=41) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/Categories/ChannelCategoryCreateView.swift` | `90% / 10% / 0%` (n=211) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/Categories/DeleteCategorySheet.swift` | `88% / 12% / 0%` (n=68) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/Categories/ServerCategoryView.swift` | `87% / 13% / 0%` (n=118) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/Categories/ServerChannelsView.swift` | `77% / 23% / 0%` (n=106) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ChannelMemberPermissionView.swift` | `86% / 14% / 0%` (n=149) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/Identity/IdentitySheet.swift` | `90% / 10% / 0%` (n=266) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerBannedUsersView.swift` | `85% / 15% / 0%` (n=163) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerEmoji/DeleteEmojiPopup.swift` | `88% / 12% / 0%` (n=65) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerEmoji/NewEmojiSheet.swift` | `86% / 14% / 0%` (n=177) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerEmoji/ServerEmojiItemView.swift` | `84% / 16% / 0%` (n=56) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerEmoji/ServerEmojiSettings.swift` | `81% / 19% / 0%` (n=111) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerInvitesView.swift` | `85% / 15% / 0%` (n=143) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerMembersView.swift` | `89% / 11% / 0%` (n=175) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerOverviewSettings.swift` | `92% / 8% / 0%` (n=458) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerRoles/CreateServerRoleView.swift` | `75% / 25% / 0%` (n=55) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerRoles/DefaultRoleSettings.swift` | `84% / 16% / 0%` (n=97) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerRoles/RoleColorPickerSheet.swift` | `81% / 19% / 0%` (n=93) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerRoles/RoleDeleteSheet.swift` | `88% / 12% / 0%` (n=65) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerRoles/RoleSettings.swift` | `88% / 12% / 0%` (n=248) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerRoles/ServerRolesSettings.swift` | `86% / 14% / 0%` (n=115) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/ServerSettings.swift` | `84% / 16% / 0%` (n=80) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channel/Settings/Server/SystemMessageSheet.swift` | `89% / 11% / 0%` (n=145) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Channels/MessageableChannel.swift` | `87% / 13% / 0%` (n=252) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Components/ComponentState.swift` | `100% / 0% / 0%` (n=24) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideActionButton.swift` | `91% / 9% / 0%` (n=138) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideButton.swift` | `92% / 8% / 0%` (n=93) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideCheckBox.swift` | `94% / 6% / 0%` (n=99) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideDivider.swift` | `81% / 19% / 0%` (n=32) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideIcon.swift` | `80% / 20% / 0%` (n=25) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideIconButton.swift` | `90% / 10% / 0%` (n=67) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideImage.swift` | `80% / 20% / 0%` (n=20) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideLoading.swift` | `81% / 19% / 0%` (n=43) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideOtp.swift` | `88% / 12% / 0%` (n=139) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideTabItem.swift` | `85% / 15% / 0%` (n=62) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideText.swift` | `88% / 12% / 0%` (n=76) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/PeptideTextField.swift` | `94% / 6% / 0%` (n=206) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Components/TextStyle.swift` | `99% / 1% / 0%` (n=147) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Features/Core/AccessibilityID.swift` | `92% / 8% / 0%` (n=40) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Features/Core/BaseViewModel.swift` | `96% / 4% / 0%` (n=23) | Implements view-model state and actions for its feature screen. |
| `Revolt/Pages/Features/Core/Components/PeptideAuthHeaderView.swift` | `80% / 20% / 0%` (n=25) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Features/Core/Components/PeptideSheet.swift` | `89% / 11% / 0%` (n=63) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Features/Core/Components/PeptideTemplateView.swift` | `72% / 28% / 0%` (n=97) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Features/Core/Components/PeptideWarningTemplateView.swift` | `61% / 39% / 0%` (n=18) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Features/Intro/Components/IntroHeader.swift` | `80% / 20% / 0%` (n=15) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Features/Intro/Components/IntroPlatformView.swift` | `87% / 13% / 0%` (n=90) | Defines a reusable UI component used across the app. |
| `Revolt/Pages/Features/Intro/IntroScreen.swift` | `81% / 19% / 0%` (n=126) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Features/Intro/Models/PlatformConfig.swift` | `100% / 0% / 0%` (n=17) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Features/Intro/Navigation/IntroNavigation.swift` | `100% / 0% / 0%` (n=1) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Features/Intro/Services/PlatformConfigService.swift` | `100% / 0% / 0%` (n=31) | Provides service-layer logic used by higher-level features. |
| `Revolt/Pages/Home/AddFriend.swift` | `86% / 14% / 0%` (n=81) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/CreateGroup/CreateGroup.swift` | `82% / 18% / 0%` (n=102) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/CreateGroup/CreateGroupAddMembders.swift` | `86% / 14% / 0%` (n=167) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/CreateGroup/CreateGroupName.swift` | `83% / 17% / 0%` (n=59) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/Discovery.swift` | `74% / 24% / 2%` (n=148) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/FriendOptionsSheet.swift` | `89% / 11% / 0%` (n=150) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/FriendRequestCard.swift` | `85% / 15% / 0%` (n=75) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/FriendsList.swift` | `90% / 10% / 0%` (n=252) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/Home.swift` | `80% / 20% / 0%` (n=165) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/Home/FriendRequestCard.swift` | `0% / 0% / 0%` (n=0) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/Home/HomeBottomNavigation.swift` | `86% / 14% / 0%` (n=42) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/HomeWelcome.swift` | `84% / 16% / 0%` (n=94) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/IncomingFriendRequestsSheet.swift` | `87% / 13% / 0%` (n=91) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/NewMessageFriendsList.swift` | `87% / 13% / 0%` (n=159) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/ReportView.swift` | `85% / 15% / 0%` (n=393) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/Sheet/ChannelOptionsSheet.swift` | `95% / 5% / 0%` (n=403) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/Sheet/NotificationSettingSheet.swift` | `87% / 13% / 0%` (n=109) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Home/ViewInvite.swift` | `93% / 7% / 0%` (n=341) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/CreateAccount/CreateAccount.swift` | `86% / 14% / 0%` (n=222) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/CreateAccount/OnboardingStage.swift` | `100% / 0% / 0%` (n=6) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/ForgotPassword/ForgotPassword.swift` | `83% / 17% / 0%` (n=96) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/ForgotPassword/ForgotPassword_Reset.swift` | `83% / 17% / 0%` (n=113) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/LoginIn/Login.swift` | `82% / 18% / 0%` (n=156) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/Mfa/Mfa.swift` | `86% / 14% / 0%` (n=140) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/Mfa/Sheets/MfaItem.swift` | `86% / 14% / 0%` (n=36) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/Mfa/Sheets/MFaNoneStep.swift` | `78% / 22% / 0%` (n=32) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/Mfa/Sheets/MfaOtp.swift` | `64% / 36% / 0%` (n=14) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/Mfa/Sheets/MfaRecovery.swift` | `73% / 27% / 0%` (n=26) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/Mfa/Sheets/MfaSheet.swift` | `90% / 10% / 0%` (n=167) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/NameYourSelf.swift` | `87% / 13% / 0%` (n=114) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/ResendEmail.swift` | `84% / 16% / 0%` (n=105) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/VerifyEmail/VerifyEmail.swift` | `87% / 13% / 0%` (n=84) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Login/Welcome.swift` | `88% / 12% / 0%` (n=129) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/About.swift` | `76% / 24% / 0%` (n=49) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/AppearanceSettings.swift` | `83% / 17% / 0%` (n=109) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/BlockedUsersView.swift` | `86% / 14% / 0%` (n=90) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/BotSettings/BotSetting.swift` | `88% / 12% / 0%` (n=170) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/BotSettings/BotSettings.swift` | `82% / 18% / 0%` (n=76) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/ChangeEmailView.swift` | `86% / 14% / 0%` (n=105) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/ChangePasswordView.swift` | `84% / 16% / 0%` (n=90) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/DeveloperSettings.swift` | `86% / 14% / 0%` (n=66) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/EnableAuthenticatorAppView.swift` | `89% / 11% / 0%` (n=111) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/ExperimentsSettings.swift` | `75% / 25% / 0%` (n=20) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/GetPasswordSheet.swift` | `86% / 14% / 0%` (n=108) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/LanguageSettings.swift` | `81% / 19% / 0%` (n=47) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/LogoutSessionSheet.swift` | `89% / 11% / 0%` (n=71) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/NotificationSettings.swift` | `83% / 17% / 0%` (n=60) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/ProfileSettings.swift` | `89% / 11% / 0%` (n=331) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/RecoveryCodesView.swift` | `88% / 12% / 0%` (n=225) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/RemoveAuthenticatorAppSheet.swift` | `90% / 10% / 0%` (n=158) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/SessionsSettings.swift` | `89% / 11% / 0%` (n=247) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/SettingAttentionView.swift` | `78% / 22% / 0%` (n=32) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/Settings.swift` | `91% / 9% / 0%` (n=117) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/SettingsCommon.swift` | `74% / 26% / 0%` (n=113) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/ShowRecoveryCodesView.swift` | `86% / 14% / 0%` (n=146) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/UserNameView.swift` | `85% / 15% / 0%` (n=101) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/UserSettings.swift` | `89% / 11% / 0%` (n=546) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/ValidatePasswordView.swift` | `90% / 10% / 0%` (n=109) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/You/PresenceSheet.swift` | `87% / 13% / 0%` (n=115) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/You/StatusPreviewSheet.swift` | `83% / 17% / 0%` (n=81) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/You/StatusSheet.swift` | `86% / 14% / 0%` (n=85) | Implements a feature page or screen-level user flow. |
| `Revolt/Pages/Settings/You/YouView.swift` | `87% / 13% / 0%` (n=190) | Implements a feature page or screen-level user flow. |
| `Revolt/RevoltApp.swift` | `88% / 12% / 0%` (n=484) | Defines `RevoltApp` (struct) for this module feature. |
| `Revolt/Theme.swift` | `100% / 0% / 0%` (n=407) | Defines `parseHex` (func) for this module feature. |
| `Revolt/Views/FriendRequestCard.swift` | `82% / 18% / 0%` (n=34) | Defines `FriendRequestCard` (struct) for this module feature. |
| `Revolt/ViewState+Extensions/ViewState+Auth.swift` | `96% / 4% / 0%` (n=135) | Extends `ViewState` with auth behavior. |
| `Revolt/ViewState+Extensions/ViewState+ChannelCache.swift` | `99% / 1% / 0%` (n=143) | Extends `ViewState` with channelcache behavior. |
| `Revolt/ViewState+Extensions/ViewState+DMChannel.swift` | `98% / 2% / 0%` (n=102) | Extends `ViewState` with dmchannel behavior. |
| `Revolt/ViewState+Extensions/ViewState+Drafts.swift` | `98% / 2% / 0%` (n=50) | Extends `ViewState` with drafts behavior. |
| `Revolt/ViewState+Extensions/ViewState+MembershipCache.swift` | `96% / 4% / 0%` (n=73) | Extends `ViewState` with membershipcache behavior. |
| `Revolt/ViewState+Extensions/ViewState+Memory.swift` | `99% / 1% / 0%` (n=360) | Extends `ViewState` with memory behavior. |
| `Revolt/ViewState+Extensions/ViewState+Navigation.swift` | `95% / 5% / 0%` (n=170) | Extends `ViewState` with navigation behavior. |
| `Revolt/ViewState+Extensions/ViewState+Notifications.swift` | `97% / 3% / 0%` (n=142) | Extends `ViewState` with notifications behavior. |
| `Revolt/ViewState+Extensions/ViewState+QueuedMessages.swift` | `98% / 2% / 0%` (n=91) | Extends `ViewState` with queuedmessages behavior. |
| `Revolt/ViewState+Extensions/ViewState+ReadyEvent.swift` | `99% / 1% / 0%` (n=183) | Extends `ViewState` with readyevent behavior. |
| `Revolt/ViewState+Extensions/ViewState+ServerCache.swift` | `96% / 4% / 0%` (n=70) | Extends `ViewState` with servercache behavior. |
| `Revolt/ViewState+Extensions/ViewState+Types.swift` | `99% / 1% / 0%` (n=241) | Extends `ViewState` with types behavior. |
| `Revolt/ViewState+Extensions/ViewState+Unreads.swift` | `99% / 1% / 0%` (n=268) | Extends `ViewState` with unreads behavior. |
| `Revolt/ViewState+Extensions/ViewState+UsersAndDms.swift` | `99% / 1% / 0%` (n=333) | Extends `ViewState` with usersanddms behavior. |
| `Revolt/ViewState+Extensions/ViewState+WebSocketEvents.swift` | `100% / 0% / 0%` (n=684) | Extends `ViewState` with websocketevents behavior. |
| `Revolt/ViewState.swift` | `99% / 1% / 0%` (n=1592) | Defines `ViewState` (class) for this module feature. |

## RevoltTests

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `RevoltTests/RevoltTests.swift` | `100% / 0% / 0%` (n=14) | Contains automated test coverage for related app behavior. |

## RevoltUITests

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `RevoltUITests/RevoltUITests.swift` | `100% / 0% / 0%` (n=19) | Contains automated test coverage for related app behavior. |
| `RevoltUITests/RevoltUITestsLaunchTests.swift` | `94% / 6% / 0%` (n=17) | Contains automated test coverage for related app behavior. |

## Root

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `Package.swift` | `100% / 0% / 0%` (n=17) | Declares Swift package products, dependencies, and targets. |
| `UITableView+ScrollPositionPreservation.swift` | `98% / 0% / 2%` (n=110) | Extends `UITableView` with scrollpositionpreservation behavior. |

## Sources

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `Sources/revolt-ios/revolt_ios.swift` | `0% / 0% / 0%` (n=0) | Provides source code supporting this module. |

## Tests

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `Tests/revolt-iosTests/revolt_iosTests.swift` | `100% / 0% / 0%` (n=4) | Contains automated test coverage for related app behavior. |

## Types

| File | Stack share (Swift / SwiftUI / UIKit) | One-line contribution |
| --- | --- | --- |
| `Types/Api.swift` | `100% / 0% / 0%` (n=66) | Defines shared domain data types used across modules. |
| `Types/Badges.swift` | `100% / 0% / 0%` (n=69) | Defines shared domain data types used across modules. |
| `Types/Bot.swift` | `100% / 0% / 0%` (n=19) | Defines shared domain data types used across modules. |
| `Types/Channel.swift` | `100% / 0% / 0%` (n=369) | Defines shared domain data types used across modules. |
| `Types/Embed.swift` | `100% / 0% / 0%` (n=187) | Defines shared domain data types used across modules. |
| `Types/Emoji.swift` | `100% / 0% / 0%` (n=66) | Defines shared domain data types used across modules. |
| `Types/File.swift` | `100% / 0% / 0%` (n=84) | Defines shared domain data types used across modules. |
| `Types/Invite.swift` | `100% / 0% / 0%` (n=57) | Defines shared domain data types used across modules. |
| `Types/Member.swift` | `100% / 0% / 0%` (n=32) | Defines shared domain data types used across modules. |
| `Types/Message.swift` | `100% / 0% / 0%` (n=208) | Defines shared domain data types used across modules. |
| `Types/Permissions.swift` | `98% / 2% / 0%` (n=167) | Defines shared domain data types used across modules. |
| `Types/Role.swift` | `100% / 0% / 0%` (n=15) | Defines shared domain data types used across modules. |
| `Types/Server.swift` | `100% / 0% / 0%` (n=81) | Defines shared domain data types used across modules. |
| `Types/ServerChannel.swift` | `100% / 0% / 0%` (n=5) | Defines shared domain data types used across modules. |
| `Types/Types.h` | `100% / 0% / 0%` (n=2) | Defines shared domain data types used across modules. |
| `Types/Types.swift` | `0% / 0% / 0%` (n=0) | Defines shared domain data types used across modules. |
| `Types/User.swift` | `100% / 0% / 0%` (n=108) | Defines shared domain data types used across modules. |
| `Types/Widget.swift` | `100% / 0% / 0%` (n=22) | Defines shared domain data types used across modules. |

