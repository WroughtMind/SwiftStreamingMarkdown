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
    #expect(renderCount == 1)
    newRun.cancel()
    await newRun.value

    var staticRenderCount = 0
    let staticController = MarkdownViewController(onRender: { staticRenderCount += 1 })
    await staticController.parse(text: "", config: config)
    await staticController.parse(text: "ready", config: config)
    await staticController.parse(text: "ready again", config: updatedConfig)
    #expect(staticRenderCount == 1)
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
