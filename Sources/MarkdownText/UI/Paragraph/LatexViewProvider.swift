//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftMath
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - LatexAttachmentData Color Resolution

extension LatexAttachmentData {
  var resolvedTextColor: MDColor {
    let fallback = MDColor(Color.Theme.Foreground.Primary.Primary750)
    #if canImport(UIKit)
    guard let lightColor = UIColor(hex: lightTextColor),
          let darkColor = UIColor(hex: darkTextColor) else {
      return fallback
    }
    return UIColor { trait in
      trait.userInterfaceStyle == .dark ? darkColor : lightColor
    }
    #elseif canImport(AppKit)
    guard let lightColor = NSColor(hex: lightTextColor),
          let darkColor = NSColor(hex: darkTextColor) else {
      return fallback
    }
    return NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark ? darkColor : lightColor
    }
    #endif
  }
}

// MARK: - Latex View Provider

final class LatexViewProvider: NSTextAttachmentViewProvider {
  private let latex: String
  private let fontSize: CGFloat
  private let textColor: MDColor
  private let displayMode: LatexAttachmentData.DisplayMode

  private struct DecodedAttachment {
    var latex: String = ""
    var fontSize: CGFloat = Typography.base.mdFont.pointSize
    var textColor: MDColor = MDColor(Color.Theme.Foreground.Primary.Primary750)
    var displayMode: LatexAttachmentData.DisplayMode = .inline
  }

  #if canImport(UIKit)
  required override init(textAttachment attachment: NSTextAttachment,
                         parentView: UIView?,
                         textLayoutManager: NSTextLayoutManager?,
                         location: any NSTextLocation) {
    let decoded = Self.decode(attachment: attachment)
    (latex, fontSize, textColor, displayMode) = (
      decoded.latex, decoded.fontSize, decoded.textColor, decoded.displayMode
    )
    super.init(textAttachment: attachment, parentView: parentView,
               textLayoutManager: textLayoutManager, location: location)
    tracksTextAttachmentViewBounds = true
  }
  #elseif canImport(AppKit)
  required override init(textAttachment attachment: NSTextAttachment,
                         parentView: NSView?,
                         textLayoutManager: NSTextLayoutManager?,
                         location: any NSTextLocation) {
    let decoded = Self.decode(attachment: attachment)
    (latex, fontSize, textColor, displayMode) = (
      decoded.latex, decoded.fontSize, decoded.textColor, decoded.displayMode
    )
    super.init(textAttachment: attachment, parentView: parentView,
               textLayoutManager: textLayoutManager, location: location)
    tracksTextAttachmentViewBounds = true
  }
  #endif

  private static func decode(attachment: NSTextAttachment) -> DecodedAttachment {
    var result = DecodedAttachment()
    if let attachmentData = LatexAttachmentData.decode(from: attachment) {
      result.latex = attachmentData.latex
      result.fontSize = attachmentData.fontSize
      result.textColor = attachmentData.resolvedTextColor
      result.displayMode = attachmentData.displayMode
    }
    return result
  }

  override func loadView() {
    let label = MTMathUILabel()
    let mathFont = MTFontManager().latinModernFont(withSize: fontSize)
    #if canImport(UIKit)
    mathFont?.fallbackFont = UIFont.systemFont(ofSize: fontSize)
    #elseif canImport(AppKit)
    mathFont?.fallbackFont = NSFont.systemFont(ofSize: fontSize)
    #endif
    label.font = mathFont
    label.latex = latex
    label.textColor = textColor
    #if canImport(UIKit)
    label.backgroundColor = .clear
    #elseif canImport(AppKit)
    label.wantsLayer = true
    label.layer?.backgroundColor = NSColor.clear.cgColor
    #endif
    // A malformed formula must remain visible in production instead of
    // collapsing into an empty attachment.
    label.displayErrorInline = true
    label.labelMode = displayMode == .block ? .display : .text
    label.setContentHuggingPriority(.defaultHigh, for: .vertical)
    #if canImport(AppKit)
    if displayMode == .block {
      self.view = BlockLatexAttachmentView(label: label)
      return
    }
    self.view = PassthroughMathView(label: label)
    #else
    self.view = label
    #endif
  }

