/*
    word2text
    convert_word.swift

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


public struct PsionWord {

    // MARK: - Word 3 Conversion Entry Points
    
    /**
     Convert an individual Word 3 file to Markdown or plain text.

     FROM 0.5.0

     - Parameters:
        - wordData: A slice of the loaded Word 3 file bytes.
        - filepath: Absolute path of the target Word 3 file. Used for logging.
        - settings: Conversion parameters.

     - Returns: A Result containing the converted text (success) or a ProcessError embedding the error code (failure).
     */
    static public func decodeWord3(_ wordData: ArraySlice<UInt8>, _ filepath: String, _ settings: ProcessSettings) -> Result<String, ProcessError> {

        var bodyText = ""
        var byteIndex = PsionWord3Constants.HeaderLength
        var textBytes: [UInt8] = []
        var outerText: [String] = ["", ""]
        var styles: [String:PsionWordStyle] = [:]
        var emphases: [String:PsionWordStyle] = [:]
        var blocks: [PsionWordFormatBlock] = []
        var document = Document()

        // Check minimum file size: enough bytes to at least check the preamble
        if wordData.count < PsionWord3Constants.PreambleLength {
            return .failure(ProcessError(code: .badPsionFileType))
        }

        // Check the data preamble (C String of up to 15 chars plus `NUL`)
        let preamble = String(decoding: wordData[0..<PsionWord3Constants.PreambleBytesLastIndex], as: UTF8.self)
        if preamble != "PSIONWPDATAFILE" || wordData.count < PsionWord3Constants.HeaderLength {
            // TODO Report actual file type
            return .failure(ProcessError(code: .badPsionFileType))
        }

        if settings.showInfo {
            log("File \(filepath) is a Psion Series 3 Word document")
        }

        // Check for encrypted files: look at file bytes 16 and 17
        // NOTE We can't handle these yet as the decode algorithm remains unknown
        if getWordValue(wordData[PsionWord3Constants.EncryptionBytesFirstIndex..<PsionWord3Constants.EncryptionBytesLastIndex]) == PsionWord3Constants.EncryptionMarker {
            return .failure(ProcessError(code: .badFileEncrypted))
        }

        // Iterate over the file's bytes to extract the records
        var recordCounter: UInt16 = 0
        while byteIndex < wordData.count - PsionWord3Constants.RecordHeaderLength {
            // Get the 16-bit record type and 16-bit data length
            let recordType = PsionWordRecordType(rawValue: getWordValue(wordData[byteIndex..<byteIndex + 2])) ?? .unknown
            let recordDataLength = getWordValue(wordData[byteIndex + 2..<byteIndex + 4])

            // Move index to start of record
            byteIndex += PsionWord3Constants.RecordHeaderLength

            if settings.showInfo {
                log("Record of type \(PsionWord3Constants.RecordTypes[recordType.rawValue - 1]) found at offset \(String(format: "0x%04x", arguments: [byteIndex])). Size: \(recordDataLength) bytes")
            }

            // Process the current record
            switch recordType {
                case .fileInfo:
                    // We don't care about this beyond its size
                    if recordDataLength != PsionWord3Constants.FileInfoRecordLength {
                        var error = ProcessError(code: .badRecordLengthFileInfo)
                        error.text = "Bad file info record size (\(recordDataLength) not \(PsionWord3Constants.FileInfoRecordLength) bytes)"
                        return .failure(error)
                    }
                case .printerConfig:
                    // We don't care about this beyond its size
                    if recordDataLength != PsionWord3Constants.PrinterConfigRecordLength {
                        var error = ProcessError(code: .badRecordLengthPrinterConfig)
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
                    let index = recordType.rawValue - PsionWordRecordType.headerText.rawValue
                    outerText[index] = decodeOuterText(wordData[byteIndex..<byteIndex + recordDataLength], index == 0, settings)
                case .styleDefinition:
                    // Check the fixed size
                    if recordDataLength != PsionWord3Constants.StyleRecordLength {
                        var error = ProcessError(code: .badRecordLengthStyleDefinition)
                        error.text = "Bad style definition record size (\(recordDataLength) not \(PsionWord3Constants.StyleRecordLength) bytes)"
                        return .failure(error)
                    }

                    let style = decodeStyle(wordData[byteIndex..<byteIndex + PsionWord3Constants.StyleRecordLength], true, settings)
                    styles[style.code] = style
                case .emphasisDefinition:
                    // Check the fixed size
                    if recordDataLength != PsionWord3Constants.EmphasisRecordLength {
                        var error = ProcessError(code: .badRecordLengthStyleDefinition)
                        error.text = "Bad emphasis definition record size (\(recordDataLength)) not \(PsionWord3Constants.EmphasisRecordLength) bytes"
                        return .failure(error)
                    }

                    let emphasis = decodeStyle(wordData[byteIndex..<byteIndex + PsionWord3Constants.EmphasisRecordLength], false, settings)
                    emphases[emphasis.code] = emphasis
                case .bodyText:
                    // Keep the raw CP 850 bytes: they are decoded per span in `makeParagraphs()`.
                    // NOTE No bytes are removed or replaced here, so the block ranges remain valid
                    textBytes = Array(wordData[byteIndex..<byteIndex + recordDataLength])
                    if settings.showInfo {
                        log("  Body text length \(textBytes.count) byte\(textBytes.count == 1 ? "" : "s")")
                    }
                case .blockInfo:
                    blocks = decodeStyleBlocks(wordData[byteIndex..<wordData.endIndex], textBytes.count, settings)
                    // Set each block's style and emphasis according to the codes.
                    // NOTE We loop this way so we don't change copy-on-write array members.
                    for index in blocks.indices {
                        blocks[index].style = styles[blocks[index].styleCode]
                        blocks[index].emphasis = emphases[blocks[index].emphasisCode]
                    }
                case .unknown:
                    var error = ProcessError(code: .badRecordType)
                    error.text = "Bad Word file record type (\(recordType.rawValue) at \(String(format: "0x%04x", arguments: [byteIndex]))"
                    return .failure(error)
            }

            recordCounter |= (1 << recordType.rawValue)
            byteIndex += recordDataLength
        }

        // Check we have at least one of every record
        if recordCounter != PsionWord3Constants.RecordTotal {
            // Processing ended, but without a complete set of records
            return .failure(ProcessError(code: .badFileMissingRecords))
        }

        // Assemble the Document from the decoded text, blocks, styles and emphases
        document.paragraphs = makeParagraphs(textBytes, blocks)

        // Add the header and foot if requested to do so
        if settings.includeHeader {
            document.header = Paragraph(spans: [Span(text: outerText[0])])
            document.footer = Paragraph(spans: [Span(text: outerText[1])])
        }

        // Use the Document to generate the converted text we'll return
        bodyText = convert(document, settings.returnMarkdown ? .markdown : .plainText, settings.includeHeader)
        return .success(bodyText)
    }


    /**
     Convert an individual Word file to plain text.

     DEPRECATED--Use `decodeWord3()` instead. Retained for temporary backwards compatibility.

     - Parameters:
        - data:     Data object containing the file bytes.
                    May be better to just pass a byte array.
        - filepath: Absolute path of the target Word file. Used for logging.
        - settings: File conversion parameters.

     - Returns: A Result containing the text (success) or a ProcessError embedding the error code (failure).
     */
    static public func processFile(_ data: ArraySlice<UInt8>, _ filepath: String, _ settings: ProcessSettings) -> Result<String, ProcessError> {

        return decodeWord3(data, filepath, settings)
    }


    /**
     Variation of the main `processFile()` to support passing in a Data object.

     DEPRECATED--Use `decodeWord3()` instead. Retained for temporary backwards compatibility.
     */
    static public func processFile(_ data: Data, _ settings: ProcessSettings? = nil, _ filepath: String = "") -> Result<String, ProcessError> {

        let bytes = [UInt8](data)
        return decodeWord3(bytes[...], filepath, settings == nil ? ProcessSettings() : settings!)
    }

 }
