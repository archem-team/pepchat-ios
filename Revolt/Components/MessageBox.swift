import Foundation
import SwiftUI
import PhotosUI
import Types
import SwiftUIIntrospect

/// Represents a reply to a message in a chat. It contains the message itself and a flag to check if the reply includes a mention.
struct Reply : Identifiable, Equatable {
    var message: Message                // The original message being replied to
    var mention: Bool = true           // Indicates whether the reply mentions the user (default is false)
    
    var id: String { message.id }
    
}



/// A SwiftUI view that displays a single reply within a list of replies.
struct ReplyView: View {
    
    @EnvironmentObject var viewState: ViewState
    
    @Binding var reply: Reply
    
    @Binding var replies: [Reply]       // A binding to the array of replies in the parent view
    
    var channel: Channel                // The channel in which the reply was made
    var server: Server?                 // The server where the channel belongs, optional
    
    /// Removes the reply at the given index from the array of replies.
    func remove() {
        //withAnimation {
            replies.removeAll(where: { $0.id == reply.id })
        //}
    }
    
    
    /// The body of the ReplyView, which displays the reply details, user avatar, content, and controls for mentions and removal.
    @ViewBuilder
    var body: some View {
        if let user = viewState.users[reply.message.author] {
            let member = server.flatMap { viewState.members[$0.id]?[user.id] }
            replyRowContent(displayName: reply.message.masquerade?.name ?? member?.nickname ?? user.display_name ?? user.username)
        } else {
            replyRowContent(displayName: "Unknown user")
        }
    }

    @ViewBuilder
    private func replyRowContent(displayName: String) -> some View {
        // Horizontal stack to display the reply information
        HStack(spacing: .padding4) {
            // Button to remove the reply
            Button(action: remove) {
                PeptideIcon(iconName: .peptideClose,
                            size: .size24, color: .iconGray07)
            }
            .padding(.trailing, .padding4)

            PeptideText(text: "Replying to",
                        font: .peptideBody4,
                        textColor: .textGray04,
                        lineLimit: 1)

            PeptideText(textVerbatim: displayName,
                        font: .peptideCallout,
                        textColor: .textDefaultGray01)

            // Display an attachment icon if the message contains attachments
            if !(reply.message.attachments?.isEmpty ?? true) {
                PeptideIcon(iconName: .peptideAttachment,
                            size: .size24, color: .iconGray07)
            }

            // Display the content of the reply, if it exists
            if let content = Binding($reply.message.content) {
                Contents(text: content,
                         fontSize: PeptideFont.peptideFootnote.fontSize,
                         font: PeptideFont.peptideFootnote.font,
                         foregroundColor: .textGray07)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: .size8)

            // Button to toggle the mention status of the reply
            Button(action: { reply.mention.toggle() }) {
                HStack(spacing: .spacing2) {
                    PeptideIcon(iconName: .peptideAt,
                                size: .size20,
                                color: reply.mention ? .iconYellow07 : .iconGray07)
                    PeptideText(text: reply.mention ? "On" : "Off",
                                font: .peptideFootnote,
                                textColor: reply.mention ? .textYellow07 : .textGray07)
                }
            }
        }
        .padding(.horizontal, .padding16)
        .frame(height: .size40)
        .background(Color.bgGray12)
    }
}


struct MessageBox: View {
    enum AutocompleteType {
        case user
        case channel
        case emoji
    }
    
    enum AutocompleteValues {
        case channels([Channel])
        case users([(User, Member?)])
        case emojis([PickerEmoji])
    }
    
    struct Photo: Identifiable, Hashable {
        let data: Data
        #if os(macOS)
        let image: NSImage?
        #else
        let image: UIImage?
        #endif
        let id: UUID
        
        let fullFileName: String
        
        let fileName : String
        let fileExtension : String
    }
    
    @EnvironmentObject var viewState: ViewState
    
    @Binding var channelReplies: [Reply]
    var focusState: FocusState<Bool>.Binding
    @Binding var showingSelectEmoji: Bool
    @Binding var editing: Message?
    
    @State var showingSelectFile = false
    @State var showingSelectPhoto = false
    
    @State var reshowKeyboard = false
    
    @State var content = ""
    
    @State var selectedPhotos: [Photo] = []
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    @State var selectedEmoji: String = ""
    
    @State var autoCompleteType: AutocompleteType? = nil
    @State var autocompleteSearchValue: String = ""
    
