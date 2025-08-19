//
//  PeptideSheet.swift
//  Revolt
//
//

import SwiftUI

/// A resizable sheet with dynamic height calculation
struct PeptideSheet<Content: View>: View {
    
    @Binding var isPresented: Bool
    @State private var sheetHeight: CGFloat = .zero
    
    let topPadding: CGFloat
    let horizontalPadding : CGFloat
    let bgColor : Color
    let maxHeight: CGFloat?
    let content: () -> Content
    
    /// Initialize the sheet
    init(isPresented: Binding<Bool>,
         topPadding: CGFloat = 32,
         horizontalPadding : CGFloat = 16,
         bgColor : Color = .bgGray12,
         maxHeight: CGFloat? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self._isPresented = isPresented
        self.topPadding = topPadding
        self.horizontalPadding = horizontalPadding
        self.bgColor = bgColor
        self.maxHeight = maxHeight
        self.content = content
    }
    
    var body: some View {
        VStack(spacing: .zero) {
            content()
        }
        .padding(.top, topPadding)
        .padding(.bottom, 8)
        .padding(.horizontal, horizontalPadding)
        .background(bgColor)
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
            if let maxHeight = maxHeight {
                sheetHeight = min(newHeight, maxHeight)
            } else {
                sheetHeight = newHeight
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(bgColor)
        .presentationCornerRadius(.radiusLarge)
        .interactiveDismissDisabled(false)
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct InnerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}




struct PeptideSheetItem {
    var index : Int
    var title : String
    var icon : ImageResource
    var isLastItem : Bool = false
}
