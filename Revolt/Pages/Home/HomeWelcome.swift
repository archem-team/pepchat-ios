//
//  HomeWelcome.swift
//  Revolt
//
//  Created by Angelo on 29/11/2023.
//

import Foundation
import SwiftUI
import Types

/// `HomeWelcome` view displays the home screen with various options for navigation.
/// It includes buttons for discovery, joining servers, donating, and opening settings.
/// The view also supports theme customization and opens external URLs when required.
struct HomeWelcome: View {
    @Environment(\.openURL) var openURL: OpenURLAction  // Allows opening external URLs.
    @EnvironmentObject var viewState: ViewState  // Access to global state, including theme information.
    var toggleSidebar: () -> ()  // Action to toggle the sidebar.

    var body: some View {
        VStack {
            // Displays a toolbar at the top with a "Home" label.
            PageToolbar(toggleSidebar: toggleSidebar) {
                Text("Home")
            }
            
            Spacer()
                .frame(maxHeight: 100)  // Adds space between the toolbar and content.
            
            // Main content: welcome message and action buttons.
            VStack(alignment: .center, spacing: 24) {
                VStack(alignment: .center, spacing: 8) {
                    Text("Welcome to")
                        .font(.title)
                        .fontWeight(.bold)  // Bold "Welcome to" text.
                    Image("wide")
                        .maybeColorInvert(color: viewState.theme.background, isDefaultImage: false, defaultIsLight: true)  // Displays an image with color inversion based on theme.
                }
                
                // List of navigation buttons.
                VStack {
                    // Discover button.
                    HomeButton(title: "Discover Revolt", description: "Find a community based on your hobbies or interests.") {
                        Image(systemName: "safari.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                    } handle: {
                        viewState.path.append(NavigationDestination.discover)  // Navigate to discovery section.
                    }
                    
                    // Testers server button.
                    HomeButton(title: "Go to the testers server", description: "You can report issues and discuss improvements with us directly here") {
                        Image(systemName: "arrow.right.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                    } handle: {
                        // Code for joining the testers server goes here.
                    }
                    
                    // Donate button.
                    HomeButton(title: "Donate to Revolt", description: "Support the project by donating - thank you") {
                        Image(systemName: "banknote")
                            .resizable()
                            .frame(width: 32, height: 20)
                    } handle: {
                        openURL(URL(string: "https://insrt.uk/donate")!)  // Opens the donation URL.
                    }
                    
                    // Open Settings button.
                    HomeButton(title: "Open Settings", description: "You can also open settings from the bottom of the server list") {
                        Image(systemName: "gearshape.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                    } handle: {
                        viewState.path.append(NavigationDestination.settings)  // Navigate to settings.
                    }
                }
            }
            
            Spacer()  // Adds space below the content.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // Ensures the view fills the available space.
        .background(viewState.theme.background.color)  // Sets the background color based on the current theme.
    }
}

/// `HomeButton` is a reusable component that creates a button with an icon, title, and description.
/// It is styled based on the app's theme and supports navigation or external actions.
struct HomeButton<Icon: View>: View {
    @EnvironmentObject var viewState: ViewState  // Access to global state, including theme information.
    
    var title: String  // The title displayed on the button.
    var description: String  // The description text displayed below the title.
    @ViewBuilder var icon: () -> Icon  // The icon displayed on the left side of the button.
    var handle: () -> ()  // Action to perform when the button is pressed.
    
    var body: some View {
        Button {
            handle()  // Executes the action when the button is pressed.
        } label: {
            HStack {
                icon()
                    .frame(width: 32, height: 32)
                    .padding(8)  // Icon padding.

                VStack(alignment: .leading) {
                    Text(title)  // The title of the button.
                    Text(description)  // The description text.
                        .font(.caption2)
                        .foregroundStyle(viewState.theme.foreground2.color)  // Text color based on theme.
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity)
                
                Image(systemName: "chevron.right")  // Right arrow indicating further navigation.
                    .padding(8)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 300, height: 80)  // Button size.
        .background(viewState.theme.background2.color)  // Button background based on theme.
        .clipShape(RoundedRectangle(cornerRadius: 5))  // Rounded corners.
    }
}

#Preview {
    HomeWelcome(toggleSidebar: {})  // Previewing the HomeWelcome view.
        .applyPreviewModifiers(withState: ViewState.preview())  // Apply theme and state for preview.
}
