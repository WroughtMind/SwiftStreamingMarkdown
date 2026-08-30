//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit
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

    view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
    let copied = view.textStorage?.attributedSubstring(from: view.selectedRange()).markdownSourceText
    #expect(copied == "first \\(x + 1\\)\n$$\ny = 2\n$$\nsecond")
    #expect(copied?.contains("\u{FFFC}") == false)

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
