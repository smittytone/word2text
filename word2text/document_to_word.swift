/*
    word2text
    document_to_word.swift

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

    // MARK: - Entry Points for Conversion from Document to Word formats

    /**
     Convert an internal Document instance, to Word 3.

     FROM 0.5.0

     - Parameters:
        - document: The Document to convert. If it has no header, none is used;
                    if it has no footer, Word's default (`%P`: page number) is used.
        - wordData: Word 3-specific file information (see `entities.swift`).

     - Returns: A Result containing the Word file's bytes (success) or a ProcessError (failure).
     */
    internal static func convertToWord3(_ document: Document, _ settings: Settings) -> DataResult {

        // Encode the Paragraphs' Spans into the body text and its style/emphasis blocks
        var textBytes: [UInt8] = []
        var blocks: [(length: Int, style: String, emphasis: String)] = []
        var listNumbers = [Int](repeating: 0, count: PsionWord3Constants.ListLevelMax)
        if settings.showInfo {
            log("Evaluating \(document.paragraphs.count) paragraphs.")
        }

        for paragraph in document.paragraphs {
            let style = word3StyleCode(for: paragraph.type)
            var spans = paragraph.spans

            // Word has no automatic bullets or numbers, so add the list marker to the text
            if let marker = listMarker(for: paragraph.type, &listNumbers) {
                spans.insert(Span(text: marker), at: 0)
            }

            let firstBlock = blocks.count
            for span in spans {
                let spanBytes = encodeWord3Text(span.text)
                if spanBytes.isEmpty { continue }
                textBytes.append(contentsOf: spanBytes)

                // Merge with the previous block if it has the same formatting (within this paragraph only)
                let emphasis = word3EmphasisCode(for: span.type)
                if blocks.count > firstBlock && blocks[blocks.count - 1].emphasis == emphasis {
                    blocks[blocks.count - 1].length += spanBytes.count
                } else {
                    blocks.append((spanBytes.count, style, emphasis))
                }
            }

            // Paragraph separator: covered by the paragraph's final block
            textBytes.append(UInt8(PsionWord3Constants.ParagraphMarker))
            if blocks.count > firstBlock {
                blocks[blocks.count - 1].length += 1
            } else {
                blocks.append((1, style, "NN"))
            }
        }

        // A Word document always has at least one paragraph
        if textBytes.isEmpty {
            textBytes.append(UInt8(PsionWord3Constants.ParagraphMarker))
            blocks.append((1, "BT", "NN"))
            if settings.showInfo {
                log("No text in the file -- meeting Word 3’s minimum paragraph count with an empty one.")
            }
        }

        // The final block covers an imaginary extra separator byte
        blocks.append((1, "BT", "NN"))

        // Record lengths are 16-bit values
        if textBytes.count > 0xFFFF || blocks.count * PsionWord3Constants.BlockUnitLength > 0xFFFF {
            var error = ProcessError(code: .badWord3TextTooLong)
            error.text = "Converted text too long to fit in a Psion Word file (\(textBytes.count) text bytes, \(blocks.count) format blocks)"
            return .failure(error)
        }

        if settings.showInfo {
            log("Generating the Word 3 records and adding them to the file.")
        }
        // File header (unencrypted)
        var psionFile: [UInt8] = Array("PSIONWPDATAFILE".utf8) + [0]
        // Format version
        appendWord(&psionFile, 1)
        // Encryption algorithm version
        appendWord(&psionFile, 0)
        psionFile.append(contentsOf: [UInt8](repeating: 0xEA, count: 16))
        appendWord(&psionFile, 0xEAEA)
        appendWord(&psionFile, 0)

        // Record type 1: File info -- values as written by a Series 3a
        appendRecord(&psionFile, .fileInfo, [0x00, 0x00, 0x19, 0x22, 0x00, 0x00, 0x08, 0x01, 0x02, 0x00])

        // Record type 2: Printer set-up -- A4 portrait, header left-aligned, values as written by a Series 3a
        appendRecord(&psionFile, .printerConfig, [
            0x82, 0x2E, 0xC6, 0x41, 0x08, 0x07, 0x08, 0x07, 0x72, 0x20, 0xB6, 0x33, 0xD0, 0x02, 0xD0, 0x02,
            0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0xF0, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])

        // Record type 3: Printer driver -- model 0 of the specified driver library
        appendRecord(&psionFile, .printerDriver, [0x00] + encodeWord3Text(settings.word3.printerDriver) + [0])

        // Record types 4 and 5: Header and footer text. Emphases are not supported
        let header = document.header.map { combineSpans($0.spans) } ?? ""
        let footer = document.footer.map { combineSpans($0.spans) } ?? "%P"
        appendRecord(&psionFile, .headerText, encodeWord3Text(header) + [0])
        appendRecord(&psionFile, .footerText, encodeWord3Text(footer) + [0])

        // Record type 6: Styles
        for style in makeStandardStyles() {
            appendRecord(&psionFile, .styleDefinition, style)
        }

        // Record type 7: Emphases
        for emphasis in makeStandardEmphases() {
            appendRecord(&psionFile, .emphasisDefinition, emphasis)
        }

        // Record type 8: Unstyled body text
        appendRecord(&psionFile, .bodyText, textBytes)

        // Record type 9: Style and emphasis blocks
        var blockBytes: [UInt8] = []
        for block in blocks {
            appendWord(&blockBytes, block.length)
            blockBytes.append(contentsOf: Array(block.style.utf8))
            blockBytes.append(contentsOf: Array(block.emphasis.utf8))
        }

        appendRecord(&psionFile, .blockInfo, blockBytes)

        if settings.showInfo {
            log("Word 3 file assembled.")
        }
        return .success(Data(psionFile))
    }


    // MARK: - Conversion Helper Functions
    
    /*
     Font code for styles that don't inherit their font.
     NOTE Font codes are interpreted by the document's printer driver: with the Series 3a's
          ROM::BJ.WDR driver, 24 (0x18, Times Roman in the Psionics list) is 'Proportional'
     */
    private static let styleFontCode: Int = 0x18


    /**
     Build an 80-byte Psion Word 3 Style record block (type 6).

     NOTE Defaults reflect values used by the Series 3a. Font sizes, indents and spacing are in 1/20 points.
          All eight tab stop slots are always written (with Word's default 0.5in stops) as Word does,
          but only `tabCount` of them are active.

     FROM 0.4.0

     - Parameters:
        - style:    A style structure.
        - tabCount: The number of tabs to apply.

     - Returns: The style record as encoded bytes.
     */
    private static func makeStyleRecord(_ style: PsionWord3Style, _ tabCount: Int = 0) -> [UInt8] {

        var record = makeCommonHeader(style)
        appendWord(&record, style.leftIndent)
        // Right indent
        appendWord(&record, 0)
        appendWord(&record, style.firstIdent)
        appendWord(&record, style.alignment.rawValue)
        appendWord(&record, style.lineSpacing)
        // Space above
        appendWord(&record, 0)
        appendWord(&record, style.spaceBelowPara)
        var keepFlags: UInt8 = 0x00
        if (style.spacing == .keepWithNext) { keepFlags |= 0x01 }
        if (style.spacing == .keepTogether) { keepFlags |= 0x02 }
        if (style.spacing == .newPage) { keepFlags |= 0x04 }
        record.append(keepFlags)
        record.append(0)
        appendWord(&record, style.outlineLevel)

        // REVISED 0.4.1 Use the style's own tab stops if it has any. Unused slots get Word's
        // default 0.5in stops, as Word itself writes them
        let tabs = Array(style.tabPositions.prefix(8))
        appendWord(&record, tabs.isEmpty ? tabCount : tabs.count)
        for slot in 0..<8 {
            if slot < tabs.count {
                appendWord(&record, tabs[slot])
                let tabType: PsionWord3TabType = slot < style.tabTypes.count ? style.tabTypes[slot] : .left
                appendWord(&record, tabType.rawValue)
            } else {
                appendWord(&record, (slot + 1) * 720)
                appendWord(&record, PsionWord3TabType.left.rawValue)
            }
        }

        return record
    }


    /**
     Build a 28-byte Psion Word 3 Emphasis record block (type 7). Font and size are inherited.

     FROM 0.4.0

     - Parameters:
        - emphasis: An internal Word 3 emphasis structure.

     - Returns: The emphasis record as encoded bytes.
     */
    private static func makeEmphasisRecord(_ emphasis: PsionWord3Style) -> [UInt8] {

        return makeCommonHeader(emphasis)
    }


    /**
     Build the 28 bytes common to Psion Word 3 Style and Emphasis records.

     FROM 0.4.0

     - Parameters:
        - wordStyle: An internal Word 3 style or emphasis record.

     - Returns: The style or emphasis record as encoded bytes.
     */
    private static func makeCommonHeader(_ wordStyle: PsionWord3Style)  -> [UInt8] {

        // Short code (2 bytes)
        var record: [UInt8] = Array(wordStyle.code.utf8.prefix(2))

        // Full name: up to 15 chars, NUL, padded with spaces as Word does, and a final NUL
        var nameBytes = Array(encodeWord3Text(wordStyle.name).prefix(15)) + [0]
        nameBytes += [UInt8](repeating: 0x20, count: 16 - nameBytes.count)
        nameBytes[15] = 0
        record += nameBytes

        var flags: UInt8 = wordStyle.isStyle ? 0x00 : 0x01
        flags += wordStyle.isUndeletable ? 0x02 : 0x00
        flags += wordStyle.isDefault ? 0x04 : 0x00
        record.append(flags)
        record.append(0)
        appendWord(&record, wordStyle.fontCode)

        flags = wordStyle.underlined ? 0x01 : 0x00
        flags += wordStyle.bold ? 0x02 : 0x00
        flags += wordStyle.italic ? 0x04 : 0x00
        if !wordStyle.isStyle {
            flags += wordStyle.superScript ? 0x08 : 0x00
            flags += wordStyle.subScript ? 0x10 : 0x00
        }
        record.append(flags)

        // Unused (older files may have 0x80)
        record.append(0)
        appendWord(&record, wordStyle.fontSize)

        flags = wordStyle.inheritUnderline ? 0x01 : 0x00
        flags += wordStyle.inheritBold ? 0x02 : 0x00
        flags += wordStyle.inheritItalic ? 0x04 : 0x00
        if !wordStyle.isStyle {
            flags += wordStyle.inheritSuperScript ? 0x08 : 0x00
            flags += wordStyle.inheritSubScript ? 0x10 : 0x00
        }
        record.append(flags)
        // Unused
        record.append(0)
        return record
    }


    /**
     Generate a list of Psion Word 3 style record block which map to the known
     Markdown paragraph styles that we support for conversion from Markdown to Word 3.

     `BT`, `HA` and `BL` match the Series 3a defaults; `HB` to `HF` and `NL` are added
     by us to cover a range of Markdown formatting.

     - Returns: Array of byte arrays for adding to the Word 3 file binary.
     */
    private static func makeStandardStyles() -> [[UInt8]] {

        let bodyStyle = PsionWord3Style(
            code: "BT",
            name: "Body text",
            isStyle: true,
            isUndeletable: true,
            isDefault: true,
            fontCode: styleFontCode,
            fontSize: 240,
            alignment: .justified,
            spaceBelowPara: 240,
            outlineLevel: 9
        )

        let headStyleA = PsionWord3Style(
            code: "HA",
            name: "Heading A",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            fontSize: 480,
            alignment: .centered,
            lineSpacing: 480,
            spaceBelowPara: 240,
            spacing: .keepWithNext,
            outlineLevel: 1
        )

        let headStyleB = PsionWord3Style(
            code: "HB",
            name: "Heading B",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            fontSize: 360,
            lineSpacing: 360,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 2
        )

        let headStyleC = PsionWord3Style(
            code: "HC",
            name: "Heading C",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            fontSize: 280,
            lineSpacing: 280,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 3
        )

        let headStyleD = PsionWord3Style(
            code: "HD",
            name: "Heading D",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            fontSize: 240,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 4
        )

        let headStyleE = PsionWord3Style(
            code: "HE",
            name: "Heading E",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            italic: true,
            fontSize: 240,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 5
        )

        let headStyleF = PsionWord3Style(
            code: "HF",
            name: "Heading F",
            isStyle: true,
            fontCode: styleFontCode,
            italic: true,
            fontSize: 240,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 6
        )

        // FROM 0.4.1
        // List styles, one per nesting level. Each has a hanging indent: the first line starts
        // `ListHangingIndent` left of the rest, and a tab stop where the rest start, so `bullet<TAB>text`
        // aligns wrapped lines with the text. Level 1 bullets (`BL`) match the Series 3a default.
        var listStyles: [PsionWord3Style] = []
        for isBullet in [true, false] {
            for level in 1...PsionWord3Constants.ListLevelMax {
                let indent = PsionWord3Constants.ListBaseIndent + (level - 1) * PsionWord3Constants.ListIndentStep
                let baseName = isBullet ? "Bulleted list" : "Numbered list"
                listStyles.append(PsionWord3Style(
                    code: (isBullet ? PsionWord3Constants.BulletListCodes : PsionWord3Constants.NumberListCodes)[level - 1],
                    name: level == 1 ? baseName : "\(baseName) \(level)",
                    isStyle: true,
                    fontCode: -1,
                    fontSize: 240,
                    leftIndent: indent,
                    firstIdent: indent - PsionWord3Constants.ListHangingIndent,
                    alignment: .justified,
                    spaceBelowPara: 240,
                    outlineLevel: 9,
                    tabPositions: [indent],
                    tabTypes: [.left]
                ))
            }
        }

        return [
            // Body text: the default style
            makeStyleRecord(bodyStyle, 8),
            // Headings
            makeStyleRecord(headStyleA),
            makeStyleRecord(headStyleB),
            makeStyleRecord(headStyleC),
            makeStyleRecord(headStyleD),
            makeStyleRecord(headStyleE),
            makeStyleRecord(headStyleF)
        ] + listStyles.map { makeStyleRecord($0) }
    }


    /**
     Generate a list of Psion Word 3 emphasis record block which map to the known
     Markdown character styles that we support for conversion from Markdown to Word 3.

     `NN` to `SS` match the Series 3a defaults; `BI` is added for Markdown bold-italic.

     FROM 0.4.0

     - Returns: Array of byte arrays for adding to the Word 3 file binary.
     */
    private static func makeStandardEmphases() -> [[UInt8]] {

        let normalEmphasis = PsionWord3Style(
            code: "NN",
            name: "Normal",
            isStyle: false,
            isUndeletable: true,
            isDefault: true,
            fontCode: -1,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true,
            inheritItalic: true
        )

        let underlineEmphasis = PsionWord3Style(
            code: "UU",
            name: "Underline",
            isStyle: false,
            fontCode: -1,
            underlined: true,
            fontSize: 0,
            inheritBold: true,
            inheritItalic: true
        )

        let boldEmphasis = PsionWord3Style(
            code: "BB",
            name: "Bold",
            isStyle: false,
            fontCode: -1,
            bold: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritItalic: true
        )

        let italicEmphasis = PsionWord3Style(
            code: "II",
            name: "Italic",
            isStyle: false,
            fontCode: -1,
            italic: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true
        )

        let boldItalicEmphasis = PsionWord3Style(
            code: "BI",
            name: "Bold italic",
            isStyle: false,
            fontCode: -1,
            bold: true,
            italic: true,
            fontSize: 0,
            inheritUnderline: true
        )

        let superscriptEmphasis = PsionWord3Style(
            code: "EE",
            name: "Superscript",
            isStyle: false,
            fontCode: -1,
            superScript: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true,
            inheritItalic: true
        )

        let subscriptEmphasis = PsionWord3Style(
            code: "SS",
            name: "Subscript",
            isStyle: false,
            fontCode: -1,
            subScript: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true,
            inheritItalic: true
        )

        return [
            makeEmphasisRecord(normalEmphasis),
            makeEmphasisRecord(underlineEmphasis),
            makeEmphasisRecord(boldEmphasis),
            makeEmphasisRecord(italicEmphasis),
            makeEmphasisRecord(superscriptEmphasis),
            makeEmphasisRecord(subscriptEmphasis),
            makeEmphasisRecord(boldItalicEmphasis)
        ]
    }


    /**
     Map an internal paragraph type to a Psion Word 3 style code. The inverse of `paragraphType(for:)`.
     Levels outside the range 1-6 are clamped to it.

     FROM 0.5.0

     - Parameters:
        - type: A paragraph type.

     - Returns: The matching two-character Word 3 style code.
     */
    private static func word3StyleCode(for type: ParagraphType) -> String {

        func index(_ level: Int) -> Int {
            return min(max(level, 1), PsionWord3Constants.ListLevelMax) - 1
        }

        switch type {
            case .body:
                return "BT"
            case .heading(let level):
                return ["HA", "HB", "HC", "HD", "HE", "HF"][index(level)]
            case .bulletItem(let level, _):
                return PsionWord3Constants.BulletListCodes[index(level)]
            case .numberItem(let level, _):
                return PsionWord3Constants.NumberListCodes[index(level)]
        }
    }


    /**
     Get the text marker -- bullet or number, plus a tab -- that a Psion Word 3 list item carries.

     Items with no bullet get the default bullet for their level. Items with no number are
     numbered on from the previous item at the same level. Any non-list paragraph restarts
     the numbering.

     FROM 0.5.0

     - Parameters:
        - type:    A paragraph type.
        - numbers: The most recent number used at each list level, updated by this call.

     - Returns: The marker, or `nil` if the paragraph is not a list item.
     */
    private static func listMarker(for type: ParagraphType, _ numbers: inout [Int]) -> String? {

        switch type {
            case .body, .heading:
                numbers = [Int](repeating: 0, count: numbers.count)
                return nil
            case .bulletItem(let level, let bullet):
                let index = min(max(level, 1), numbers.count) - 1
                resetNumbers(below: index, &numbers)
                let defaultBullet = PsionWord3Constants.ListBullets[index % PsionWord3Constants.ListBullets.count]
                return (bullet.map { String($0) } ?? defaultBullet) + "\t"
            case .numberItem(let level, let number):
                let index = min(max(level, 1), numbers.count) - 1
                resetNumbers(below: index, &numbers)
                numbers[index] = number ?? numbers[index] + 1
                return "\(numbers[index]).\t"
        }
    }


    /**
     Clear the list numbering of levels deeper than the specified one.

     FROM 0.5.0

     - Parameters:
        - index:   The inset level at which to begin clearing list numbers.
        - numbers: The list of numbers to be updated.
     */
    private static func resetNumbers(below index: Int, _ numbers: inout [Int]) {

        for deeper in (index + 1)..<numbers.count {
            numbers[deeper] = 0
        }
    }


    /**
     Map a span type to the Word 3 emphasis code that best matches it.

     Only the emphases written by `makeStandardEmphases()` are available, so where a type
     combines emphases, e.g., bold and underline, one is chosen. Priority: bold italic, bold,
     italic, underline, superscript, subscript. Word 3 has no strikethrough, so it is dropped.

     FROM 0.5.0

     - Parameters:
        - type: A span type.

     - Returns: The matching two-character Word 3 emphasis code.
     */
    private static func word3EmphasisCode(for type: SpanType) -> String {

        if type.isSuperset(of: .boldItalic) {
            return "BI"
        }

        if type.contains(.bold) {
            return "BB"
        }

        if type.contains(.italic) {
            return "II"
        }

        if type.contains(.underline) {
            return "UU"
        }

        if type.contains(.superScript) {
            return "EE"
        }

        if type.contains(.subScript) {
            return "SS"
        }

        return "NN"
    }


    /**
     Append a record (type, length, data) to a Psion Word 3 file's bytes.

     FROM 0.4.0

     - Parameters:
        - file: Pointer to the byte array forming a record.
        - type: The Word record type.
        - data: The record bytes to append.
     */
    private static func appendRecord(_ file: inout [UInt8], _ type: PsionWord3RecordType, _ data: [UInt8]) {

        appendWord(&file, type.rawValue)
        appendWord(&file, data.count)
        file.append(contentsOf: data)
    }


    /**
     Append a 16-bit little endian value. Negative values (eg. -1 for 'inherited') wrap to their two's complement.

     FROM 0.4.0

     - Parameters:
        - bytes: Pointer to the byte array forming a record.
        - value: The value to inject as a pair of bytes.
     */
    private static func appendWord(_ bytes: inout [UInt8], _ value: Int) {

        let word = UInt16(truncatingIfNeeded: value)
        bytes.append(UInt8(word & 0xFF))
        bytes.append(UInt8(word >> 8))
    }

}
