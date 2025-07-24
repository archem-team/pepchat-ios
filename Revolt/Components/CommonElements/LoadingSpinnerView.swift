//
//  LoadingSpinnerView.swift
//  Revolt
//
//  Created by Tom on 2023-11-13.
//
//  File from https://github.com/KeatoonMask/SwiftUI-Animation/
//  under the Apache 2.0 license
//

import SwiftUI
import Types

/// A loading spinner view that animates a spinner until an action is complete.
struct LoadingSpinnerView: View {

    @State var frameSize: CGSize  // Size of the spinner
    @Binding var isActionComplete: Bool  // Binding to track if the action is complete
    
    let rotationTime: Double = 0.75  // Duration for one rotation of the spinner
    let animationTime: Double = 1.9 // Total duration for all animations
    let fullRotation: Angle = .degrees(360)  // Angle for a full rotation
    static let initialDegree: Angle = .degrees(270)  // Starting angle for the spinner
    
    @State var spinnerStart: CGFloat = 0.0  // Start point for the spinner trim
    @State var spinnerEndS1: CGFloat = 0.03  // End point for spinner segment 1
    @State var spinnerEndS2S3: CGFloat = 0.03  // End point for spinner segments 2 and 3
    
    @State var rotationDegreeS1 = initialDegree  // Current rotation angle for spinner segment 1
    @State var rotationDegreeS2 = initialDegree  // Current rotation angle for spinner segment 2
    @State var rotationDegreeS3 = initialDegree  // Current rotation angle for spinner segment 3

    var body: some View {
        ZStack {
            // Show a checkmark when the action is complete
            if isActionComplete {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.green)
            }
            
            // S3 - Spinner segment 3
            SpinnerCircle(start: spinnerStart, end: spinnerEndS2S3, rotation: rotationDegreeS3, color: .iconYellow07, frameSize: frameSize)

            // S2 - Spinner segment 2
            SpinnerCircle(start: spinnerStart, end: spinnerEndS2S3, rotation: rotationDegreeS2, color: .iconYellow07, frameSize: frameSize)

            // S1 - Spinner segment 1
            SpinnerCircle(start: spinnerStart, end: spinnerEndS1, rotation: rotationDegreeS1, color: .iconYellow07, frameSize: frameSize)
        }
        .frame(width: frameSize.width, height: frameSize.height)  // Set the frame size of the spinner
        .onAppear() {
            self.animateSpinner()  // Start the spinner animation on appear
            // Set up a timer to repeat the animation
            Timer.scheduledTimer(withTimeInterval: animationTime, repeats: true) { (mainTimer) in
                self.animateSpinner()  // Animate the spinner again after the animation time
            }
        }
    }

    // MARK: Animation methods
    
    /// Animates the spinner with a specified duration and completion handler.
    /// - Parameters:
    ///   - duration: The duration for the animation.
    ///   - completion: A closure to be called when the animation completes.
    func animateSpinner(with duration: Double, completion: @escaping (() -> Void)) {
        Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            withAnimation(Animation.easeInOut(duration: self.rotationTime)) {
                completion()  // Call the completion closure after the animation
            }
        }
    }

    /// Triggers the animation sequence for the spinner.
    func animateSpinner() {
        // Animate spinner segment 1
        animateSpinner(with: rotationTime) { self.spinnerEndS1 = 1.0 }

        // Continue animations for segments 2 and 3 if the action is not complete
        if !isActionComplete {
            animateSpinner(with: (rotationTime * 2) - 0.025) {
                self.rotationDegreeS1 += fullRotation
                self.spinnerEndS2S3 = 0.8
            }
            
            animateSpinner(with: (rotationTime * 2)) {
                self.spinnerEndS1 = 0.03
                self.spinnerEndS2S3 = 0.03
            }
            
            animateSpinner(with: (rotationTime * 2) + 0.0525) { self.rotationDegreeS2 += fullRotation }
            
            animateSpinner(with: (rotationTime * 2) + 0.225) { self.rotationDegreeS3 += fullRotation }
        }
    }
}

// MARK: SpinnerCircle

/// A view representing a single segment of the spinner.
struct SpinnerCircle: View {
    var start: CGFloat  // Starting point of the circle trim
    var end: CGFloat  // Ending point of the circle trim
    var rotation: Angle  // Current rotation angle of the segment
    var color: Color  // Color of the spinner segment
    
    var frameSize: CGSize  // Size of the spinner frame

    var body: some View {
        Circle()
            .trim(from: start, to: end)  // Create a circle trimmed to the specified start and end
            .stroke(style: StrokeStyle(lineWidth: frameSize.width / 10, lineCap: .round))  // Style the stroke
            .fill(color)  // Fill the circle with the specified color
            .rotationEffect(rotation)  // Apply rotation effect
    }
}

#Preview {
    @State var action = false

    return LoadingSpinnerView(frameSize: CGSize(width: 100, height: 100), isActionComplete: $action)
        .task {
            try! await Task.sleep(for: .seconds(3))  // Simulate an action completing after 3 seconds
            action = true  // Mark the action as complete
        }
}
