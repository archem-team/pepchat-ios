//
//  PageToolbar.swift
//  Revolt
//
//  Created by Angelo on 27/11/2023.
//

import Foundation
import SwiftUI
import Types

/// A customizable toolbar view for pages in the app, which can include a sidebar toggle button, main content, and an optional trailing view.
struct PageToolbar<C: View, T: View>: View {
    @EnvironmentObject var viewState: ViewState  // Access the global application state

    var toggleSidebar: () -> ()  // Closure to toggle the sidebar

    var contents: () -> C  // Closure for the main content of the toolbar
    var trailing: (() -> T)?  // Optional closure for trailing content

    /// Initializer for the PageToolbar.
    /// - Parameters:
    ///   - toggleSidebar: A closure to handle sidebar toggling.
    ///   - contents: A closure to define the main content of the toolbar.
    ///   - trailing: An optional closure for trailing content.
    init(toggleSidebar: @escaping () -> (), @ViewBuilder contents: @escaping () -> C, trailing: (() -> T)? = nil) {
        self.toggleSidebar = toggleSidebar
        self.contents = contents
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            HStack(alignment: .center) {
                // Button to toggle the sidebar
                Button {
                    toggleSidebar()  // Call the sidebar toggle closure
                } label: {
                    Image(systemName: "line.3.horizontal")  // Icon for sidebar toggle
                        .resizable()
                        .frame(width: 24, height: 14)  // Icon size
                        .foregroundStyle(viewState.theme.foreground2.color)  // Icon color from theme
                }

                Spacer()  // Pushes the content to the center

                // Render the trailing content if it exists
                if let trailing {
                    trailing()  // Call the trailing closure
                }
            }

            HStack(alignment: .center) {
                Spacer()  // Space around the contents

                // Render the main content
                contents()  // Call the main content closure

                Spacer()  // Space around the contents
            }
        }
        .padding(.horizontal, 12)  // Horizontal padding
        .padding(.top, 4)  // Top padding
        .padding(.bottom, 8)  // Bottom padding
        .background(viewState.theme.topBar.color)  // Background color from theme
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(maxWidth: .infinity, maxHeight: 1)  // Bottom border line
                .foregroundStyle(viewState.theme.background2)  // Border color from theme
        }
    }
}

// Extension for PageToolbar to support a case without trailing content
extension PageToolbar where T == EmptyView {
    init(toggleSidebar: @escaping () -> (), @ViewBuilder contents: @escaping () -> C) {
        self.toggleSidebar = toggleSidebar
        self.contents = contents
        self.trailing = nil  // No trailing content
    }
}

// Preview provider for the PageToolbar
#Preview {
    PageToolbar(toggleSidebar: {}) {
        Text("Placeholder")  // Main content placeholder
    } trailing: {
        Text("Ending")  // Optional trailing content
    }
    .applyPreviewModifiers(withState: ViewState.preview())  // Apply preview modifiers
}