    @State var isSendingMessage : Bool = false
    
    @State private var isTyping: Bool = false
    @State private var typingTimer: Timer? = nil
    @State private var viewHeight: CGFloat = 0
    @State private var maxMentionListHeight: CGFloat = 200
    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardVisible: Bool = false
    @State private var keyboardAnimationDuration: Double = 0.25
    
    let channel: Channel
    let server: Server?
    
    @State var submitedMention : Bool = false
    
    @State private var mentionsScrollViewContentSize: CGSize = .zero
    

    init(channel: Channel,
         server: Server?,
         channelReplies: Binding<[Reply]>,
         focusState f: FocusState<Bool>.Binding,
         showingSelectEmoji: Binding<Bool>,
         editing: Binding<Message?>) {
        self.channel = channel
        self.server = server
        _channelReplies = channelReplies
        focusState = f
        _showingSelectEmoji = showingSelectEmoji
        _editing = editing
        
        if let msg = editing.wrappedValue {
            content = msg.content ?? ""
        }
        
    }
    
    func sendMessage() {
        var c = content
        
        // Find and convert ALL user mentions to the correct format <@user_id>
        let mentionRegex = try! NSRegularExpression(pattern: "@([A-Za-z0-9_]+)")
        let mentionMatches = mentionRegex.matches(in: c, range: NSRange(c.startIndex..., in: c))
        
        // Process in reverse to avoid changing the indices
        for match in mentionMatches.reversed() {
            if let range = Range(match.range, in: c),
               let usernameRange = Range(match.range(at: 1), in: c) {
                let username = String(c[usernameRange])
                
                // Find the user by username
                if let user = viewState.users.values.first(where: { $0.username == username }) {
                    let replacement = "<@\(user.id)>"
                    c.replaceSubrange(range, with: replacement)
                    print("DEBUG: Converted @\(username) to \(replacement)")
                }
            }
        }
        
        content = ""
        let replies = channelReplies
        channelReplies = []
        
        if let message = editing {
            Task {
                editing = nil
                let _ = await viewState.http.editMessage(channel: channel.id, message: message.id, edits: MessageEdit(content: c))
            }
            
        } else {
            let f = selectedPhotos.map({ ($0.data, $0.fullFileName) })
            
            Task {
                isSendingMessage = true
                await viewState.queueMessage(channel: channel.id, replies: replies, content: c, attachments: f)
                selectedPhotos = []
                isSendingMessage = false
            }
        }
    }
    
