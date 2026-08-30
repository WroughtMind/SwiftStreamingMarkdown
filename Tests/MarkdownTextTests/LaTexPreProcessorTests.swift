//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import CoreText
import Markdown
import SwiftMath
@testable import SwiftStreamingMarkdown
import XCTest

final class LaTexPreProcessorTests: XCTestCase {

  let preprocessor = LaTexPreProcessorImpl()

  func testNoLatex() throws {
    let testString = "Your string with (parentheticals), [square parentheticals], and money, like $5. That's a lot of $$!"
    let result = preprocessor.process(input: testString)
    XCTAssertEqual(result, testString)
  }

  func testBlockMath() {
    let input = """
    $$a = b + c \\\\ d = e + f$$
    """
    let expectation = """
    ```blockmath
    a = b + c \\\\ d = e + f
    ```
    """
    let output = preprocessor.process(input: input)
    XCTAssertEqual(output, expectation)
  }

  func testBlockMathWithIndentationAndSpaces() {
    // Note we are adding white space after the closing `$$` since the model can return them
    let whiteSpaces = String(repeating: " ", count: 3)
    let input = """
    $$   ax^2 + bx + c = 0       $$ \(whiteSpaces)
    """

    let expectation = """
    ```blockmath
       ax^2 + bx + c = 0
    ```
    """
    let output = preprocessor.process(input: input)
    XCTAssertEqual(output, expectation)
  }

  func testBlockMathWithBracket() throws {
    let testString = """
    Your string with
    \\[
    wrapped text\\]
    and more text
    """
    let expectation = """
    Your string with
    ```blockmath
    wrapped text
    ```
    and more text
    """
    let newLatex = preprocessor.process(input: testString)
    XCTAssertEqual(newLatex, expectation)
  }

  func testBlockMathWithBracketWithSpaces() throws {
    let whiteSpaces = String(repeating: " ", count: 3)
    let testString = """
    Your string with
    \\[
    wrapped text\\]\(whiteSpaces)
    and more text
    """
    let expectation = """
    Your string with
    ```blockmath
    wrapped text
    ```
    and more text
    """
    let newLatex = preprocessor.process(input: testString)
    XCTAssertEqual(newLatex, expectation)
  }

  func testInlineMath() throws {
    let input = """
    This is \\(inline latex\\). Some more \\( inline (parenthesis) latex \\).
    """
    let expectation = """
    This is `\\(inline latex\\)`. Some more `\\( inline (parenthesis) latex \\)`.
    """
    let newLatex = preprocessor.process(input: input)
    XCTAssertEqual(newLatex, expectation)
  }

  func testTableWithDollarSign() throws {
    let input = """
    Here's a list of restaurant near you:


    | Restaurant    | Price |
    | -------- | ------- |
    | January  | $$$$   |
    | February | $$$$     |
    | March    | $$$$    |
    """
    let newLatex = preprocessor.process(input: input)
    XCTAssertEqual(newLatex, input)
  }

