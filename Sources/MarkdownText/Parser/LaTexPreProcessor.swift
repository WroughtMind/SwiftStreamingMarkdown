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

  static let inlineDollarMath = try! NSRegularExpression(
    pattern: #"(?<![\\$])\$(?![\s$])((?:\\.|[^$\n])+?)(?<!\\)\$(?!\$)"#
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
    guard Self.hasFormulaCandidate(in: input, rules: rules) else { return input }
    let codeRanges = MarkdownCodeRangeScanner.ranges(in: input)
    let stableInput = withholdIncompleteMath
      ? Self.stableStreamingPrefix(input, codeRanges: codeRanges)
      : input
    let blocks = blockReplacements(in: stableInput, rules: rules, codeRanges: codeRanges)
    return applying(
      blocks + inlineReplacements(
        in: stableInput,
        rules: rules,
        codeRanges: codeRanges,
        blockRanges: blocks.map(\.range)
      ),
      to: stableInput
    )
  }

  /// This replace block math with a special code block node. By treating it as a code block it will avoid over escaping characters within latex.
  func processBlockMath(input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> String {
    guard (rules.contains(.blockDollar) && input.contains("$$"))
            || (rules.contains(.blockSlashBracket) && input.contains("\\[")) else {
      return input
    }
    let codeRanges = MarkdownCodeRangeScanner.ranges(in: input)
    return applying(blockReplacements(in: input, rules: rules, codeRanges: codeRanges), to: input)
  }

  private struct Replacement {
    let range: NSRange
    let value: String
  }

  private func blockReplacements(
    in input: String,
    rules: Set<MarkdownParseOption.LatexMatching>,
    codeRanges: [NSRange]
  ) -> [Replacement] {
    var replacements: [Replacement] = []
    if rules.contains(.blockDollar) {
      for match in input.matches(of: Self.dollarBlockMath) {
        let range = NSRange(match.range, in: input)
        guard !Self.overlaps(range, codeRanges) else { continue }
        replacements.append(Replacement(
          range: range,
          value: Self.buildCodeBlock(
            indentation: match[Self.latexOpenIndentation],
            latex: match[Self.latexRef]
          )
        ))
      }
    }
    if rules.contains(.blockSlashBracket) {
      let protectedRanges = (codeRanges + replacements.map(\.range)).sorted {
        $0.location < $1.location
      }
      for match in input.matches(of: Self.slashBracketMath) {
        let range = NSRange(match.range, in: input)
        guard !Self.overlaps(range, protectedRanges) else { continue }
        replacements.append(Replacement(
          range: range,
          value: Self.buildCodeBlock(
            indentation: match[Self.latexOpenIndentation],
            latex: match[Self.latexRef]
          )
        ))
      }
    }
    return replacements
  }

  /// This wraps inline math as inline code to avoid over-unescaping issue
  func processInlineMath(input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> String {
    guard (rules.contains(.inlineDollar) && Self.hasInlineDollarCandidate(in: input))
            || (rules.contains(.inlineSlashBracket) && input.contains("\\(")) else {
      return input
    }
    let codeRanges = MarkdownCodeRangeScanner.ranges(in: input)
    return applying(inlineReplacements(
      in: input,
      rules: rules,
      codeRanges: codeRanges,
      blockRanges: nil
    ), to: input)
  }

  private func inlineReplacements(
    in input: String,
    rules: Set<MarkdownParseOption.LatexMatching>,
    codeRanges: [NSRange],
    blockRanges: [NSRange]?
  ) -> [Replacement] {
    let blockRanges = blockRanges
      ?? blockReplacements(in: input, rules: rules, codeRanges: codeRanges).map(\.range)
    var replacements: [Replacement] = []
    let blockProtectedRanges = (codeRanges + blockRanges).sorted { $0.location < $1.location }
    if rules.contains(.inlineSlashBracket) {
      for match in input.matches(of: Self.inlineParenthesisMath) {
        let range = NSRange(match.range, in: input)
        guard !Self.overlaps(range, blockProtectedRanges) else { continue }
        replacements.append(Replacement(
          range: range,
          value: "`\\(\(match[Self.latexRef])\\)`"
        ))
      }
    }
    if rules.contains(.inlineDollar) {
      let range = NSRange(input.startIndex..<input.endIndex, in: input)
      let protectedRanges = (blockProtectedRanges + replacements.map(\.range)).sorted {
        $0.location < $1.location
      }
      for match in Self.inlineDollarMath.matches(in: input, range: range) {
        guard !Self.overlaps(match.range, protectedRanges),
              let latexRange = Range(match.range(at: 1), in: input) else { continue }
        replacements.append(Replacement(
          range: match.range,
          value: "`\\(\(input[latexRange])\\)`"
        ))
      }
    }
    return replacements
  }

  private func applying(_ replacements: [Replacement], to input: String) -> String {
    let result = NSMutableString(string: input)
    for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
      result.replaceCharacters(in: replacement.range, with: replacement.value)
    }
    return result as String
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
  static func stableStreamingPrefix(
    _ input: String,
    codeRanges: [NSRange]? = nil
  ) -> String {
    guard !input.isEmpty else { return input }
    let codeRanges = codeRanges ?? MarkdownCodeRangeScanner.ranges(in: input)
    var cut = input.endIndex

    func considerUnclosed(open: String, close: String) {
      guard let openRange = lastUnprotectedRange(of: open, in: input, codeRanges: codeRanges) else { return }
      let closeRange = lastUnprotectedRange(of: close, in: input, codeRanges: codeRanges)
      if closeRange == nil || openRange.lowerBound > closeRange!.lowerBound {
        cut = min(cut, openRange.lowerBound)
      }
    }

    considerUnclosed(open: "\\(", close: "\\)")
    considerUnclosed(open: "\\[", close: "\\]")

    var blockDollarRanges: [Range<String.Index>] = []
    var searchStart = input.startIndex
    while let range = input.range(of: "$$", range: searchStart..<input.endIndex) {
      if !Self.overlaps(NSRange(range, in: input), codeRanges) {
        blockDollarRanges.append(range)
      }
      searchStart = range.upperBound
    }
    if blockDollarRanges.count.isMultiple(of: 2) == false,
       let opening = blockDollarRanges.last {
      cut = min(cut, opening.lowerBound)
    }

    return cut < input.endIndex ? String(input[..<cut]) : input
  }

  private static func lastUnprotectedRange(
    of needle: String,
    in input: String,
    codeRanges: [NSRange]
  ) -> Range<String.Index>? {
    var result: Range<String.Index>?
    var cursor = input.startIndex
    while let range = input.range(of: needle, range: cursor..<input.endIndex) {
      if !overlaps(NSRange(range, in: input), codeRanges) {
        result = range
      }
      cursor = range.upperBound
    }
    return result
  }

  private static func overlaps(_ range: NSRange, _ protectedRanges: [NSRange]) -> Bool {
    var lower = 0
    var upper = protectedRanges.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if NSMaxRange(protectedRanges[middle]) <= range.location {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    guard lower < protectedRanges.count else { return false }
    return protectedRanges[lower].location < NSMaxRange(range)
  }

  private static func hasFormulaCandidate(
    in input: String,
    rules: Set<MarkdownParseOption.LatexMatching>
  ) -> Bool {
    (rules.contains(.blockDollar) && input.contains("$$"))
      || (rules.contains(.inlineDollar) && hasInlineDollarCandidate(in: input))
      || (rules.contains(.inlineSlashBracket) && input.contains("\\("))
      || (rules.contains(.blockSlashBracket) && input.contains("\\["))
  }

  private static func hasInlineDollarCandidate(in input: String) -> Bool {
    inlineDollarMath.firstMatch(
      in: input,
      range: NSRange(input.startIndex..<input.endIndex, in: input)
    ) != nil
  }

}
