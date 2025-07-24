//
//  PermissionToggle.swift
//  Revolt
//
//  Created by Angelo on 25/09/2024.
//

import Foundation
import SwiftUI

struct PermissionToggle<Label: View>: View {
    @Binding var value: Bool? // Optional binding to represent permission state
    @ViewBuilder var label: () -> Label // Closure to generate the label view

    var body: some View {
        HStack(spacing: .spacing16) {
            label() // Display the label
            Spacer(minLength: .zero) // Add space between label and picker
            permissionPicker // Permission selection picker
        }
        //.padding() // Optional: Add padding to enhance touch target area
    }
    
    // Computed property for the permission picker using a horizontal stack of option buttons
    private var permissionPicker: some View {
        HStack(spacing: .zero) {
            PermissionOptionButton(
                option: false,
                systemImage: "xmark",
                activeForeground: .iconDefaultGray01,
                inactiveForeground: .iconRed07,
                activeBackground: .bgRed07,
                currentValue: $value
            )
            
            PermissionOptionButton(
                option: nil,
                systemImage: "square",
                activeForeground: .iconDefaultGray01,
                inactiveForeground: .iconGray07,
                activeBackground: .iconGray07,
                currentValue: $value
            )
            
            PermissionOptionButton(
                option: true,
                systemImage: "checkmark",
                activeForeground: .iconDefaultGray01,
                inactiveForeground: .iconGreen07,
                activeBackground: .bgGreen07,
                currentValue: $value
            )
        }
        .background {
            RoundedRectangle(cornerRadius: .radiusXSmall)
                .fill(Color.bgGray11)
        }
        .overlay(
            RoundedRectangle(cornerRadius: .radiusXSmall)
                .stroke(Color.iconDefaultGray01.opacity(0.3), lineWidth: .size1)
        )
    }
}

// MARK: - PermissionOptionButton

/// A helper view representing one of the permission options as a button.
private struct PermissionOptionButton: View {
    let option: Bool?                // The option value to set (false, nil, true)
    let systemImage: String          // The SF Symbol name for the button image
    let activeForeground: Color      // Foreground color when this option is active
    let inactiveForeground: Color    // Foreground color when this option is inactive
    let activeBackground: Color      // Background color when this option is active
    @Binding var currentValue: Bool? // Binding to the current permission value

    var body: some View {
        Button {
            currentValue = option
        } label: {
            Image(systemName: systemImage)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(currentValue == option ? activeForeground : inactiveForeground)
                .frame(width: 12, height: 12)
                .padding(.padding8)
                .background {
                    if currentValue == option {
                        RoundedRectangle(cornerRadius: .radiusXSmall)
                            .fill(activeBackground)
                    } else {
                        RoundedRectangle(cornerRadius: .radiusXSmall)
                            .fill(Color.clear)
                    }
                }
        }
    }
}

// MARK: - Preview

struct PermissionToggle_Previews: PreviewProvider {
    static var previews: some View {
        // Sample Preview for the PermissionToggle
        VStack {
            PermissionToggle(value: .constant(nil)) {
                Text("Notifications")
                    .font(.headline)
            }
            .padding()
        }
        .fillMaxSize()
        .preferredColorScheme(.dark)
    }
}
