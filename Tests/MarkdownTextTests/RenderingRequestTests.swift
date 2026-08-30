#if canImport(AppKit)
import AppKit
import Combine
import Markdown
@testable import SwiftStreamingMarkdown
import Testing

@Suite("Rendering request lifecycle")
@MainActor
struct RenderingRequestTests {
  @Test("Latest request and render configuration win")
  func latestRequestAndConfigWin() async {
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

    let firstRender = Task {
      for await renderable in controller.$markdownToRender.values where !renderable.isEmpty {
        return renderable
      }
      return RenderableDocument.empty
    }
    await controller.start(config: config)
    source.yield("old")
    await parser.waitUntilOldRequestStarts()
    source.yield("new")
    await parser.finishOldRequest()
    let renderable = await firstRender.value
    #expect(renderable.plainText == "new")
    let renderedFont = renderable.attributedStrings.first?.attribute(
      NSAttributedString.Key.font,
      at: 0,
      effectiveRange: nil
    ) as? NSFont
    #expect(renderedFont?.pointSize == font.pointSize)

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
    let restyledRender = Task {
      for await renderable in controller.$markdownToRender.values {
        let font = renderable.attributedStrings.first?.attribute(
          NSAttributedString.Key.font,
          at: 0,
          effectiveRange: nil
        ) as? NSFont
        if font?.pointSize == updatedFont.pointSize {
          return renderable
        }
      }
      return RenderableDocument.empty
    }
    await controller.start(config: updatedConfig)

    #expect(await restyledRender.value.plainText == "new")
    #expect(renderCount == 1)
    await controller.end()
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
  private var oldRequestStarted = false
  private var oldRequestStartWaiter: CheckedContinuation<Void, Never>?
  private var oldRequestWaiter: CheckedContinuation<Void, Never>?

  func parse(text: String, option: MarkdownParseOption) async -> MarkdownParseResult {
    if text == "old" {
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