    func getAutocompleteValues(fromType type: AutocompleteType) -> AutocompleteValues {
        switch type {
        case .user:
            var users: [(User, Member?)]
            switch channel {
            case .saved_messages(_):
                users = viewState.currentUser.map { [($0, nil)] } ?? []
            case .dm_channel(let dMChannel):
                users = dMChannel.recipients.compactMap { viewState.users[$0].map { ($0, nil) } }
            case .group_dm_channel(let groupDMChannel):
                users = groupDMChannel.recipients.compactMap { viewState.users[$0].map { ($0, nil) } }
            case .text_channel(_), .voice_channel(_):
                if let server = server, let members = viewState.members[server.id] {
                    users = members.values.compactMap { m in viewState.users[m.id.user].map { ($0, m) } }
                } else {
                    users = []
                }
            }
            return AutocompleteValues.users(users.filter { pair in
                (pair.0.display_name?.lowercased().starts(with: autocompleteSearchValue.lowercased()) ?? false)
                || (pair.1?.nickname?.lowercased().starts(with: autocompleteSearchValue.lowercased()) ?? false)
                || (pair.0.usernameWithDiscriminator().lowercased().starts(with: autocompleteSearchValue.lowercased()))
            })
        case .channel:
            let channels: [Channel]
            switch channel {
            case .saved_messages(_), .dm_channel(_), .group_dm_channel(_):
                channels = [channel]
            case .text_channel(_), .voice_channel(_):
                channels = server.map { $0.channels.compactMap { viewState.channels[$0] } } ?? []
            }
            
            return AutocompleteValues.channels(channels.filter { channel in
                channel.getName(viewState).lowercased().starts(with: autocompleteSearchValue.lowercased())
            })
        case .emoji:
            return AutocompleteValues.emojis(loadEmojis(withState: viewState)
                .values
                .flatMap { $0 }
                .filter { emoji in
                    let names: [String]
                    
                    if let emojiId = emoji.emojiId, let emoji = viewState.emojis[emojiId] {
                        names = [emoji.name]
                    } else {
                        var values = emoji.alternates
                        values.append(emoji.base)
                        names = values.map { String(String.UnicodeScalarView($0.compactMap(Unicode.Scalar.init))) }
                    }
                    
                    return names.contains(where: { $0.lowercased().starts(with: autocompleteSearchValue.lowercased()) })
                })
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Replies section
            ForEach($channelReplies) { reply in
                ReplyView(reply: reply, replies: $channelReplies, channel: channel, server: server)
            }
            .animation(.default, value: channelReplies)
            
            // Editing indicator
            if editing != nil {
                HStack(spacing: .padding4) {
                    Button {
                        editing = nil
                        content = ""
                    } label: {
                        PeptideIcon(iconName: .peptideClose,
                                    size: .size24, color: .iconGray07)
                    }
                    .padding(.trailing, .padding4)
                    
                    PeptideText(text: "Editing Message",
                                font: .peptideBody4,
                                textColor: .textGray04,
                                lineLimit: 1)
                    
                    Spacer(minLength: .size8)
                }
                .padding(.horizontal, .padding16)
                .frame(height: .size40)
                .background(Color.bgGray12)
            }
            
            // Chat input section
            VStack(alignment: .leading, spacing: .padding4) {
                // Attachment thumbnails section
                if selectedPhotos.count > 0 {
                    attachmentThumbnailsView()
                }
                
                // Main input row with message box and buttons
                HStack(alignment: .center, spacing: .padding8) {
                    // Upload button (if permissions allow)
                    if let currentUser = viewState.currentUser, editing == nil {
                        if resolveChannelPermissions(from: currentUser, targettingUser: currentUser, targettingMember: server.flatMap { viewState.members[$0.id]?[currentUser.id] }, channel: channel, server: server).contains(.uploadFiles) {
                            UploadButton(showingSelectFile: $showingSelectFile, showingSelectPhoto: $showingSelectPhoto, selectedPhotoItems: $selectedPhotoItems, selectedPhotos: $selectedPhotos)
                                .frame(alignment: .top)
                        }
                    }
                    
                    // Message input field with mention overlay
                    ZStack(alignment: .top) {
                        textFieldWithHandlers()
                            .onDisappear {
                                typingTimer?.invalidate()
                                typingTimer = nil
                                if isTyping {
                                    viewState.sendEndTyping(channel: self.channel.id)
                                }
                            }
                            .sheet(isPresented: $showingSelectEmoji) {
                                EmojiPicker(background: AnyView(Color.bgGray12)) { emoji in
                                    if let id = emoji.emojiId {
                                        content.append(":\(id):")
                                    } else {
                                        content.append(String(String.UnicodeScalarView(emoji.base.compactMap(Unicode.Scalar.init))))
                                    }
                                    
                                    showingSelectEmoji = false
                                }
                                .padding([.top, .horizontal], .padding16)
                                .presentationDetents([.fraction(0.4), .large])
                                .presentationDragIndicator(.visible)
                                .presentationBackground(Color.bgGray12)
                            }
                        
                        // Mention popup
                        if let type = autoCompleteType, 
                           case AutocompleteValues.users(let users) = getAutocompleteValues(fromType: type), 
                           !users.isEmpty,
                           focusState.wrappedValue { // Only show when text field has focus
                            
                            mentionUsersListView(users: users)
                                .background(Color.bgGray11)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.borderGray10.opacity(0.3), lineWidth: 0.5)
                                )
                                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                                .frame(maxHeight: 200)
                                .offset(y: -220) // Position above text field with more spacing
                                .zIndex(10)
                        }
                    }
                    .padding(top: .padding8, bottom: .padding8, leading: .padding16, trailing: .padding8)
                    .frame(minHeight: .size40)
                    .background {
                        RoundedRectangle(cornerRadius: .radiusLarge).fill(Color.bgGray11)
                    }
                    
                    // Emoji button
                    emojiButtonView()
                    
                    // Send button
                    if !content.isEmpty || !selectedPhotos.isEmpty {
                        Button(action: sendMessage) {
                            PeptideIcon(iconName: .peptideSend,
                                        size: 36,
                                        color: .bgDefaultPurple13)
                            .frame(width: .size40, height: .size40)
                            .background{
                                Circle().fill(Color.bgYellow07)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, .padding16)
            .padding(.vertical, .padding8)
            .background(Color.bgDefaultPurple13)
        }
        .background(Color.bgDefaultPurple13)
    }
    
    private func setupKeyboardHeightTracking() {
        // Reset keyboard height
        keyboardHeight = 0
        keyboardVisible = false
        
        // Observe keyboard notifications
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
               let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
                keyboardHeight = keyboardFrame.height
                keyboardAnimationDuration = duration
                
                withAnimation(.easeOut(duration: duration)) {
                    keyboardVisible = true
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
                withAnimation(.easeOut(duration: duration)) {
                    keyboardVisible = false
                    keyboardHeight = 0
                }
            }
        }
    }
    
    // MARK: - TextField Configuration
    
    @ViewBuilder
    private func textFieldConfiguration() -> some View {
        TextField("", text: $content, axis: .vertical)
            .focused(focusState)
            .placeholder(when: content.isEmpty) {
                PeptideText(text: "Message \(channel.getName(viewState))",
                            font: .peptideBody3,
                            textColor: .textGray07,
                            alignment: .leading)
            }
            .font(.peptideBody3Font)
            .foregroundStyle(.textDefaultGray01)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .tint(.textDefaultGray01)
            .lineLimit(1...8) // Allow 1 to 8 lines
    }
    
    @ViewBuilder
    private func textFieldIntrospection() -> some View {
        textFieldConfiguration()
            .introspect(.textEditor) { (textField: UITextView) in
                // Configure text field for better keyboard behavior
                textField.inputAccessoryView = nil
                textField.autocorrectionType = .no
                
                // Allow non-contiguous layout to avoid input issues with emoji/IME composition
                textField.layoutManager.allowsNonContiguousLayout = true
                
                // Set return key type to default (allows new lines)
                textField.returnKeyType = .default
                
                // Set the keyboard appearance to match the dark theme
                textField.keyboardAppearance = .dark
                
                // Enable multiline editing - simplified configuration
                textField.isScrollEnabled = true
                textField.textContainer.maximumNumberOfLines = 0
                
                // Adjust text container insets for better placeholder positioning
                textField.textContainerInset = UIEdgeInsets(top: 6, left: 10, bottom: 14, right: 14)
            }
    }
    
    @ViewBuilder
    private func textFieldWithHandlers() -> some View {
        textFieldIntrospection()
            .onSubmit {
                // Handle submit - for now allow default behavior (new line)
            }
            .onChange(of: content) { _, value in
                handleContentChange(value)
            }
            .onChange(of: focusState.wrappedValue) { _, v in
                if v, showingSelectEmoji {
                    showingSelectEmoji = false
                }
            }
            .onChange(of: showingSelectEmoji) { b, a in
                if b, !a {
                    focusState.wrappedValue = true
                }
            }
            .onChange(of: editing) { _, a in
                if let a {
                    selectedPhotos = []
                    selectedPhotoItems = []
                    autoCompleteType = nil
                    autocompleteSearchValue = ""
                    content = a.content ?? ""
                } else {
                    channelReplies = []
                    content = ""
                }
            }
    }
    
    @ViewBuilder
    private func emojiButtonView() -> some View {
        Group {
            Button {
                focusState.wrappedValue = false
                showingSelectEmoji.toggle()
            } label: {
                PeptideIcon(iconName: .peptideSmile,
                            size: .size24,
                            color: .iconGray04)
            }
        }
        .frame(alignment: .top)
    }
    
    // MARK: - Mention Components
    
    @ViewBuilder
    private func mentionUserButton(user: User, member: Member?) -> some View {
        Button {
            // Handle user selection with improved safety checks
            let currentContent = content
            
            // Find the last @ symbol
            if let lastAtIndex = currentContent.lastIndex(of: "@") {
                // Safety check: make sure index is valid
                guard lastAtIndex >= currentContent.startIndex && lastAtIndex < currentContent.endIndex else {
                    // Fallback: append mention at the end
                    content = currentContent + "<@\(user.id)> "
                    submitedMention = true
                    autoCompleteType = nil
                    return
                }
                
                // Replace everything from @ to the end with the mention
                let beforeAt = String(currentContent[..<lastAtIndex])
                let mention = "<@\(user.id)> "
                content = beforeAt + mention
            } else {
                // Fallback: append mention at the end
                content = currentContent + "<@\(user.id)> "
            }
            
            submitedMention = true
            autoCompleteType = nil
        } label: {
            HStack(spacing: 12) {
                Avatar(user: user,
                       member: member,
                       width: .size32,
                       height: .size32,
                       withPresence: true)
                
                PeptideText(textVerbatim: "\(member?.nickname ?? user.display_name ?? user.username)",
                            font: .peptideButton,
                            textColor: .textDefaultGray01,
                            lineLimit: 1)
                
                Spacer(minLength: .zero)
                
                let username = "\(user.username)#\(user.discriminator)"
                
                PeptideText(textVerbatim: username,
                            font: .peptideFootnote,
                            textColor: .textGray07,
                            lineLimit: 1)
            }
        }
        .padding(.horizontal, .padding12)
        .frame(height: .size48)
    }
    
    @ViewBuilder
    private func mentionUsersListView(users: [(User, Member?)]) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(users, id: \.0.id) { (user, member) in
                    mentionUserButton(user: user, member: member)
                }
            }
            .background(
                GeometryReader { geo -> Color in
                    DispatchQueue.main.async {
                        mentionsScrollViewContentSize = geo.size
                    }
                    return Color.clear
                }
            )
        }
        .introspect(.scrollView) { (scrollView: UIScrollView) in
            scrollView.bounces = true
            scrollView.layer.masksToBounds = true
            scrollView.layer.cornerRadius = 8
        }
        .frame(maxHeight: min(mentionsScrollViewContentSize.height, maxMentionListHeight))
    }
    
    @ViewBuilder
    private func attachmentThumbnailsView() -> some View {
                        ScrollView(.horizontal) {
                            HStack(spacing: .spacing4) {
                ForEach($selectedPhotos, id: \.self) { fileBinding in
                    let file = fileBinding.wrappedValue
                                    
                                    if let image = file.image {
                        imageAttachmentView(for: file)
                    } else {
                        fileAttachmentView(for: file)
                    }
                }
            }
        }
        .padding(.vertical, .padding8)
    }
    
    @ViewBuilder
    private func imageAttachmentView(for file: Photo) -> some View {
                                        ZStack(alignment: .topTrailing) {
    #if os(iOS)
            Image(uiImage: file.image!)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .size40, maxHeight: .size40)
                                                .clipShape(RoundedRectangle(cornerRadius: .radiusXSmall, style: .circular))
                                                .overlay(alignment: .center){
                                                    if isSendingMessage {
                                                        ProgressView()
                                                            .tint(Color.iconYellow07)
                                                    }
                                                }
                                                .padding(top: .padding8, trailing: .padding8)
    #else
            Image(nsImage: file.image!)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .size40, maxHeight: .size40)
                                                .clipShape(RoundedRectangle(cornerRadius: .radiusXSmall, style: .circular))
                                                .overlay(alignment: .center){
                                                    if isSendingMessage {
                                                        ProgressView()
                                                            .tint(Color.iconYellow07)
                                                    }
                                                }
                                                .padding(top: .padding8, trailing: .padding8)
    #endif
                                            
                                            Button(action: {
                                                    selectedPhotos.removeAll(where: { $0.id == file.id })
                                             }) {
                                                PeptideIcon(iconName: .peptideClose,
                                                            size: .size20,
                                                            color: .iconGray04)
                                            }
                                        }
                                        .frame(width: .size48, height: .size48)
    }
                                        
    @ViewBuilder
    private func fileAttachmentView(for file: Photo) -> some View {
                                        ZStack(alignment: .topTrailing) {
                                            HStack(spacing: .spacing4){
                                                PeptideIcon(iconName: .peptideAttachment,
                                                            size: .size24,
                                                            color: .iconDefaultGray01)
                                                
                                                VStack(alignment: .leading, spacing: .zero){
                                                    PeptideText(textVerbatim: file.fileName,
                                                                font: .peptideCaption1,
                                                                textColor: .textDefaultGray01)
                                                    
                                                    PeptideText(textVerbatim: file.fileExtension,
                                                                font: .peptideCaption1,
                                                                textColor: .textGray07)
                                                }
                                            }
                                            .padding(.leading, .padding4)
                                            .padding(.trailing, .padding8)
                                            .frame(height: .size40)
                                            .background{
                                                RoundedRectangle(cornerRadius: .radius8)
                                                    .fill(Color.bgGray11)
                                            }
                                            .padding(top: .padding8, trailing: .padding8)
                                            
                                            Button(action: {
                                                    selectedPhotos.removeAll(where: { $0.id == file.id })
                                            }) {
                                                PeptideIcon(iconName: .peptideClose,
                                                            size: .size20,
                                                            color: .iconGray04)
            }
                                        }
                                    }
                                    
    private func handleContentChange(_ value: String) {
        // Reset autocomplete by default
        autoCompleteType = nil
        autocompleteSearchValue = ""
        
        // Safety check for empty string
        guard !value.isEmpty else {
            // Handle typing indicator for empty string
            handleTypingIndicator()
            return
        }
        
        // Find the last @ symbol in the text
        if let lastAtIndex = value.lastIndex(of: "@") {
            // Safety check: make sure we can get next index
            guard lastAtIndex < value.endIndex else {
                checkOtherAutocompleteTriggers(value)
                handleTypingIndicator()
                return
            }
            
            let afterAtIndex = value.index(after: lastAtIndex)
            
            // Safety check: make sure the range is valid
            guard afterAtIndex <= value.endIndex else {
                checkOtherAutocompleteTriggers(value)
                handleTypingIndicator()
                return
            }
            
            // Get text after @ symbol
            let textAfterAt = String(value[afterAtIndex...])
            
            // If there's no space after @, then we're in a mention
            if !textAfterAt.contains(" ") && !textAfterAt.contains("\n") {
                if !submitedMention {
                    autoCompleteType = .user
                    autocompleteSearchValue = textAfterAt
                }
                submitedMention = false
            } else {
                // There's a space, check if we need to look for other triggers
                checkOtherAutocompleteTriggers(value)
            }
        } else {
            // No @ found, check for other triggers
            checkOtherAutocompleteTriggers(value)
        }
        
        // Handle typing indicator
        handleTypingIndicator()
    }
    
    private func handleTypingIndicator() {
        Task {
            if !isTyping {
                isTyping = true
                viewState.sendBeginTyping(channel: self.channel.id)
            }

            typingTimer?.invalidate()
            typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                Task { @MainActor in
                    isTyping = false
                    viewState.sendEndTyping(channel: self.channel.id)
                }
            }
        }
    }
    
    private func checkOtherAutocompleteTriggers(_ value: String) {
        // Safety check for empty string
        guard !value.isEmpty else { return }
        
        // Check for # and : triggers using the original logic
        let words = value.split(separator: " ")
        guard let last = words.last, !last.isEmpty else { return }
        
        let pre = last.first
        let searchValue = String(last.dropFirst())
        
        switch pre {
        case "#":
            autoCompleteType = .channel
            autocompleteSearchValue = searchValue
        case ":":
            autoCompleteType = .emoji
            autocompleteSearchValue = searchValue
        default:
            break
        }
    }
}


