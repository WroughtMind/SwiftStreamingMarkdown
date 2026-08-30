//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

struct UnorderedListView: View {

  let items: [MarkdownListItem]
  let nestedLevel: Int
  @Environment(\.markdownConfig) private var config

  var body: some View {
    VStack(alignment: .leading, spacing: listItemSpacing, content: {
      ForEach(0..<items.count, id: \.self) { idx in
        Grid(
          alignment: .leading,
          horizontalSpacing: listMarkerSpacing,
          verticalSpacing: listItemSpacing
        ) {
          GridRow(alignment: .centerOfFirstLine) {
            bulletView(forListItem: items[idx])
            if let firstChild = items[idx].children.first {
              if case .paragraph(_, let contents) = firstChild {
                ListItemContentWrapper(paragraphContents: contents) {
                  SingleBlockView(renderable: firstChild)
                }
                .accessibilityLabel(Text(listItemAccessibilityLabel(for: contents.string, at: idx, checkbox: items[idx].checkbox)))
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

  func bulletView(forListItem listItem: MarkdownListItem) -> some View {
    ZStack(alignment: .trailing) {
      if let checkbox = listItem.checkbox {
        Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
          .resizable()
          .frame(width: markerFontSize * 0.86, height: markerFontSize * 0.86)
          .foregroundStyle(listMarkerColor)
          .transition(.opacity)
      } else if nestedLevel % 2 == 0 {
        Image(systemName: "circle.fill")
          .resizable()
          .frame(width: markerFontSize * 0.28, height: markerFontSize * 0.28)
          .foregroundStyle(listMarkerColor)
          .transition(.opacity)
      } else {
        Image(systemName: "circle")
          .resizable()
          .frame(width: markerFontSize * 0.28, height: markerFontSize * 0.28)
          .foregroundStyle(listMarkerColor)
          .transition(.opacity)
      }
    }
    .frame(width: listMarkerColumnWidth, alignment: .trailing)
  }

  private var markerFontSize: CGFloat {
    config.paragraphStyle.textFonts.normal.pointSize
  }

  private func listItemAccessibilityLabel(for content: String, at index: Int, checkbox: MarkdownListItem.Checkbox?) -> String {
    let label = markdownListAccessibilityLabel(for: content, at: index, length: items.count)
    switch checkbox {
    case .checked: return "\(label), \(String.taskListItemChecked)"
    case .unchecked: return "\(label), \(String.taskListItemUnchecked)"
    case .none: return label
    }
  }
}

extension VerticalAlignment {
  private enum CenterOfFirstLine: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
      let heightAfterFirstLine = context[.lastTextBaseline] - context[.firstTextBaseline]
      let heightOfFirstLine = context.height - heightAfterFirstLine
      return heightOfFirstLine / 2
    }
  }
  static let centerOfFirstLine = Self(CenterOfFirstLine.self)
}

#Preview(body: {
  return UnorderedListView(items: [
    MarkdownListItem(children: [.paragraph(id: "1-1",
                                           content: NSMutableAttributedString(string: "item 1"))],
                     startsWithBold: false),
    MarkdownListItem(children: [.paragraph(id: "1-2",
                                           content: NSMutableAttributedString(string: "item 2"))],
                     startsWithBold: false),
    MarkdownListItem(children: [.paragraph(id: "1-3",
                                           content: NSMutableAttributedString(string: "item 3, this is a very long item with a lot of texts. it may create a multi-line paragraph."))],
                     startsWithBold: false),
    MarkdownListItem(children: [.paragraph(id: "1-4",
                                           content: NSMutableAttributedString(string: "a completed task"))],
                     startsWithBold: false,
                     checkbox: .checked),
    MarkdownListItem(children: [.paragraph(id: "1-5",
                                           content: NSMutableAttributedString(string: "an open task"))],
                     startsWithBold: false,
                     checkbox: .unchecked)
  ],
  nestedLevel: 0).padding()
})
