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

    /**
     Build a Document from a loaded Psion Word file.

     - Parameters:
        - source:     The loaded Word 3 file bytes.
        - sourceType: The type of Psion Word file.
        - settings:   The conversion settings.

     - Returns: A Result containing the converted Document (success) or a ProcessError (failure).
     */
    internal static func makeDocument(from source: Data, ofType sourceType: ContentType, _ settings: Settings) -> DocumentResult {

        // Confirm the source type is correct
        guard sourceType == .word3 else {
            // This is an internal error
            return .failure(ProcessError(code: .badConversionSource))
        }

        let wordData = [UInt8](source)
        var byteIndex = PsionWord3Constants.HeaderLength
        var textBytes: [UInt8] = []
        var outerText: [String] = ["", ""]
        var styles: [String:PsionWord3Style] = [:]
        var emphases: [String:PsionWord3Style] = [:]
        var blocks: [PsionWord3FormatBlock] = []
        var document = Document()

        // Check minimum file size: enough bytes to at least check the preamble
        if wordData.count < PsionWord3Constants.PreambleLength {
            return .failure(ProcessError(code: .badWord3FileType))
        }

        // Check the data preamble (C String of up to 15 chars plus `NUL`)
        let preamble = String(decoding: wordData[0..<PsionWord3Constants.PreambleBytesLastIndex], as: UTF8.self)
        if preamble != "PSIONWPDATAFILE" || wordData.count < PsionWord3Constants.HeaderLength {
            // TODO Report actual file type
            return .failure(ProcessError(code: .badWord3FileType))
        }

        // Check for encrypted files: look at file bytes 16 and 17
        // NOTE We can't handle these yet as the decode algorithm remains unknown
        if getWordValue(wordData[PsionWord3Constants.EncryptionBytesFirstIndex..<PsionWord3Constants.EncryptionBytesLastIndex]) == PsionWord3Constants.EncryptionMarker {
            return .failure(ProcessError(code: .word3FileEncrypted))
        }

        // Iterate over the file's bytes to extract the records
        var recordCounter: UInt16 = 0
        while byteIndex < wordData.count - PsionWord3Constants.RecordHeaderLength {
            // Get the 16-bit record type and 16-bit data length
            let rawRecordType = getWordValue(wordData[byteIndex..<byteIndex + 2])
            let recordType = PsionWord3RecordType(rawValue: rawRecordType) ?? .unknown
            let recordDataLength = getWordValue(wordData[byteIndex + 2..<byteIndex + 4])

            // Move index to start of record
            byteIndex += PsionWord3Constants.RecordHeaderLength

            // Make sure the whole record is present: a truncated file may end part-way through one
            guard byteIndex + recordDataLength <= wordData.count else {
                var error = ProcessError(code: .badWord3FileTruncated)
                error.text = "Word file is truncated (record at \(String(format: "0x%04x", arguments: [byteIndex - PsionWord3Constants.RecordHeaderLength])) needs \(recordDataLength) bytes, but only \(wordData.count - byteIndex) remain)"
                return .failure(error)
            }

            if settings.showInfo && recordType != .unknown {
                let recordTypeName = PsionWord3Constants.RecordTypes[recordType.rawValue - 1]
                log("Record of type \(recordTypeName) found at offset \(String(format: "0x%04x", arguments: [byteIndex - PsionWord3Constants.RecordHeaderLength])). Size: \(recordDataLength) bytes")
            }

            // Process the current record
            switch recordType {
                case .fileInfo:
                    // We don't care about this beyond its size
                    if recordDataLength != PsionWord3Constants.FileInfoRecordLength {
                        var error = ProcessError(code: .badWord3RecordLengthFileInfo)
                        error.text = "Bad file info record size (\(recordDataLength) not \(PsionWord3Constants.FileInfoRecordLength) bytes)"
                        return .failure(error)
                    }
                case .printerConfig:
                    // We don't care about this beyond its size
                    if recordDataLength != PsionWord3Constants.PrinterConfigRecordLength {
                        var error = ProcessError(code: .badWord3RecordLengthPrinterConfig)
                        error.text = "Bad printer config record size (\(recordDataLength) not \(PsionWord3Constants.PrinterConfigRecordLength) bytes)"
                        return .failure(error)
                    }
                case .printerDriver:
                    // We don't care about this
                    break
                case .headerText:
                    fallthrough
                case .footerText:
                    // Index in strings store is 0 for header, 1 for footer
                    let index = recordType.rawValue - PsionWord3RecordType.headerText.rawValue
                    outerText[index] = decodeWord3OuterText(wordData[byteIndex..<byteIndex + recordDataLength], index == 0, settings)
                case .styleDefinition:
                    // Check the fixed size
                    if recordDataLength != PsionWord3Constants.StyleRecordLength {
                        var error = ProcessError(code: .badWord3RecordLengthStyleDefinition)
                        error.text = "Bad style definition record size (\(recordDataLength) not \(PsionWord3Constants.StyleRecordLength) bytes)"
                        return .failure(error)
                    }

                    let style = decodeWord3Style(wordData[byteIndex..<byteIndex + PsionWord3Constants.StyleRecordLength], true, settings)
                    styles[style.code] = style
                case .emphasisDefinition:
                    // Check the fixed size
                    if recordDataLength != PsionWord3Constants.EmphasisRecordLength {
                        var error = ProcessError(code: .badWord3RecordLengthEmphasisDefinition)
                        error.text = "Bad emphasis definition record size (\(recordDataLength)) not \(PsionWord3Constants.EmphasisRecordLength) bytes"
                        return .failure(error)
                    }

                    let emphasis = decodeWord3Style(wordData[byteIndex..<byteIndex + PsionWord3Constants.EmphasisRecordLength], false, settings)
                    emphases[emphasis.code] = emphasis
                case .bodyText:
                    // Keep the raw CP 850 bytes: they are decoded per span in `makeParagraphs()`.
                    // NOTE No bytes are removed or replaced here, so the block ranges remain valid
                    textBytes = Array(wordData[byteIndex..<byteIndex + recordDataLength])
                    if settings.showInfo {
                        log("  Body text length \(textBytes.count) byte\(textBytes.count == 1 ? "" : "s")")
                    }
                case .blockInfo:
                    blocks = decodeWord3StyleBlocks(wordData[byteIndex..<wordData.endIndex], textBytes.count, settings)
                    // Set each block's style and emphasis according to the codes.
                    // NOTE We loop this way so we don't change copy-on-write array members.
                    for index in blocks.indices {
                        blocks[index].style = styles[blocks[index].styleCode]
                        blocks[index].emphasis = emphases[blocks[index].emphasisCode]
                    }
                case .unknown:
                    var error = ProcessError(code: .badWord3RecordType)
                    error.text = "Bad Word file record type \(rawRecordType) at \(String(format: "0x%04x", arguments: [byteIndex - PsionWord3Constants.RecordHeaderLength]))"
                    return .failure(error)
            }

            recordCounter |= (1 << recordType.rawValue)
            byteIndex += recordDataLength
        }

        // Check we have at least one of every record
        if recordCounter != PsionWord3Constants.RecordTotal {
            // Processing ended, but without a complete set of records
            return .failure(ProcessError(code: .badWord3FileMissingRecords))
        }

        // Assemble the Document from the decoded text, blocks, styles and emphases
        document.paragraphs = makeParagraphs(textBytes, blocks)

        // Add the header and foot if requested to do so
        if settings.word3.includeHeaders {
            document.header = Paragraph(spans: [Span(text: outerText[0])])
            document.footer = Paragraph(spans: [Span(text: outerText[1])])
        }

        return .success(document)
    }


    // MARK: - Conversion Helper Functions

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
    private static func makeParagraphs(_ rawText: [UInt8], _ blocks: [PsionWord3FormatBlock]) -> [Paragraph] {

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
                currentParagraph.type = paragraphType(fromWord3StyleCode: block.styleCode)
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


    // MARK: - Word 3 Data Decoders

    /**
     Map a Psion Word 3 style code to a paragraph type.

     FROM 0.5.0

     - Parameters:
        - styleCode: A two-character Word 3 style code, eg. `HA` or `B2`.

     - Returns: The matching ParagraphType. Unrecognised codes, including user-defined
                styles, are treated as body text.
     */
    private static func paragraphType(fromWord3StyleCode styleCode: String) -> ParagraphType {

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
        // Find the first nul, if present
        if let range: Range<String.Index> = style.name.range(of: "\0") {
            style.name = String(style.name[..<range.lowerBound])
        }

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
    internal static func decodeWord3StyleBlocks(_ data: ArraySlice<UInt8>, _ textLength: Int, _ settings: Settings) -> [PsionWord3FormatBlock] {

        var blocks: [PsionWord3FormatBlock] = []
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
            var block = PsionWord3FormatBlock()
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
