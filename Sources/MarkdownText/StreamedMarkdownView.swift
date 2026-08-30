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
  }
}

final class StreamedMarkdownController: ObservableObject {

  @Published var markdownToRender: RenderableDocument = .empty
  let listener: MarkdownListener?

  private let parser: MarkdownParser
  private let onRender: (() -> Void)?
  private let streamCoordinator: StreamCoordinator
  private var didRender = false

  init(
    source: StreamedMarkdownSource,
    listener: MarkdownListener? = nil,
    onRender: (() -> Void)? = nil,
    parser: MarkdownParser = MarkdownParserImpl()
  ) {
    self.listener = listener
    self.onRender = onRender
    self.parser = parser
    streamCoordinator = StreamCoordinator(source: source)
  }

  func start(config: MarkdownRenderConfig) async {
    let run = await streamCoordinator.beginRun()
    await withTaskCancellationHandler {
      for await text in run.snapshots {
        guard !Task.isCancelled else { return }
        let parsed = await parser.parse(
          text: text,
          option: .init(
            speculativeRewrite: true,
            imageSupport: config.imageConfig.enabled
          )
        )
        guard streamCoordinator.isCurrent(run, text: text) else { continue }
        let renderable = await RenderableDocument(document: parsed.document, config: config)
        guard !Task.isCancelled else { return }
        await MainActor.run {
          streamCoordinator.withCurrent(run, text: text) {
            guard !Task.isCancelled else { return }
            self.markdownToRender = renderable
            if !renderable.isEmpty, !self.didRender {
              self.didRender = true
              self.onRender?()
            }
          }
        }
      }
    } onCancel: {
      run.continuation.finish()
    }
    await streamCoordinator.endRun(run)
  }
}

private final class StreamRun: @unchecked Sendable {
  let snapshots: AsyncStream<String>
  let continuation: AsyncStream<String>.Continuation

  init() {
    (snapshots, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
  }
}

private actor StreamCoordinator {
  private let source: StreamedMarkdownSource
  private nonisolated let currentState = CurrentStreamState()
  private var sourceTask: Task<Void, Never>?
  private var activeRun: StreamRun?
  private var latestText: String?
  private var sourceFinished = false

  init(source: StreamedMarkdownSource) {
    self.source = source
  }

  deinit {
    sourceTask?.cancel()
  }

  func beginRun() -> StreamRun {
    startSourceIfNeeded()
    activeRun?.continuation.finish()

    let run = StreamRun()
    activeRun = run
    currentState.update(run: run, text: latestText)
    if let latestText {
      run.continuation.yield(latestText)
    }
    if sourceFinished {
      run.continuation.finish()
    }
    return run
  }

  nonisolated func isCurrent(_ run: StreamRun, text: String) -> Bool {
    currentState.isCurrent(run, text: text)
  }

  nonisolated func withCurrent(
    _ run: StreamRun,
    text: String,
    perform: () -> Void
  ) {
    currentState.withCurrent(run, text: text, perform: perform)
  }

  func endRun(_ run: StreamRun) {
    guard activeRun === run else { return }
    run.continuation.finish()
    activeRun = nil
    currentState.update(run: nil, text: latestText)
  }

  private func startSourceIfNeeded() {
    guard sourceTask == nil else { return }
    sourceTask = Task { [weak self, source] in
      for await text in source.text {
        guard !Task.isCancelled else { break }
        await self?.receive(text)
      }
      await self?.finishSource()
    }
  }

  private func receive(_ text: String) {
    guard latestText != text else { return }
    latestText = text
    currentState.update(run: activeRun, text: text)
    activeRun?.continuation.yield(text)
  }

  private func finishSource() {
    sourceFinished = true
    activeRun?.continuation.finish()
  }
}

private final class CurrentStreamState: @unchecked Sendable {
  private let lock = NSLock()
  private var run: StreamRun?
  private var text: String?

  func update(run: StreamRun?, text: String?) {
    lock.lock()
    self.run = run
    self.text = text
    lock.unlock()
  }

  func isCurrent(_ run: StreamRun, text: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return self.run === run && self.text == text
  }

  func withCurrent(_ run: StreamRun, text: String, perform: () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard self.run === run, self.text == text else { return }
    perform()
  }
}
