//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import HighlightSwift

actor HighlightTaskManager: ObservableObject {
  private struct Work {
    let request: HighlightRequest
    let colors: HighlightColors
    let completion: @MainActor (HighlightRequest, AttributedString) -> Void
  }

  /// Shared Highlight instance to avoid creating multiple JSContext/HLJS instances.
  /// Each Highlight() creates its own JSContext and evaluates highlight.min.js (~600KB).
  /// When multiple CodeBlockViews render concurrently, N separate JSContexts cause
  /// JavaScriptCore OOM crashes (COPILOT-IOS-3F9C, 3F7Z, 3FSQ).
  private static let sharedHighlight = Highlight()

  private var latestWork: Work?
  private var isProcessing = false

  func enqueueCode(
    _ request: HighlightRequest,
    colors: HighlightColors,
    completion: @escaping @MainActor (HighlightRequest, AttributedString) -> Void
  ) {
    latestWork = Work(request: request, colors: colors, completion: completion)

    if !isProcessing {
      Task {
        await processQueue()
      }
    }
  }

  private func processQueue() async {
    guard !isProcessing else { return }

    isProcessing = true

    while let work = latestWork {
      latestWork = nil

      if let result = try? await Self.sharedHighlight.attributedText(
        work.request.code,
        colors: work.colors
      ) {
        await MainActor.run {
          work.completion(work.request, result)
        }
      }
    }

    isProcessing = false
  }
}
