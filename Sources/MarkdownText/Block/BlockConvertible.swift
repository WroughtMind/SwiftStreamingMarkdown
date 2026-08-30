//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// A markdown block that can be converted into `MarkdownRenderable`

protocol BlockConvertible {

  /// Convert into `MarkdownRenderable`
  /// - Parameter attributeContainer: The inherited attributes
  /// - Parameter config: The mark down rendering config used to override fonts & text color if needed.
  /// - Returns: A `MarkdownRenderable` that is ready to be rendered by Views.
  func convert(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> MarkdownRenderable
}

extension Markup {
  var blockConvertibleChildren: [BlockConvertible] {
    return self.children.compactMap { $0 as? BlockConvertible }
  }
}

#if canImport(AppKit)
extension NSMutableAttributedString {
  func applyPreferredLineSpacing(from fonts: TextFonts) {
    guard length > 0, let preferredLineHeight = fonts.preferredLineHeight else { return }
    let lineSpacing = max(preferredLineHeight - fonts.normal.lineHeight, 0)
    var updates: [(NSRange, NSMutableParagraphStyle)] = []
    enumerateAttribute(
      .paragraphStyle,
      in: NSRange(location: 0, length: length)
    ) { value, range, _ in
      let paragraphStyle = (value as? NSParagraphStyle)?.mutableCopy()
        as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
      paragraphStyle.lineSpacing = lineSpacing
      paragraphStyle.alignment = .left
      updates.append((range, paragraphStyle))
    }
    for (range, paragraphStyle) in updates {
      addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
    }
  }
}
#endif
