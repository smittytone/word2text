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
    Structure to hold a Psion Word 3 Style or Emphasis record.

    Not all of the fields are used by each type.
*/
public struct PsionWord3Style {

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
    Word file record types.
    NOTE We require raw values for these, to match to record type bytes.
*/
public enum PsionWord3RecordType: Int {

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
    Text section formatting information.
*/
public struct PsionWord3FormatBlock {

    public var startIndex: Int                          = 0              // Index into the raw text from Section 8 (first character)
    public var endIndex: Int                            = 0              // Index into the raw text from Section 8 (last character)
    public var styleCode: String                        = "BT"           // Span's Word 3 style code
    public var emphasisCode: String                     = "NN"           // Span's Word 3 emphasis code
    // FROM
    public var style: PsionWord3Style?                   = nil
    public var emphasis: PsionWord3Style?                = nil
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
    DISCARD BEFORE RELEASE

    Additional date required for conversion to Word 3 files.

    Includes footer and header format strings, and
    the printer driver library recorded in the file. Word takes its available fonts
    from this driver, so it must be one the target device has. If it isn't, Word
    falls back to fixed-pitch Courier when the file is opened. Defaults to the
    Series 3a ROM's Canon BubbleJet driver.

    FROM 0.5.0

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


public struct TextData {

    public var withOuter: Bool                  = false

    public init() {

    }

    public init(withOuter: Bool) {

        self.withOuter = withOuter
    }

}
*/
