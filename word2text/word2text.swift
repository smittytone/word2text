/*
    word2text
    word2text.swift

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
import Clicore


/**
    Main entry point
 */
@main
struct Word2Text {

    public static func main() async throws {

        // Make sure the signal does not terminate the application
        Stdio.enableCtrlHandler("word2text interrupted -- halting")

        // FROM 0.4.0
        var settings = Settings()
#if os(macOS)
        // Use emoji markers on macOS
        Stdio.settings.useEmoji = true
#endif

        // No arguments? Show Help
        if CommandLine.arguments.count == 1 {
            showHelp()
            Stdio.exitApp()
        }

        // Expand composite flags
        let collatedArguments = Cli.unify(args: CommandLine.arguments)

        // Process the (separated) arguments
        var files: [String] = []
        var argIsAValue = false
        var argCount = 0
        var previousArgument = ""
        for argument in collatedArguments {
            if argIsAValue {
                // Make sure we're not reading in an option rather than a value
                if argument.prefix(1) == "-" {
                    Stdio.reportErrorAndExit("Missing value for \(previousArgument)")
                }

                argIsAValue = false
            } else {
                switch argument {
                    case "-f", "--force":
                        settings.forceWrite = true
                    case "-m", "--markdown":
                        settings.returnMarkdown = true
                    case "-s", "--stop":
                        settings.haltOnFirstError = true
                    case "-r", "--reverse":
                        settings.reverseConversion = true
                    case "-o", "--outer":
                        settings.word3.includeHeaders = true
                    case "-c", "--compatiblename":
                        settings.word3.fixName = true
                    case "-v", "--verbose":
                        settings.showInfo = true
                    case "--stdout":
                        settings.outputAsFile = false
                    case "-h", "-help", "--help":
                        showHelp()
                        Stdio.exitApp()
                    case "--version":
                        showHeader()
                        Stdio.exitApp()
                    default:
                        if argument.prefix(1) == "-" {
                            Stdio.reportErrorAndExit("Unknown argument: \(argument)")
                        } else {
                            files.append(argument)
                        }
                }

                previousArgument = argument
            }

            argCount += 1

            // Trap commands that come last and therefore have missing args
            if argCount == CommandLine.arguments.count && argIsAValue {
                Stdio.reportErrorAndExit("Missing value for \(argument)")
            }
        }

        // Pre-process the file list looking for directories.
        // We also take the time to rationalise the paths of passed files
        settings.files = processPaths(files, settings.reverseConversion)
        if settings.files.count == 0 {
            let errorMessage = settings.reverseConversion ? "No Markdown files passed for conversion" : "No Psion Word files passed for conversion"
            Stdio.reportErrorAndExit(errorMessage)
        }

        // FROM 0.4.0 -- check we have extant files
        settings.files = checkFiles(settings.files)
        if settings.files.count == 0 {
            let errorMessage = settings.reverseConversion ? "No Markdown files located for conversion" : "No Psion Word files located for conversion"
            Stdio.reportErrorAndExit(errorMessage)
        }

        // Convert the file(s) to text/markdown
        processFiles(settings)

        // All done -- exit gracefully
        Stdio.exitApp()
    }


    /**
     Convert paths into absolutes, resolving passed directory paths
     as we go.

     - Parameters:
        - paths:   An array of paths as passed via the command line.
        - toPsion: Are we converting to .WRD not from it? Default: `false`.

     - Returns: An array of absolute paths to `WRD` files.
     */
    internal static func processPaths(_ paths: [String], _ toPsion: Bool = false) -> [String] {

        let supportedExtensions = toPsion ? ["TEXT", "TXT", "MD", "MARKDOWN", "MDOWN"] : ["WRD"]
        var validFiles: [String] = []
        for path in paths {
            let absolutePath = Path.getFullPath(path)
            if Path.doesPathReferenceDirectory(absolutePath) {
                // `absolutePath` references a directory so get the file list from it
                let directoryContentsEnumerator = FileManager.default.enumerator(atPath: absolutePath)
                while let file = directoryContentsEnumerator?.nextObject() as? String {
                    let extn = (file as NSString).pathExtension.uppercased()
                    if supportedExtensions.contains(extn) {
                        validFiles.append(absolutePath + "/" + file)
                    }
                }
            } else {
                // `absolutePath` references a file, so check its extension
                let extn = (absolutePath as NSString).pathExtension.uppercased()
                if supportedExtensions.contains(extn) {
                    validFiles.append(absolutePath)
                } else {
                    Stdio.reportWarning("\(path) is not of the correct type -- it will not be processed")
                }
            }
        }

        return validFiles
    }