  func testConsecutiveFormula() throws {
    let input = """
    Here are a couple of most famous math formulas
    $$a^2 + b^2 = c^$$

    $$e^{i\\pi} + 1 = 0$$

    $$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$
    $$A = \\pi r^2$$

    $$F = ma$$

    $$\\text{Mass-Energy Equivalence: } E = mc^2$$

    $$(a + b)^n = \\sum_{k=0}^{n} \\binom{n}{k} a^{n-k} b^k$$

    $$f(x) = \\sum_{n=0}^{\\infty} \\frac{f^{(n)}(a)}{n!}(x - a)^n$$

    $$f'(x) = \\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h}$$

    $$\\int_a^b f(x)\\,dx = \\lim_{n \\to \\infty} \\sum_{i=1}^{n} f(x_i^*) \\Delta x$$

    $$C = S_0 N(d_1) - K e^{-rT} N(d_2)$$
    $$d_1 = \\frac{\\ln\\left(\\frac{S_0}{K}\\right) + \\left(r + \\frac{\\sigma^2}{2}\\right)T}{\\sigma \\sqrt{T}}, \\quad$$
    $$d_2 = d_1 - \\sigma \\sqrt{T}$$
    """
    let newLatex = preprocessor.process(input: input)
    let expectation = """
    Here are a couple of most famous math formulas
    ```blockmath
    a^2 + b^2 = c^
    ```

    ```blockmath
    e^{i\\pi} + 1 = 0
    ```

    ```blockmath
    x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}
    ```
    ```blockmath
    A = \\pi r^2
    ```

    ```blockmath
    F = ma
    ```

    ```blockmath
    \\text{Mass-Energy Equivalence: } E = mc^2
    ```

    ```blockmath
    (a + b)^n = \\sum_{k=0}^{n} \\binom{n}{k} a^{n-k} b^k
    ```

    ```blockmath
    f(x) = \\sum_{n=0}^{\\infty} \\frac{f^{(n)}(a)}{n!}(x - a)^n
    ```

    ```blockmath
    f'(x) = \\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h}
    ```

    ```blockmath
    \\int_a^b f(x)\\,dx = \\lim_{n \\to \\infty} \\sum_{i=1}^{n} f(x_i^*) \\Delta x
    ```

    ```blockmath
    C = S_0 N(d_1) - K e^{-rT} N(d_2)
    ```
    ```blockmath
    d_1 = \\frac{\\ln\\left(\\frac{S_0}{K}\\right) + \\left(r + \\frac{\\sigma^2}{2}\\right)T}{\\sigma \\sqrt{T}}, \\quad
    ```
    ```blockmath
    d_2 = d_1 - \\sigma \\sqrt{T}
    ```
    """
    // print(newLatex)
    XCTAssertEqual(newLatex, expectation)
  }

  func testInline() throws {
    let text = """
    This double integral:
    - Sweeps across a rectangular region from \\( x = 0 \\) to \\( \\pi \\), and \\( y = 1 \\) to \\( e \\)
    - Combines a sine of a product \\( xy \\), a logarithmic denominator, and a cosine term multiplied by a polynomial
    - Is a great example of how calculus can get delightfully \\( \\text{tangled} \\)
    """
    let processed = preprocessor.processInlineMath(input: text)
    let expected = """
    This double integral:
    - Sweeps across a rectangular region from `\\( x = 0 \\)` to `\\( \\pi \\)`, and `\\( y = 1 \\)` to `\\( e \\)`
    - Combines a sine of a product `\\( xy \\)`, a logarithmic denominator, and a cosine term multiplied by a polynomial
    - Is a great example of how calculus can get delightfully `\\( \\text{tangled} \\)`
    """
    XCTAssertEqual(processed, expected)
  }

  func testBlockMathWithWhitespace() throws {
    let text = """
    - Net force on the ring:
      \\[
        F = f - m\\,g = (k\\,m\\,g) - m\\,g = (k-1)\\,m\\,g.
      \\]
    - Therefore the ring’s acceleration is
      \\[
        a_{\\rm ring} = \\frac{F}{m} = (k-1)\\,g
        \\quad\\text{(upward).}
      \\]
    """
    let processed = preprocessor.processBlockMath(input: text)
    let expected = """
    - Net force on the ring:
      ```blockmath
        F = f - m\\,g = (k\\,m\\,g) - m\\,g = (k-1)\\,m\\,g.
      ```
    - Therefore the ring’s acceleration is
      ```blockmath
        a_{\\rm ring} = \\frac{F}{m} = (k-1)\\,g
        \\quad\\text{(upward).}
      ```
    """
    XCTAssertEqual(expected, processed)
  }