/// A button view for uploading files or photos, allowing users to select files from their device.
struct UploadButton: View {
    @EnvironmentObject var viewState: ViewState // Access to the global application state
    
    @Binding var showingSelectFile: Bool          // Binding for showing the file selection dialog
    @Binding var showingSelectPhoto: Bool         // Binding for showing the photo selection dialog
    @Binding var selectedPhotoItems: [PhotosPickerItem] // Binding for the selected photo items
    @Binding var selectedPhotos: [MessageBox.Photo]    // Binding for the selected photos
    
    @State private var isPresentedAttachmentsSheet : Bool = false
    
    
    /// Handles the completion of file selection.
    /// - Parameter res: The result of the file selection operation, containing either a URL or an error.
    func onFileCompletion(res: Result<URL, Error>) {
        // Check if the file selection was successful and start accessing the resource
        if case .success(let url) = res, url.startAccessingSecurityScopedResource() {
            let data = try? Data(contentsOf: url) // Attempt to read data from the file URL
            url.stopAccessingSecurityScopedResource() // Stop accessing the resource
            
            guard let data = data else { return } // Exit if data could not be loaded
            
            // Create an image from the loaded data based on the platform
#if os(macOS)
            let image = NSImage(data: data) // Use NSImage for macOS
#else
            let image = UIImage(data: data) // Use UIImage for iOS
#endif
            
            
            let fullFileName = url.lastPathComponent // e.g., "example.png"
            let fileName = url.deletingPathExtension().lastPathComponent // e.g., "example"
            let fileExtension = url.pathExtension // e.g., "png"
            
            // Append the new photo to the selectedPhotos array
            selectedPhotos.append(.init(data: data,
                                        image: image,
                                        id: UUID(),
                                        fullFileName: fullFileName,
                                        fileName:fileName,
                                        fileExtension: fileExtension
                                       ))
        }
    }
    
