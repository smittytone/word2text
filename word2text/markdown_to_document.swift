/*
    word2text
    markdown_to_document.swift

    Copyright © 2026 Tony Smith. All rights reserved.

    MIT License
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
*/

import Foundation


extension PsionWord {

    // MARK: - Entry point for Document creation from text formats

    /**
     Convert Markdown, or Plain Text, into a Document.

     FROM 0.5.0

     - Parameters:
        - source:     The source text.
        - sourceType: The type of the source: Markdown or Plain Text.

     - Returns: A DocumentResult containing the generated document, or a ProcessError
     */
    internal static func makeDocument(from source: String, ofType sourceType: ContentType, _ settings: Settings) -> DocumentResult {

        // Confirm the source type is correct
        guard sourceType == .plainText || sourceType == .markdown else {
            return .failure(ProcessError(code: .badConversionSource))
        }

        var document = Document()
        if sourceType == .plainText {
            document.paragraphs = makePlainTextParagraphs(source)
            return .success(document)
        }

        for item in makeMarkdownParagraphs(source) {
            // Fenced code is passed through verbatim, as a single unformatted span
            let spans = item.parseInline ? parseMarkdownSpans(item.text) : [Span(text: item.text)]
            document.paragraphs.append(Paragraph(type: item.type, spans: spans))
        }

        return .success(document)
    }


    // MARK: - Conversion functions

    /**
     Split plain text into body text paragraphs, with no formatting applied.

     Each line is a paragraph, so `\n` is a paragraph break. Blank (or whitespace-only) lines
     don't create empty paragraphs, so `\n\n` (or more) is also a single paragraph break.
     Line text is otherwise unchanged.

     FROM 0.5.0

     - Parameters:
        - text: The source text.

     - Returns: The text's paragraphs.
     */
    private static func makePlainTextParagraphs(_ text: String) -> [Paragraph] {

        var paragraphs: [Paragraph] = []
        for line in text.normalised.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.allSatisfy({ $0.isWhitespace }) {
                continue
            }

            paragraphs.append(Paragraph(type: .body, spans: [Span(text: String(line))]))
        }