  override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                 location: any NSTextLocation,
                                 textContainer: NSTextContainer?,
                                 proposedLineFragment: CGRect,
                                 position: CGPoint) -> CGRect {
    let mathLabel: MTMathUILabel?
    #if canImport(AppKit)
    if let blockView = view as? BlockLatexAttachmentView {
      mathLabel = blockView.label
    } else if let inlineView = view as? PassthroughMathView {
      mathLabel = inlineView.label
    } else {
      mathLabel = view as? MTMathUILabel
    }
    #else
    mathLabel = view as? MTMathUILabel
    #endif
    guard let mathLabel else {
      return .zero
    }
    #if canImport(UIKit)
    mathLabel.sizeToFit()
    let size = mathLabel.bounds.size
    #elseif canImport(AppKit)
    let size = mathLabel.intrinsicContentSize
    #endif
    let height = size.height.rounded(.up) + 1.0
    if displayMode == .block {
      let availableWidth = proposedLineFragment.width > 0 && proposedLineFragment.width.isFinite
        ? proposedLineFragment.width
        : size.width.rounded(.up)
      return CGRect(
        x: 0,
        y: 0,
        width: availableWidth,
        height: height
      )
    }
    let font = attributes[.font] as? MDFont ?? MDFont.systemFont(ofSize: fontSize)
    let yOffset = (font.xHeight - height) / 2.0
    return CGRect(x: 0, y: yOffset, width: size.width.rounded(.up), height: height)
  }
}

#if canImport(AppKit)
private final class PassthroughMathView: NSView {
  let label: MTMathUILabel

  init(label: MTMathUILabel) {
    self.label = label
    super.init(frame: .zero)
    addSubview(label)
  }

  required init?(coder: NSCoder) { nil }

  override var intrinsicContentSize: NSSize { label.intrinsicContentSize }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func layout() {
    super.layout()
    label.frame = bounds
  }
}

private final class BlockLatexAttachmentView: NSView {
  let label: MTMathUILabel
  private let scrollView = NSScrollView()
  private let formulaDocumentView = NSView()

  init(label: MTMathUILabel) {
    self.label = label
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = false
    scrollView.autohidesScrollers = true
    formulaDocumentView.addSubview(label)
    scrollView.documentView = formulaDocumentView
    addSubview(scrollView)
  }

  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  override func layout() {
    super.layout()
    scrollView.frame = bounds
    let formulaSize = label.intrinsicContentSize
    let contentWidth = max(bounds.width, formulaSize.width.rounded(.up))
    formulaDocumentView.frame = CGRect(
      origin: .zero,
      size: CGSize(width: contentWidth, height: bounds.height)
    )
    label.frame = CGRect(
      x: formulaSize.width < contentWidth ? (contentWidth - formulaSize.width) / 2 : 0,
      y: 0,
      width: formulaSize.width.rounded(.up),
      height: bounds.height
    )
  }

  override func mouseDown(with event: NSEvent) {
    enclosingTextView?.mouseDown(with: event)
  }

  override func mouseDragged(with event: NSEvent) {
    enclosingTextView?.mouseDragged(with: event)
  }

  override func scrollWheel(with event: NSEvent) {
    let isHorizontalScroll = event.scrollingDeltaX != 0
      || (event.modifierFlags.contains(.shift) && event.scrollingDeltaY != 0)
    guard
      isHorizontalScroll,
      formulaDocumentView.frame.width > scrollView.contentView.bounds.width
    else {
      nextResponder?.scrollWheel(with: event)
      return
    }
    scrollView.scrollWheel(with: event)
  }

  private var enclosingTextView: NSTextView? {
    var ancestor = superview
    while let view = ancestor {
      if let textView = view as? NSTextView { return textView }
      ancestor = view.superview
    }
    return nil
  }
}
#endif
