/*
    word2text
    convert_markdown.swift

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
    Generate a Psion Series 3 Word file from Markdown text.

    FROM 0.4.0
*/
extension PsionWord {

    // MARK: - Markdown/Plain Text to Word Entry Points

    /**
     Convert Markdown-formatted text into a Psion Series 3 Word document.
     See `README.md` for details of currently supported formatting.

     FROM 0.4.0

     - Parameters:
        - source:   The source text (plain or Markdown).
        - ofType:   The type of file we are converting from. Default: Markdown.
        - settings: Conversion settings.

     - Returns: A Result containing the Word 3 file's bytes (success) or a ProcessError (failure).
     */
    static public func encodeWord3(using sourceText: String, ofType sourceType: ContentType = .markdown, _ settings: Settings) -> DataResult {

        switch makeDocument(from: sourceText, ofType: sourceType, settings) {
            case .failure(let error):
                return .failure(error)
            case .success(var document):
                // Add generic footer and header text to the Document
                document.header = Paragraph(spans: [Span(text: "")])
                document.footer = Paragraph(spans: [Span(text: "%P")])
                return convertToWord3(document, settings)
        }
    }





    /**
     Convert Markdown-formatted text into a Psion Series 3 Word document.
     See `README.md` for details of currently supported formatting.

     DEPRECATED -- USE `encodeWord3()` instead. Temporarily retained for backwards compatibility.

     - Parameters:
        - markdown:      The Markdown source text.
        - header:        Page header text. Defaults to none, as in a new Series 3a document.
        - footer:        Page footer text. Defaults to Word's own default (`%P`: page number).
        - printerDriver: The printer driver library recorded in the file. Word takes its available fonts
                         from this driver, so it must be one the target device has. If it isn't, Word
                         falls back to fixed-pitch Courier when the file is opened. Defaults to the
                         Series 3a ROM's Canon BubbleJet driver.

        - Returns: A Result containing the Word file's bytes (success) or a ProcessError (failure).
     */
    static public func generateFile(fromMarkdown markdown: String, header: String = "", footer: String = "%P", printerDriver: String = "ROM::BJ.WDR") -> Result<Data, ProcessError> {

        var compSettings = Settings()
        compSettings.word3.printerDriver = printerDriver
        if compSettings.includeHeaders {
            compSettings.word3.includeHeaders = true
        }

        return encodeWord3(using: markdown, ofType: .markdown, Settings())
    }

}
