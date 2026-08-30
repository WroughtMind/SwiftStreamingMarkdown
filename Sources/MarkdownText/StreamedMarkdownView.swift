//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
import Equatable

/// A source of incremental Markdown text for `StreamedMarkdownView`.
///
/// Each value yielded by `text` is a *complete snapshot* of the Markdown
/// source so far (a growing prefix), not an incremental delta. The view
/// re-parses each snapshot and updates the rendered output.
public protocol StreamedMarkdownSource {
  var text: AsyncStream<String> { get }
}

/// A SwiftUI view that incrementally parses and renders streamed Markdown.
///
/// Provide a `StreamedMarkdownSource` whose `text` async sequence yields
/// progressively larger snapshots of the Markdown source; the view re-parses
/// on each emission and refreshes the rendered output.
@Equatable
public struct StreamedMarkdownView: View {

  private let config: MarkdownRenderConfig
  @EquatableIgnoredUnsafeClosure private let onRender: (() -> Void)?
  @StateObject private var controller: StreamedMarkdownController

  /// Create a `StreamedMarkdownView`.
  /// - Parameters:
  ///   - source: The streamed Markdown source. Each emission must be the
  ///     complete Markdown source so far, not an incremental delta.
  ///   - config: Render configuration. Defaults to `.default`.
  ///   - listener: Optional listener that receives render and interaction events.
  ///   - onRender: Called once after the first non-empty document is ready to render.
  public init(
    source: StreamedMarkdownSource,
    config: MarkdownRenderConfig = .default,
    listener: MarkdownListener? = nil,
    onRender: (() -> Void)? = nil
  ) {
    self.config = config
    self.onRender = onRender
    _controller = StateObject(
      wrappedValue: StreamedMarkdownController(
        source: source,
        listener: listener,
        onRender: onRender
      )
    )
  }

  public var body: some View {
    DocumentView(
      renderableDocument: controller.markdownToRender,
      config: config,
      listener: controller.listener
    )
    .task(id: config) {
      await controller.start(config: config)
    }
    .onDisappear {
      Task {
        await controller.end()
      }
    }
  }
}

final class StreamedMarkdownController: ObservableObject {

  @Published var markdownToRender: RenderableDocument = .empty
  let listener: MarkdownListener?

  private let source: StreamedMarkdownSource
  private let parser: MarkdownParser
  private let onRender: (() -> Void)?
  private var task: Task<Void, Never>?
  private var didRender = false
  @WithLock private var latestText: String? = nil

  init(
    source: StreamedMarkdownSource,
    listener: MarkdownListener? = nil,
    onRender: (() -> Void)? = nil,
    parser: MarkdownParser = MarkdownParserImpl()
  ) {
    self.source = source
    self.listener = listener
    self.onRender = onRender
    self.parser = parser
  }

  func start(config: MarkdownRenderConfig) async {
    task?.cancel()
    task = Task { [weak self] in
      guard let self else { return }

      let (snapshots, continuation) = AsyncStream<String>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      if let latestText = self.latestText {
        continuation.yield(latestText)
      }
      let sourceTask = Task {
        for await text in self.source.text {
          guard !Task.isCancelled else { break }
          guard self.latestText != text else { continue }
          self.latestText = text
          continuation.yield(text)
        }
        continuation.finish()
      }
      defer {
        sourceTask.cancel()
        continuation.finish()
      }

      for await text in snapshots {
        guard !Task.isCancelled else { return }
        let parsed = await self.parser.parse(
          text: text,
          option: .init(
            speculativeRewrite: true,
            imageSupport: config.imageConfig.enabled
          )
        )
        guard self.latestText == text else { continue }
        let renderable = await RenderableDocument(document: parsed.document, config: config)
        guard !Task.isCancelled else { return }
        guard self.latestText == text else { continue }
        await MainActor.run {
          guard !Task.isCancelled, self.latestText == text else { return }
          self.markdownToRender = renderable
          if !renderable.isEmpty, !self.didRender {
            self.didRender = true
            self.onRender?()
          }
        }
      }
    }
  }

  func end() async {
    task?.cancel()
    task = nil
  }
}
