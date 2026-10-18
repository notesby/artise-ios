//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// The editor works in UTF-16 offsets, like iOS text views (`NSRange`) and the Android app's editor,
// so a selection means the same thing everywhere.

extension String {
    var utf16Length: Int {
        utf16.count
    }
    
    /// The text between two UTF-16 offsets.
    func utf16Slice(_ from: Int, _ to: Int) -> String {
        let length = utf16Length
        let start = min(max(from, 0), length)
        let end = min(max(to, start), length)
        return NSString(string: self).substring(with: NSRange(location: start, length: end - start))
    }
    
    func utf16Slice(from: Int) -> String {
        utf16Slice(from, utf16Length)
    }
    
    /// The UTF-16 unit at `offset`, or `nil` outside the text.
    func utf16Unit(at offset: Int) -> UInt16? {
        guard offset >= 0, offset < utf16Length else { return nil }
        return utf16[utf16.index(utf16.startIndex, offsetBy: offset)]
    }
    
    /// Where the line holding `offset` starts: just after the newline before it.
    func lineStart(containing offset: Int) -> Int {
        var index = min(offset, utf16Length) - 1
        while index >= 0 {
            if utf16Unit(at: index) == newline {
                return index + 1
            }
            index -= 1
        }
        return 0
    }
    
    /// Where the line holding `offset` ends: at its newline, or the end of the text.
    func lineEnd(containing offset: Int) -> Int {
        var index = max(offset, 0)
        while index < utf16Length {
            if utf16Unit(at: index) == newline {
                return index
            }
            index += 1
        }
        return utf16Length
    }
    
    /// The line number (from 0) holding `offset`.
    func lineNumber(at offset: Int) -> Int {
        utf16Slice(0, offset).utf16.filter { $0 == newline }.count
    }
    
    func hasPrefix(_ prefix: String, atUTF16 offset: Int) -> Bool {
        utf16Slice(offset, offset + prefix.utf16Length) == prefix
    }
    
    /// The text with the UTF-16 range replaced.
    func replacingUTF16(_ from: Int, _ to: Int, with replacement: String) -> String {
        utf16Slice(0, from) + replacement + utf16Slice(from: to)
    }
}

private let newline = UInt16(UInt8(ascii: "\n"))

extension NSRegularExpression {
    /// The first match in `text`, in UTF-16 offsets.
    func firstMatch(in text: String) -> NSTextCheckingResult? {
        firstMatch(in: text, range: NSRange(location: 0, length: text.utf16Length))
    }
    
    func matches(in text: String) -> [NSTextCheckingResult] {
        matches(in: text, range: NSRange(location: 0, length: text.utf16Length))
    }
    
    /// A match starting exactly at `offset`, or `nil`.
    func match(in text: String, at offset: Int) -> NSTextCheckingResult? {
        guard offset <= text.utf16Length else { return nil }
        let match = firstMatch(in: text, options: .anchored, range: NSRange(location: offset, length: text.utf16Length - offset))
        return match?.range.location == offset ? match : nil
    }
    
    static func make(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            fatalError("Invalid pattern \(pattern): \(error)")
        }
    }
}

extension NSTextCheckingResult {
    /// The text of capture group `index`, or "" when it didn't take part.
    func group(_ index: Int, in text: String) -> String {
        let range = range(at: index)
        guard range.location != NSNotFound else { return "" }
        return text.utf16Slice(range.location, range.location + range.length)
    }
    
    var end: Int {
        range.location + range.length
    }
}
