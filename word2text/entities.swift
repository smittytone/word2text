/*
    word2text
    entities.swift

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


/*
    Word file processing error codes.
    NOTE We require raw values for these, for output as stderr codes.
*/
public enum ProcessErrorKind: Int, Error {

    case noError                                = 0
    case badFile                                = 1
    case badPsionFileType                       = 2
    case badFileEncrypted                       = 3
    case badRecordLengthFileInfo                = 4
    case badRecordLengthPrinterConfig           = 5
    case badRecordLengthStyleDefinition         = 6
    case badRecordLengthEmphasisDefinition      = 7
    case badRecordType                          = 8
    case badFileMissingRecords                  = 9
    case badTextTooLong                         = 10
    case badFileNotUTF8                         = 11
    case fileAlreadyExists                      = 12
    case badConversionSource                    = 13
}


/*
    Structure to hold the outcome of a failed file processing operation.
    Supports `error.localizedDescription`.

    The `code` value will be an error code (ProcessErrorKind). Its raw value can be used as an exit code.

    The `text` property will be an error message. It is required only by certain errors,
    specifically those which interpolate information into the error message.
*/
public struct ProcessError: Error, LocalizedError {

    public var code: ProcessErrorKind                  = .noError
    public var text: String?                           = nil
    public var errorDescription: String? {
        switch self.code {
            case .noError:
                return nil
            case .badFile:
                return "File not found"
            case .badPsionFileType:
                return "Not a Psion Series 3 Word file"
            case .badFileEncrypted:
                return "Word file is encrypted"
            case .badRecordLengthFileInfo,
                 .badRecordLengthPrinterConfig,
                 .badRecordLengthStyleDefinition,
                 .badRecordLengthEmphasisDefinition,
                 .badRecordType:
                if let text = self.text {
                    return text
                } else {
                    return "Error message not provided"
                }
            case .badFileMissingRecords:
                return "File did not include required records"
            case .badTextTooLong:
                if let text = self.text {
                    return text
                } else {
                    return "Text too long for a Psion Word file (max. 64KB)"
                }
            case .badFileNotUTF8:
                return "Source file is not UTF-8"
            case .fileAlreadyExists:
                return "Output file already exists -- use `--force to overwrite"
            case .badConversionSource:
                return "Incompatible input or output type selected"
        }
    }
}


/*
    Configuration data for Word file processing operations.

    REVISED 0.4.0
*/
public struct ProcessSettings {

    public var showInfo: Bool               = false
    public var includeHeader: Bool          = false
    public var haltOnFirstError: Bool       = false
    public var outputAsFile: Bool           = true
    public var returnMarkdown: Bool         = false
    public var files: [String]              = []
    // FROM 0.4.0
    public var reverseConversion: Bool      = false
    public var forceWrite: Bool             = false
    // FROM 0.5.0
    public var fixName: Bool                = false
    // FROM TBD
    public var jobs: [Conversion]           = []

    public init() {

    }
}


/**
 UNUSED FOR NOW
 Conversion job record

 FROM 0.x.0
 */
public struct Conversion {

    public var sourceFilePath: String       = ""
    public var inputType: ContentType        = .word3
    public var outputType: ContentType       = .plainText
}


/*
    Possible input and output content types for conversion.

    FROM 0.5.0
 */
public enum ContentType {

    case plainText
    case markdown
    case word3
    case word5
}


/*
    Notification for libraries.

    FROM 0.3.0
*/
public struct ProcessNotification {

    public static let log       = Notification.Name(rawValue: "com.bps.word2text.note.log.message")
    public static let warning   = Notification.Name(rawValue: "com.bps.word2text.note.log.warning")
}


/*
    Structure to hold a Style or Emphasis record.

    Not all of the fields are used by each type.
*/
public struct PsionWordStyle {