        return paragraphs
    }


    /**
     Split Markdown source into paragraphs, each tagged with a paragraph type.

     List items' bullets and numbers are recorded in their type rather than added to their text.

     FROM 0.5.0

     - Parameters:
        - markdown: The Markdown source text.

     - Returns: An array of paragraphs: type, raw text, and whether the text needs inline processing.
     */
    private static func makeMarkdownParagraphs(_ markdown: String) -> [(type: ParagraphType, text: String, parseInline: Bool)] {

        var paragraphs: [(type: ParagraphType, text: String, parseInline: Bool)] = []
        var current: (type: ParagraphType, text: String)? = nil
        var fence: String? = nil

        // Indentation of the markers of the currently open list items, outermost first
        var listIndents: [Int] = []

        // Width of a line's leading whitespace (tabs to the next multiple of four columns)
        func indentWidth(_ line: String) -> Int {
            var width = 0
            for character in line {
                if character == " " {
                    width += 1
                } else if character == "\t" {
                    width += 4 - (width % 4)
                } else {
                    break
                }
            }

            return width
        }

        // Nesting level (1-based) of a list item whose marker is at `indent`. An item is nested
        // inside the previous one if it is indented further than that item's marker
        func listLevel(_ indent: Int) -> Int {
            while let last = listIndents.last, indent <= last {
                listIndents.removeLast()
            }

            listIndents.append(indent)
            return min(listIndents.count, PsionWord3Constants.ListLevelMax)
        }

        func flush() {
            if let paragraph = current, !paragraph.text.isEmpty {
                paragraphs.append((paragraph.type, paragraph.text, true))
            }

            current = nil
        }

        // Convert Windows paragraph breaks to Unix style
       for rawLine in markdown.normalised.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Inside a fenced code block: pass lines through verbatim
            if let marker = fence {
                if trimmed.hasPrefix(marker) && trimmed.allSatisfy({ $0 == marker.first! }) {
                    fence = nil
                } else {
                    paragraphs.append((.body, line, false))
                }

                continue
            }

            // Start of a fenced code block
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                listIndents = []
                fence = String(trimmed.prefix(3))
                continue
            }

            // Blank line ends the current paragraph
            if trimmed.isEmpty {
                flush()
                continue
            }

            // Setext heading underline -- only applies to a plain paragraph
            if let paragraph = current, paragraph.type == .body {
                if trimmed.allSatisfy({ $0 == "=" }) {
                    current = (.heading(level: 1), paragraph.text)
                    flush()
                    listIndents = []
                    continue
                }

                if trimmed.allSatisfy({ $0 == "-" }) {
                    current = (.heading(level: 2), paragraph.text)
                    flush()
                    listIndents = []
                    continue
                }
            }

            // Thematic break (`---`, `***`, `___`) -- not supported, so drop it
            let compact = trimmed.filter { $0 != " " && $0 != "\t" }
            if compact.count >= 3, let first = compact.first, "-*_".contains(first), compact.allSatisfy({ $0 == first }) {
                flush()
                listIndents = []
                continue
            }

            // ATX heading
            if let heading = parseAtxHeading(trimmed) {
                flush()
                listIndents = []
                paragraphs.append((.heading(level: heading.level), heading.text, true))
                continue
            }

            // Bulleted list item. The bullet is chosen when the Word file is written
            if let first = trimmed.first, "-*+".contains(first) {
                let rest = trimmed.dropFirst()
                if rest.isEmpty || rest.first == " " || rest.first == "\t" {
                    flush()
                    let level = listLevel(indentWidth(line))
                    current = (.bulletItem(level: level, bullet: nil), rest.trimmingCharacters(in: .whitespaces))
                    continue
                }
            }

            // Numbered list item. The source number is retained
            let digits = trimmed.prefix(while: { $0.isASCII && $0.isNumber })
            if !digits.isEmpty && digits.count < 10 {
                let rest = trimmed.dropFirst(digits.count)
                if let delimiter = rest.first, delimiter == "." || delimiter == ")" {
                    let afterDelimiter = rest.dropFirst()
                    if afterDelimiter.isEmpty || afterDelimiter.first == " " || afterDelimiter.first == "\t" {
                        flush()
                        let level = listLevel(indentWidth(line))
                        current = (.numberItem(level: level, number: Int(digits)), afterDelimiter.trimmingCharacters(in: .whitespaces))
                        continue
                    }
                }
            }

            // Continuation of the current paragraph or list item, or the start of a new paragraph
            if let paragraph = current {
                current = (paragraph.type, paragraph.text.isEmpty ? trimmed : paragraph.text + " " + trimmed)
            } else {
                // An unindented paragraph ends any open list
                if indentWidth(line) == 0 {
                    listIndents = []
                }

                current = (.body, trimmed)
            }
        }

        flush()
        return paragraphs
    }


    /**
     Split paragraph text into Spans of plain, bold, italic and bold-italic text, removing
     the Markdown emphasis markers.

     The same as `parseMarkdownEmphasis()`, but returns Spans rather than Word emphasis codes.

     FROM 0.5.0

     - Parameters:
        - text: The paragraph text.

     - Returns: An array of Spans.
     */
    private static func parseMarkdownSpans(_ text: String) -> [Span] {

        let asciiPunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")
        func isPunctuation(_ c: Character) -> Bool {
            return c.isPunctuation || c.isSymbol
        }

        // Tokenise into literal text and delimiter runs
        let chars = Array(text)
        var tokens: [MarkdownToken] = []
        var literal = ""
        var i = 0

        func flushLiteral() {
            if !literal.isEmpty {
                tokens.append(MarkdownToken(text: literal))
                literal = ""
            }
        }

        while i < chars.count {
            let c = chars[i]

            // Backslash escape
            if c == "\\" && i + 1 < chars.count && asciiPunctuation.contains(chars[i + 1]) {
                literal.append(chars[i + 1])
                i += 2
                continue
            }

            // Code span: copy verbatim up to the matching backtick run
            if c == "`" {
                var runEnd = i
                while runEnd < chars.count && chars[runEnd] == "`" { runEnd += 1 }
                let runLength = runEnd - i
                var search = runEnd
                var closeStart: Int? = nil
                while search < chars.count {
                    if chars[search] == "`" {
                        var closeEnd = search
                        while closeEnd < chars.count && chars[closeEnd] == "`" { closeEnd += 1 }
                        if closeEnd - search == runLength {
                            closeStart = search
                            break
                        }

                        search = closeEnd
                    } else {
                        search += 1
                    }
                }

                let end = closeStart != nil ? closeStart! + runLength : runEnd
                literal += String(chars[i..<end])
                i = end
                continue
            }

            // Emphasis delimiter run
            if c == "*" || c == "_" {
                var runEnd = i
                while runEnd < chars.count && chars[runEnd] == c { runEnd += 1 }

                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = runEnd < chars.count ? chars[runEnd] : nil
                let beforeIsSpace = before == nil || before!.isWhitespace
                let afterIsSpace = after == nil || after!.isWhitespace
                let beforeIsPunctuation = before != nil && isPunctuation(before!)
                let afterIsPunctuation = after != nil && isPunctuation(after!)
                let leftFlanking = !afterIsSpace && (!afterIsPunctuation || beforeIsSpace || beforeIsPunctuation)
                let rightFlanking = !beforeIsSpace && (!beforeIsPunctuation || afterIsSpace || afterIsPunctuation)

                var token = MarkdownToken(delimiter: c, count: runEnd - i)
                if c == "*" {
                    token.canOpen = leftFlanking
                    token.canClose = rightFlanking
                } else {
                    // Underscores can't create intraword emphasis
                    token.canOpen = leftFlanking && (!rightFlanking || beforeIsPunctuation)
                    token.canClose = rightFlanking && (!leftFlanking || afterIsPunctuation)
                }

                flushLiteral()
                tokens.append(token)
                i = runEnd
                continue
            }

            literal.append(c)
            i += 1
        }

        flushLiteral()

        // Pair closers with the nearest preceding compatible opener
        for closer in tokens.indices where tokens[closer].delimiter != nil && tokens[closer].canClose {
            let delimiter = tokens[closer].delimiter
            while tokens[closer].count > 0 {
                guard let opener = tokens[..<closer].lastIndex(where: { $0.delimiter == delimiter && $0.canOpen && $0.count > 0 }) else {
                    break
                }

                // Strong (2) if both runs allow it, otherwise regular (1)
                let use = (tokens[opener].count >= 2 && tokens[closer].count >= 2) ? 2 : 1
                tokens[opener].count -= use
                tokens[closer].count -= use
                tokens[opener].opens.append(use)
                tokens[closer].closes.append(use)

                // Delimiters between the pair can no longer open emphasis
                for k in (opener + 1)..<closer {
                    tokens[k].canOpen = false
                }
            }
        }

        // Emit the Spans. Unmatched delimiter characters are kept as literal text
        var spans: [Span] = []
        var boldDepth = 0
        var italicDepth = 0

        func addSpan(_ text: String) {
            guard !text.isEmpty else { return }
            var type: SpanType = .normal
            if boldDepth > 0 {
                type.insert(.bold)
            }

            if italicDepth > 0 {
                type.insert(.italic)
            }

            if let last = spans.last, last.type == type {
                spans[spans.count - 1].text += text
            } else {
                spans.append(Span(type: type, text: text))
            }
        }

        for token in tokens {
            if let delimiter = token.delimiter {
                for use in token.closes {
                    if use == 2 { boldDepth -= 1 } else { italicDepth -= 1 }
                }

                addSpan(String(repeating: delimiter, count: token.count))

                for use in token.opens {
                    if use == 2 { boldDepth += 1 } else { italicDepth += 1 }
                }
            } else {
                addSpan(token.text)
            }
        }

        return spans
    }


    /**
     Parse a `#` heading, if present.

     FROM 0.4.0

     - Parameters:
        - line: A whitespace-trimmed line of Markdown.

     - Returns: The heading level (1-6) and text, or `nil` if the line is not a heading.
     */
    private static func parseAtxHeading(_ line: String) -> (level: Int, text: String)? {

        let hashes = line.prefix(while: { $0 == "#" })
        guard hashes.count >= 1 && hashes.count <= 6 else { return nil }

        let rest = line.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }

        // Remove any closing sequence of hashes, which must be preceded by a space
        var text = rest.trimmingCharacters(in: .whitespaces)
        let withoutClosing = String(text.reversed().drop(while: { $0 == "#" }).reversed())
        if withoutClosing.isEmpty || withoutClosing.hasSuffix(" ") || withoutClosing.hasSuffix("\t") {
            text = withoutClosing.trimmingCharacters(in: .whitespaces)
        }

        return (hashes.count, text)
    }
}
