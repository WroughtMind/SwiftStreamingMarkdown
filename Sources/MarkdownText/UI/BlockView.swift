//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

struct BlockView: View {

  @Environment(\.markdownConfig) var config: MarkdownRenderConfig

  let renderables: [MarkdownRenderable]

  init(renderables: [MarkdownRenderable]) {
    self.renderables = renderables
  }

  var body: some View {
    LazyVStack(alignment: .leading, spacing: config.blockSpacing) {
      ForEach(renderables) { renderable in
        SingleBlockView(renderable: renderable)
      }
    }
  }
}

struct SingleBlockView: View {

  @Environment(\.markdownConfig) var config: MarkdownRenderConfig

  let renderable: MarkdownRenderable

  init(renderable: MarkdownRenderable) {
    self.renderable = renderable
  }

  var body: some View {
    Group {
      switch renderable {
      case .heading(_, _, let contents):
        ParagraphView(contents: contents, lineSpacing: contents.preferredLineSpacing)
          .transition(.opacity)
          .accessibilityAddTraits(.isHeader)
      case .paragraph(_, let contents):
        ParagraphView(contents: contents, lineSpacing: contents.preferredLineSpacing)
          .transition(.opacity)
      case .latex(_, let latexString):
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 0) {
            Spacer(minLength: 0)
            blockMath(latexString)
            Spacer(minLength: 0)
          }
          ScrollView(.horizontal) {
            blockMath(latexString)
          }
          .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity)
      case .orderedList(_, let items):
        OrderedListView(items: items)
      case .unorderedList(_, let items, let nestedLevel):
        UnorderedListView(items: items, nestedLevel: nestedLevel)
      case .codeBlock(_, let language, let code):
        CodeBlockView(language: language ?? "",
                      code: code)
      case .thematicBreak:
        ThematicBreakView()
      case .table(_, let headers, let rows, let rawMarkdown):
        TableView(headings: headers,
                  rows: rows,
                  rawMarkdown: rawMarkdown)
      case .blockQuote(_, let item):
        BlockQuoteView(item: item)
      case .image(let id, let data):
        BlockImageView(data: data)
          .id(id)
      }
    }
  }

  private func blockMath(_ latex: String) -> some View {
    BlockMathView(
      latex: latex,
      color: config.paragraphStyle.textColor,
      pointSize: config.paragraphStyle.textFonts.normal.pointSize
    )
  }
}

private extension NSAttributedString {
  var preferredLineSpacing: CGFloat? {
    guard length > 0 else { return nil }
    var textFonts: TextFonts?
    enumerateAttribute(
      .typography,
      in: NSRange(location: 0, length: length)
    ) { value, _, stop in
      guard let value = value as? TextFonts else { return }
      textFonts = value
      stop.pointee = true
    }
    guard let textFonts, let preferredLineHeight = textFonts.preferredLineHeight else {
      return nil
    }
    return max(preferredLineHeight - textFonts.normal.lineHeight, 0)
  }
}
