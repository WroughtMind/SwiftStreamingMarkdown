#if canImport(AppKit)
import AppKit
import Combine
import Markdown
@testable import SwiftStreamingMarkdown
import Testing

@Suite("Rendering request lifecycle")
@MainActor
struct RenderingRequestTests {
  @Test("Latest request, configuration, and structured run win")
  func latestRequestAndConfigWin() async {
    #expect(MarkdownController(listener: nil).hasRenderListener == false)

    let source = ControlledMarkdownSource()
    let parser = ControlledMarkdownParser()
    var renderCount = 0
    let controller = StreamedMarkdownController(
      source: source,
      onRender: { renderCount += 1 },
      parser: parser
    )
    let font = NSFont.systemFont(ofSize: 27)
    let config = MarkdownRenderConfig.default.withParagraphStyle(value: .init(
      textFonts: TextFonts(
        normal: font,
        italic: nil,
        bold: nil,
        boldItalic: nil,
        preferredLetterSpacing: nil,
        preferredLineHeight: nil
      ),
      textColor: .primary
    ))

    let oldRun = Task {
      await controller.start(config: config)
    }
    source.yield("old")
    await parser.waitUntilOldRequestStarts()
    source.yield("final")

    let updatedFont = NSFont.systemFont(ofSize: 31)
    let updatedConfig = config.withParagraphStyle(value: .init(
      textFonts: TextFonts(
        normal: updatedFont,
        italic: nil,
        bold: nil,
        boldItalic: nil,
        preferredLetterSpacing: nil,
        preferredLineHeight: nil
      ),
      textColor: .primary
    ))
    let finalRender = Task {
      for await renderable in controller.$markdownToRender.values {
        let font = renderable.attributedStrings.first?.attribute(
          NSAttributedString.Key.font,
          at: 0,
          effectiveRange: nil
        ) as? NSFont
        if renderable.plainText == "final", font?.pointSize == updatedFont.pointSize {
          return renderable
        }
      }
      return RenderableDocument.empty
    }
    oldRun.cancel()
    let newRun = Task {
      await controller.start(config: updatedConfig)
    }

    #expect(await finalRender.value.plainText == "final")
    await parser.finishOldRequest()
    await oldRun.value

    let continuedRender = Task {
      for await renderable in controller.$markdownToRender.values {
        if renderable.plainText == "after restart" {
          return renderable
        }
      }
      return RenderableDocument.empty
    }
    source.yield("after restart")

    #expect(await continuedRender.value.plainText == "after restart")
    #expect(renderCount == 0)
    controller.reportRendered()
    controller.reportRendered()
    #expect(renderCount == 1)
    newRun.cancel()
    await newRun.value

    var staticRenderCount = 0
    let staticController = MarkdownViewController(onRender: { staticRenderCount += 1 })
    await staticController.parse(text: "", config: config)
    await staticController.parse(text: "ready", config: config)
    await staticController.parse(text: "ready again", config: updatedConfig)
    #expect(staticRenderCount == 0)
    staticController.reportRendered()
    staticController.reportRendered()
    #expect(staticRenderCount == 1)

    let oldHighlight = HighlightRequest(code: "old", colorScheme: .light, theme: .standard)
    let newHighlight = HighlightRequest(code: "new", colorScheme: .dark, theme: .xcode)
    let highlightResult = HighlightResultStore()
    highlightResult.begin(oldHighlight)
    highlightResult.publish(AttributedString("old highlighted"), for: oldHighlight)
    #expect(highlightResult.attributedString(for: oldHighlight) == AttributedString("old highlighted"))
    #expect(highlightResult.attributedString(for: newHighlight) == nil)
    highlightResult.begin(newHighlight)
    #expect(highlightResult.attributedString(for: newHighlight) == nil)
    highlightResult.publish(AttributedString("late old"), for: oldHighlight)
    #expect(highlightResult.attributedString(for: newHighlight) == nil)
    highlightResult.publish(AttributedString("new highlighted"), for: newHighlight)
    #expect(highlightResult.attributedString(for: newHighlight) == AttributedString("new highlighted"))

    let selectionAttributes = markdownSelectedTextAttributes(
      selectionColor: .red,
      selectedTextColor: .white
    )
    #expect(selectionAttributes[.backgroundColor] != nil)
    #expect(selectionAttributes[.foregroundColor] != nil)

    await staticController.parse(
      text: "link [end](https://example.com)\n\nmath \\(x\\)\n\nlast",
      config: updatedConfig
    )
    let mergedText = try? #require(staticController.renderable?.attributedStrings.first)
    #expect(mergedText != nil)
    if let mergedText {
      let string = mergedText.string as NSString
      var linkCount = 0
      var attachmentCount = 0
      mergedText.enumerateAttributes(
        in: NSRange(location: 0, length: mergedText.length)
      ) { attributes, _, _ in
        if attributes[.link] != nil { linkCount += 1 }
        if attributes[.attachment] != nil { attachmentCount += 1 }
      }
      #expect(linkCount > 0)
      #expect(attachmentCount > 0)
      var location = 0
      while location < string.length {
        let range = string.range(of: "\n", range: NSRange(location: location, length: string.length - location))
        guard range.location != NSNotFound else { break }
        #expect(mergedText.attribute(.link, at: range.location, effectiveRange: nil) == nil)
        #expect(mergedText.attribute(.attachment, at: range.location, effectiveRange: nil) == nil)
        #expect(mergedText.attribute(.underlineStyle, at: range.location, effectiveRange: nil) == nil)
        #expect(mergedText.attribute(.font, at: range.location, effectiveRange: nil) != nil)
        #expect(mergedText.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) != nil)
        location = NSMaxRange(range)
      }
    }
  }
}

private final class ControlledMarkdownSource: StreamedMarkdownSource {
  let text: AsyncStream<String>
  private let continuation: AsyncStream<String>.Continuation

  init() {
    (text, continuation) = AsyncStream.makeStream()
  }

  func yield(_ text: String) {
    continuation.yield(text)
  }
}

private actor ControlledMarkdownParser: MarkdownParser {
  private var didBlockOldRequest = false
  private var oldRequestStarted = false
  private var oldRequestStartWaiter: CheckedContinuation<Void, Never>?
  private var oldRequestWaiter: CheckedContinuation<Void, Never>?

  func parse(text: String, option: MarkdownParseOption) async -> MarkdownParseResult {
    if text == "old", !didBlockOldRequest {
      didBlockOldRequest = true
      oldRequestStarted = true
      oldRequestStartWaiter?.resume()
      oldRequestStartWaiter = nil
      await withCheckedContinuation { continuation in
        oldRequestWaiter = continuation
      }
    }
    return MarkdownParseResult(document: Document(parsing: text), speculativeRewritten: false)
  }

  func waitUntilOldRequestStarts() async {
    guard !oldRequestStarted else { return }
    await withCheckedContinuation { continuation in
      oldRequestStartWaiter = continuation
    }
  }

  func finishOldRequest() {
    oldRequestWaiter?.resume()
    oldRequestWaiter = nil
  }
}
#endif
