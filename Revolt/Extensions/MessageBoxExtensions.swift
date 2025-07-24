import SwiftUI
import SwiftUIIntrospect

extension View {
    /// Configure TextField for chat functionality
    func configureChatTextField() -> some View {
        self.introspect(.textEditor) { textField in
            // Configure text field for better keyboard behavior
            textField.inputAccessoryView = nil
            textField.autocorrectionType = .no
            
            // Make sure text field resizing doesn't cause jumps
            textField.layoutManager.allowsNonContiguousLayout = false
            
            // Set return key type to default (allows new lines)
            textField.returnKeyType = .default
            
            // Set the keyboard appearance to match the dark theme
            textField.keyboardAppearance = .dark
            
            // Enable multiline editing - simplified configuration
            textField.isScrollEnabled = true
            textField.textContainer.maximumNumberOfLines = 0
        }
    }
    
    /// Apply placeholder to a TextField when it's empty
    func withChatPlaceholder(text: String, viewState: ViewState) -> some View {
        self.placeholder(when: text.isEmpty) {
            PeptideText(text: "Message \(text)",
                        font: .peptideBody3,
                        textColor: .textGray07,
                        alignment: .leading)
        }
    }
}

// Helper for handling mention visualization
struct MentionListContainer: View {
    let users: [(User, Member?)]
    let autocompleteSearchValue: String
    let content: Binding<String>
    @Binding var submitedMention: Bool
    @Binding var autoCompleteType: MessageBox.AutocompleteType?
    let geometry: GeometryProxy
    @Binding var mentionsScrollViewContentSize: CGSize
    let maxMentionListHeight: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(users, id: \.0.id) { (user, member) in
                        mentionButton(for: user, member: member)
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
            .introspect(.scrollView) { scrollView in
                scrollView.bounces = true
                scrollView.layer.masksToBounds = true
                scrollView.layer.cornerRadius = 12
            }
            .frame(maxHeight: min(mentionsScrollViewContentSize.height, maxMentionListHeight))
            .background(Color.bgGray11)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderGray10.opacity(0.3), lineWidth: 0.5)
            )
        }
        .frame(width: geometry.size.width - 32) // Account for padding
        .offset(y: -maxMentionListHeight - 20) // Position above text field with more spacing
        .zIndex(1) // Ensure it appears above other content
        .transition(.opacity)
    }
    
    private func mentionButton(for user: User, member: Member?) -> some View {
        Button {
            // Handle user selection with improved safety checks
            let currentContent = content.wrappedValue
            
            // Find the last @ symbol
            if let lastAtIndex = currentContent.lastIndex(of: "@") {
                // Safety check: make sure index is valid
                guard lastAtIndex >= currentContent.startIndex && lastAtIndex < currentContent.endIndex else {
                    // Fallback: append mention at the end
                    content.wrappedValue = currentContent + "@\(user.username) "
                    submitedMention = true
                    autoCompleteType = nil
                    return
                }
                
                // Replace everything from @ to the end with the mention
                let beforeAt = String(currentContent[..<lastAtIndex])
                let mention = "@\(user.username) "
                content.wrappedValue = beforeAt + mention
            } else {
                // Fallback: append mention at the end
                content.wrappedValue = currentContent + "@\(user.username) "
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
} 