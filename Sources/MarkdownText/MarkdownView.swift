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
  @StateObject var controller: MarkdownViewController

  /// Create a `MarkdownView`.
  /// - Parameters:
  ///   - text: The raw Markdown source to parse and render.
  ///   - config: Render configuration. Defaults to `.default`.
  ///   - listener: Optional listener that receives render and interaction events.
  public init(
    text: String,
    config: MarkdownRenderConfig = .default,
    listener: MarkdownListener? = nil
  ) {
    self.text = text
    self.config = config
    _controller = StateObject(wrappedValue: MarkdownViewController(listener: listener))
  }

  public var body: some View {
    Group {
      if let renderable = controller.renderable {
        DocumentView(renderableDocument: renderable, config: config, listener: controller.listener)
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

  let listener: MarkdownListener?

  init(listener: MarkdownListener? = nil) {
    self.listener = listener
  }

  func parse(text: String, config: MarkdownRenderConfig) async {
    let renderable = await parser.parse(text: text, config: config)
    guard !Task.isCancelled else { return }
    await MainActor.run {
      guard !Task.isCancelled else { return }
      self.renderable = renderable
    }
  }
}
