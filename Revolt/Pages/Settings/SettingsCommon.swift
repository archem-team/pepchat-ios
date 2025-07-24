//
//  SettingsCommon.swift
//  Revolt
//
//  Created by Angelo on 2024-02-10.
//

import SwiftUI

/// A simple text field view for settings fields.
fileprivate struct SettingsFieldTextField: View {
    var body: some View {
        Text("Text Field") // Placeholder text for a text field.
    }
}

/// A navigation item for setting fields that may include a value.
struct SettingFieldNavigationItem: View {
    @EnvironmentObject var viewState: ViewState // Access to the application's state.
    
    @State var includeValueIfAvailable: Bool // State to determine if a value should be included.

    var body: some View {
        Text("Hello, World!") // Placeholder text for this view.
    }
}

/// A container for presenting a settings sheet with navigation capabilities.
struct SettingsSheetContainer<Content: View>: View {
    @EnvironmentObject var viewState: ViewState // Access to the application's state.
    
    @Binding var showSheet: Bool // Binding to control the visibility of the sheet.
    @ViewBuilder var sheet: () -> Content // The content to be displayed in the sheet.
    
    var body: some View {
        NavigationView {
            sheet()
                .padding()
                .backgroundStyle(viewState.theme.background) // Set background style from the theme.
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showSheet = false // Dismiss the sheet when the cancel button is pressed.
                        } label: {
                            Text("Cancel")
                        }
                    }
                }
        }
    }
}

/// A container for a settings sheet that may or may not be dismissible.
struct MaybeDismissableSettingsSheetContainer<Content: View>: View {
    @EnvironmentObject var viewState: ViewState // Access to the application's state.
    
    @Binding var showSheet: Bool // Binding to control the visibility of the sheet.
    @Binding var sheetDismissDisabled: Bool // Binding to enable/disable dismissing the sheet.
    @ViewBuilder var sheet: () -> Content // The content to be displayed in the sheet.
    
    var body: some View {
        NavigationView {
            sheet()
                .padding()
                .backgroundStyle(viewState.theme.background) // Set background style from the theme.
                .interactiveDismissDisabled(sheetDismissDisabled) // Control the dismiss behavior.
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showSheet = false // Dismiss the sheet when the cancel button is pressed.
                        } label: {
                            Text("Cancel")
                        }
                    }
                }
        }
    }
}

/// A checkbox list item for settings, with customizable change handlers.
struct CheckboxListItem: View {
    @EnvironmentObject var viewState: ViewState // Access to the application's state.

    @State var title: String // Title for the checkbox.
    @Binding var isOn: Bool // Binding to control the checkbox state.
    var description : String? = nil
    var willChange: ((Bool) -> (Bool))? // Optional callback before the state changes.
    var onChange: ((Bool) -> Void)? // Optional callback after the state changes.
    
    // Initializer with title and state.
    init(title: String, description : String? = nil,  isOn: Bool, onChange: ((Bool) -> Void)? = nil, willChange: ((Bool) -> Bool)? = nil) {
        self._title = State(initialValue: title)
        self.description = description
        self._isOn = .constant(isOn)
        self.onChange = onChange
        self.willChange = willChange
    }
    
    // Initializer with title and binding to state.
    init(title: String, description : String? = nil, isOn: Binding<Bool>, onChange: ((Bool) -> Void)? = nil, willChange: ((Bool) -> Bool)? = nil) {
        self._title = State(initialValue: title)
        self.description = description
        self._isOn = isOn
        self.onChange = onChange
        self.willChange = willChange
    }
    
    /// Prepares to change the checkbox state, calling optional handlers if defined.
    private func prepareChange() {
        if let willChange = willChange, !willChange(isOn) {
            isOn = !isOn // Revert change if `willChange` returns false.
            return
        }
        
        onChange?(isOn) // Call `onChange` handler if defined.
    }
    
    var body: some View {
        HStack {
            
            VStack(alignment: .leading, spacing: .zero){
                PeptideText(textVerbatim: title,
                            font: .peptideHeadline,
                            textColor: .textDefaultGray01,
                            alignment: .center,
                            lineLimit: 1)
                
                if let description = description, !description.isEmpty {
                    PeptideText(textVerbatim: description,
                                font: .peptideFootnote,
                                textColor: .textGray06,
                                alignment: .center,
                                lineLimit: 1)
                }
                
                
            }
            
            Spacer()
            Toggle(isOn: $isOn) {} // Create a toggle for the checkbox.
                .toggleStyle(PeptideSwitchToggleStyle()) // Use switch style for the toggle.
        }
        .onTapGesture {
            isOn.toggle() // Toggle the state when the row is tapped.
        }
        .onChange(of: isOn) {
            prepareChange() // Prepare for change when `isOn` changes.
        }
        //.backgroundStyle(viewState.theme.background2)
    }
}