    public var code: String                            = ""
    public var name: String                            = ""
    public var isStyle: Bool                           = true           // `true` for a style, `false` for an emphasis
    public var isUndeletable: Bool                     = false
    public var isDefault: Bool                         = false
    public var fontCode: Int                           = 0
    public var underlined: Bool                        = false
    public var bold: Bool                              = false
    public var italic: Bool                            = false
    public var superScript: Bool                       = false          // Emphasis only
    public var subScript: Bool                         = false          // Emphasis only
    public var fontSize: Int                           = 10             // Multiple of 0.05
    public var inheritUnderline: Bool                  = false
    public var inheritBold: Bool                       = false
    public var inheritItalic: Bool                     = false
    public var inheritSuperScript: Bool                = false
    public var inheritSubScript: Bool                  = false
    public var leftIndent: Int                         = 0              // This and all remaining members
    public var rightIndent: Int                        = 0              // are Style only
    public var firstIdent: Int                         = 0
    public var alignment: PsionWordAlignment           = .left
    public var lineSpacing: Int                        = 240
    public var spaceAbovePara: Int                     = 0
    public var spaceBelowPara: Int                     = 0
    public var spacing: PsionWordSpacing               = .noSpacing
    public var outlineLevel: Int                       = 0
    public var tabPositions: [Int]                     = []
    public var tabTypes: [PsionWordTabType]            = []
}


/*
    Text section formatting information.
*/
public struct PsionWordFormatBlock {

    public var startIndex: Int                          = 0              // Index into the raw text from Section 8 (first character)
    public var endIndex: Int                            = 0              // Index into the raw text from Section 8 (last character)
    public var styleCode: String                        = "BT"           // Span's Word 3 style code
    public var emphasisCode: String                     = "NN"           // Span's Word 3 emphasis code
    // FROM
    public var style: PsionWordStyle?                   = nil
    public var emphasis: PsionWordStyle?                = nil
}


/*
    Text alignment options.
    NOTE We require raw values for these
*/
public enum PsionWordAlignment: Int {

    case left                                   = 0
    case right                                  = 1
    case centered                               = 2
    case justified                              = 3
    case unknown                                = 99
}


/*
    Paragraph spacing options
*/
public enum PsionWordSpacing {

    case keepWithNext
    case keepTogether
    case newPage
    case noSpacing
}

extension PsionWordSpacing {

    mutating func set(_ value: UInt8) {
        if value & 0x01 > 0 {
            self = .keepWithNext
        } else if value & 0x02 > 0 {
            self = .keepTogether
        } else if value & 0x04 > 0 {
            self = .newPage
        } else {
            self = .noSpacing
        }
    }
}


/*
    Tabulation options
*/
public enum PsionWordTabType: Int {

    case left                                   = 0
    case right                                  = 1
    case centered                               = 2
}


/*
    Word file record types.
    NOTE We require raw values for these, to match to record type bytes.
*/
public enum PsionWordRecordType: Int {

    case fileInfo                               = 1
    case printerConfig                          = 2
    case printerDriver                          = 3
    case headerText                             = 4
    case footerText                             = 5
    case styleDefinition                        = 6
    case emphasisDefinition                     = 7
    case bodyText                               = 8
    case blockInfo                              = 9
    case unknown                                = 99
}


/*
    Markdown formatting record.

    FROM 0.4.0
 */
struct MarkdownToken {

    var text: String                            = ""
    var delimiter: Character?                   = nil
    var count: Int                              = 0
    var canOpen: Bool                           = false
    var canClose: Bool                          = false
    var opens: [Int]                            = []
    var closes: [Int]                           = []
}


/*
    Internal conversion node to which all external source, currently
    Word 3, Plain Text and Markdown. The focus is on Word 3, but other
    items may need to be added if Word 5 support is brought on board.

    FROM 0.5.0
 */
public struct Document {

    var header: Paragraph?                      = nil
    var footer: Paragraph?                      = nil
    var paragraphs: [Paragraph]                 = []
}


/*
    Internal conversion paragraph entity. Word 3 focused for now.

    FROM 0.5.0
 */
struct Paragraph {

    var type: ParagraphType                     = .body                 // Styling
    var spans: [Span]                           = []                    // Array of text units, each of one or no empahsis
    var word3Style: PsionWordStyle?             = nil                   // Word 3 Style name, if set
}


