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
  #if canImport(AppKit)
  private weak var parentParagraphView: ParagraphNSView?
  private weak var representedAttachment: NSTextAttachment?
  #endif

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
    parentParagraphView = parentView as? ParagraphNSView
    representedAttachment = attachment
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
    let naturalSize = label.intrinsicContentSize
    let attachmentView: NSView & FormulaSelectionDisplaying
    if displayMode == .block {
      attachmentView = BlockLatexAttachmentView(
        label: label,
        naturalSize: naturalSize,
        originalTextColor: textColor
      )
    } else {
      attachmentView = PassthroughMathView(
        label: label,
        naturalSize: naturalSize,
        originalTextColor: textColor
      )
    }
    self.view = attachmentView
    if let attachment = representedAttachment {
      parentParagraphView?.registerFormulaSelectionView(attachmentView, for: attachment)
    }
    #else
    self.view = label
    #endif
  }

  override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                 location: any NSTextLocation,
                                 textContainer: NSTextContainer?,
                                 proposedLineFragment: CGRect,
                                 position: CGPoint) -> CGRect {
    let measuredSize: CGSize
    #if canImport(AppKit)
    if let blockView = view as? BlockLatexAttachmentView {
      measuredSize = blockView.naturalSize
    } else if let inlineView = view as? PassthroughMathView {
      measuredSize = inlineView.naturalSize
    } else {
      return .zero
    }
    #else
    guard let mathLabel = view as? MTMathUILabel else {
      return .zero
    }
    mathLabel.sizeToFit()
    measuredSize = mathLabel.bounds.size
    #endif
    let height = measuredSize.height.rounded(.up) + 1.0
    if displayMode == .block {
      let availableWidth = proposedLineFragment.width > 0 && proposedLineFragment.width.isFinite
        ? proposedLineFragment.width
        : measuredSize.width.rounded(.up)
      return CGRect(
        x: 0,
        y: 0,
        width: availableWidth,
        height: height
      )
    }
    let font = attributes[.font] as? MDFont ?? MDFont.systemFont(ofSize: fontSize)
    let yOffset = (font.xHeight - height) / 2.0
    return CGRect(x: 0, y: yOffset, width: measuredSize.width.rounded(.up), height: height)
  }
}

#if canImport(AppKit)
private final class PassthroughMathView: NSView, FormulaSelectionDisplaying {
  let label: MTMathUILabel
  let naturalSize: CGSize
  private let originalTextColor: NSColor

  init(label: MTMathUILabel, naturalSize: CGSize, originalTextColor: NSColor) {
    self.label = label
    self.naturalSize = naturalSize
    self.originalTextColor = originalTextColor
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    addSubview(label)
  }

  required init?(coder: NSCoder) { nil }

  override var intrinsicContentSize: NSSize { naturalSize }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func setFormulaSelected(
    _ isSelected: Bool,
    backgroundColor: NSColor?,
    textColor: NSColor?
  ) {
    layer?.backgroundColor = isSelected ? backgroundColor?.cgColor : NSColor.clear.cgColor
    label.textColor = isSelected ? (textColor ?? originalTextColor) : originalTextColor
  }

  override func layout() {
    super.layout()
    label.frame = bounds
  }
}

private final class BlockLatexAttachmentView: NSView, FormulaSelectionDisplaying {
  let label: MTMathUILabel
  let naturalSize: CGSize
  private let originalTextColor: NSColor
  private let scrollView = NSScrollView()
  private let formulaDocumentView = NSView()

  init(label: MTMathUILabel, naturalSize: CGSize, originalTextColor: NSColor) {
    self.label = label
    self.naturalSize = naturalSize
    self.originalTextColor = originalTextColor
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.documentView = formulaDocumentView
    addSubview(label)
  }

  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  func setFormulaSelected(
    _ isSelected: Bool,
    backgroundColor: NSColor?,
    textColor: NSColor?
  ) {
    layer?.backgroundColor = isSelected ? backgroundColor?.cgColor : NSColor.clear.cgColor
    label.textColor = isSelected ? (textColor ?? originalTextColor) : originalTextColor
  }

  override func layout() {
    super.layout()
    let labelWidth = naturalSize.width.rounded(.up)
    if naturalSize.width > bounds.width {
      if scrollView.superview !== self {
        label.removeFromSuperview()
        formulaDocumentView.addSubview(label)
        addSubview(scrollView)
      }
      scrollView.frame = bounds
      formulaDocumentView.frame = CGRect(
        origin: .zero,
        size: CGSize(width: labelWidth, height: bounds.height)
      )
      label.frame = CGRect(x: 0, y: 0, width: labelWidth, height: bounds.height)
    } else {
      if label.superview !== self {
        scrollView.removeFromSuperview()
        label.removeFromSuperview()
        addSubview(label)
      }
      label.frame = CGRect(
        x: (bounds.width - labelWidth) / 2,
        y: 0,
        width: labelWidth,
        height: bounds.height
      )
    }
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
      scrollView.superview === self,
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
