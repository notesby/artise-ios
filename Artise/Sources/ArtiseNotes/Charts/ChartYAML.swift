//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A value in a chart file, as far as chart files go: text, lists and fields, block or flow style
/// (`[a, b]`, `{k: v}`). Enough to read what Ari and people write; anything else is "can only be edited as text".
public indirect enum YAMLValue: Equatable, Sendable {
    /// Plain or quoted text; `quoted` keeps `'2026'` a label rather than a number.
    case scalar(String, quoted: Bool)
    case list([YAMLValue])
    case map([YAMLEntry])
    
    public static let null = YAMLValue.scalar("", quoted: false)
    
    /// The text of a scalar; `nil` for a list or fields.
    public var text: String? {
        if case .scalar(let text, let quoted) = self {
            return quoted || !["~", "null", "Null", "NULL"].contains(text) ? text : ""
        }
        return nil
    }
    
    public var list: [YAMLValue]? {
        if case .list(let items) = self {
            return items
        }
        return nil
    }
    
    public var entries: [YAMLEntry]? {
        if case .map(let entries) = self {
            return entries
        }
        return nil
    }
    
    public subscript(key: String) -> YAMLValue? {
        entries?.last { $0.key == key }?.value
    }
    
    /// A scalar as a table cell: a plain number (or one written "1,200") is a number, anything else a label.
    public var cell: ChartCell {
        guard case .scalar(let text, let quoted) = self else { return .text("") }
        if !quoted, let number = YAMLValue.number(text) {
            return .number(number)
        }
        if quoted, let number = YAMLValue.number(text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: " ", with: "")) {
            // The server reads "1,200" and "$1,200.50" as numbers too.
            return .number(number)
        }
        return .text(self.text ?? "")
    }
    
    /// `12000`, `-3.5`, `1_000`, `1,200` (thousands): a number. Anything else, `nil`.
    static func number(_ text: String) -> Double? {
        var plain = text.trimmingCharacters(in: .whitespaces)
        if plain.range(of: #"^-?\d{1,3}(,\d{3})+(\.\d+)?$"#, options: .regularExpression) != nil {
            plain = plain.replacingOccurrences(of: ",", with: "")
        }
        plain = plain.replacingOccurrences(of: "_", with: "")
        guard plain.range(of: #"^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Double(plain)
    }
}

public struct YAMLEntry: Equatable, Sendable {
    public let key: String
    public let value: YAMLValue
    
    public init(_ key: String, _ value: YAMLValue) {
        self.key = key
        self.value = value
    }
}

/// Why a chart file can't be read as fields.
public struct YAMLError: Error, Equatable, Sendable {
    /// From 1.
    public let line: Int
    public let reason: String
}

/// Reads and writes the YAML of chart files. Not a general YAML library: no anchors, tags, block scalars or multiple
/// documents, which chart files never need. What it can't read, it says so, and the editor offers the file as text.
public enum ChartYAML {
    // MARK: - Reading
    