    /// The body of the UploadButton view, defining the UI elements and interactions.
    var body: some View {
        
        Button {
            // Gesture recognizer for tapping the button
            //showingSelectPhoto = true
            isPresentedAttachmentsSheet.toggle()
        } label: {
            
            PeptideIcon(iconName: .peptideAdd,
                        size: .size24,
                        color: .iconDefaultGray01)
            .frame(width: .size40, height: .size40)
            .background(Circle().fill(Color.bgGray11))
        }
        // Presents a photo picker when the user taps the button
        .photosPicker(isPresented: $showingSelectPhoto, selection: $selectedPhotoItems)
        .photosPickerStyle(.presentation) // Style for the photos picker
        
        // File importer for selecting files from the device
        .fileImporter(isPresented: $showingSelectFile, allowedContentTypes: [.item], onCompletion: onFileCompletion)
        
        // Context menu for additional file/photo selection options
        /*.contextMenu {
         Button(action: {
         showingSelectFile = true // Show file selection dialog
         }) {
         Text("Select File")
         }
         Button(action: {
         showingSelectPhoto = true // Show photo selection dialog
         }) {
         Text("Select Photo")
         }
         }*/
        // Responds to changes in selected photo items
        .onChange(of: selectedPhotoItems) { before, after in
            // Ensure there are new items to process
            if after.isEmpty { return }
            Task {
                for item in after {
                    // Load the data for each selected item
                    if let data = try? await item.loadTransferable(type: Data.self) {
#if os(macOS)
                        let img = NSImage(data: data) // Create NSImage for macOS
#else
                        let img = UIImage(data: data) // Create UIImage for iOS
#endif
                        
                        
                        
                        // Append the loaded image and data to selectedPhotos
                        if let img = img {
                            let fileType = item.supportedContentTypes[0].preferredFilenameExtension! // Get the file type
                            let fileName = (item.itemIdentifier ?? "Image") + ".\(fileType)" // Generate the filename
                            selectedPhotos.append(.init(data: data,
                                                        image: img, id: UUID(),
                                                        fullFileName: fileName,
                                                        fileName: fileName,
                                                        fileExtension: ""))
                        }
                    }
                }
                selectedPhotoItems.removeAll() // Clear the selected photo items
            }
        }
        .sheet(isPresented: $isPresentedAttachmentsSheet){
            AttachmentsSheet(isPresented: $isPresentedAttachmentsSheet, onClick: { attachments in
                
                switch attachments {
                case .gallery:
                    showingSelectPhoto = true
                case .camera: break
                    //.peptideCamera
                case .file:
                    showingSelectFile = true
                }
            })
        }
    }
}

