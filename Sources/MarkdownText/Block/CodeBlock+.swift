//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

extension CodeBlock: BlockConvertible {
  func convert(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> MarkdownRenderable {
    if self.language == LaTexPreProcessorImpl.customCodeType {
      #if canImport(AppKit)
      let font = config.paragraphStyle.textFonts.normal
      let textColor = NSColor(config.paragraphStyle.textColor)
      let attachmentData = LatexAttachmentData(
        latex: self.code.trimmingCharacters(in: .newlines),
        fontSize: font.pointSize,
        lightTextColor: textColor.resolvedForAppearance(.aqua).toHexString(),
        darkTextColor: textColor.resolvedForAppearance(.darkAqua).toHexString(),
        displayMode: .block
      )
      let payload = try! JSONEncoder().encode(attachmentData)
      let attachment = NSTextAttachment(data: payload, ofType: UTType.data.identifier)
      var container = attributeContainer
      container[.font] = font
      container[.typography] = config.paragraphStyle.textFonts
      if let kern = config.paragraphStyle.textFonts.preferredLetterSpacing {
        container[.kern] = kern
      }
      container[.foregroundColor] = textColor
      return .paragraph(
        id: self.id,
        content: NSMutableAttributedString(attachment: attachment).mergingAttributes(container)
      )
      #else
      return .latex(id: self.id, content: self.code)
      #endif
    } else {
      return .codeBlock(id: self.id, language: self.language, code: self.code)
    }
  }
}
