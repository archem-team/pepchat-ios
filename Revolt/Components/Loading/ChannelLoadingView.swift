import SwiftUI

struct ChannelLoadingView: View {
    @State private var animationOffset: CGFloat = -200
    @State private var fadeOpacity: Double = 0.3
    
    var body: some View {
        ZStack {
            // Background
            Color.bgGray12.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Animated loading icon
                ZStack {
                    Circle()
                        .fill(Color.bgGray11.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    PeptideIcon(
                        iconName: .peptideMessage,
                        size: .size32,
                        color: .iconDefaultGray01
                    )
                    .opacity(fadeOpacity)
                }
                
                // Loading text
                VStack(spacing: 8) {
                    PeptideText(
                        text: "Loading Messages",
                        font: .peptideHeadline,
                        textColor: .textDefaultGray01
                    )
                    
                    PeptideText(
                        text: "Please wait while we fetch your conversation",
                        font: .peptideFootnote,
                        textColor: .textGray07
                    )
                }
                
                // Animated progress indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.bgGray10)
                        .frame(width: 200, height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(
                            colors: [
                                Color.iconDefaultGray01.opacity(0.6),
                                Color.iconDefaultGray01,
                                Color.iconDefaultGray01.opacity(0.6)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 60, height: 4)
                        .offset(x: animationOffset)
                }
                .clipped()
            }
        }
        .onAppear {
            // Start animations
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                fadeOpacity = 1.0
            }
            
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                animationOffset = 200
            }
        }
    }
}

#Preview {
    ChannelLoadingView()
        .applyPreviewModifiers(withState: ViewState.preview())
}
