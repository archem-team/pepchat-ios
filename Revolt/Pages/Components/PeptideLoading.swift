//
//  PeptideLoading.swift
//  Revolt
//
//

import SwiftUI

struct PeptideLoading: View {
    @State private var activeDot = 0
    var dotCount = 4
    var dotSize: CGFloat = .size4
    var dotSpacing: CGFloat = .size4
    var activeColor: Color = .bgDefaultPurple13
    var offset : CGFloat = -8
    
    @State private var timer: Timer?
    
    
    var body: some View {
        ZStack {
            
            // Dots with sequential bounce
            HStack(spacing: dotSpacing) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(activeColor)
                        .frame(width: dotSize, height: dotSize)
                        .offset(y: activeDot == index ? offset : 0)
                        .animation( .easeInOut(duration: 0.5)
                            .repeatCount(activeDot == index ? 1 : 0, autoreverses: true) , value: 0)
                    
                }
            }
        }
        .onAppear {
            startAnimationSequence()
        }
        .onDisappear{
            stopAnimationSequence()
        }
    }
    
    // Function to manage the sequential animation of dots
    private func startAnimationSequence() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            withAnimation {
                activeDot = (activeDot + 1) % dotCount // Moves to the next dot in sequence
            }
        }
    }
    
    private func stopAnimationSequence() {
        timer?.invalidate()
        timer = nil
    }
}



#Preview {
    PeptideLoading()
}


