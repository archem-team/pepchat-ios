import SwiftUI

/// A skeleton loading view that mimics the structure of message cells
/// Used when messages are being loaded to provide visual feedback
struct MessageSkeletonView: View {
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Avatar skeleton
            Circle()
                .fill(shimmerGradient())
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                // Username and timestamp skeleton
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient())
                        .frame(width: CGFloat.random(in: 80...120), height: 16)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient())
                        .frame(width: 60, height: 12)
                }
                
                // Message content skeleton
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient())
                        .frame(width: CGFloat.random(in: 200...300), height: 16)
                    
                    if Bool.random() {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(shimmerGradient())
                            .frame(width: CGFloat.random(in: 150...250), height: 16)
                    }
                    
                    if Bool.random() {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(shimmerGradient())
                            .frame(width: CGFloat.random(in: 100...200), height: 16)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            startShimmerAnimation()
        }
    }
    
    private func shimmerGradient() -> LinearGradient {
        LinearGradient(
            colors: [
                Color.bgGray11.opacity(0.3),
                Color.bgGray10.opacity(0.5),
                Color.bgGray11.opacity(0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: shimmerOffset)
    }
    
    private func startShimmerAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 200
        }
    }
}

/// A skeleton view showing multiple message placeholders
struct ChatSkeletonView: View {
    let messageCount: Int
    
    init(messageCount: Int = 8) {
        self.messageCount = messageCount
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<messageCount, id: \.self) { index in
                MessageSkeletonView()
                    .animation(.easeInOut(duration: 0.5).delay(Double(index) * 0.1), value: index)
            }
        }
        .padding(.top, 20)
    }
}

/// A compact skeleton view for continuation messages (without avatar)
struct MessageSkeletonContinuationView: View {
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Empty space for avatar alignment
            Spacer()
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                // Message content skeleton (shorter than main messages)
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient())
                    .frame(width: CGFloat.random(in: 150...280), height: 16)
                
                if Bool.random() {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient())
                        .frame(width: CGFloat.random(in: 100...200), height: 16)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onAppear {
            startShimmerAnimation()
        }
    }
    
    private func shimmerGradient() -> LinearGradient {
        LinearGradient(
            colors: [
                Color.bgGray11.opacity(0.3),
                Color.bgGray10.opacity(0.5),
                Color.bgGray11.opacity(0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: shimmerOffset)
    }
    
    private func startShimmerAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 200
        }
    }
}

#Preview {
    VStack {
        ChatSkeletonView(messageCount: 5)
        Spacer()
    }
    .background(Color.bgDefaultPurple13)
} 