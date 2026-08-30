//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

struct OrderedListView: View {

  let items: [MarkdownListItem]
  @Environment(\.markdownConfig) var config: MarkdownRenderConfig

  var body: some View {
    VStack(alignment: .leading, spacing: listItemSpacing, content: {
      ForEach(0..<items.count, id: \.self) { idx in
        Grid(
          alignment: .leading,
          horizontalSpacing: listMarkerSpacing,
          verticalSpacing: listItemSpacing
        ) {
          GridRow(alignment: .centerOfFirstLine) {
            Text(verbatim: "\(idx+1).")
              .font(config.orderedListStyle.textFonts, bold: true)
              .foregroundStyle(listMarkerColor)
              .transition(.opacity)
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
              .frame(width: listMarkerColumnWidth, alignment: .trailing)
            if let firstChild = items[idx].children.first {
              if case .paragraph(_, let contents) = firstChild {
                ListItemContentWrapper(paragraphContents: contents) {
                  SingleBlockView(renderable: firstChild)
                }
                .accessibilityLabel(Text(markdownListAccessibilityLabel(for: contents.string, at: idx, length: items.count)))
              } else {
                SingleBlockView(renderable: firstChild)
              }
            }
          }
          if items[idx].children.count > 1 {
            GridRow(alignment: .top) {
              Color.clear
                .frame(width: listMarkerColumnWidth, height: 0)
              BlockView(renderables: Array(items[idx].children.dropFirst()))
            }
          }
        }
      }
    })
  }

  private var listIndentation: CGFloat {
    config.layoutStyle.listIndentation
      ?? config.paragraphStyle.textFonts.normal.pointSize * 1.45
  }

  private var listMarkerSpacing: CGFloat {
    config.layoutStyle.listMarkerSpacing
      ?? config.paragraphStyle.textFonts.normal.pointSize * 0.1
  }

  private var listMarkerColumnWidth: CGFloat {
    max(0, listIndentation - listMarkerSpacing)
  }

  private var listItemSpacing: CGFloat {
    config.layoutStyle.listItemSpacing
      ?? config.paragraphStyle.textFonts.normal.pointSize * 0.26
  }

  private var listMarkerColor: Color {
    config.layoutStyle.listMarkerColor ?? config.orderedListStyle.textColor
  }
}

// Wrapper to provide proper baseline alignment for UIViewRepresentable content
struct ListItemContentWrapper<Content: View>: View {
  let paragraphContents: NSMutableAttributedString
  let content: () -> Content

  init(paragraphContents: NSMutableAttributedString, @ViewBuilder content: @escaping () -> Content) {
    self.paragraphContents = paragraphContents
    self.content = content
  }

  var body: some View {
    content()
      .alignmentGuide(.centerOfFirstLine) { _ in
        let font = extractFirstFont()
        return font.lineHeight / 2.0
      }
  }

  private func extractFirstFont() -> MDFont {
    // First check if the first character is a citation attachment - use its
    // own font so the alignment guide matches the actual rendered glyph,
    // not a stale default.
    if let citation = firstCharacterCitationAttachment(in: paragraphContents) {
      return citation.font
    }
    // Otherwise, look for regular font attributes
    if let font = firstFont(in: paragraphContents) {
      return font
    }
    return Typography.base.mdFont
  }

  private func firstCharacterCitationAttachment(in attributedString: NSAttributedString) -> InlineCitationAttachment? {
    guard attributedString.length > 0 else { return nil }
    return attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? InlineCitationAttachment
  }

  private func firstFont(in attributedString: NSAttributedString) -> MDFont? {
    guard attributedString.length > 0 else { return nil }

    // Fast path: attribute at location 0
    if let font = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? MDFont {
      return font
    }

    var found: MDFont?
    attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: attributedString.length)) { value, _, stop in
      if let font = value as? MDFont {
        found = font
        stop.pointee = true
      }
    }
    return found
  }
}

func markdownListAccessibilityLabel(
  for item: String,
  at index: Int,
  length: Int
) -> String {
  String.markdownListItem(length: length, index: index + 1, item: item)
}

#Preview(body: {
  let items: [MarkdownListItem] = (0..<40).map { i in
    MarkdownListItem(children: [.paragraph(id: "\(i)", content: NSMutableAttributedString(string: "item \(i + 1)"))], startsWithBold: false)
  }
  return ScrollView {
    OrderedListView(items: items)
  }
})
