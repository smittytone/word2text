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
        - wordData: The loaded Word 3 file bytes.
        - settings: Conversion parameters.

     - Returns: A Result containing the converted text (success) or a ProcessError embedding the error code (failure).
     */
    static public func decodeWord3(using wordData: Data, _ settings: Settings) -> StringResult {

        switch makeDocument(from: wordData, ofType: .word3, settings) {
            case .failure(let error):
                return .failure(error)
            case .success(let document):
                return convertToText(document, settings)
        }
    }


    /**
     Convert an individual Word file to plain text.

     DEPRECATED--Use `decodeWord3()` instead. Retained for TEMPORARY backwards compatibility.

     - Parameters:
        - data:     Data object containing the file bytes.
                    May be better to just pass a byte array.
        - filepath: Absolute path of the target Word file. Used for logging.
        - settings: File conversion parameters.

     - Returns: A Result containing the text (success) or a ProcessError embedding the error code (failure).
     */
    static public func processFile(_ data: ArraySlice<UInt8>, _ filepath: String = "", _ settings: Settings? = nil) -> StringResult {

        var compSettings = Settings()
        if settings != nil {
            compSettings = settings!
            if compSettings.includeHeaders {
                compSettings.word3.includeHeaders = true
            }
        }

        return decodeWord3(using: Data(data), compSettings)
    }


    /**
     Variation of the main `processFile()` to support passing in a Data object.

     DEPRECATED--Use `decodeWord3()` instead. Retained for TEMPORARY backwards compatibility.
     */
    static public func processFile(_ data: Data, _ settings: Settings? = nil, _ filepath: String = "") -> StringResult {

        var compSettings = Settings()
        if settings != nil {
            compSettings = settings!
            if compSettings.includeHeaders {
                compSettings.word3.includeHeaders = true
            }
        }

        return decodeWord3(using: data, compSettings)
    }

 }
