//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct LatexAttachmentData: Codable, Equatable {
  enum DisplayMode: String, Codable {
    case inline
    case block
  }

  let latex: String
  let fontSize: CGFloat
  let lightTextColor: String
  let darkTextColor: String
  let displayMode: DisplayMode

  var sourceText: String {
    switch displayMode {
    case .inline:
      return "\\(\(latex)\\)"
    case .block:
      return "$$\n\(latex)\n$$"
    }
  }

  static func decode(from attachment: NSTextAttachment) -> LatexAttachmentData? {
    guard
      attachment.fileType == UTType.data.identifier,
      let data = attachment.contents
    else { return nil }
    return try? JSONDecoder().decode(LatexAttachmentData.self, from: data)
  }
}

extension NSAttributedString {
  var markdownSourceText: String {
    var result = ""
    enumerateAttribute(
      .attachment,
      in: NSRange(location: 0, length: length)
    ) { value, range, _ in
      if let attachment = value as? NSTextAttachment,
         let formula = LatexAttachmentData.decode(from: attachment) {
        result += formula.sourceText
      } else {
        result += attributedSubstring(from: range).string
      }
    }
    return result
  }
}
