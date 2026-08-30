//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
import Equatable

/// This is a view that is able to both parse and render markdown with default configuration.
/// Use this view instead of `DocumentView` if you don't want to perform the parsing yourself.
@Equatable
public struct MarkdownView: View {

  private let text: String
  private let config: MarkdownRenderConfig
  @EquatableIgnoredUnsafeClosure private let onRender: (() -> Void)?
  @StateObject var controller: MarkdownViewController

  /// Create a `MarkdownView`.
  /// - Parameters:
  ///   - text: The raw Markdown source to parse and render.
  ///   - config: Render configuration. Defaults to `.default`.
  ///   - listener: Optional listener that receives render and interaction events.
  ///   - onRender: Called once when the first non-empty document surface appears.
  public init(
    text: String,
    config: MarkdownRenderConfig = .default,
    listener: MarkdownListener? = nil,
    onRender: (() -> Void)? = nil
  ) {
    self.text = text
    self.config = config
    self.onRender = onRender
    _controller = StateObject(
      wrappedValue: MarkdownViewController(listener: listener, onRender: onRender)
    )
  }

  public var body: some View {
    Group {
      if let renderable = controller.renderable, !renderable.isEmpty {
        DocumentView(renderableDocument: renderable, config: config, listener: controller.listener)
          .onAppear {
            controller.reportRendered()
          }
      } else {
        DocumentView(renderableDocument: .empty, config: config, listener: controller.listener)
      }
    }
    .task(id: MarkdownRequest(text: text, config: config)) {
      await controller.parse(text: text, config: config)
    }
  }
}

private struct MarkdownRequest: Hashable {
  let text: String
  let config: MarkdownRenderConfig
}

final class MarkdownViewController: ObservableObject {

  @Published var renderable: RenderableDocument?

  private let parser = MarkdownParserImpl()
  private let onRender: (() -> Void)?
  private var didRender = false

  let listener: MarkdownListener?

  init(listener: MarkdownListener? = nil, onRender: (() -> Void)? = nil) {
    self.listener = listener
    self.onRender = onRender
  }

  func parse(text: String, config: MarkdownRenderConfig) async {
    let renderable = await parser.parse(text: text, config: config)
    guard !Task.isCancelled else { return }
    await MainActor.run {
      guard !Task.isCancelled else { return }
      self.renderable = renderable
    }
  }

  @MainActor
  func reportRendered() {
    guard !didRender else { return }
    didRender = true
    onRender?()
  }
}
