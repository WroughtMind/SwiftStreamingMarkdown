//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI

extension Markdown.Document {

  func convert(with config: MarkdownRenderConfig) -> [MarkdownRenderable] {
    let renderables = self
      .blockConvertibleChildren
      .map { $0.convert(attributeContainer: NSAttributeContainer(), config: config) }
    #if canImport(AppKit)
    return renderables.mergingAdjacentParagraphs(spacing: config.blockSpacing)
    #else
    return renderables
    #endif
  }
}

#if canImport(AppKit)
private extension Array where Element == MarkdownRenderable {
  func mergingAdjacentParagraphs(spacing: CGFloat) -> [MarkdownRenderable] {
    var result: [MarkdownRenderable] = []
    for renderable in self {
      guard
        case .paragraph(_, let next) = renderable,
        case .paragraph(let id, let current) = result.last
      else {
        result.append(renderable)
        continue
      }

      let merged = NSMutableAttributedString(attributedString: current)
      if merged.length > 0 {
        let location = merged.length - 1
        let paragraphStyle = (
          merged.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        )?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = spacing
        let paragraphRange = (merged.string as NSString).paragraphRange(
          for: NSRange(location: location, length: 0)
        )
        merged.addAttribute(.paragraphStyle, value: paragraphStyle, range: paragraphRange)
        merged.append(NSAttributedString(string: "\n"))
      }
      merged.append(next)
      result[result.count - 1] = .paragraph(id: id, content: merged)
    }
    return result
  }
}
#endif
