//
//  ServerEmojiItemView.swift
//  Revolt
//
//

import SwiftUI
import Types

struct ServerEmojiItemView: View {
    
    /// The environment object that holds the current state of the application.
    @EnvironmentObject var viewState: ViewState
    
    var emoji : Emoji
    var onDeleteClicked : () -> Void
    
    var body: some View {
    
        HStack(spacing: .spacing12) {
            // Display the emoji image.
            LazyImage(source: .emoji(emoji.id), height: .size40, width: .size40,  clipTo: Rectangle())
            
            VStack(alignment: .leading, spacing: .zero){
                
                if let user = viewState.users[emoji.creator_id] {
                
                    PeptideText(textVerbatim: emoji.name,
                                font: .peptideButton,
                                textColor: .textDefaultGray01)
                    
                    HStack(spacing: .spacing2){
                        
                        PeptideText(text: "Added by",
                                    font: .peptideCaption1,
                                    textColor: .textGray07)
                        
                        
                        PeptideText(textVerbatim: "\(user.display_name ?? user.username)",
                                    font: .peptideCaption1,
                                    textColor: .textDefaultGray01)
                        .onTapGesture{
                            
                            self.viewState.openUserSheet(user: user)
                            
                        }
                    }
                    
                } else {
                    // Show loading state while fetching user data.
                    PeptideText(textVerbatim: "Loading...",
                                font: .peptideCaption1,
                                textColor: .textDefaultGray01)
                    .task {
                            // Fetch user data for the emoji creator if not already loaded.
                            if let user = try? await viewState.http.fetchUser(user: emoji.creator_id).get() {
                                viewState.users[emoji.creator_id] = user // Cache the user data.
                            }
                        }
                }
                
                
            }
            
            Spacer(minLength: .zero)
            
            Button {
                
                self.onDeleteClicked()
                
            } label: {
                PeptideIcon(iconName: .peptideTrashDelete,
                            size: .size20,
                            color: .iconRed07)
            }
            
            
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        /*.swipeActions {
            // Swipe action to delete the emoji.
            Button(role: .destructive) {
                Task {
                    await viewState.http.deleteEmoji(emoji: emoji.id) // Delete the emoji from the server.
                }
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
        }*/
    }
}

#Preview {
    @Previewable @StateObject var viewState : ViewState = .preview()
    let emoji = Emoji(id: "01GX773A8JPQ0VP64NWGEBMQ1E", parent: .server(EmojiParentServer(id: "0")), creator_id: "0", name: "balls")
    ServerEmojiItemView(emoji: emoji){}
        .backgroundGray11(verticalPadding: .padding4)
        .applyPreviewModifiers(withState: viewState)
        .preferredColorScheme(.dark)
}
