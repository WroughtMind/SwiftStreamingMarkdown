//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown

/// Locates Markdown code spans before formula preprocessing so their bytes stay untouched.
public enum MarkdownCodeRangeScanner {
  public static func ranges(in input: String) -> [NSRange] {
    var collector = CodeRangeCollector()
    collector.visit(Document(parsing: input))
    let lineStarts = sourceLineStarts(in: input)
    return collector.sourceRanges.compactMap {
      stringRange(for: $0, in: input, lineStarts: lineStarts)
    }.map { NSRange($0, in: input) }.sorted(by: { $0.location < $1.location })
  }

  private struct CodeRangeCollector: MarkupWalker {
    var sourceRanges: [SourceRange] = []

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
      if let range = codeBlock.range { sourceRanges.append(range) }
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
      if let range = inlineCode.range { sourceRanges.append(range) }
    }
  }

  private static func sourceLineStarts(in input: String) -> [String.Index] {
    var starts = [input.startIndex]
    for index in input.indices where input[index] == "\n" {
      starts.append(input.index(after: index))
    }
    return starts
  }

  private static func stringRange(
    for range: SourceRange,
    in input: String,
    lineStarts: [String.Index]
  ) -> Range<String.Index>? {
    guard let lower = stringIndex(for: range.lowerBound, in: input, lineStarts: lineStarts),
          let upper = stringIndex(for: range.upperBound, in: input, lineStarts: lineStarts) else {
      return nil
    }
    return lower..<upper
  }

  private static func stringIndex(
    for location: SourceLocation,
    in input: String,
    lineStarts: [String.Index]
  ) -> String.Index? {
    guard location.line > 0, location.line <= lineStarts.count, location.column > 0 else { return nil }
    let lineStart = lineStarts[location.line - 1]
    guard let utf8Start = lineStart.samePosition(in: input.utf8) else { return nil }
    let utf8Index = input.utf8.index(
      utf8Start,
      offsetBy: location.column - 1,
      limitedBy: input.utf8.endIndex
    )
    return utf8Index.flatMap { String.Index($0, within: input) }
  }
}
