//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit
import SwiftMath
@testable import SwiftStreamingMarkdown
import Testing

private final class InvalidationCountingParagraphNSView: ParagraphNSView {
  private(set) var intrinsicSizeInvalidationCount = 0

  override func invalidateIntrinsicContentSize() {
    intrinsicSizeInvalidationCount += 1
    super.invalidateIntrinsicContentSize()
  }
}

@Suite("ParagraphNSView Measurement Tests")
@MainActor
struct ParagraphNSViewTests {

  @Test("Streaming formulas stay in one reusable selection surface")
  func streamingFormulasStayInOneReusableSelectionSurface() async {
    let config = MarkdownRenderConfig.default.withBlockSpacing(value: 18)
    let parser = MarkdownParserImpl()
    let initialMarkdown = "first \\(x + 1\\)\n\n$$\ny = 2\n$$"
    let initial = await parser.parse(text: initialMarkdown, config: config)
    let appended = await parser.parse(
      text: "\(initialMarkdown)\n\nsecond",
      config: config
    )

    guard
      case .paragraph(let initialID, let initialContent) = initial.renderables.first,
      case .paragraph(let appendedID, let appendedContent) = appended.renderables.first
    else {
      Issue.record("Expected one continuous paragraph surface")
      return
    }
    #expect(initial.renderables.count == 1)
    #expect(appended.renderables.count == 1)
    #expect(appendedID == initialID)
    let view = ParagraphNSView()
    view.setParagraphContents(initialContent, animatedByWord: false)
    #expect(view.renderedPrefixMatches(appendedContent, length: initialContent.length))
    view.setParagraphContents(appendedContent, animatedByWord: false)

    let selectionBackground = NSColor(
      calibratedRed: 0.72,
      green: 0.24,
      blue: 0.18,
      alpha: 1
    )
    let selectionForeground = NSColor.white
    view.selectedTextAttributes = [
      .backgroundColor: selectionBackground,
      .foregroundColor: selectionForeground,
    ]
    let attachmentLocation = NSTextContentStorage().documentRange.location
    var formulaProviders: [NSTextAttachmentViewProvider] = []
    view.textStorage?.enumerateAttribute(
      .attachment,
      in: NSRange(location: 0, length: view.textStorage?.length ?? 0)
    ) { value, _, _ in
      guard let attachment = value as? NSTextAttachment,
            LatexAttachmentData.decode(from: attachment) != nil else { return }
      let provider = LatexViewProvider(
        textAttachment: attachment,
        parentView: view,
        textLayoutManager: nil,
        location: attachmentLocation
      )
      provider.loadView()
      formulaProviders.append(provider)
    }

    let formulaViews = formulaProviders.compactMap(\.view)
    guard formulaViews.count == 2 else {
      Issue.record("Expected inline and block formula views")
      return
    }
    #expect(formulaViews.allSatisfy { $0 is FormulaSelectionDisplaying })

    let blockFormulaView = formulaViews[1]
    guard let blockFormulaLabel = blockFormulaView.subviews.first as? MTMathUILabel else {
      Issue.record("Expected the block formula label to be hosted directly while it fits")
      return
    }
    let naturalFormulaWidth = blockFormulaLabel.intrinsicContentSize.width
    blockFormulaView.frame.size.width = naturalFormulaWidth
    blockFormulaView.layout()
    #expect(blockFormulaView.subviews.allSatisfy { !($0 is NSScrollView) })
    blockFormulaView.frame.size.width = naturalFormulaWidth / 2
    blockFormulaView.layout()
    #expect(blockFormulaView.subviews.contains { $0 is NSScrollView })
    blockFormulaView.frame.size.width = naturalFormulaWidth
    blockFormulaView.layout()
    #expect(blockFormulaView.subviews.allSatisfy { !($0 is NSScrollView) })

    view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
    #expect(view.selectedRange() == NSRange(location: 0, length: view.string.utf16.count))
    NotificationCenter.default.post(name: NSTextView.didChangeSelectionNotification, object: view)
    #expect(formulaViews.allSatisfy { $0.layer?.backgroundColor == selectionBackground.cgColor })

    let copied = view.textStorage?.attributedSubstring(from: view.selectedRange()).markdownSourceText
    #expect(copied == "first \\(x + 1\\)\n$$\ny = 2\n$$\nsecond")
    #expect(copied?.contains("\u{FFFC}") == false)

    view.setSelectedRange(NSRange(location: view.string.utf16.count - 1, length: 1))
    NotificationCenter.default.post(name: NSTextView.didChangeSelectionNotification, object: view)
    #expect(formulaViews.allSatisfy { $0.layer?.backgroundColor == NSColor.clear.cgColor })

    let paragraphStyle = initialContent.attribute(
      .paragraphStyle,
      at: initialContent.length - 1,
      effectiveRange: nil
    ) as? NSParagraphStyle
    #expect(paragraphStyle?.paragraphSpacing == 18)
  }

  /// Regression: a paragraph is often measured before SwiftUI has given the view a frame
  /// (e.g. during a navigation transition). Measuring through the view's own text container
  /// used to return a zero height in that state because `widthTracksTextView` forces the
  /// container width to follow the frame width (0), collapsing the paragraph. Measurement
  /// must instead honor the requested width regardless of the view's frame.
  @Test("Measures a non-zero, width-dependent height without a frame")
  func measuresHeightWithoutFrame() {
    let view = ParagraphNSView()
    let longText = String(repeating: "word ", count: 200)
    view.setParagraphContents(NSMutableAttributedString(string: longText), animatedByWord: false)

    let narrow = view.measureSize(fittingWidth: 200)
    let wide = view.measureSize(fittingWidth: 1000)

    #expect(narrow.height > 0, "Wrapping content must have a non-zero height even without a frame")
    #expect(wide.height > 0, "Wrapping content must have a non-zero height even without a frame")
    #expect(
      narrow.height > wide.height,
      "A narrower width must wrap to more lines and therefore be taller, proving the requested width is honored"
    )
  }

  @Test("Empty content measures as zero")
  func measuresEmptyContentAsZero() {
    let view = ParagraphNSView()
    view.setParagraphContents(NSMutableAttributedString(string: ""), animatedByWord: false)

    #expect(view.measureSize(fittingWidth: 400) == .zero)
  }

  @Test("Repeated measurement and layout at one width stay stable")
  func repeatedMeasurementAndLayoutStayStable() {
    let view = InvalidationCountingParagraphNSView()
    view.setParagraphContents(
      NSMutableAttributedString(string: String(repeating: "stable layout ", count: 80)),
      animatedByWord: false
    )

    let firstMeasurement = view.measureSize(fittingWidth: 320)
    let secondMeasurement = view.measureSize(fittingWidth: 320)

    #expect(firstMeasurement == secondMeasurement)
    #expect(firstMeasurement.width == 320)

    view.frame = NSRect(origin: .zero, size: firstMeasurement)
    let invalidationsBeforeLayout = view.intrinsicSizeInvalidationCount
    view.layout()
    view.layout()

    #expect(view.intrinsicSizeInvalidationCount == invalidationsBeforeLayout)
  }
}
#endif
