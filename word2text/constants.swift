/*
    word2text
    constants.swift

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
    Constants used in the description of Psion Word files.
*/
public struct PsionWord3Constants {

    static let BlockUnitLength: Int                 = 6
    static let RecordHeaderLength: Int              = 4
    static let RecordTypes: [String]                = [
        "FILE INFO",
        "PRINTER CONFIG",
        "PRINTER DRIVER INFO",
        "HEADER TEXT",
        "FOOTER TEXT",
        "STYLE DEFINITION",
        "EMPHASIS DEFINITION",
        "BODY TEXT",
        "STYLE APPLICATION"
    ]

    static let PreambleLength                       = 16
    static let HeaderLength                         = 40
    static let FileInfoRecordLength                 = 10
    static let PrinterConfigRecordLength            = 58
    static let StyleRecordLength                    = 80
    static let EmphasisRecordLength                 = 28

    static let ParagraphMarker                      = 0
    static let EncryptionMarker                     = 256
    static let RecordTotal                          = 1022

    static let PreambleBytesLastIndex               = PreambleLength - 1
    static let EncryptionBytesFirstIndex            = 16
    static let EncryptionBytesLastIndex             = 18

    // FROM 0.4.1
    // Lists: Word has no list levels or automatic bullets, so each level of a Markdown list
    // gets its own style (with a deeper hanging indent) and the bullet or number is placed in
    // the text, followed by a tab. Levels deeper than `ListLevelMax` use the deepest style.
    static let ListLevelMax: Int                    = 6
    // Indents, in 1/20 points. Level 1 matches Word's own Bulleted list style: text at 0.5in,
    // bullet a hanging 0.25in to the left. Each further level adds `ListIndentStep`.
    // NOTE Word displays no first line further right than 2880 (2in), whatever the style says,
    //      so the deepest level's bullet must stay within that: 720 - 360 + 5 * 480 = 2760
    static let ListBaseIndent: Int                  = 720
    static let ListHangingIndent: Int               = 360
    static let ListIndentStep: Int                  = 480
    static let BulletListCodes: [String]            = ["BL", "B2", "B3", "B4", "B5", "B6"]
    static let NumberListCodes: [String]            = ["NL", "N2", "N3", "N4", "N5", "N6"]
    // Bullets cycle through these by level: middle dot, black square, currency sign
    static let ListBullets: [String]                = ["\u{00B7}", "\u{25A0}", "\u{00A4}"]


    /**
     Get the list type and level of a style code.

     - Parameters:
        - code: A Word 3 style code.

     - Returns: `isBullet` (`true` for bulleted, `false` for numbered) and `level` (1-based), or `nil` if the code is not a list style.
     */
    static func listInfo(_ code: String) -> (isBullet: Bool, level: Int)? {

        if let index = BulletListCodes.firstIndex(of: code) {
            return (true, index + 1)
        }

        if let index = NumberListCodes.firstIndex(of: code) {
            return (false, index + 1)
        }

        return nil
    }
}
