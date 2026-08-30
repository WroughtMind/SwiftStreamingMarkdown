//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

struct BlockQuoteView: View {
  let item: BlockQuoteType

  init(item: BlockQuoteRenderable) {
    self.item = item.quoteType
  }

  var body: some View {
    InternalBlockQuoteView(item: item)
  }
}

private struct InternalBlockQuoteView: View {
  let item: BlockQuoteType
  @Environment(\.markdownConfig) private var config

  var body: some View {
    HStack(spacing: blockQuoteContentSpacing) {

      if item.isNested {
        QuoteDivider()
          .frame(width: config.layoutStyle.blockQuoteBorderWidth)
      }

      VStack(spacing: 12.0) {
        switch item {
        case .text(let text):
          HStack {
            QuoteTextView(text: text)

            Spacer()
          }
          .fixedSize(horizontal: false, vertical: true)
        case .nested(let subItems):
          ForEach(subItems.indices, id: \.self) { index in
            InternalBlockQuoteView(item: subItems[index])
              .fixedSize(horizontal: false, vertical: true)
          }
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.vertical, 4.0)
      .fixedSize(horizontal: false, vertical: true)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var blockQuoteContentSpacing: CGFloat {
    config.layoutStyle.blockQuoteContentSpacing
      ?? config.paragraphStyle.textFonts.normal.pointSize
  }
}

struct QuoteTextView: View {
  @Environment(\.markdownConfig) var config: MarkdownRenderConfig

  let text: String

  var body: some View {
    Text(text)
      .font(config.blockQuoteStyle.textFonts)
      .foregroundStyle(config.blockQuoteStyle.textColor)
      .padding(.vertical, 4.0)
      .fixedSize(horizontal: false, vertical: true)
  }
}

struct QuoteDivider: View {
  @Environment(\.markdownConfig) private var config

  var body: some View {
    RoundedRectangle(cornerRadius: 8.0, style: .continuous)
      .foregroundStyle(config.layoutStyle.blockQuoteBorderColor)
  }
}

indirect enum BlockQuoteType: Equatable, Hashable {
  case text(String)
  case nested([BlockQuoteType])

  var isNested: Bool {
    switch self {
    case .text:
      false
    case .nested:
      true
    }
  }
}
