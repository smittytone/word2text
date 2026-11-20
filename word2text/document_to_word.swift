/*
    word2text
    document_to_word3.swift

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
    internal static func convert(_ document: Document, _ wordData: Word3Data = Word3Data()) -> Result<Data, ProcessError> {

        // Encode the Paragraphs' Spans into the body text and its style/emphasis blocks
        var textBytes: [UInt8] = []
        var blocks: [(length: Int, style: String, emphasis: String)] = []
        var listNumbers = [Int](repeating: 0, count: PsionWordConstants.ListLevelMax)

        for paragraph in document.paragraphs {
            let style = styleCode(for: paragraph.type)
            var spans = paragraph.spans

            // Word has no automatic bullets or numbers, so add the list marker to the text
            if let marker = listMarker(for: paragraph.type, &listNumbers) {
                spans.insert(Span(text: marker), at: 0)
            }

            let firstBlock = blocks.count
            for span in spans {
                let spanBytes = encodePsionText(span.text)
                if spanBytes.isEmpty { continue }
                textBytes.append(contentsOf: spanBytes)

                // Merge with the previous block if it has the same formatting (within this paragraph only)
                let emphasis = emphasisCode(for: span.type)
                if blocks.count > firstBlock && blocks[blocks.count - 1].emphasis == emphasis {
                    blocks[blocks.count - 1].length += spanBytes.count
                } else {
                    blocks.append((spanBytes.count, style, emphasis))
                }
            }

            // Paragraph separator: covered by the paragraph's final block
            textBytes.append(UInt8(PsionWordConstants.ParagraphMarker))
            if blocks.count > firstBlock {
                blocks[blocks.count - 1].length += 1
            } else {
                blocks.append((1, style, "NN"))
            }
        }

        // A Word document always has at least one paragraph
        if textBytes.isEmpty {
            textBytes.append(UInt8(PsionWordConstants.ParagraphMarker))
            blocks.append((1, "BT", "NN"))
        }

        // The final block covers an imaginary extra separator byte
        blocks.append((1, "BT", "NN"))

        // Record lengths are 16-bit values
        if textBytes.count > 0xFFFF || blocks.count * PsionWordConstants.BlockUnitLength > 0xFFFF {
            var error = ProcessError(code: .badTextTooLong)
            error.text = "Converted text too long to fit in a Psion Word file (\(textBytes.count) text bytes, \(blocks.count) format blocks)"
            return .failure(error)
        }

        // File header (unencrypted)
        var file: [UInt8] = Array("PSIONWPDATAFILE".utf8) + [0]
        // Format version
        appendWord(&file, 1)
        // Encryption algorithm version
        appendWord(&file, 0)
        file.append(contentsOf: [UInt8](repeating: 0xEA, count: 16))
        appendWord(&file, 0xEAEA)
        appendWord(&file, 0)

        // Record type 1: File info -- values as written by a Series 3a
        appendRecord(&file, .fileInfo, [0x00, 0x00, 0x19, 0x22, 0x00, 0x00, 0x08, 0x01, 0x02, 0x00])

        // Record type 2: Printer set-up -- A4 portrait, header left-aligned, values as written by a Series 3a
        appendRecord(&file, .printerConfig, [
            0x82, 0x2E, 0xC6, 0x41, 0x08, 0x07, 0x08, 0x07, 0x72, 0x20, 0xB6, 0x33, 0xD0, 0x02, 0xD0, 0x02,
            0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0xF0, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])

        // Record type 3: Printer driver -- model 0 of the specified driver library
        appendRecord(&file, .printerDriver, [0x00] + encodePsionText(wordData.printerDriver) + [0])

        // Record types 4 and 5: Header and footer text. Emphases are not supported
        let header = document.header.map { combineSpans($0.spans) } ?? ""
        let footer = document.footer.map { combineSpans($0.spans) } ?? "%P"
        appendRecord(&file, .headerText, encodePsionText(header) + [0])
        appendRecord(&file, .footerText, encodePsionText(footer) + [0])

        // Record type 6: Styles
        for style in markdownStyles() {
            appendRecord(&file, .styleDefinition, style)
        }

        // Record type 7: Emphases
        for emphasis in markdownEmphases() {
            appendRecord(&file, .emphasisDefinition, emphasis)
        }

        // Record type 8: Unstyled body text
        appendRecord(&file, .bodyText, textBytes)

        // Record type 9: Style and emphasis blocks
        var blockBytes: [UInt8] = []
        for block in blocks {
            appendWord(&blockBytes, block.length)
            blockBytes.append(contentsOf: Array(block.style.utf8))
            blockBytes.append(contentsOf: Array(block.emphasis.utf8))
        }

        appendRecord(&file, .blockInfo, blockBytes)

        return .success(Data(file))
    }


    // MARK: - Conversion Helper Functions
    
    /*
     Font code for styles that don't inherit their font.
     NOTE Font codes are interpreted by the document's printer driver: with the Series 3a's
          ROM::BJ.WDR driver, 24 (0x18, Times Roman in the Psionics list) is 'Proportional'
     */
    private static let styleFontCode: Int = 0x18

    /**
     The style records written to Markdown-derived documents.
     BT, HA and BL match the Series 3a defaults; HB to HF and NL are added to cover Markdown.
     */
    private static func markdownStyles() -> [[UInt8]] {

        let bodyStyle = PsionWordStyle(
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

        let headStyleA = PsionWordStyle(
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

        let headStyleB = PsionWordStyle(
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

        let headStyleC = PsionWordStyle(
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

        let headStyleD = PsionWordStyle(
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

        let headStyleE = PsionWordStyle(
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

        let headStyleF = PsionWordStyle(
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
        var listStyles: [PsionWordStyle] = []
        for isBullet in [true, false] {
            for level in 1...PsionWordConstants.ListLevelMax {
                let indent = PsionWordConstants.ListBaseIndent + (level - 1) * PsionWordConstants.ListIndentStep
                let baseName = isBullet ? "Bulleted list" : "Numbered list"
                listStyles.append(PsionWordStyle(
                    code: (isBullet ? PsionWordConstants.BulletListCodes : PsionWordConstants.NumberListCodes)[level - 1],
                    name: level == 1 ? baseName : "\(baseName) \(level)",
                    isStyle: true,
                    fontCode: -1,
                    fontSize: 240,
                    leftIndent: indent,
                    firstIdent: indent - PsionWordConstants.ListHangingIndent,
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
     Build an 80-byte Word style record.

     FROM 0.4.0

     - Note: Defaults reflect values used by the Series 3a. Font sizes, indents and spacing are in 1/20 points.
             All eight tab stop slots are always written (with Word's default 0.5in stops) as Word does,
             but only `tabCount` of them are active.

     - Parameters:
        - style:    A style structure.
        - tabCount: The number of tabs to apply.

     - Returns: The style record as encoded bytes.
     */
    private static func makeStyleRecord(_ style: PsionWordStyle, _ tabCount: Int = 0) -> [UInt8] {

        var record = makeStyleHeader(style)
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
                let tabType: PsionWordTabType = slot < style.tabTypes.count ? style.tabTypes[slot] : .left
                appendWord(&record, tabType.rawValue)
            } else {
                appendWord(&record, (slot + 1) * 720)
                appendWord(&record, PsionWordTabType.left.rawValue)
            }
        }

        return record
    }


    /**
     Build a 28-byte type 7 (emphasis) record. Font and size are inherited.

     FROM 0.4.0

     - Parameters:
        - emphasis: A Word emphasis structure.

     - Returns: The emphasis record as encoded bytes.
     */
    private static func makeEmphasisRecord(_ emphasis: PsionWordStyle) -> [UInt8] {

        return makeStyleHeader(emphasis)
    }


    /**
     Build the 28 bytes common to style and emphasis records.

     FROM 0.4.0
     */
    private static func makeStyleHeader(_ style: PsionWordStyle)  -> [UInt8] {

        // Short code (2 bytes)
        var record: [UInt8] = Array(style.code.utf8.prefix(2))

        // Full name: up to 15 chars, NUL, padded with spaces as Word does, and a final NUL
        var nameBytes = Array(encodePsionText(style.name).prefix(15)) + [0]
        nameBytes += [UInt8](repeating: 0x20, count: 16 - nameBytes.count)
        nameBytes[15] = 0
        record += nameBytes

        var flags: UInt8 = style.isStyle ? 0x00 : 0x01
        flags += style.isUndeletable ? 0x02 : 0x00
        flags += style.isDefault ? 0x04 : 0x00
        record.append(flags)
        record.append(0)
        appendWord(&record, style.fontCode)

        flags = style.underlined ? 0x01 : 0x00
        flags += style.bold ? 0x02 : 0x00
        flags += style.italic ? 0x04 : 0x00
        if !style.isStyle {
            flags += style.superScript ? 0x08 : 0x00
            flags += style.subScript ? 0x10 : 0x00
        }
        record.append(flags)

        // Unused (older files may have 0x80)
        record.append(0)
        appendWord(&record, style.fontSize)

        flags = style.inheritUnderline ? 0x01 : 0x00
        flags += style.inheritBold ? 0x02 : 0x00
        flags += style.inheritItalic ? 0x04 : 0x00
        if !style.isStyle {
            flags += style.inheritSuperScript ? 0x08 : 0x00
            flags += style.inheritSubScript ? 0x10 : 0x00
        }
        record.append(flags)
        // Unused
        record.append(0)
        return record
    }

    
    /**
     The Word emphasis records written to Markdown-derived documents.
     `NN` to `SS` match the Series 3a defaults; `BI` is added for Markdown bold-italic.

     FROM 0.4.0

     - Returns: Array of byte arrays to add to the Word binary.
     */
    private static func markdownEmphases() -> [[UInt8]] {

        let normalEmphasis = PsionWordStyle(
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

        let underlineEmphasis = PsionWordStyle(
            code: "UU",
            name: "Underline",
            isStyle: false,
            fontCode: -1,
            underlined: true,
            fontSize: 0,
            inheritBold: true,
            inheritItalic: true
        )

        let boldEmphasis = PsionWordStyle(
            code: "BB",
            name: "Bold",
            isStyle: false,
            fontCode: -1,
            bold: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritItalic: true
        )

        let italicEmphasis = PsionWordStyle(
            code: "II",
            name: "Italic",
            isStyle: false,
            fontCode: -1,
            italic: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true
        )

        let boldItalicEmphasis = PsionWordStyle(
            code: "BI",
            name: "Bold italic",
            isStyle: false,
            fontCode: -1,
            bold: true,
            italic: true,
            fontSize: 0,
            inheritUnderline: true
        )

        let superscriptEmphasis = PsionWordStyle(
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

        let subscriptEmphasis = PsionWordStyle(
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
     Map a paragraph type to a Word 3 style code. The inverse of `paragraphType(for:)`.
     Levels outside the range 1-6 are clamped to it.

     FROM 0.5.0

     - Parameters:
        - type: A paragraph type.

     - Returns: The matching two-character Word 3 style code.
     */
    private static func styleCode(for type: ParagraphType) -> String {

        func index(_ level: Int) -> Int {
            return min(max(level, 1), PsionWordConstants.ListLevelMax) - 1
        }

        switch type {
            case .body:
                return "BT"
            case .heading(let level):
                return ["HA", "HB", "HC", "HD", "HE", "HF"][index(level)]
            case .bulletItem(let level, _):
                return PsionWordConstants.BulletListCodes[index(level)]
            case .numberItem(let level, _):
                return PsionWordConstants.NumberListCodes[index(level)]
        }
    }


    /**
     Get the text marker -- bullet or number, plus a tab -- that a Word 3 list item carries.

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
                let defaultBullet = PsionWordConstants.ListBullets[index % PsionWordConstants.ListBullets.count]
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
     */
    private static func resetNumbers(below index: Int, _ numbers: inout [Int]) {

        for deeper in (index + 1)..<numbers.count {
            numbers[deeper] = 0
        }
    }


    /**
     Map a span type to the Word 3 emphasis code that best matches it.

     Only the emphases written by `markdownEmphases()` are available, so where a type
     combines emphases, eg. bold and underline, one is chosen. Priority: bold italic, bold,
     italic, underline, superscript, subscript. Word 3 has no strikethrough, so it is dropped.

     FROM 0.5.0

     - Parameters:
        - type: A span type.

     - Returns: The matching two-character Word 3 emphasis code.
     */
    private static func emphasisCode(for type: SpanType) -> String {

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
     Append a record (type, length, data) to the file bytes.

     FROM 0.4.0

     - Parameters:
        - file: Pointer to the byte array forming a record.
        - type: The Word record type.
        - data: The record bytes to append.
     */
    private static func appendRecord(_ file: inout [UInt8], _ type: PsionWordRecordType, _ data: [UInt8]) {

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
