/*
    word2text
    word_to_document.swift

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

    // MARK: - Entry point for Document creation from Word formats

    /**
     Convert Word Blocks into a sequence of Paragraphs.
     Paragraphs map to Word paragraphs, i.e., text of a given style, ending in `0`.
     Paragraphs contain Spans, i.e., text of a given emphasis within a paragraph.
     Word Blocks are text units of a given style and emphasis, so 1 Span = 1 Block, 1 Paragraph = x Blocks

     FROM 0.5.0

     - Parameters:
        - rawText: The body text as raw CP 850 bytes, unmodified from the file.
        - blocks:  The block formatting data extracted from the document.

     - Returns: The document's paragraphs, with their text decoded to Unicode.
     */
    internal static func makeParagraphs(_ rawText: [UInt8], _ blocks: [PsionWordFormatBlock]) -> [Paragraph] {

        var paragraphs: [Paragraph] = []
        var currentParagraph = Paragraph()
        for block in blocks {
            // Check block size (negative size/extends beyond the raw text bytes)
            guard block.startIndex <= block.endIndex && block.endIndex < rawText.count else { continue }

            // Get a span's text, minus the `0` paragraph separator if the block ends a paragraph
            let isParagraphEnd = rawText[block.endIndex] == PsionWord3Constants.ParagraphMarker
            let spanBytes = isParagraphEnd ? rawText[block.startIndex..<block.endIndex] : rawText[block.startIndex...block.endIndex]
            var span = Span()
            span.text = decodeWord3Text(spanBytes)

            if let emphasis = block.emphasis {
                if emphasis.bold {
                    span.type.insert(.bold)
                }

                if emphasis.italic {
                    span.type.insert(.italic)
                }

                if emphasis.subScript {
                    span.type.insert(.subScript)
                }

                if emphasis.superScript {
                    span.type.insert(.superScript)
                }

                if emphasis.underlined {
                    span.type.insert(.underline)
                }
            }

            currentParagraph.spans.append(span)

            if currentParagraph.spans.count == 1 {
                // A paragraph's style is set by its first block
                currentParagraph.type = paragraphType(block.styleCode)
                currentParagraph.word3Style = block.style
            }

            if isParagraphEnd {
                // Store the current para and prep the next one
                paragraphs.append(removeListMarker(from: currentParagraph))
                currentParagraph = Paragraph()
            }
        }

        // Catch a final paragraph that lacks a Psion Word end-of-para marker
        if !currentParagraph.spans.isEmpty {
            paragraphs.append(removeListMarker(from: currentParagraph))
        }

        return paragraphs
    }


    /**
     Remove the bullet or number that Word 3 list items carry as part of their text,
     eg. `·<TAB>` or `12.<TAB>`, and record it in the paragraph's type instead.

     The marker may be split across spans, eg. if only the number is bold, so it is
     located in the paragraph's combined text then removed span by span. Paragraphs
     that aren't list items, or which have no marker, are returned unchanged.

     FROM 0.5.0

     - Parameters:
        - paragraph: The paragraph to process.

     - Returns: The paragraph without its list marker.
     */
    private static func removeListMarker(from paragraph: Paragraph) -> Paragraph {

        let text = Array(paragraph.spans.map { $0.text }.joined())
        var markerLength = 0
        var result = paragraph

        switch paragraph.type {
            case .bulletItem(let level, _):
                // A bullet is any single non-alphanumeric, non-space character followed by a tab
                guard text.count >= 2, text[1] == "\t" else {
                    return paragraph
                }
                let bullet = text[0]
                guard !bullet.isLetter && !bullet.isNumber && !bullet.isWhitespace else {
                    return paragraph
                }
                result.type = .bulletItem(level: level, bullet: bullet)
                markerLength = 2
            case .numberItem(let level, _):
                // A number is one or more digits, then `.` or `)`, then a tab or space
                let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
                guard !digits.isEmpty, text.count >= digits.count + 2, text[digits.count] == "." || text[digits.count] == ")",
                        text[digits.count + 1] == "\t" || text[digits.count + 1] == " ", let number = Int(String(digits)) else {
                    return paragraph
                }
                result.type = .numberItem(level: level, number: number)
                markerLength = digits.count + 2
            case .body, .heading:
                return paragraph
        }

        // Remove the marker's characters from the leading span(s), dropping any left empty
        var spans: [Span] = []
        for var span in result.spans {
            if markerLength > 0 {
                let removed = min(markerLength, span.text.count)
                span.text = String(span.text.dropFirst(removed))
                markerLength -= removed
                if span.text.isEmpty {
                    continue
                }
            }

            spans.append(span)
        }

        result.spans = spans
        return result
    }


    /**
     Map a Word 3 style code to a paragraph type.

     FROM 0.5.0

     - Parameters:
        - styleCode: A two-character Word 3 style code, eg. `HA` or `B2`.

     - Returns: The matching ParagraphType. Unrecognised codes, including user-defined
                styles, are treated as body text.
     */
    private static func paragraphType(_ styleCode: String) -> ParagraphType {

        // Bulleted and numbered lists, levels 1-6
        if let list = PsionWord3Constants.listInfo(styleCode) {
            return list.isBullet ? .bulletItem(level: list.level, bullet: nil) : .numberItem(level: list.level, number: nil)
        }

        // Headings A-F map to levels 1-6
        if styleCode.count == 2 && styleCode.hasPrefix("H"), let last = styleCode.unicodeScalars.last, ("A"..."F").contains(last) {
            return .heading(level: Int(last.value) - Int(("A" as Unicode.Scalar).value) + 1)
        }

        return .body
    }


    // MARK: - Word 3 Data Decoders

    /**
     Parse a Psion Word Style or Emphasis record.

     - Parameters:
        - data:     A slice of the word file bytes.
        - isStyle: `true` if the record holds a Style; `false` if it is an Emphasis.
        - settings: File conversion parameters.

     - Returns: A PsionWord3Style containing the record's information.
     */
    internal static func decodeWord3Style(_ data: ArraySlice<UInt8>, _ isStyle: Bool, _ settings: Settings) -> PsionWord3Style {

        var style = PsionWord3Style()

        // Code and name
        let index = data.startIndex
        style.code = String(bytes: data[index..<index + 2], encoding: .windowsCP1252) ?? ""
        style.name = String(decoding: data[index + 2..<index + 18], as: UTF8.self)
        // Find the first nul
        let range: Range<String.Index> = style.name.range(of: "\0")!
        style.name = String(style.name[..<range.lowerBound])

        if style.name.isEmpty {
            style.name = "Unknown"
        }

        // NOTE Many of these properties are irrelevant to text or even Markdown output, so
        //      I may remove unneeded properties at a later time. Do not rely on their presence!

        // Type
        style.isStyle = ((data[index + 18] & 0x01) == 0)
        style.isUndeletable = ((data[index + 18] & 0x02) > 0)
        style.isDefault = ((data[index + 18] & 0x04) > 0)

        // Font type and size
        style.fontCode = getWordValue(data[index + 20..<index + 22])
        style.fontSize = getWordValue(data[index + 24..<index + 26])

        // Textual properties
        style.underlined = ((data[index + 22] & 0x01) > 0)
        style.bold = ((data[index + 22] & 0x02) > 0)
        style.italic = ((data[index + 22] & 0x04) > 0)
        style.superScript = ((data[index + 22] & 0x08) > 0)
        style.subScript = ((data[index + 22] & 0x10) > 0)

        // Property inheritance
        style.inheritUnderline = ((data[index + 26] & 0x01) > 0)
        style.inheritBold = ((data[index + 26] & 0x02) > 0)
        style.inheritItalic = ((data[index + 26] & 0x04) > 0)
        style.inheritSuperScript = ((data[index + 26] & 0x08) > 0)
        style.inheritSubScript = ((data[index + 26] & 0x10) > 0)

        // The following properties apply to Styles only so exit if it's an Emphasis
        if !style.isStyle {
            if settings.showInfo {
                log("  Emphasis code: \(style.code) (\(style.name))")
            }

            return style
        }

        // Indents
        style.leftIndent = getWordValue(data[index + 28..<index + 30])
        style.rightIndent = getWordValue(data[index + 30..<index + 32])
        style.firstIdent = getWordValue(data[index + 32..<index + 34])

        // Text alignment
        let alignValue: Int = getWordValue(data[index + 34..<index + 36])
        style.alignment = PsionWordAlignment(rawValue: alignValue) ?? .left

        // Spacing values
        style.lineSpacing = getWordValue(data[index + 36..<index + 38])
        style.spaceAbovePara = getWordValue(data[index + 38..<index + 40])
        style.spaceBelowPara = getWordValue(data[index + 40..<index + 42])
        style.spacing.set(data[index + 42])

        // Outline level
        style.outlineLevel = getWordValue(data[index + 44..<index + 46])

        // Tabs
        let tabCount: Int = getWordValue(data[index + 46..<index + 48])
        if tabCount > 0 {
            var tabIndex: Int = index + 48
            for _ in 0..<tabCount {
                style.tabPositions.append(getWordValue(data[tabIndex..<tabIndex + 2]))
                let tabType: Int = getWordValue(data[tabIndex + 2..<tabIndex + 4])
                style.tabTypes.append(PsionWordTabType(rawValue: tabType) ?? .left)
                tabIndex += 4
            }
        }

        if settings.showInfo {
            log("  Style code: \(style.code) (\(style.name))")
        }

        return style
    }


    /**
     Parse a Psion Word block styling record and extract the formatting blocks.

     - Parameters:
        - data:       A slice of the Word file bytes containing the block formatting data.
        - textLength: The number of bytes in the corresponding body text.
        - settings:   File conversion parameters.

     - Returns: An array of internal style records.
     */
    internal static func decodeWord3StyleBlocks(_ data: ArraySlice<UInt8>, _ textLength: Int, _ settings: Settings) -> [PsionWordFormatBlock] {

        var blocks: [PsionWordFormatBlock] = []
        var recordIndex = data.startIndex
        var textIndex = 0

        // Stop when the text is used up, or when there isn't a whole block unit left to read
        while textIndex < textLength && recordIndex + PsionWord3Constants.BlockUnitLength <= data.endIndex {
            let blockLength = getWordValue(data[recordIndex..<recordIndex + 2])
            let styleCode = decodeWord3Text(data[recordIndex + 2..<recordIndex + 4])
            let emphasisCode = decodeWord3Text(data[recordIndex + 4..<recordIndex + 6])
            recordIndex += PsionWord3Constants.BlockUnitLength

            // Skip empty blocks: they cover no text
            guard blockLength > 0 else {
                continue
            }

            // NOTE The loop condition and the guard ensure that, for every block,
            //      0 <= startIndex <= endIndex <= textLength - 1
            var block = PsionWordFormatBlock()
            block.styleCode = styleCode
            block.emphasisCode = emphasisCode
            block.startIndex = textIndex
            block.endIndex = min(textIndex + blockLength, textLength) - 1
            blocks.append(block)

            if settings.showInfo {
                log("  Text bytes range \(block.startIndex)-\(block.endIndex) has style code \(styleCode) and emphasis code \(emphasisCode)")
            }

            textIndex += blockLength
        }

        return blocks
    }


    /**
     Decode Psion Word text bytes (CP 850, plus Word's special characters) as a string.
     The inverse of `encodeWord3Text()`.

     Each byte becomes exactly one Unicode scalar -- nothing is dropped -- so character
     positions in the result match byte positions in the source, eg. for block ranges.

     - Parameters:
        - bytes: The bytes to decode.

     - Returns: The decoded string.
     */
    private static func decodeWord3Text(_ bytes: ArraySlice<UInt8>) -> String {

        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            switch byte {
                case 0:
                    // Paragraph separator
                    scalars.append("\n")
                case 7:
                    // Unbreakable hyphen
                    scalars.append("\u{2011}")
                case 14:
                    // Soft hyphen
                    scalars.append("\u{00AD}")
                case 15:
                    // Unbreakable space
                    scalars.append("\u{00A0}")
                case 0x80...0xFF:
                    scalars.append(cp850UpperHalf[Int(byte) - 0x80])
                default:
                    // 0x00-0x7F match their Unicode values
                    scalars.append(Unicode.Scalar(byte))
            }
        }

        return String(scalars)
    }


    /**
     Decode a header or footer record's text.

     - Parameters:
        - data:     A slice of the Word 3 file bytes containing the whole record, including its `NUL` terminator.
        - isHeader: `true` if the record is the header; `false` if it is the footer.
        - settings: File conversion parameters.

     - Returns: The text as a string.
     */
    internal static func decodeWord3OuterText(_ data: ArraySlice<UInt8>, _ isHeader: Bool, _ settings: Settings) -> String {

        // Remove the C String NUL terminator, if present
        let textBytes = data.last == 0 ? data.dropLast() : data
        let outerText = decodeWord3Text(textBytes).trimmingCharacters(in: .whitespacesAndNewlines)

        if settings.showInfo {
            log("  \(isHeader ? "Header" : "Footer") text length \(textBytes.count) byte\(textBytes.count == 1 ? "" : "s")")
        }

        // String is empty (NUL only)?
        return outerText.isEmpty ? (isHeader ? "No header" : "No footer") : outerText
    }


    /**
     Read a 16-bit little endian value from the Word file byte store.

     - Parameters:
        - data:  Two-byte slice of the word file bytes.

     - Returns: The value as an (unsigned) integer, or -1 on error.
     */
    internal static func getWordValue(_ data: ArraySlice<UInt8>) -> Int {

        // Make sure data slice is correctly dimensioned
        if data.isEmpty || data.count == 1 {
            return -1
        }

        return Int(data[data.startIndex]) + (Int(data[data.startIndex + 1]) << 8)
    }

}
