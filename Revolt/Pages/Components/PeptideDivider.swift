//
//  PeptideDivider.swift
//  Revolt
//
//

import SwiftUI

struct PeptideDivider: View {
    
    var size : CGFloat = .size1
    var backgrounColor : Color = .borderGray10
        
    var body: some View {
        Rectangle()
            .fill(backgrounColor)
            .frame(height: size)
    }
}


struct DashedDivider: View {
     var body: some View {
         Line()
           .stroke(style: StrokeStyle(lineWidth: 1, dash: [5,5]))
           .frame(height: 1)
           .foregroundStyle(Color.borderGray10)
    }
}


struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}

#Preview {
    
    VStack(spacing: 20){
        
        PeptideDivider()

        DashedDivider()
        
    }
    .preferredColorScheme(.dark)
    
}
