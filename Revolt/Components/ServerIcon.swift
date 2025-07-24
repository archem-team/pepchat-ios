//
//  ServerIcon.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI
import Types

/// A view that displays the icon of a server.
///
/// The `ServerIcon` attempts to show the server's icon if available; otherwise,
/// it falls back to a text-based representation of the server's name.
struct ServerIcon<S: Shape>: View {
    /// The environment object containing the current view state.
    @EnvironmentObject var viewState: ViewState
    
    /// The server whose icon is to be displayed.
    var server: Server
    
    /// The optional height of the icon.
    var height: CGFloat? = nil
    
    /// The optional width of the icon.
    var width: CGFloat? = nil
    
    /// The shape to which the icon should be clipped.
    var clipTo: S
    
    /// The body of the `ServerIcon`.
    ///
    /// Displays a lazy-loaded image if the server has an icon. If no icon is available,
    /// it defaults to a `FallbackServerIcon` displaying the first character of the server's name.
    var body: some View {
        if let icon = server.icon {
            LazyImage(source: .file(icon), height: height, width: height, clipTo: clipTo)
        } else {
            FallbackServerIcon(name: server.name, width: width, height: height, clipTo: clipTo)
        }
    }
}

/// A fallback view for displaying a server icon when no icon is available.
///
/// This view presents a text-based representation of the server's name using its first character.
struct FallbackServerIcon<S: Shape>: View {
    /// The environment object containing the current view state.
    @EnvironmentObject var viewState: ViewState
    
    /// The name of the server.
    var name: String
    
    /// The optional width of the icon.
    var width: CGFloat?
    
    /// The optional height of the icon.
    var height: CGFloat?
    
    /// The shape to which the icon should be clipped.
    var clipTo: S
    
    /// The body of the `FallbackServerIcon`.
    ///
    /// Displays a colored shape with the first character of the server's name centered within it.
    var body: some View {
        ZStack(alignment: .center) {
            let firstTwoCharacters = getFirstTwoCharacters(from: name)
            
            clipTo
                .fill(Color.bgGray11)
                .frame(width: width, height: height)
            
            PeptideText(text: "\(firstTwoCharacters)",
                        font: .peptideTitle3,
                        textColor: .textDefaultGray01)
            
            /*Text(verbatim: "\(firstTwoCharacters)")
                .bold()*/
        }
    }
    
    func getFirstTwoCharacters(from input: String?) -> String {
        guard let input = input, !input.isEmpty else {
            return "?"
        }
        return String(input.prefix(2)).uppercased()
    }
}

/// A view that displays a server icon in a list, allowing for selection highlights.
///
/// The `ServerListIcon` allows users to see which server is currently selected and highlights
/// the selected server with rounded corners.
struct ServerListIcon: View {
    /// The environment object containing the current view state.
    @EnvironmentObject var viewState: ViewState
    
    /// The server whose icon is to be displayed.
    var server: Server
    
    /// The optional height of the icon.
    var height: CGFloat? = nil
    
    /// The optional width of the icon.
    var width: CGFloat? = nil
    
    /// A binding to the currently selected main view.
    @Binding var currentSelection: MainSelection
    
    /// The body of the `ServerListIcon`.
    ///
    /// Renders the `ServerIcon` and applies a rounded rectangle shape with a corner radius
    /// that varies based on whether the server is selected.
    var body: some View {
        ServerIcon(
            server: server,
            height: height,
            width: width,
            clipTo: Circle()
            //clipTo: RoundedRectangle(cornerRadius: currentSelection == .server(server.id) ? 12 : 100)
        )
        .animation(.easeInOut, value: currentSelection == .server(server.id))
    }
}


//#Preview{
//
//    let viewState = ViewState.preview()
//    let server0 = viewState.servers.values.first!
//    
//    ServerListIcon(server: server0,
//                   height: 48,
//                   width: 48,
//                   currentSelection: .constant(.server(server0.id)))
//        .applyPreviewModifiers(withState: viewState)
//        .preferredColorScheme(.dark)
//}


#Preview {
    
    @Previewable @StateObject var viewState = ViewState.preview()
    
    ServerIcon(server: viewState.servers["0"]!,
               height: 40,
               width: 40,
               clipTo: Rectangle())
    .addBorder(Color.clear, cornerRadius: .radiusXSmall)
    .applyPreviewModifiers(withState: viewState)
    .preferredColorScheme(.dark)
}
