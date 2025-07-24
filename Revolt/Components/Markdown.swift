//
//  Markdown.swift
//  Revolt
//
//  Created by Angelo on 15/10/2023.
//

import Foundation
import SwiftUI
import MarkdownKit
import UIKit

struct UIKLabel: UIViewRepresentable {
    typealias TheUIView = UILabel
    fileprivate var configuration = { (view: TheUIView) in }
    
    func makeUIView(context: UIViewRepresentableContext<Self>) -> TheUIView { TheUIView() }
    func updateUIView(_ uiView: TheUIView, context: UIViewRepresentableContext<Self>) {
        configuration(uiView)
    }
}

struct Markdown: View {
    @EnvironmentObject var viewState: ViewState
    var text: String
    
    var body: some View {
        UIKLabel {
            let parser = MarkdownParser()
            $0.attributedText = parser.parse(text)
            $0.numberOfLines = 0
        }
    }
} 