  func testBlockMathWithSpecificSymbols() throws {
    let text = """
    \\[
    \\varphi(x) = f(x) - \\big(f(a) + f'(a)(x-a)\\big).
    \\]

    - Vector \\(\\overrightarrow{FA} = (a+c,0)\\)

    \\[
    2+2(2q-1) = 2q^2 \\implies 2+4q-2 = 2q^2 \\implies 4q = 2q^2 \\implies q^2 - 2q = 0.
    \\]

    \\[
    Fe^{3+}_{(aq)} + xCl^-_{(aq)} \\rightleftharpoons [FeCl_x]^{3-x}_{(aq)} \\quad (x = 1,2,3,4)
    \\]

    \\(a_1, \\dots, a_n\\)
    """

    let processed = preprocessor.process(input: text)
    let expected = """
    ```blockmath
    \\varphi(x) = f(x) - \\big(f(a) + f'(a)(x-a)\\big).
    ```

    - Vector `\\(\\overrightarrow{FA} = (a+c,0)\\)`

    ```blockmath
    2+2(2q-1) = 2q^2 \\implies 2+4q-2 = 2q^2 \\implies 4q = 2q^2 \\implies q^2 - 2q = 0.
    ```

    ```blockmath
    Fe^{3+}_{(aq)} + xCl^-_{(aq)} \\rightleftharpoons [FeCl_x]^{3-x}_{(aq)} \\quad (x = 1,2,3,4)
    ```

    `\\(a_1, \\dots, a_n\\)`
    """
    XCTAssertEqual(expected, processed)
  }

  // MARK: - Matching-rule gating

  func testBlockDollarDisabledLeavesDollarsAsPlainText() {
    let input = """
    The price is $$5 and the total is $$10.
    $$a = b + c$$
    """
    let processed = preprocessor.process(
      input: input,
      matchingRules: [.inlineSlashBracket, .blockSlashBracket]
    )
    XCTAssertEqual(processed, input)
  }

  func testBlockDollarDisabledStillProcessesOtherRules() {
    let input = """
    $$a = b + c$$
    \\[
    x = y + z
    \\]
    Inline \\(p + q\\) here.
    """
    let expected = """
    $$a = b + c$$
    ```blockmath
    x = y + z
    ```
    Inline `\\(p + q\\)` here.
    """
    let processed = preprocessor.process(
      input: input,
      matchingRules: [.inlineSlashBracket, .blockSlashBracket]
    )
    XCTAssertEqual(processed, expected)
  }