    /**
     Check the existence of each file in a list of paths.

     FROM 0.4.0

     - Parameters:
        - files: Array of paths to check.

     - Returns: An array of extant files. Empty on error.
     */
    private static func checkFiles(_ files: [String]) -> [String] {

        var validFiles: [String] = []
        for file in files {
            if FileManager.default.fileExists(atPath: file) {
                validFiles.append(file)
            } else {
                Stdio.reportError("File \(file) cannot be located -- it will be ignored")
            }
        }

        return validFiles
    }


    /**
     Process a sequence of Psion WRD or Text/Markdown files.

     - Parameters:
        - settings: The processing preferences.
     */
    private static func processFiles(_ settings: Settings) {

        for filepath in settings.files {
            switch Path.getFileData(filepath) {
                case .failure(let error):
                    Stdio.reportError(error.localizedDescription)
                case .success(let filedata):
                    if settings.reverseConversion {
                        // Convert text or Markdown to WRD
                        guard let sourceText = String(bytes: filedata, encoding: .utf8) else {
                            outputWord(.failure(ProcessError(code:.fileNotUTF8)), settings, filepath)
                            continue
                        }

                        // FROM 0.5.0 -- Check file extension
                        let sourceType: ContentType = (filepath as NSString).pathExtension.uppercased().hasPrefix("T") ? .plainText : .markdown

                        let result: DataResult = !filedata.isEmpty
                        ? PsionWord.encodeWord3(using: sourceText, ofType: sourceType, settings)
                        : .failure(ProcessError(code: .fileEmpty))
                        outputWord(result, settings, filepath)
                    } else {
                        // Convert WRD to text or Markdown
                        let result: StringResult = !filedata.isEmpty
                        ? PsionWord.decodeWord3(using: filedata, settings)
                        : .failure(ProcessError(code: .fileEmpty))
                        outputText(result, settings, filepath)
                    }
            }
        }
    }


    /**
     Output the result of a Text/Markdown to Psion Word conversion.

     FROM 0.4.0

     - Parameters:
        - result:         The result of the conversion operation.
        - settings:       Conversion preferences.
        - sourceFilePath: The path of the source file, for reporting.
     */
    private static func outputWord(_ result: DataResult, _ settings: Settings, _ sourceFilePath: String) {

        switch result {
            case .failure(let error):
                let errorMessage = "File \(sourceFilePath) could not be converted: \(error.localizedDescription)"
                if settings.haltOnFirstError {
                    Stdio.reportErrorAndExit(errorMessage, Int32(error.code.rawValue))
                } else {
                    Stdio.reportWarning(errorMessage)
                }
            case .success(let fileData):
                // Output to a file: generate the name and extension
                let outFilePath = checkWord3Filename(sourceFilePath, settings.word3.fixName)
                if FileManager.default.fileExists(atPath: outFilePath) {
                    if !settings.forceWrite {
                        let errorMessage = "File \(outFilePath) already exists -- use `--force` to overwrite"
                        let errCode: ProcessErrorKind = .fileAlreadyExists
                        if settings.haltOnFirstError {
                            Stdio.reportErrorAndExit(errorMessage, Int32(errCode.rawValue))
                        } else {
                            Stdio.reportWarning(errorMessage)
                        }
                        return
                    } else {
                        Stdio.reportWarning("File \(outFilePath) already exists -- overwriting (`--force` flag set)")
                    }
                }

                let outFileURL = URL(fileURLWithPath: outFilePath)
                do {
                    try fileData.write(to: outFileURL)
                    if settings.showInfo {
                        Stdio.report("File \(sourceFilePath) converted to \(outFilePath)")
                    }
                } catch {
                    let errorMessage = "File \(outFilePath) could not be written"
                    if settings.haltOnFirstError {
                        Stdio.reportErrorAndExit(errorMessage)
                    } else {
                        Stdio.reportError(errorMessage)
                    }
                }
        }
    }


