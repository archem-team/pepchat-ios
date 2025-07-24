//
//  ReversedScrollView.swift
//  Revolt
//
//  Created by Angelo on 15/10/2023.
//

import Foundation
import SwiftUI
import Types

/// A view that provides a reversed scroll view containing a vertically stacked set of views.
///
/// The `ReversedScrollView` allows for scrolling through content that is arranged in a vertical stack, with
/// the scroll direction reversed. This is useful for scenarios such as chat interfaces, where new messages
/// should appear at the bottom of the view while allowing users to scroll up to view older messages.
///
/// - Parameter Content: The type of view that will be displayed in the scroll view.
struct ReversedScrollView<Content: View>: View {
    
    // MARK: - Properties
    
    /// Optional padding to be applied horizontally to the content of the scroll view.
    var padding: CGFloat? = nil
    
    /// A closure that provides the content of the scroll view, receiving a `ScrollViewProxy` to manage scrolling.
    @ViewBuilder var builder: (ScrollViewProxy) -> Content

    // MARK: - Body
    
    /// The body of the `ReversedScrollView`.
    ///
    /// The body creates a `GeometryReader` that allows access to the available size of the scroll view.
    /// Inside it, a `ScrollViewReader` is used to manage the scroll position. The content is displayed
    /// in a `LazyVStack`, and the view can be padded and sized according to the available geometry.
    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        Spacer()
                        builder(scrollProxy)
                    }
                    .padding(.horizontal, padding)
                    .frame(
                        minWidth: minWidth(in: proxy, for: .vertical),
                        minHeight: minHeight(in: proxy, for: .vertical)
                    )
                }
            }
        }
    }
}

/// A helper function to determine the minimum width based on the provided geometry proxy and axis.
///
/// - Parameters:
///   - proxy: The `GeometryProxy` providing access to the size of the parent view.
///   - axis: The axis set to check for width constraints.
/// - Returns: The minimum width if the horizontal axis is included, otherwise `nil`.
func minWidth(in proxy: GeometryProxy, for axis: Axis.Set) -> CGFloat? {
    axis.contains(.horizontal) ? proxy.size.width : nil
}

/// A helper function to determine the minimum height based on the provided geometry proxy and axis.
///
/// - Parameters:
///   - proxy: The `GeometryProxy` providing access to the size of the parent view.
///   - axis: The axis set to check for height constraints.
/// - Returns: The minimum height if the vertical axis is included, otherwise `nil`.
func minHeight(in proxy: GeometryProxy, for axis: Axis.Set) -> CGFloat? {
    axis.contains(.vertical) ? proxy.size.height : nil
}
