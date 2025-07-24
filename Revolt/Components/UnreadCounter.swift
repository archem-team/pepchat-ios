//
//  UnreadCounter.swift
//  Revolt
//
//  Created by Angelo on 20/11/2023.
//

import Foundation
import SwiftUI
import Types

/// A view that displays an unread message counter.
///
/// The `UnreadCounter` presents a visual representation of unread messages and mentions.
/// It varies its appearance based on the type of unread count—either mentions or general unread messages.
struct UnreadCounter: View {
    /// The environment object containing the current view state.
    @EnvironmentObject var viewState: ViewState
    
    /// The unread count type, which can indicate mentions or general unread messages.
    var unread: UnreadCount
    
    /// The size of the mention counter circle.
    var mentionSize: CGFloat = 20
    
    /// The size of the general unread message circle.
    var unreadSize: CGFloat = 8
    
    /// The body of the `UnreadCounter`.
    ///
    /// Renders different views based on the type of unread count. If the unread count is for
    /// mentions, it displays a larger red circle with the mention count.
    /// If the unread count is for general messages, it displays a smaller circle.
    var body: some View {
        switch unread {
        case .mentions(let count):
            UnreadMentionsView(count: count, mentionSize: mentionSize)
            
        case .unreadWithMentions(let count):
            UnreadMentionsView(count: count, mentionSize: mentionSize)
            
        case .unread:
            UnreadView(unreadSize: unreadSize)
        }
    }
}


struct UnreadMentionsView : View {
    
    var count : String
    var mentionSize: CGFloat = 20

    
    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .fill(Color.bgRed07)
                .frame(width: mentionSize, height: mentionSize)
                .overlay{
                    Circle().stroke(Color.borderPurple13, lineWidth: .size2)
                }
            
            PeptideText(text: "\(count)",
                        font: .peptideFootnote,
                        textColor: .textDefaultGray01)
            
           
        }
    }
}


struct UnreadView : View {
    var unreadSize: CGFloat = 8
    var body: some View {
        Circle()
            .fill(Color.bgGray02)
            .frame(width: unreadSize, height: unreadSize)
    }
}


#Preview {
    
    let v = ViewState.preview()
    
    
    VStack {
        UnreadCounter(unread: .unread)
        
        UnreadCounter(unread: .mentions("50"))
        
    }
    .preferredColorScheme(.dark)
    .environmentObject(v)
    
}