    /// The fields of a file whose top level is fields.
    public static func parse(_ text: String) throws(YAMLError) -> [YAMLEntry] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated().map { Line(number: $0.offset + 1, raw: $0.element) }
        var reader = BlockReader(lines: lines.filter { !$0.isTrivia })
        guard !reader.isAtEnd else { return [] }
        guard case .map(let entries) = try reader.block(indent: 0) else {
            throw YAMLError(line: 1, reason: "the file should be fields, one per line")
        }
        if let extra = reader.current {
            throw YAMLError(line: extra.number, reason: "unexpected indentation")
        }
        return entries
    }
    
    /// One value written on one line: `abc`, `"a, b"`, `[1, 2]`, `{k: v}`.
    public static func parseInline(_ text: String, line: Int = 1) throws(YAMLError) -> YAMLValue {
        var flow = FlowReader(text: Array(text), line: line)
        let value = try flow.value(inFlow: false)
        flow.skipSpaces()
        guard flow.isAtEnd else {
            throw YAMLError(line: line, reason: "unexpected text after a value")
        }
        return value
    }
    
    struct Line {
        let number: Int
        let raw: String
        
        var indent: Int {
            raw.prefix { $0 == " " }.count
        }
        
        /// The line without its indentation and its comment.
        var content: String {
            Self.stripComment(String(raw.dropFirst(indent))).trimmingCharacters(in: .whitespaces)
        }
        
        var isTrivia: Bool {
            content.isEmpty
        }
        
        /// A `#` that starts the line or follows a space, outside quotes, starts a comment.
        static func stripComment(_ text: String) -> String {
            var quote: Character?
            var previous: Character = " "
            for (offset, character) in text.enumerated() {
                if let open = quote {
                    if character == open {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#", previous == " " || previous == "\t" {
                    return String(text.prefix(offset))
                }
                previous = character
            }
            return text
        }
    }
    
    /// Reads indented blocks: fields (`key: value`) and lists (`- item`).
    struct BlockReader {
        var lines: [Line]
        var index = 0
        
        init(lines: [Line]) {
            self.lines = lines
        }
        
        var isAtEnd: Bool {
            index >= lines.count
        }
        
        var current: Line? {
            isAtEnd ? nil : lines[index]
        }
        
        mutating func block(indent: Int) throws(YAMLError) -> YAMLValue {
            guard let first = current else { return .null }
            if first.raw.contains("\t") && first.raw.prefix(first.indent + 1).contains("\t") {
                throw YAMLError(line: first.number, reason: "tabs can't indent")
            }
            return first.content == "-" || first.content.hasPrefix("- ") ? try list(indent: first.indent) : try map(indent: first.indent)
        }
        
        private mutating func list(indent: Int) throws(YAMLError) -> YAMLValue {
            var items: [YAMLValue] = []
            while let line = current, line.indent == indent, line.content == "-" || line.content.hasPrefix("- ") {
                index += 1
                let rest = String(line.content.dropFirst()).trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    try items.append(nested(deeperThan: indent))
                } else if rest == "-" || rest.hasPrefix("- ") {
                    // `- - a`: a list inside the list, its other items under it.
                    lines.insert(Line(number: line.number, raw: String(repeating: " ", count: indent + 2) + rest), at: index)
                    try items.append(list(indent: indent + 2))
                } else if Self.keyAndRest(rest) != nil, !rest.hasPrefix("["), !rest.hasPrefix("{"), !rest.hasPrefix("\""), !rest.hasPrefix("'") {
                    // `- key: value` and its other fields under it.
                    let itemIndent = indent + 2
                    var entries = try fields(Line(number: line.number, raw: String(repeating: " ", count: itemIndent) + rest), indent: itemIndent)
                    if let next = current, next.indent == itemIndent, !next.content.hasPrefix("- ") {
                        guard case .map(let more) = try map(indent: itemIndent) else { break }
                        entries += more
                    }
                    items.append(.map(entries))
                } else {
                    try items.append(inline(rest, line: line))
                }
            }
            return .list(items)
        }
        
        private mutating func map(indent: Int) throws(YAMLError) -> YAMLValue {
            var entries: [YAMLEntry] = []
            while let line = current, line.indent == indent {
                if line.content.hasPrefix("- ") || line.content == "-" {
                    throw YAMLError(line: line.number, reason: "a list item where a field was expected")
                }
                index += 1
                entries += try fields(line, indent: indent)
            }
            if let line = current, line.indent > indent {
                throw YAMLError(line: line.number, reason: "unexpected indentation")
            }
            return .map(entries)
        }
        
        /// One `key: value` line, with its value's block when the value starts on the next lines.
        private mutating func fields(_ line: Line, indent: Int) throws(YAMLError) -> [YAMLEntry] {
            guard let (key, rest) = Self.keyAndRest(line.content) else {
                throw YAMLError(line: line.number, reason: "a field should be written name: value")
            }
            if rest.isEmpty {
                // Its value is the block under it; a list may sit at the key's own indentation.
                if let next = current, next.indent == indent, next.content.hasPrefix("- ") || next.content == "-" {
                    return try [YAMLEntry(key, list(indent: indent))]
                }
                return try [YAMLEntry(key, nested(deeperThan: indent))]
            }
            return try [YAMLEntry(key, inline(rest, line: line))]
        }
        
        private mutating func nested(deeperThan indent: Int) throws(YAMLError) -> YAMLValue {
            guard let next = current, next.indent > indent else { return .null }
            return try block(indent: next.indent)
        }
        
        /// A flow value may go on over the next lines until its brackets close.
        private mutating func inline(_ text: String, line: Line) throws(YAMLError) -> YAMLValue {
            var text = text
            while Self.isOpenFlow(text), let next = current {
                index += 1
                text += " " + next.content
            }
            return try ChartYAML.parseInline(text, line: line.number)
        }
        
        static func isOpenFlow(_ text: String) -> Bool {
            guard text.hasPrefix("[") || text.hasPrefix("{") else { return false }
            var depth = 0
            var quote: Character?
            for character in text {
                if let open = quote {
                    if character == open {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "[" || character == "{" {
                    depth += 1
                } else if character == "]" || character == "}" {
                    depth -= 1
                }
            }
            return depth > 0
        }
        
        /// `key: rest` (or `key:`), the key unquoted; `nil` when the line isn't a field.
        static func keyAndRest(_ content: String) -> (String, String)? {
            var flow = FlowReader(text: Array(content), line: 0)
            guard let key = try? flow.scalar(inFlow: false, stopAtColon: true), flow.consume(":") else { return nil }
            guard flow.isAtEnd || flow.peek == " " else { return nil }
            let rest = String(flow.text[flow.position...]).trimmingCharacters(in: .whitespaces)
            return (key.text ?? "", rest)
        }
    }
    
    /// Reads one line's value: a scalar, or a flow list or flow fields.
    struct FlowReader {
        let text: [Character]
        let line: Int
        var position = 0
        
        var isAtEnd: Bool {
            position >= text.count
        }
        
        var peek: Character? {
            isAtEnd ? nil : text[position]
        }
        
        mutating func skipSpaces() {
            while let character = peek, character == " " || character == "\t" {
                position += 1
            }
        }
        
        mutating func consume(_ character: Character) -> Bool {
            guard peek == character else { return false }
            position += 1
            return true
        }
        
        mutating func value(inFlow: Bool) throws(YAMLError) -> YAMLValue {
            skipSpaces()
            switch peek {
            case "[":
                position += 1
                var items: [YAMLValue] = []
                skipSpaces()
                if consume("]") {
                    return .list([])
                }
                while true {
                    try items.append(value(inFlow: true))
                    skipSpaces()
                    if consume("]") {
                        return .list(items)
                    }
                    guard consume(",") else { throw YAMLError(line: line, reason: "a list should be written [a, b, c]") }
                    skipSpaces()
                    if consume("]") {
                        return .list(items)
                    }
                }
            case "{":
                position += 1
                var entries: [YAMLEntry] = []
                skipSpaces()
                if consume("}") {
                    return .map([])
                }
                while true {
                    skipSpaces()
                    let key = try scalar(inFlow: true, stopAtColon: true)
                    skipSpaces()
                    guard consume(":") else { throw YAMLError(line: line, reason: "fields should be written {name: value}") }
                    let item = try value(inFlow: true)
                    entries.append(YAMLEntry(key.text ?? "", item))
                    skipSpaces()
                    if consume("}") {
                        return .map(entries)
                    }
                    guard consume(",") else { throw YAMLError(line: line, reason: "fields should be written {name: value}") }
                }
            default:
                return try scalar(inFlow: inFlow, stopAtColon: false)
            }
        }
        
        mutating func scalar(inFlow: Bool, stopAtColon: Bool) throws(YAMLError) -> YAMLValue {
            skipSpaces()
            if let quote = peek, quote == "\"" || quote == "'" {
                position += 1
                var result = ""
                while true {
                    guard let character = peek else { throw YAMLError(line: line, reason: "a quote isn't closed") }
                    position += 1
                    if character == quote {
                        // '' is a quote inside single quotes.
                        if quote == "'", peek == "'" {
                            position += 1
                            result.append("'")
                            continue
                        }
                        break
                    }
                    if quote == "\"", character == "\\", let escaped = peek {
                        position += 1
                        switch escaped {
                        case "n": result.append("\n")
                        case "t": result.append("\t")
                        case "u":
                            let hex = String(text[position..<min(position + 4, text.count)])
                            position += hex.count
                            if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                                result.unicodeScalars.append(scalar)
                            }
                        default: result.append(escaped)
                        }
                        continue
                    }
                    result.append(character)
                }
                return .scalar(result, quoted: true)
            }
            var result = ""
            while let character = peek {
                if inFlow, ",]}".contains(character) {
                    break
                }
                if stopAtColon || inFlow, character == ":" {
                    let next = position + 1 < text.count ? text[position + 1] : " "
                    if next == " " || (inFlow && ",]}".contains(next)) || (stopAtColon && position + 1 >= text.count) {
                        break
                    }
                }
                result.append(character)
                position += 1
            }
            return .scalar(result.trimmingCharacters(in: .whitespaces), quoted: false)
        }
    }
    
    // MARK: - Writing
    
    /// A value on one line, flow style: what `key: …` and `- …` take. A scalar is quoted when it says so: build text
    /// with `text(_:inFlow:)`, and numbers as plain scalars.
    public static func inline(_ value: YAMLValue) -> String {
        switch value {
        case .scalar(let text, let quoted):
            return quoted ? quote(text) : text
        case .list(let items):
            return "[" + items.map(flowItem).joined(separator: ", ") + "]"
        case .map(let entries):
            return "{" + entries.map { flowKey($0.key) + ": " + flowItem($0.value) }.joined(separator: ", ") + "}"
        }
    }
    
    private static func flowItem(_ value: YAMLValue) -> String {
        inline(value)
    }
    
    /// Text to write, quoted only when YAML would read it as something else (`"2026"`, `"yes"`, `"a: b"`).
    public static func text(_ text: String, inFlow: Bool) -> YAMLValue {
        .scalar(text, quoted: needsQuotes(text, inFlow: inFlow))
    }
    
    private static func flowKey(_ key: String) -> String {
        needsQuotes(key, inFlow: true) ? quote(key) : key
    }
    
    /// Text that YAML would read as something else (a number, true, a date, a list…) or can't hold plain.
    public static func needsQuotes(_ text: String, inFlow: Bool) -> Bool {
        if text.isEmpty || text != text.trimmingCharacters(in: .whitespaces) {
            return true
        }
        if let first = text.first, "-?:,[]{}#&*!|>'\"%@`".contains(first) {
            return true
        }
        if text.contains(": ") || text.contains(" #") || text.hasSuffix(":") || text.contains("\n") || text.contains("\t") {
            return true
        }
        if inFlow, text.contains(where: { ",[]{}".contains($0) }) {
            return true
        }
        let lower = text.lowercased()
        if ["true", "false", "yes", "no", "on", "off", "null", "~", "y", "n"].contains(lower) {
            return true
        }
        if YAMLValue.number(text) != nil || text.range(of: #"^\d{4}-\d{1,2}(-\d{1,2})?([Tt ].*)?$"#, options: .regularExpression) != nil {
            return true
        }
        return text.range(of: #"^[-+]?(\.inf|\.nan|0x[0-9a-f]+|0o[0-7]+)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    
    /// Double quotes, with `\` and `"` escaped.
    public static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
}