  func testWeiBeiFormulaContract() throws {
    for plain in ["", "完成段落\n"] {
      XCTAssertEqual(
        preprocessor.process(
          input: plain,
          matchingRules: MarkdownParseOption.LatexMatching.allCases,
          withholdIncompleteMath: true
        ),
        plain
      )
    }
    let formulas = [
      #"\frac{a}{b} + \tfrac{c}{d} + \dfrac{e}{f}"#,
      #"\hat{x} + \widehat{wage} + \beta"#,
      #"\sqrt{x} + \sum_{i=1}^{n} i + \partial_x f + \left\{x^2\right\}"#,
      #"\text{中文数学}，x_1^2"#,
    ]
    let markdown = [
      "\\(\(formulas[0])\\)",
      "$\(formulas[1])$",
      "$$\(formulas[2])$$",
      "\\[\n\(formulas[3])\n\\]",
    ].joined(separator: "\n")
    let processed = preprocessor.process(input: markdown)

    for command in [
      #"\frac"#, #"\tfrac"#, #"\dfrac"#, #"\hat"#, #"\widehat"#,
      #"\beta"#, #"\sqrt"#, #"\sum"#, #"\partial"#, #"\text{中文数学}"#,
    ] {
      XCTAssertTrue(processed.contains(command), "preprocessor changed \(command)")
    }
    XCTAssertTrue(processed.contains(#"\tfrac{c}{d}"#))
    XCTAssertTrue(processed.contains(#"\dfrac{e}{f}"#))

    for formula in formulas {
      var error: NSError?
      let list = MTMathListBuilder.build(fromString: formula, error: &error)
      XCTAssertNil(error, formula)
      XCTAssertFalse(list?.atoms.isEmpty ?? true, formula)
    }

    func formulaHeight(_ latex: String, mode: MTMathUILabelMode) -> CGFloat {
      let label = MTMathUILabel()
      label.font = MathFont.latinModernFont.mtfont(size: 16)
      label.labelMode = mode
      label.latex = latex
      return label.intrinsicContentSize.height
    }
    let displayTfrac = formulaHeight(#"\tfrac{a}{b}"#, mode: .display)
    let displayFrac = formulaHeight(#"\frac{a}{b}"#, mode: .display)
    let displayDfrac = formulaHeight(#"\dfrac{a}{b}"#, mode: .display)
    XCTAssertLessThan(displayTfrac, displayFrac)
    XCTAssertEqual(displayFrac, displayDfrac, accuracy: 0.001)

    let textTfrac = formulaHeight(#"\tfrac{a}{b}"#, mode: .text)
    let textFrac = formulaHeight(#"\frac{a}{b}"#, mode: .text)
    let textDfrac = formulaHeight(#"\dfrac{a}{b}"#, mode: .text)
    XCTAssertGreaterThan(textDfrac, textFrac)
    XCTAssertEqual(textFrac, textTfrac, accuracy: 0.001)
    XCTAssertGreaterThan(formulaHeight("x + y", mode: .display), 0)

    let fallback = try XCTUnwrap(CTFontCreateUIFontForLanguage(.system, 16, nil))
    let mathFont = MathFont.latinModernFont.mtfont(size: 16)
    mathFont.fallbackFont = fallback
    for size: CGFloat in [16, 11] {
      let resizedFont = mathFont.copy(withSize: size)
      let resizedFallback = try XCTUnwrap(resizedFont.fallbackFont)
      XCTAssertEqual(CTFontGetSize(resizedFallback), size)

      let textRun = resizedFont.attributedStringWithFallback(for: "中文")
      for location in 0..<textRun.length {
        let fontAttribute = try XCTUnwrap(
          textRun.attribute(
            kCTFontAttributeName as NSAttributedString.Key,
            at: location,
            effectiveRange: nil
          )
        )
        let resolvedFont = fontAttribute as! CTFont
        var character = Array((textRun.string as NSString).substring(with: NSRange(location: location, length: 1)).utf16)
        var glyph = [CGGlyph](repeating: 0, count: character.count)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(
          resolvedFont,
          &character,
          &glyph,
          character.count
        ))
        XCTAssertTrue(glyph.allSatisfy { $0 != 0 })
      }
    }

    let incomplete = "完成段落\n\\(\\widehat{wage}"
    let stable = preprocessor.process(
      input: incomplete,
      matchingRules: MarkdownParseOption.LatexMatching.allCases,
      withholdIncompleteMath: true
    )
    XCTAssertEqual(stable, "完成段落\n")

    let incompleteDollar = "完成段落\n$\\widehat{wage}"
    XCTAssertEqual(
      preprocessor.process(
        input: incompleteDollar,
        matchingRules: MarkdownParseOption.LatexMatching.allCases,
        withholdIncompleteMath: true
      ),
      incompleteDollar
    )

    let incompleteSlashBracket = "完成段落\n\\[\\sum_{i=1}^{n}"
    XCTAssertEqual(
      preprocessor.process(
        input: incompleteSlashBracket,
        matchingRules: MarkdownParseOption.LatexMatching.allCases,
        withholdIncompleteMath: true
      ),
      "完成段落\n"
    )

    let ordinaryMarkdownBrackets = """
    [标题]
    [链接](https://example.com)
    [[来源标签]]
    """
    XCTAssertEqual(
      preprocessor.process(
        input: ordinaryMarkdownBrackets,
        matchingRules: MarkdownParseOption.LatexMatching.allCases,
        withholdIncompleteMath: true
      ),
      ordinaryMarkdownBrackets
    )

    let ordinaryDollarText = """
    价格是 $100
    行内代码是 `$x$`
    ```sh
    echo "$PATH $HOME"
    ```
    """
    XCTAssertEqual(
      preprocessor.process(
        input: ordinaryDollarText,
        matchingRules: MarkdownParseOption.LatexMatching.allCases,
        withholdIncompleteMath: true
      ),
      ordinaryDollarText
    )

    let commandsThatMustNotBeRewritten =
      #"\(\boxed{x} + \overrightarrow{AB} + \implies + \rightleftharpoons\)"#
    let preservedCommands = preprocessor.process(input: commandsThatMustNotBeRewritten)
    for command in [#"\boxed"#, #"\overrightarrow"#, #"\implies"#, #"\rightleftharpoons"#] {
      XCTAssertTrue(preservedCommands.contains(command), "preprocessor changed \(command)")
    }
    var preservedError: NSError?
    let preservedList = MTMathListBuilder.build(
      fromString: #"\boxed{x} + \overrightarrow{AB} + \implies + \rightleftharpoons"#,
      error: &preservedError
    )
    XCTAssertNil(preservedError)
    XCTAssertFalse(preservedList?.atoms.isEmpty ?? true)

    func renderedText(in display: MTDisplay) -> String {
      if let line = display as? MTCTLineDisplay {
        return line.atoms.map(\.nucleus).joined()
      }
      if let list = display as? MTMathListDisplay {
        return list.subDisplays.map { renderedText(in: $0) }.joined()
      }
      return ""
    }

    func reflectedAccent(in display: MTDisplay) -> MTDisplay? {
      if let reflectedValue = Mirror(reflecting: display).children.first(where: { $0.label == "accent" })?.value {
        let valueMirror = Mirror(reflecting: reflectedValue)
        if valueMirror.displayStyle == .optional {
          if let unwrapped = valueMirror.children.first?.value as? MTDisplay {
            return unwrapped
          }
        } else if let accent = reflectedValue as? MTDisplay {
          return accent
        }
      }
      if let list = display as? MTMathListDisplay {
        for child in list.subDisplays {
          if let accent = reflectedAccent(in: child) {
            return accent
          }
        }
      }
      return nil
    }

    for variable in ["x", "y"] {
      let hatLabel = MTMathUILabel(frame: .zero)
      hatLabel.font = mathFont
      hatLabel.labelMode = .display
      hatLabel.latex = "\\hat{\(variable)}"
      XCTAssertNil(hatLabel.error)
      let hatSize = hatLabel.sizeThatFits(.zero)
      XCTAssertGreaterThan(hatSize.width, 0)
      XCTAssertGreaterThan(hatSize.height, 0)
      hatLabel.frame = CGRect(origin: .zero, size: hatSize)
      #if os(macOS)
      hatLabel.layout()
      #else
      hatLabel.layoutIfNeeded()
      #endif
      let hatDisplay = try XCTUnwrap(hatLabel.displayList)
      let accent = try XCTUnwrap(reflectedAccent(in: hatDisplay), "\\hat{\(variable)}")
      XCTAssertGreaterThan(accent.width, 0)
      XCTAssertGreaterThan(accent.ascent + accent.descent, 0)
    }

    let displayFormula = #"\boxed{\widehat{wage}}，\overrightarrow{AB} + \sum_{i=1}^{n} i + x_{\text{中文}}"#
    for size: CGFloat in [16, 13] {
      let label = MTMathUILabel(frame: .zero)
      label.font = mathFont.copy(withSize: size)
      label.labelMode = .display
      label.latex = displayFormula
      XCTAssertNil(label.error)
      let fitted = label.sizeThatFits(.zero)
      XCTAssertGreaterThan(fitted.width, 0)
      XCTAssertGreaterThan(fitted.height, 0)
      label.frame = CGRect(origin: .zero, size: fitted)
      #if os(macOS)
      label.layout()
      #else
      label.layoutIfNeeded()
      #endif
      let display = try XCTUnwrap(label.displayList)
      XCTAssertGreaterThan(display.width, 0)
      XCTAssertGreaterThan(display.ascent + display.descent, 0)
      let nativeTextRuns = renderedText(in: display)
      XCTAssertTrue(nativeTextRuns.contains("，"))
      XCTAssertTrue(nativeTextRuns.contains("中文"))
    }
  }
}
