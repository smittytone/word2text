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


public typealias StringResult = Result<String, ProcessError>
public typealias DataResult = Result<Data, ProcessError>
public typealias DocumentResult = Result<Document, ProcessError>


// MARK: - Internal Entities

/*
    Word file processing error codes.
    NOTE We require raw values for these, for output as stderr codes.
*/
public enum ProcessErrorKind: Int, Error {

    case noError                                        = 0
    // General file handling errors
    case fileAlreadyExists                              = 10
    case fileNotUTF8                                    = 11
    case fileEmpty                                      = 12
    // Conversion Errors
    case badConversionSource                            = 20
    case badConversionDestination                       = 21
    // Psion Word 3 Errors
    case badWord3FileType                               = 30
    case word3FileEncrypted                             = 31
    case badWord3RecordLengthFileInfo                   = 32
    case badWord3RecordLengthPrinterConfig              = 33
    case badWord3RecordLengthStyleDefinition            = 34
    case badWord3RecordLengthEmphasisDefinition         = 35
    case badWord3RecordType                             = 36
    case badWord3FileMissingRecords                     = 37
    case badWord3TextTooLong                            = 38
    case badWord3FileTruncated                          = 39
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
            // General File Errors
            case .fileEmpty:
                return "File not found"
            case .fileNotUTF8:
                return "Source file is not UTF-8"
            case .fileAlreadyExists:
                return "Output file already exists -- use `--force to overwrite"
            // Conversion Errors
            case .badConversionSource, .badConversionDestination:
                return "Incompatible input or output type selected"
            // Psion Word 3 Errors
            case .badWord3FileType:
                return "Not a Psion Series 3 Word file"
            case .word3FileEncrypted:
                return "Word file is encrypted"
            case .badWord3RecordLengthFileInfo,
                 .badWord3RecordLengthPrinterConfig,
                 .badWord3RecordLengthStyleDefinition,
                 .badWord3RecordLengthEmphasisDefinition,
                 .badWord3RecordType,
                 .badWord3FileTruncated:
                if let text = self.text {
                    return text
                } else {
                    return "Error message not provided"
                }
            case .badWord3FileMissingRecords:
                return "File did not include required records"
            case .badWord3TextTooLong:
                if let text = self.text {
                    return text
                } else {
                    return "Text too long for a Psion Word file (max. 64KB)"
                }
        }
    }
}


/**
 Word 3-specific settings

 FROM 0.5.0
 */
public struct Word3Settings {

    public var printerDriver: String        = "ROM::BJ.WDR"         // Driver name in Psion Series 3 ROM.
    public var includeHeaders: Bool         = false
    public var fixName: Bool                = false                 // if `true`, convert source text filename to Psion compatible one

    public init() {

    }
}


/*
    Configuration data for Word file processing operations.
*/
public struct Settings {

    public var showInfo: Bool               = false                 // Logging on or off
    public var includeHeaders: Bool         = false                 // Include header and footer text in Word 3 to text DEPRECATED
    public var haltOnFirstError: Bool       = false
    public var outputAsFile: Bool           = true                  // If `false`, write text to stdout
    public var returnMarkdown: Bool         = false                 // If `true`, create Markdown from Word 3, not plain text
    public var files: [String]              = []                    // List of paths of files to process
    // FROM 0.4.0
    public var reverseConversion: Bool      = false                 // Convert from text to Word
    public var forceWrite: Bool             = false                 // If `true`, overwrite exiting file(s)
    // FROM 0.5.0
    public var word3: Word3Settings         = Word3Settings()
    // FROM TBD
    public var jobs: [Conversion]           = []                    // UNUSED FOR NOW

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
    public var inputType: ContentType       = .word3
    public var outputType: ContentType      = .plainText
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
    var word3Style: PsionWord3Style?             = nil                   // Word 3 Style name, if set
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
