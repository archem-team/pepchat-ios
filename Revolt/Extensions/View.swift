//
//  View.swift
//  Revolt
//
//  Created by Angelo on 2024-03-10.
//

import Foundation
import SwiftUI

extension View {
    
    /**
     Adds a border with rounded corners to any SwiftUI `View`.
     
     - Parameters:
     - content: A `ShapeStyle` used for the border, such as a color or gradient.
     - width: The width of the border. Default is 1.
     - cornerRadius: The corner radius applied to the view.
     
     - Returns: A `View` with the specified border and rounded corners applied.
     
     **Example usage**:
     ```swift
     Text("Hello")
     .addBorder(Color.red, width: 2, cornerRadius: 8)
     ```
     
     This method creates a rounded rectangle border around the view, clipping it to the shape of the rounded rectangle.
     */
    public func addBorder<S>(_ content: S, width: CGFloat = 1, cornerRadius: CGFloat) -> some View where S : ShapeStyle {
        let roundedRect = RoundedRectangle(cornerRadius: cornerRadius)
        return clipShape(roundedRect)
            .overlay(roundedRect.strokeBorder(content, lineWidth: width))
    }
    
    /**
     Adds a placeholder to any `View` that can be displayed conditionally.
     
     - Parameters:
     - shouldShow: A `Bool` that determines whether the placeholder should be shown.
     - alignment: The alignment of the placeholder within the view. Default is `.leading`.
     - placeholder: A closure that provides the placeholder view to display.
     
     - Returns: A `View` that conditionally displays the placeholder when `shouldShow` is true.
     
     **Example usage**:
     ```swift
     TextField("Enter text", text: $text)
     .placeholder(when: text.isEmpty) {
     Text("Placeholder").foregroundColor(.gray)
     }
     ```
     
     This method overlays the placeholder on the view, but only makes it visible when `shouldShow` is true.
     */
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder()
                .opacity(shouldShow ? 1 : 0)
                .allowsHitTesting(false)
            self
        }
    }
    
    /**
     Conditionally applies a view modifier based on a boolean value.
     
     - Parameters:
     - conditional: A `Bool` that determines whether the `content` closure should be applied.
     - content: A closure that modifies the view if `conditional` is true.
     
     - Returns: A `View` with the modifier applied if `conditional` is true; otherwise, the original view.
     
     **Example usage**:
     ```swift
     Text("Hello")
     .if(condition) { view in
     view.foregroundColor(.red)
     }
     ```
     
     This method applies the provided view modification only when the condition is true.
     */
    @ViewBuilder
    func `if`<Content: View>(_ conditional: Bool, content: (Self) -> Content) -> some View {
        if conditional {
            content(self)
        } else {
            self
        }
    }
    
    /**
     Conditionally applies one of two view modifiers based on a boolean value.
     
     - Parameters:
     - conditional: A `Bool` that determines whether the `content` closure or the `else` closure should be applied.
     - content: A closure that modifies the view if `conditional` is true.
     - other: A closure that modifies the view if `conditional` is false.
     
     - Returns: A `View` with the appropriate modifier applied based on the value of `conditional`.
     
     **Example usage**:
     ```swift
     Text("Hello")
     .if(condition, content: { view in
     view.foregroundColor(.red)
     }, else: { view in
     view.foregroundColor(.blue)
     })
     ```
     
     This method applies one of two provided view modifications depending on whether the condition is true or false.
     */
    @ViewBuilder
    func `if`<Content: View, Else: View>(_ conditional: Bool, content: (Self) -> Content, else other: (Self) -> Else) -> some View {
        if conditional {
            content(self)
        } else {
            other(self)
        }
    }
    
    /**
     Applies a set of preview modifiers to a `View` based on a provided `ViewState`.
     
     - Parameter viewState: An object of type `ViewState` which contains theme and style properties to apply to the view.
     
     - Returns: A `View` with preview modifiers applied, such as theme-based tint, foreground style, and background color.
     
     **Example usage**:
     ```swift
     Text("Hello")
     .applyPreviewModifiers(withState: someViewState)
     ```
     
     This method is intended for applying theme-based styling to views in SwiftUI previews.
     */
    @MainActor
    func applyPreviewModifiers(withState viewState: ViewState) -> some View {
        self.environmentObject(viewState)
            //.tint(viewState.theme.accent.color)
            //.foregroundStyle(viewState.theme.foreground.color)
            //.background(viewState.theme.background.color)
    }
    
    @MainActor
    func alertPopup<V: View>(show: Bool, @ViewBuilder content: @escaping () -> V) -> AlertPopup<Self, V> {
        AlertPopup(show: show, inner: self, popup: content)
    }
    
    @MainActor
    func alertPopup(content: String, show: Bool) -> AlertPopup<Self, Text> {
        self.alertPopup(show: show) {
            Text(content)
        }
    }
    
    @MainActor
    func alertPopup(content: String?) -> AlertPopup<Self, Text> {
        self.alertPopup(show: content != nil) {
            Text(content ?? "")
        }
    }
    
    func fillMaxSize(backgroundColor : Color = .bgDefaultPurple13) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor)
    }
    
    @MainActor
    func observeKeyboardVisibility(isVisible: Binding<Bool>) -> some View {
        self
        
            .onAppear {
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
                    isVisible.wrappedValue = true
                }
                
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
                    isVisible.wrappedValue = false
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidShowNotification, object: nil)
                NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
            }
    }
    
    @MainActor
    func keyboardHeight(keyboardHeight: Binding<CGFloat>) -> some View {
        self.onAppear {
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    Task { @MainActor in
                            let screenHeight = UIScreen.main.bounds.height
                            let keyboardTop = keyboardFrame.minY
                            
                        // Calculate with more precision by measuring just the height directly
                        // rather than using safe area insets which can cause extra gaps
                        keyboardHeight.wrappedValue = keyboardFrame.height
                    }
                }
            }
            
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                        keyboardHeight.wrappedValue = 0
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }


    
    func padding(top: CGFloat = .zero, bottom: CGFloat = .zero, leading: CGFloat = .zero, trailing: CGFloat = .zero) -> some View {
        self
            .padding(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
    }
    
    
    func hideKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
