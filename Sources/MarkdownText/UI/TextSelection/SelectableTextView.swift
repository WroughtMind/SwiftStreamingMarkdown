//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

/// A scrollable, uneditable, selectable text view used by `TextSelectionView`.
/// On appearance it preselects the first paragraph so the user can immediately
/// extend the selection.
struct SelectableTextView: View {
  let text: String
  let textStyle: MarkdownRenderConfig.MarkdownTextStyle
  let selectionColor: Color
  let selectedTextColor: Color?

  var body: some View {
    SelectableTextViewRepresentable(
      text: text,
      textStyle: textStyle,
      selectionColor: selectionColor,
      selectedTextColor: selectedTextColor
    )
  }
}

private func selectionAttributedString(
  for text: String,
  style: MarkdownRenderConfig.MarkdownTextStyle
) -> NSAttributedString {
  let fonts = style.textFonts
  let font = fonts.normal
  let paragraphStyle = NSMutableParagraphStyle()
  paragraphStyle.alignment = .left
  if let preferredLineHeight = fonts.preferredLineHeight, preferredLineHeight > font.lineHeight {
    paragraphStyle.lineSpacing = preferredLineHeight - font.lineHeight
  }
  var attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: MDColor(style.textColor),
    .paragraphStyle: paragraphStyle
  ]
  if let kern = fonts.preferredLetterSpacing {
    attributes[.kern] = kern
  }
  return NSAttributedString(string: text, attributes: attributes)
}

/// The range of the first paragraph (up to the first newline), or the whole
/// string when it contains no newline.
private func firstParagraphRange(in text: String) -> NSRange {
  let nsText = text as NSString
  guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }
  let newline = nsText.rangeOfCharacter(from: .newlines)
  if newline.location != NSNotFound {
    return NSRange(location: 0, length: newline.location)
  }
  return NSRange(location: 0, length: nsText.length)
}

private func clampedSelectionRange(_ range: NSRange, textLength: Int) -> NSRange {
  let location = min(range.location, textLength)
  let length = min(range.length, textLength - location)
  return NSRange(location: location, length: length)
}

#if canImport(UIKit)
import UIKit

private struct SelectableTextViewRepresentable: UIViewRepresentable {
  let text: String
  let textStyle: MarkdownRenderConfig.MarkdownTextStyle
  let selectionColor: Color
  let selectedTextColor: Color?

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.backgroundColor = .clear
    textView.showsVerticalScrollIndicator = false
    textView.tintColor = UIColor(selectionColor)
    textView.attributedText = selectionAttributedString(for: text, style: textStyle)
    DispatchQueue.main.async {
      let range = firstParagraphRange(in: text)
      if let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
         let end = textView.position(from: start, offset: range.length) {
        textView.selectedTextRange = textView.textRange(from: start, to: end)
        textView.becomeFirstResponder()
      }
    }
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    let updatedText = selectionAttributedString(for: text, style: textStyle)
    if !textView.attributedText.isEqual(to: updatedText) {
      let selectedRange = textView.selectedRange
      textView.attributedText = updatedText
      textView.selectedRange = clampedSelectionRange(
        selectedRange,
        textLength: updatedText.length
      )
    }
    textView.tintColor = UIColor(selectionColor)
  }
}
#elseif canImport(AppKit)
import AppKit

private struct SelectableTextViewRepresentable: NSViewRepresentable {
  let text: String
  let textStyle: MarkdownRenderConfig.MarkdownTextStyle
  let selectionColor: Color
  let selectedTextColor: Color?

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true

    guard let textView = scrollView.documentView as? NSTextView else {
      return scrollView
    }
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 0, height: 0)
    textView.selectedTextAttributes = markdownSelectedTextAttributes(
      selectionColor: selectionColor,
      selectedTextColor: selectedTextColor
    )
    textView.textStorage?.setAttributedString(selectionAttributedString(for: text, style: textStyle))

    DispatchQueue.main.async {
      textView.setSelectedRange(firstParagraphRange(in: text))
      textView.window?.makeFirstResponder(textView)
    }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    let updatedText = selectionAttributedString(for: text, style: textStyle)
    if textView.attributedString().isEqual(to: updatedText) == false {
      let selectedRange = textView.selectedRange()
      textView.textStorage?.setAttributedString(updatedText)
      textView.setSelectedRange(clampedSelectionRange(
        selectedRange,
        textLength: updatedText.length
      ))
    }
    textView.selectedTextAttributes = markdownSelectedTextAttributes(
      selectionColor: selectionColor,
      selectedTextColor: selectedTextColor
    )
  }
}
#endif