    /**
     Output the result of a Psion Word to Text/Markdown conversion.

     FROM 0.4.0

     - Parameters:
        - result:         The result of the conversion operation.
        - settings:       Conversion preferences.
        - sourceFilePath: The path of the source file, for reporting.
     */
    private static func outputText(_ result: StringResult, _ settings: Settings, _ sourceFilePath: String) {

        switch result {
            case .failure(let error):
                let errorMessage = "File \(sourceFilePath) could not be converted: \(error.localizedDescription)"
                if settings.haltOnFirstError {
                    Stdio.reportErrorAndExit(errorMessage, Int32(error.code.rawValue))
                } else {
                    Stdio.reportWarning(errorMessage)
                }
            case .success(let processedText):
                // Report the processed text
                if !settings.outputAsFile {
                    // Output processed text to STDOUT so it's available for piping or redirection
                    if settings.showInfo {
                        Stdio.report("File \(sourceFilePath) converted")
                    }

                    Stdio.output(processedText)
                } else {
                    // Output to a file: generate the name and extension...
                    var outFilePath = (sourceFilePath as NSString).deletingPathExtension
                    outFilePath += settings.returnMarkdown ? ".md" : ".txt"
                    if FileManager.default.fileExists(atPath: outFilePath) && !settings.forceWrite {
                        Stdio.reportWarning("File \(outFilePath) already exists -- use `--force` to overwrite")
                        return
                    }

                    do {
                        try processedText.write(toFile: outFilePath, atomically: true, encoding: .utf8)
                        if settings.showInfo {
                            Stdio.report("File \(sourceFilePath) converted to \(outFilePath)")
                        }
                    } catch {
                        Stdio.reportWarning("File \(outFilePath) could not be written: writing to stdout instead:")
                        Stdio.output(processedText)
                    }
                }
        }
    }


    /**
     Check a proposed output filename meets the Psion 3 specification. Optionally, convert an
     incompatible name to one that is, i.e., up to eight ASCII letters (A-Z) or digits (0-9),
     with no initial digit. Accented letters are converted to their unaccented equivalents.
     A name with no allowed characters becomes `DOCUMENT`.

     FROM 0.5.0

     - Parameters:
        - path: The output file's full path.
        - fixName: Convert the name if `true`, otherwise issue a warning.

     - Returns: A converted name suffixed `.WRD`. The filename will always be uppercase.
     */
    internal static func checkWord3Filename(_ path: String, _ fixName: Bool) -> String {

        var outFileURL = URL(fileURLWithPath: path).deletingPathExtension()
        let sourceName = outFileURL.lastPathComponent
        var name = outFileURL.lastPathComponent.uppercased()
        var lastChange = ""

        // Word 3 filenames may only contain the ASCII letters A-Z and digits 0-9.
        // NOTE `CharacterSet.alphanumerics` and `.decimalDigits` are not used as they
        //      include non-ASCII letters and digits, eg. `É` and `١`
        let isAllowed: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let isDigit: (Character) -> Bool = { $0.isASCII && $0.isNumber }

        if !name.allSatisfy(isAllowed) {
            if fixName {
                // Replace accented letters with their unaccented equivalents, eg. `É` becomes `E`,
                // then remove any remaining disallowed characters
                name = name.folding(options: .diacriticInsensitive, locale: nil).filter(isAllowed)
                lastChange = "removing characters from name"
            } else {
                lastChange = "rename before transferring to your device"
            }

            Stdio.reportWarning("The output filename (\(sourceName)) contains non-alphanumeric characters, which is not allowed by Word 3 -- \(lastChange)")
        }

        if let first = name.first, isDigit(first) {
            if fixName {
                // Remove the leading digits only: digits later in the name are allowed
                name = String(name.drop(while: isDigit))
                lastChange = "removing numbers from start of name"
            } else {
                lastChange = "rename before transferring to your device"
            }

            Stdio.reportWarning("The output filename (\(sourceName)) starts with a number, which is not allowed by Word 3 -- \(lastChange)")
        }

        if name.count > 8 {
            if fixName {
                name = String(name.prefix(8))
                lastChange = "truncating name"
            } else {
                lastChange = "truncate before transferring to your device"
            }

            Stdio.reportWarning("The output filename (\(sourceName)) is longer than the 8.3 format allowed by Word 3 -- \(lastChange)")
        }

        // Fixing may have removed every character, eg. from `2024` or `---`
        if fixName && name.isEmpty {
            name = "DOCUMENT"
            Stdio.reportWarning("The output filename has no characters allowed by Word 3 -- using \(name).WRD")
        }

        outFileURL = outFileURL.deletingLastPathComponent()
        if #available(macOS 13, *) {
            return outFileURL.appending(component: "\(name).WRD", directoryHint: .notDirectory).path
        } else {
            return outFileURL.path + "/\(name).WRD"
        }
    }

}
