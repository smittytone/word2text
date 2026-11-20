/*
    word2text
    document_to_markdown.swift

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

    // MARK: - Entry Points for Conversion from Document to Text Formats

    /**
     Convert an internal Document instance, to plain text or Markdown.

     - Parameters:
        - document:   A Document instance instances.
        - outputType: Type of file to generate. Default: Plain Text.
        - addOuter:   Include header and/or footer text if preseent

     - Returns: The conversion as a string. Issues and empty string on error.
     */
    internal static func convert(_ document: Document, _ outputType: ContentType = .plainText, _ addOuter: Bool = false) -> String {

        guard outputType == .markdown || outputType == .plainText else { return "" }

        var docText = ""

        if outputType == .markdown {
            docText = documentToMarkdown(document)
        } else {
            docText = documentToText(document)
        }

        // Apply headers and/or footers if present and requested
        if addOuter {
            if let footer = document.footer, let header = document.header {
                let footerText = combineSpans(footer.spans, outputType)
                let headerText = combineSpans(header.spans, outputType)
                let lineCount = max(footerText.count, headerText.count)
                let line = String(repeating: "*", count: lineCount)
                docText = "\(docText)\n\(line)\n\(footerText)\n"
                docText = "\(headerText)\n\(line)\n\(docText)"
            } else if let footer = document.footer {
                let footerText = combineSpans(footer.spans, outputType)
                let line = String(repeating: "*", count: footerText.count)
                docText = "\(docText)\n\(line)\n\(footerText)\n"
            } else if let header = document.header {
                let headerText = combineSpans(header.spans, outputType)
                let line = String(repeating: "*", count: headerText.count)
                docText = "\(headerText)\n\(line)\n\(docText)"
            }
        }

        return plainCharacters(docText)
    }


    // MARK: - Conversion Helper Functions

    /**
     Convert a Document to Markdown.

     FROM 0.5.0

     - Parameters:
        - document: The Document to convert.

     - Returns: The converted Markdown as a string.
     */
    private static func documentToMarkdown(_ document: Document) -> String {

        var docText = ""

        // Paragraphs are separated by blank lines, except consecutive items of the same list,
        // which must stay together to form a single Markdown list
        var previousType: ParagraphType? = nil

        // Widths of the Markdown list markers (eg. `* `, `12. `) of the open list levels, used to
        // indent nested items so they sit under their parent's text, however wide its marker
        var listMarkerWidths: [Int] = []

        // Get the indent for a list item at `level` (1-based) with the given marker, and record
        // the marker's width for any items nested within this one
        func listIndent(_ level: Int, _ marker: String) -> String {
            let parentLevels = level - 1
            while listMarkerWidths.count < parentLevels {
                // Missing parent levels get the width of a bullet marker
                listMarkerWidths.append(2)
            }

            listMarkerWidths = Array(listMarkerWidths.prefix(parentLevels))
            let indent = listMarkerWidths.reduce(0, +)
            listMarkerWidths.append(marker.isEmpty ? 2 : marker.count)
            return String(repeating: " ", count: indent)
        }

        for paragraph in document.paragraphs {
            // Any paragraph that isn't a list item, including an empty one, ends the open lists
            if paragraph.type.listItem == nil {
                listMarkerWidths = []
            }

            // Combine the paragraph's text spans
            let spanText = combineSpans(paragraph.spans, .markdown)

            // Skip empty paragraphs, which the Psion uses for spacing: Markdown adds its own
            if spanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            // Style span text according to paragraph style
            // NOTE No `default:` so the compiler flags any new ParagraphType not handled here
            var line: String
            switch paragraph.type {
                case .body:
                    line = spanText
                case .heading(let level):
                    line = String(repeating: "#", count: level) + " \(spanText)"
                case .bulletItem(let level, _):
                    line = listIndent(level, "* ") + "* \(spanText)"
                case .numberItem(let level, let number):
                    // An item with no number in its text is output without a marker
                    let marker = number.map { "\($0). " } ?? ""
                    line = listIndent(level, marker) + marker + spanText
            }

            if let previousType {
                // Items of the same list, including nested items, stay together.
                // Only adjacent top-level items of different list types are separated
                var sameList = false
                if let previousList = previousType.listItem, let currentList = paragraph.type.listItem {
                    sameList = previousList.level > 1 || currentList.level > 1 || previousList.isBullet == currentList.isBullet
                }

                docText += sameList ? "\n" : "\n\n"
            }

            docText += line
            previousType = paragraph.type
        }

        if !docText.isEmpty {
            docText += "\n"
        }

        return docText
    }


    /**
     Convert a Document to Plain Text.

     FROM 0.5.0

     - Parameters:
        - document: The Document to convert.

     - Returns: The converted text as a string.
     */
    private static func documentToText(_ document: Document) -> String {

        var docText = ""

        for paragraph in document.paragraphs {
            // Plain text follows the Psion layout, including empty paragraphs,
            // but restores the list markers taken from the source text
            var marker = ""
            switch paragraph.type {
                case .bulletItem(_, let bullet):
                    if let bullet {
                        marker = "\(bullet)\t"
                    }
                case .numberItem(_, let number):
                    if let number {
                        marker = "\(number).\t"
                    }
                case .body, .heading:
                    break
            }

            // Indent nested list items by one tab per parent level. As markers end in a tab,
            // this places an item's marker under its parent's text, whatever the marker's width
            // NOTE The Psion stores no indentation in the text: it comes from each list style
            var indent = ""
            if let list = paragraph.type.listItem {
                indent = String(repeating: "\t", count: list.level - 1)
            }

            docText += "\(indent)\(marker)\(combineSpans(paragraph.spans, .plainText))\n"
        }

        return docText
    }

}
