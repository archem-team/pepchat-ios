//
//  TileGrid.swift
//  Revolt
//
//  Created by Angelo on 29/08/2024.
//

import Foundation
import SwiftUI
import ExyteGrid

/// A view that represents a tile containing a title and content, which can be expanded to show more details.
struct Tile<Body: View>: View {
    @EnvironmentObject var viewState: ViewState // The current view state environment object.

    var title: String // The title of the tile.
    var content: () -> Body // A closure providing the content of the tile.

    @State var showPopout: Bool = false // State to manage the display of the popout sheet.

    /// Initializes a `Tile` view with a title and content.
    /// - Parameters:
    ///   - title: The title of the tile.
    ///   - content: A closure that returns the content to be displayed inside the tile.
    init(
        _ title: String,
        @ViewBuilder content: @escaping () -> Body
    ) {
        self.title = title
        self.content = content
    }

    /// The body of the `Tile` view.
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title) // Display the title of the tile.
                    .bold()
                    .font(.title3)

                HStack {
                    VStack(alignment: .leading) {
                        content() // Display the content passed to the tile.
                    }

                    Spacer(minLength: 0) // Spacer to push content to the left.
                }
                .frame(maxWidth: .infinity) // Allow content to take maximum width available.

                Spacer(minLength: 0) // Spacer to push content to the top.
            }
            .frame(maxWidth: .infinity) // Set maximum width for the inner VStack.
        }
        .frame(height: 160) // Fixed height for the tile.
        .padding(.horizontal, 16) // Horizontal padding for the tile.
        .padding(.top, 8) // Top padding for the tile.
        .background(viewState.theme.background2, in: RoundedRectangle(cornerRadius: 12)) // Background styling for the tile.
        .onTapGesture {
            showPopout.toggle() // Toggle the popout display on tap.
        }
        .sheet(isPresented: $showPopout) { // Present a sheet when showPopout is true.
            ScrollView {
                VStack(alignment: .leading) {
                    Text(title) // Display the title in the popout.
                        .bold()
                        .font(.title)

                    Group {
                        content() // Display the same content in the popout.
                    }
                }
            }
            .padding(.horizontal, 16) // Padding for the popout content.
            .presentationDetents([.medium]) // Set presentation detents for the sheet.
            .presentationBackground(viewState.theme.background) // Background for the sheet.
        }
    }
}
