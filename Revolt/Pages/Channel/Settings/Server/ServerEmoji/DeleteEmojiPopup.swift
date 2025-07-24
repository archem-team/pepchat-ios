//
//  DeleteEmojiPopup.swift
//  Revolt
//
//  Created by Mehdi on 2/19/25.
//

import SwiftUI

struct DeleteEmojiPopup: View {
    @Binding var isPresented: Bool
    var emojiName: String
    var deleteEmojiCallback: (() -> Void)?

    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                PeptideText(
                    text: "Delete \(emojiName)?",
                    font: .peptideTitle3,
                    textColor: .textDefaultGray01,
                    alignment: .leading
                )
                .padding(.bottom, .size32)

                PeptideText(
                    text: "Do you want to delete \(emojiName) emoji?\nThis cannot be undone.",
                    font: .peptideBody3,
                    textColor: .textGray06,
                    alignment: .leading
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .size24)
            .padding(.top, .size24)
            .padding(.bottom, .size32)

            Divider()
                .frame(height: 1.5)
                .background(.borderGray10)

            HStack {
                PeptideButton(
                    title: "Dismiss",
                    bgColor: .clear,
                    contentColor: .textDefaultGray01,
                    isFullWidth: false
                ) {
                    isPresented.toggle()
                }

                PeptideButton(
                    title: "Delete Emoji",
                    bgColor: .bgRed07,
                    contentColor: .textDefaultGray01,
                    isFullWidth: false
                ) {
                    isPresented.toggle()
                    deleteEmojiCallback?()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.all, .size24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgGray11, in: RoundedRectangle(cornerRadius: .size16))
        .padding(.all, .size16)
    }
}

struct DeleteEmojiSheet_Previews: PreviewProvider {
    static var previews: some View {
        DeleteEmojiPopup(
            isPresented: .constant(true),
            emojiName: "sonic-03",
            deleteEmojiCallback: {}
        )
    }
}
