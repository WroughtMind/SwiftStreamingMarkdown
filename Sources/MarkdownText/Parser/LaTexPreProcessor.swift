//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import RegexBuilder

/// Pre-process the inline and block latex in markdown.
/// This is a less heavy-weight approach than forking commonmark-gfm and swift-markdown to support parsing latex nodes.
protocol LaTexPreProcessor {
  func process(
    input: String,
    matchingRules: [MarkdownParseOption.LatexMatching],
    withholdIncompleteMath: Bool
  ) -> String
}

extension LaTexPreProcessor {
  func process(input: String) -> String {
    process(
      input: input,
      matchingRules: MarkdownParseOption.LatexMatching.allCases,
      withholdIncompleteMath: false
    )
  }

  func process(input: String, matchingRules: [MarkdownParseOption.LatexMatching]) -> String {
    process(input: input, matchingRules: matchingRules, withholdIncompleteMath: false)
  }
}

final class LaTexPreProcessorImpl: LaTexPreProcessor {

  static let latexRef = Reference(Substring.self)
  static let latexOpenIndentation = Reference(Substring.self)

  static let dollarBlockMath = Regex {
    Anchor.startOfLine
    Capture(as: latexOpenIndentation) {
      ZeroOrMore(.horizontalWhitespace)
    }
    "$$"
    Capture(as: latexRef) {
      OneOrMore(.any, .reluctant)
    }
    ZeroOrMore(.horizontalWhitespace)
    "$$"
    ZeroOrMore(.horizontalWhitespace)
    Anchor.endOfLine
  }

  static let slashBracketMath = Regex {
    Anchor.startOfLine
    Capture(as: latexOpenIndentation) {
      ZeroOrMore(.horizontalWhitespace)
    }
    "\\["
    Capture(as: latexRef) {
      OneOrMore(.any, .reluctant)
    }
    ZeroOrMore(.horizontalWhitespace)
    "\\]"
    ZeroOrMore(.horizontalWhitespace)
    Anchor.endOfLine
  }

  static let inlineParenthesisMath = Regex {
    "\\("
    Capture(as: latexRef) {
      OneOrMore(.any, .reluctant)
    }
    "\\)"
  }

  static let inlineDollarMath = try? NSRegularExpression(
    pattern: #"(?<![\\$])\$(?![\s$])((?:\\.|[^$\n])+?)(?<!\\)\$(?![$\d])"#
  )

  static let customCodeType = "blockmath"
  static let inlineCodePrefix = "\\("
  static let inlineCodeSuffix = "\\)"
  static let newline = "\n"

  init() {}

  func process(
    input: String,
    matchingRules: [MarkdownParseOption.LatexMatching],
    withholdIncompleteMath: Bool
  ) -> String {
    let rules = Set(matchingRules)
    let stableInput = withholdIncompleteMath ? Self.stableStreamingPrefix(input) : input
    let result = processBlockMath(input: stableInput, rules: rules)
    return processInlineMath(input: result, rules: rules)
  }

  /// This replace block math with a special code block node. By treating it as a code block it will avoid over escaping characters within latex.
  func processBlockMath(input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> String {
    var result = input
    if rules.contains(.blockDollar) {
      result.replace(Self.dollarBlockMath, with: { match in
        let indentation = match[Self.latexOpenIndentation]
        let latex = match[Self.latexRef]
        return Self.buildCodeBlock(indentation: indentation, latex: latex)
      })
    }

    if rules.contains(.blockSlashBracket) {
      result.replace(Self.slashBracketMath, with: { match in
        let indentation = match[Self.latexOpenIndentation]
        let latex = match[Self.latexRef]
        return Self.buildCodeBlock(indentation: indentation, latex: latex)
      })
    }
    return result
  }

  /// This wraps inline math as inline code to avoid over-unescaping issue
  func processInlineMath(input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> String {
    var result = input
    if rules.contains(.inlineSlashBracket) {
      result = result.replacing(Self.inlineParenthesisMath, with: { match in
        "`\\(\(match[Self.latexRef])\\)`"
      })
    }
    if rules.contains(.inlineDollar), let inlineDollarMath = Self.inlineDollarMath {
      let range = NSRange(result.startIndex..<result.endIndex, in: result)
      for match in inlineDollarMath.matches(in: result, range: range).reversed() {
        guard let fullRange = Range(match.range, in: result),
              let latexRange = Range(match.range(at: 1), in: result) else { continue }
        result.replaceSubrange(fullRange, with: "`\\(\(result[latexRange])\\)`")
      }
    }
    return result
  }

  // MARK: - Convenience overloads (default to every supported rule)

  func processBlockMath(input: String) -> String {
    return processBlockMath(input: input, rules: Set(MarkdownParseOption.LatexMatching.allCases))
  }

  func processInlineMath(input: String) -> String {
    return processInlineMath(input: input, rules: Set(MarkdownParseOption.LatexMatching.allCases))
  }

  private static func buildCodeBlock(indentation: Substring, latex: Substring) -> String {
    let processedLatex = latex.trimmingCharacters(in: .newlines)
    let nextLineIntendation = latex.hasPrefix(Self.newline) ? "" : indentation
    return "\(indentation)```\(Self.customCodeType)\(Self.newline)\(nextLineIntendation)\(processedLatex)\(Self.newline)\(indentation)```"
  }

  /// Drops only an unfinished trailing formula while a streamed snapshot is
  /// still growing. Complete formulas and their original commands are untouched.
  static func stableStreamingPrefix(_ input: String) -> String {
    var cut = input.endIndex

    func considerUnclosed(open: String, close: String) {
      guard let openRange = input.range(of: open, options: .backwards) else { return }
      let closeRange = input.range(of: close, options: .backwards)
      if closeRange == nil || openRange.lowerBound > closeRange!.lowerBound {
        cut = min(cut, openRange.lowerBound)
      }
    }

    considerUnclosed(open: "\\(", close: "\\)")
    considerUnclosed(open: "\\[", close: "\\]")

    var blockDollarRanges: [Range<String.Index>] = []
    var searchStart = input.startIndex
    while let range = input.range(of: "$$", range: searchStart..<input.endIndex) {
      blockDollarRanges.append(range)
      searchStart = range.upperBound
    }
    if blockDollarRanges.count.isMultiple(of: 2) == false,
       let opening = blockDollarRanges.last {
      cut = min(cut, opening.lowerBound)
    }

    let lineStart = input.lastIndex(of: "\n").map(input.index(after:)) ?? input.startIndex
    var inlineDollarOpen: String.Index?
    var index = lineStart
    while index < input.endIndex {
      let next = input.index(after: index)
      guard input[index] == "$" else {
        index = next
        continue
      }
      let previous = index > input.startIndex ? input[input.index(before: index)] : nil
      let following = next < input.endIndex ? input[next] : nil
      if previous == "\\" || previous == "$" || following == "$" {
        index = next
        continue
      }
      if inlineDollarOpen == nil {
        if let following, !following.isWhitespace {
          inlineDollarOpen = index
        }
      } else if following?.isNumber != true {
        inlineDollarOpen = nil
      }
      index = next
    }
    if let inlineDollarOpen {
      cut = min(cut, inlineDollarOpen)
    }

    return cut < input.endIndex ? String(input[..<cut]) : input
  }
}