/// Preview provider for the UploadButton to enable SwiftUI previews.
struct MessageBox_Previews: PreviewProvider {
    static var viewState: ViewState = ViewState.preview().applySystemScheme(theme: .dark) // Preview state
    @State static var replies: [Reply] = [] // Example replies for the preview
    @State static var showingSelectEmoji = false // Flag for showing emoji selection
    @FocusState static var focused: Bool // Focus state for the text input
    
    /// Previews the MessageBox with a mock channel and server data.
    static var previews: some View {
        Group {
            if let channel = viewState.channels["0"], let server = viewState.servers["0"] {
                MessageBox(channel: channel, server: server, channelReplies: $replies, focusState: $focused, showingSelectEmoji: $showingSelectEmoji, editing: .constant(nil))
                    .applyPreviewModifiers(withState: viewState)
                    .preferredColorScheme(.dark)
            } else {
                Text("Preview unavailable — channel or server not in preview state")
            }
        }
    }
}




struct FixedSizeScrollView: ViewModifier {
    let axis: Axis.Set
    
    init(axis: Axis.Set) {
        self.axis = axis
    }
    
    func body(content: Content) -> some View {
        ViewThatFits(in: axis) {
            content
            ScrollView(axis) {
                content
            }
        }
    }
}

extension View {
    func fixedSizeScrollView(_ axis: Axis.Set = .vertical) -> some View {
        modifier(FixedSizeScrollView(axis: axis))
    }
}

