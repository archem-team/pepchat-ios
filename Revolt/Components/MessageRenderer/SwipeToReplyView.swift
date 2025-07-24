//
//  SwipeToReplyView.swift
//  Revolt
//
//

import SwiftUI

// ✅ Generic SwipeToReplyView that accepts any content and an action callback
struct SwipeToReplyView<Content: View>: View {
    @State private var offset: CGFloat = 0
    @State private var iconSize: CGFloat = 12
    @State private var showReplyIcon = false
    @State private var actionTriggered = false
    @State private var isSwiping = false // Prevents interference with scrolling
    
    let content: Content
    let onReply: () -> Void  // Callback function when swiped fully
    let enableSwipe: Bool
    
    init(enableSwipe: Bool = true, onReply: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.enableSwipe = enableSwipe
        self.onReply = onReply
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Background (Reply Icon)
            if enableSwipe {
                HStack {
                    Spacer()
                    if showReplyIcon {
                        let innerIconSize = max(iconSize - 8, 0)
                        
                        PeptideIcon(iconName: .peptideReply,
                                    size: innerIconSize,
                                    color: .iconInverseGray13)
                        .frame(width: iconSize, height: iconSize)
                        .background {
                            Circle().fill(Color.iconYellow07)
                        }
                        .padding(.trailing, innerIconSize)
                        .transition(.scale)
                    }
                }
            }
            
            // Main swipable content
            content
                .if(enableSwipe) {
                    $0.offset(x: offset)
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { gesture in
                                if !isSwiping {
                                    // Detect if the user is swiping horizontally
                                    isSwiping = abs(gesture.translation.width) > abs(gesture.translation.height)
                                }
                                
                                if isSwiping {
                                    // ✅ Only allow swipe to left (negative values)
                                    if gesture.translation.width < 0 {
                                        withAnimation(.linear(duration: 0.1)) {
                                            offset = max(gesture.translation.width, -150) // Limit swipe amount
                                            iconSize = min(32, max(12, abs(offset) / 3)) // Change icon size
                                        }
                                        showReplyIcon = true
                                        
                                        // Execute action when the icon reaches max size
                                        if iconSize >= 32 && !actionTriggered {
                                            actionTriggered = true
                                            onReply() // ✅ Trigger the callback
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                if isSwiping {
                                    // ✅ Reset all values smoothly
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.2)) {
                                        offset = 0
                                        showReplyIcon = false
                                        actionTriggered = false
                                        iconSize = 12
                                    }
                                }
                                isSwiping = false // Reset swipe detection
                            }
                    )
                }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        SwipeToReplyView(enableSwipe: true, onReply: {
            print("✅ Swipe action triggered")
        }, content: {
            HStack {
                Text("Message")
                Spacer(minLength: .zero)
            }
            .frame(height: 60)
            .padding(20)
            .background(Color.red)
        })
        
        SwipeToReplyView(enableSwipe: false, onReply: {
        }, content: {
            HStack {
                Text("Message")
                Spacer(minLength: .zero)
            }
            .frame(height: 60)
            .padding(20)
            .background(Color.red)
        })
    }
}
