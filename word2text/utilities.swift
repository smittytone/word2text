/*
    word2text
    utilities.swift

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

    // MARK: Text Encoding

    /*
     Unicode equivalents of IBM Code Page 850 bytes 0x80-0xFF, the Series 3 character set
     */
    internal static let cp850UpperHalf: [Unicode.Scalar] = Array((
        "ÇüéâäàåçêëèïîìÄÅ" +
        "ÉæÆôöòûùÿÖÜø£Ø×ƒ" +
        "áíóúñÑªº¿®¬½¼¡«»" +
        "░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐" +
        "└┴┬├─┼ãÃ╚╔╩╦╠═╬¤" +
        "ðÐÊËÈıÍÎÏ┘┌█▄¦Ì▀" +
        "ÓßÔÒõÕµþÞÚÛÙýÝ¯´" +
        "\u{00AD}±‗¾¶§÷¸°¨·¹³²■\u{00A0}"
    ).unicodeScalars)

    internal static let cp850Lookup: [Unicode.Scalar: UInt8] = {
        var lookup: [Unicode.Scalar: UInt8] = [:]
        for (index, scalar) in cp850UpperHalf.enumerated() {
            lookup[scalar] = UInt8(0x80 + index)
        }

        return lookup
    }()


    /**
     Replace Word 3's special characters, which a Document holds as their Unicode equivalents,
     with plain ones, as plain text and Markdown don't need them.

     - Parameters:
        - text: The text to process.

     - Returns: The text with unbreakable spaces and hyphens made plain, and soft hyphens removed.
     */
    internal static func plainCharacters(_ text: String) -> String {

        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar {
                case "\u{00A0}":
                    // Unbreakable space
                    scalars.append(" ")
                case "\u{2011}":
                    // Unbreakable hyphen
                    scalars.append("-")
                case "\u{00AD}":
                    // Soft hyphen: only shown when a line breaks at it
                    continue
                default:
                    scalars.append(scalar)
            }
        }

        return String(scalars)
    }


    //MARK: - Common Document Functions

    /**
     Combine a paragraph's spans into a single text item.

     - Parameters:
        - spans:      An array of Spans.
        - toMarkdown: Include markdown formatting. Default: `false`.

     - Returns: The combined span.
    */
    internal static func combineSpans(_ spans: [Span], _ outputType: ContentType = .plainText) -> String {

        var spanText = ""
        for span in spans {
            spanText += outputType == .markdown ? span.markdown : span.text
        }

        return spanText
    }


    // MARK: - Misc.

    /**
     Output raw bytes as hex values.

     Required for debugging ONLY.
     */
    internal static func debugPrintBytes(_ data: ArraySlice<UInt8>) {

        var s = ""
        for byte in data {
            s += String(format: "%02X", byte)
        }

        print(s)
    }

}