/*
    Internal conversion text span entity. A span is a unit of text with zero or
    more emphases (bold, italic, etc.).

    The `markdowwn` computed property returns the Span text with embedded
    Markdown formatting (see below).

    FROM 0.5.0
 */
struct Span {

    var type: SpanType                          = .normal
    var text: String                            = ""


    /*
     The span's text with Markdown emphasis markers applied.

     Leading and trailing whitespace is placed outside the markers, as Markdown
     won't recognise, say, `** bold**` as emphasis. Whitespace-only text gets no markers.

     NOTE Markdown has no underline, superscript or subscript, so these
          emphases are not marked. Strikethrough uses the GFM `~~` extension. This may
          not be used by all Markdown parsers/previewers.
     */
    var markdown: String {

        var marker = ""
        if self.type.contains(.bold) {
            marker += "**"
        }

        if self.type.contains(.italic) {
            marker += "*"
        }

        let strike = self.type.contains(.strikethrough) ? "~~" : ""

        // Nothing to mark?
        let core = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (marker.isEmpty && strike.isEmpty) || core.isEmpty {
            return self.text
        }

        // Separate the leading and trailing whitespace from the core text
        let leading = self.text.prefix(while: { $0.isWhitespace })
        let trailing = String(self.text.reversed().prefix(while: { $0.isWhitespace }).reversed())
        return "\(leading)\(strike)\(marker)\(core)\(marker)\(strike)\(trailing)"
    }
}


/*
    An internal conversion paragraph entity's style, with a focus on Markdown output.

    Levels are 1-based and should be kept in the range 1-6 when Paragraphs are created.
    Headers and footers are not types: their role comes from where they are stored in
    a Document.

    FROM 0.5.0
*/
public enum ParagraphType: Equatable {

    case body
    case heading(level: Int)                                            // 1-6
    case bulletItem(level: Int, bullet: Character?)                     // 1-6; bullet taken from the source text, if any
    case numberItem(level: Int, number: Int?)                           // 1-6; number taken from the source text, if any


    /*
     For list items, whether the list is bulleted and the item's level; `nil` for other types
     */
    var listItem: (isBullet: Bool, level: Int)? {
        switch self {
            case .bulletItem(let level, _):
                return (true, level)
            case .numberItem(let level, _):
                return (false, level)
            case .body, .heading:
                return nil
        }
    }
}


/*
    An internal conversion span entity's character-level emphasis.

    An OptionSet, so emphases can be combined, eg. `[.bold, .underline]`.
    An empty set is normal text.
    Word 3 supports underline, bold, italic, superscript and subscript; Word 5 adds strikethrough.

    FROM 0.5.0
*/
public struct SpanType: OptionSet, Hashable {

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let bold                      = SpanType(rawValue: 1 << 0)
    public static let italic                    = SpanType(rawValue: 1 << 1)
    public static let underline                 = SpanType(rawValue: 1 << 2)
    public static let strikethrough             = SpanType(rawValue: 1 << 3)
    public static let superScript               = SpanType(rawValue: 1 << 4)
    public static let subScript                 = SpanType(rawValue: 1 << 5)

    // Convenience combinations
    public static let normal: SpanType          = []
    public static let boldItalic: SpanType      = [.bold, .italic]
}


/*
    Additional date required for conversion to Word 3 files.

    Includes footer and header format strings, and
    the printer driver library recorded in the file. Word takes its available fonts
    from this driver, so it must be one the target device has. If it isn't, Word
    falls back to fixed-pitch Courier when the file is opened. Defaults to the
    Series 3a ROM's Canon BubbleJet driver.

    FROM 0.5.0
 */
public struct Word3Data {

    public var header: String                   = ""                    // Format string
    public var footer: String                   = "%P"                  // Format string
    public var printerDriver: String            = "ROM::BJ.WDR"         // Driver name in Psion Series 3 ROM.


    public init() {

    }

    public init(header: String, footer: String, printerDriver: String) {

        self.header = header
        self.footer = footer
        self.printerDriver = printerDriver
    }
}
