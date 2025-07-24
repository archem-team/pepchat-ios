import SwiftUI
import SwiftUIIntrospect
import Combine

extension View {
    /// Introspect and configure UIScrollView for better keyboard dismissal behavior
    func configureScrollViewForChat() -> some View {
        self.introspect(.scrollView, on: .iOS(.v16, .v17)) { scrollView in
            scrollView.keyboardDismissMode = .interactive
            scrollView.alwaysBounceVertical = true
            scrollView.contentInsetAdjustmentBehavior = .always
            
            // Make scroll deceleration faster for a more responsive feel
            scrollView.decelerationRate = .fast
            
            // Improve scrolling behavior during keyboard presentation
            scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        }
    }
    
    /// Introspect and configure UITextView for better keyboard behavior
    func configureTextViewForChat() -> some View {
        self.introspect(.textEditor, on: .iOS(.v16, .v17)) { textView in
            textView.autocorrectionType = .no
            textView.autocapitalizationType = .none
            textView.isScrollEnabled = true
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
            
            // Add a better keyboard dismiss mode
            textView.returnKeyType = .default
            textView.enablesReturnKeyAutomatically = true
            
            // Disable some unintended behaviors
            textView.overrideUserInterfaceStyle = .dark
            textView.showsVerticalScrollIndicator = false
        }
    }
    
    /// Apply common chat UI fixes and behaviors with Combine for better keyboard tracking
    func applyChatUIFixes(keyboardHeight: Binding<CGFloat>, scrollToBottom: @escaping () -> Void) -> some View {
        self.modifier(ChatUIFixesModifier(keyboardHeight: keyboardHeight, scrollToBottom: scrollToBottom))
    }
    
    /// Track keyboard height changes and update the binding
    func keyboardHeight(keyboardHeight: Binding<CGFloat>) -> some View {
        self.modifier(KeyboardHeightModifier(keyboardHeight: keyboardHeight))
    }
    
    /// Modify layout when keyboard appears/disappears using the keyboardHeight value
    func adaptToKeyboard(height keyboardHeight: Binding<CGFloat>) -> some View {
        self.modifier(KeyboardAdaptiveModifier(keyboardHeight: keyboardHeight))
    }
}

/// A view modifier that implements chat UI fixes
struct ChatUIFixesModifier: ViewModifier {
    @Binding var keyboardHeight: CGFloat
    let scrollToBottom: () -> Void
    
    func body(content: Content) -> some View {
        content
            .keyboardHeight(keyboardHeight: $keyboardHeight)
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                    .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification))
                    .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            ) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottom()
                }
            }
            .transaction { transaction in
                // Disable animations when keyboard appears to prevent jumpy behavior
                if keyboardHeight > 0 {
                    transaction.animation = nil
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

/// A view modifier that adjusts the view's padding when the keyboard appears and disappears
struct KeyboardAdaptiveModifier: ViewModifier {
    @Binding var keyboardHeight: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - 8 : 0) // Subtract small offset for better appearance
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
    }
}

/// A view modifier that tracks keyboard height changes
struct KeyboardHeightModifier: ViewModifier {
    @Binding var keyboardHeight: CGFloat
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Ensure keyboard height is zero when view appears
                keyboardHeight = 0
                
                // Additional setup for proper keyboard interaction
                UIApplication.shared.hideKeyboardWhenTappedAround()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                    .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
            ) { notification in
                guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return
                }
                
                // Set keyboard height based on notification type
                if notification.name == UIResponder.keyboardWillShowNotification {
                    keyboardHeight = keyboardFrame.height
                } else {
                    // Important: immediately set to zero when keyboard hides
                    withAnimation(.easeOut(duration: 0.25)) {
                        keyboardHeight = 0
                    }
                }
            }
    }
}

// Extension to dismiss keyboard when tapping anywhere on the screen
extension UIApplication {
    func hideKeyboardWhenTappedAround() {
        // Find the key window
        let keyWindow = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene })
            .flatMap({ $0 as? UIWindowScene })?.windows
            .first(where: \.isKeyWindow)
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardAction))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = TapGestureDelegate.shared
        keyWindow?.addGestureRecognizer(tapGesture)
    }
    
    @objc func dismissKeyboardAction() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// Tap gesture delegate to allow touches on other controls
class TapGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = TapGestureDelegate()
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't handle the tap if the touched view is a UIControl (buttons, etc.)
        return !(touch.view is UIControl)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
} 