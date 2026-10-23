//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The kinds of chart the server draws.
public enum ChartType: String, CaseIterable, Hashable, Sendable {
    case bar
    case line
    case area
    case pie
    case donut
    case stacked
    case kpi
    case table
    
    /// Pie and donut show one series, never below zero.
    public var showsOneSeries: Bool {
        self == .pie || self == .donut
    }
}

/// One `where` filter of a sourced chart: records whose field has this value.
public struct ChartFilter: Hashable, Sendable {
    public var field: String
    public var value: String
    
    public init(field: String, value: String) {
        self.field = field
        self.value = value
    }
}

/// Where a sourced chart reads its numbers each time it's drawn (the chat's records, or a CSV in the notes).
public struct ChartSource: Hashable, Sendable {
    /// A record type (`payment`, `booking`…) or a CSV path.
    public var records: String
    public var filters: [ChartFilter]
    /// `last 6 months`, `this year`, `2026-Q3`, `from 2026-05-01`…
    public var period: String
    /// `day`, `week`, `month`, `quarter`, `year`, or a field.
    public var x: String
    /// `count`, or `sum(f)`, `avg(f)`, `min(f)`, `max(f)`.
    public var y: String
    /// One series per value of this field; empty for one series.
    public var group: String
    
    public init(records: String = "", filters: [ChartFilter] = [], period: String = "last 6 months", x: String = "month",
                y: String = "count", group: String = "") {
        self.records = records
        self.filters = filters
        self.period = period
        self.x = x
        self.y = y
        self.group = group
    }
    
    public static let periods = ["last 7 days", "last 30 days", "last 3 months", "last 6 months", "last 12 months",
                                 "this week", "this month", "this quarter", "this year"]
    public static let steps = ["day", "week", "month", "quarter", "year"]
    public static let aggregates = ["sum", "avg", "min", "max"]
}

/// A chart file as the editor's fields. The file's own text is kept: writing changes only the fields that changed,
/// so the order of the fields, the comments and the way the rest is written stay as they were.
public struct ChartDraft: Equatable, Sendable {
    public enum Mode: String, Hashable, Sendable {
        /// Its own numbers, in `data:`.
        case data
        /// Read from the chat's records each time, `source:`.
        case source
    }
    
    public var title: String
    /// As written: one the server doesn't know is caught by the checks.
    public var type: String
    public var unit: String
    public var caption: String
    /// `#RRGGBB`, one per series at most; the workspace's palette fills the rest.
    public var colors: [String]
    /// A kpi chart's change against the row before (`compare: previous`).
    public var comparesPrevious: Bool
    /// The columns drawn; empty draws every column after the labels.
    public var series: [String]
    public var mode: Mode
    /// The labels' column, then one per series.
    public var columns: [String]
    public var rows: [[ChartCell]]
    public var source: ChartSource
    
    public init(title: String = "", type: String = ChartType.bar.rawValue, unit: String = "", caption: String = "", colors: [String] = [],
                comparesPrevious: Bool = false, series: [String] = [], mode: Mode = .data, columns: [String] = [],
                rows: [[ChartCell]] = [], source: ChartSource = ChartSource()) {
        self.title = title
        self.type = type
        self.unit = unit
        self.caption = caption
        self.colors = colors
        self.comparesPrevious = comparesPrevious
        self.series = series
        self.mode = mode
        self.columns = columns
        self.rows = rows
        self.source = source
    }
    
    public var chartType: ChartType? {
        ChartType(rawValue: type.trimmingCharacters(in: .whitespaces).lowercased())
    }
    
    /// The columns that are drawn: `series`, else every column after the labels.
    public var drawnSeries: [String] {
        series.isEmpty ? Array(columns.dropFirst()) : series
    }
    
    // MARK: - Editing the table
    
    public mutating func addRow() {
        rows.append([.text("")] + Array(repeating: .number(0), count: max(columns.count - 1, 0)))
    }
    
    public mutating func addColumn(named name: String) {
        columns.append(name)
        for index in rows.indices {
            rows[index].append(.number(0))
        }
    }
    
    public mutating func removeColumn(at index: Int) {
        guard columns.indices.contains(index), columns.count > 2 else { return }
        let name = columns.remove(at: index)
        series.removeAll { $0 == name }
        for row in rows.indices where rows[row].indices.contains(index) {
            rows[row].remove(at: index)
        }
    }
    
    /// A renamed column stays drawn under its new name.
    public mutating func renameColumn(at index: Int, to name: String) {
        guard columns.indices.contains(index) else { return }
        let old = columns[index]
        columns[index] = name
        series = series.map { $0 == old ? name : $0 }
    }
    
    /// Cells copied from a spreadsheet (tabs between cells, a line per row) replace the table: the first line names the
    /// columns when its cells after the first aren't numbers. Numbers are read in `locale`'s way.
    public mutating func paste(_ text: String, locale: Locale) {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } }
        guard let width = lines.map(\.count).max(), width >= 2 else { return }
        lines = lines.map { $0 + Array(repeating: "", count: width - $0.count) }
        if let first = lines.first, first.dropFirst().allSatisfy({ ChartNumbers.parse($0, locale: locale) == nil }) {
            columns = first
            lines.removeFirst()
        } else if columns.count != width {
            columns = (0..<width).map { $0 == 0 ? "Label" : "Serie \($0)" }
        }
        rows = lines.map { cells in
            cells.enumerated().map { index, cell in
                index > 0 ? ChartNumbers.parse(cell, locale: locale).map(ChartCell.number) ?? .text(cell) : .text(cell)
            }
        }
        series = series.filter { columns.dropFirst().contains($0) }
    }
}

/// Numbers as people type them (`1,234.50` in Mexico, `1.234,50` in Brazil), always written plain in the file
/// (`1234.5`).
public enum ChartNumbers {
    public static func parse(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }
        // A plain number (`1234.5`) reads in any language.
        return YAMLValue.number(trimmed)
    }
    
    /// A number as `locale` writes it, without grouping, for the grid: `1234,5` in Brazil.
    public static func format(_ number: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: number)) ?? ChartCell.plain(number)
    }
}

/// What's wrong with a draft, checked as the server checks a chart before saving it (`chartspec.py`), in the same
/// order, so the person can't save a chart that can't be drawn.
public enum ChartProblem: Equatable, Sendable {
    case title
    case titleTooLong
    case unknownType(String)
    case compareNotKPI
    case badColor(String)
    case source
    /// Fewer than two columns.
    case columns
    /// A column without a name, or two with one name.
    case names
    case noRows
    case tooManyRows(Int)
    /// Row (from 1) with a different number of cells than the columns.
    case rowLength(row: Int, expected: Int)
    case tooManySeries(Int)
    case unknownSeries(String)
    case oneSeries(type: String, count: Int)
    /// Row (from 1), column, and what's there.
    case notANumber(row: Int, column: String, value: String)
    case negative(type: String)
    case tooBig
}

public enum ChartChecks {
    public static let maxSeries = 8
    public static let maxRows = 500
    public static let maxBytes = 64 * 1024
    public static let maxTitle = 120
    
    /// The first problem, as the server would name it; `nil` when the chart can be drawn.
    public static func problem(_ draft: ChartDraft, fileText: String? = nil) -> ChartProblem? {
        if let fileText, fileText.utf8.count > maxBytes {
            return .tooBig
        }
        guard let type = draft.chartType ?? (draft.type.trimmingCharacters(in: .whitespaces).isEmpty ? .bar : nil) else {
            return .unknownType(draft.type)
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return .title
        }
        if title.count > maxTitle {
            return .titleTooLong
        }
        if draft.comparesPrevious, type != .kpi {
            return .compareNotKPI
        }
        if let bad = draft.colors.first(where: { $0.trimmingCharacters(in: .whitespaces).range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil }) {
            return .badColor(bad)
        }
        if draft.mode == .source {
            let source = draft.source
            return [source.records, source.period, source.x, source.y].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty } ? .source : nil
        }
        let columns = draft.columns.map { $0.trimmingCharacters(in: .whitespaces) }
        if columns.count < 2 {
            return .columns
        }
        if columns.contains(where: \.isEmpty) || Set(columns).count != columns.count {
            return .names
        }
        if draft.rows.isEmpty {
            return .noRows
        }
        if draft.rows.count > maxRows {
            return .tooManyRows(draft.rows.count)
        }
        if let index = draft.rows.firstIndex(where: { $0.count != columns.count }) {
            return .rowLength(row: index + 1, expected: columns.count)
        }
        let drawn = draft.drawnSeries.map { $0.trimmingCharacters(in: .whitespaces) }
        if drawn.count > maxSeries {
            return .tooManySeries(drawn.count)
        }
        if let missing = drawn.first(where: { !columns.dropFirst().contains($0) }) {
            return .unknownSeries(missing)
        }
        if type.showsOneSeries, drawn.count != 1 {
            return .oneSeries(type: type.rawValue, count: drawn.count)
        }
        if type == .table {
            return nil
        }
        for name in drawn {
            guard let column = columns.firstIndex(of: name) else { continue }
            for (index, row) in draft.rows.enumerated() where row[column].number == nil {
                return .notANumber(row: index + 1, column: name, value: row[column].plain)
            }
        }
        if type.showsOneSeries, let column = drawn.first.flatMap(columns.firstIndex(of:)),
           draft.rows.contains(where: { ($0[column].number ?? 0) < 0 }) {
            return .negative(type: type.rawValue)
        }
        return nil
    }
}

/// Why a file can't be shown as the editor's fields; it can still be edited as text.
public enum ChartFileError: Error, Equatable, Sendable {
    case unreadable(YAMLError)
    /// Fields this editor doesn't know how to show (the server refuses them too).
    case unknownFields([String])
    /// A known field written in a shape the editor can't show (`data:` as text, `colors:` as fields…).
    case unexpectedShape(String)
}

/// A chart file's text, read as the editor's fields and written back with only what changed rewritten.
public struct ChartFile: Equatable, Sendable {
    /// The fields in the order the server's `make_chart` writes them, used for fields a file didn't have yet.
    public static let order = ["title", "type", "unit", "caption", "compare", "source", "data", "series", "colors"]
    
    /// A top-level field's lines, or lines between fields (blank, comments), kept as they are.
    struct Segment: Equatable {
        let key: String?
        var lines: [String]
    }
    
    let segments: [Segment]
    /// The fields as they were read, to tell what changed.
    public let original: ChartDraft
    
    public static func read(_ text: String) throws(ChartFileError) -> ChartFile {
        let entries: [YAMLEntry]
        do {
            entries = try ChartYAML.parse(text)
        } catch {
            throw .unreadable(error)
        }
        let unknown = entries.map(\.key).filter { !order.contains($0) }
        if !unknown.isEmpty {
            throw .unknownFields(unknown)
        }
        let draft = try Self.draft(entries)
        return ChartFile(segments: Self.segments(text), original: draft)
    }
    
    /// No file yet: writing it writes every field the draft has.
    public static let blank = ChartFile(segments: [], original: ChartDraft(type: ""))
    
    /// A new chart: its title, a bar chart, two columns (in the person's language) and one row to fill in.
    public static func new(title: String, labelsColumn: String, valuesColumn: String) -> String {
        let draft = ChartDraft(title: title, type: ChartType.bar.rawValue, columns: [labelsColumn, valuesColumn], rows: [[.text(""), .number(0)]])
        return blank.writing(draft)
    }
    
    /// The file with `draft`'s fields: unchanged fields keep their lines (and comments), changed ones are rewritten
    /// in place, emptied ones go, and new ones are added at the end in the usual order.
    public func writing(_ draft: ChartDraft) -> String {
        var segments = segments
        var present = Set(segments.compactMap(\.key))
        for index in segments.indices.reversed() {
            guard let key = segments[index].key else { continue }
            if Self.part(key, of: draft) == Self.part(key, of: original) {
                continue
            }
            if let lines = Self.lines(key, of: draft) {
                segments[index].lines = lines
            } else {
                segments.remove(at: index)
                present.remove(key)
            }
        }
        var text = segments.flatMap(\.lines)
        while text.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            text.removeLast()
        }
        for key in Self.order where !present.contains(key) && Self.part(key, of: draft) != Self.part(key, of: original) {
            text += Self.lines(key, of: draft) ?? []
        }
        return text.joined(separator: "\n") + "\n"
    }
    
    // MARK: - Fields
    
    /// A field's value in a comparable form; `nil` when the draft leaves it out.
    private static func part(_ key: String, of draft: ChartDraft) -> YAMLValue? {
        func text(_ value: String) -> YAMLValue? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : ChartYAML.text(trimmed, inFlow: false)
        }
        func list(_ values: [String]) -> YAMLValue? {
            values.isEmpty ? nil : .list(values.map { ChartYAML.text($0, inFlow: true) })
        }
        switch key {
        case "title": return text(draft.title)
        case "type": return text(draft.type)
        case "unit": return text(draft.unit)
        case "caption": return text(draft.caption)
        case "compare": return draft.comparesPrevious ? ChartYAML.text("previous", inFlow: false) : nil
        case "series": return list(draft.series)
        case "colors": return list(draft.colors.map { $0.uppercased() })
        case "data":
            guard draft.mode == .data else { return nil }
            return .map([YAMLEntry("columns", .list(draft.columns.map { ChartYAML.text($0, inFlow: true) })),
                         YAMLEntry("rows", .list(draft.rows.map { .list($0.map(cellValue)) }))])
        case "source":
            guard draft.mode == .source else { return nil }
            let source = draft.source
            var entries = [YAMLEntry("records", ChartYAML.text(source.records, inFlow: false))]
            if !source.filters.isEmpty {
                entries.append(YAMLEntry("where", .map(source.filters.map { YAMLEntry($0.field, ChartYAML.text($0.value, inFlow: true)) })))
            }
            entries += [YAMLEntry("period", ChartYAML.text(source.period, inFlow: false)), YAMLEntry("x", ChartYAML.text(source.x, inFlow: false)),
                        YAMLEntry("y", ChartYAML.text(source.y, inFlow: false))]
            if !source.group.trimmingCharacters(in: .whitespaces).isEmpty {
                entries.append(YAMLEntry("group", ChartYAML.text(source.group, inFlow: false)))
            }
            return .map(entries)
        default: return nil
        }
    }
    
    /// A cell as it's written: numbers plain, labels quoted when YAML would read them otherwise.
    private static func cellValue(_ cell: ChartCell) -> YAMLValue {
        switch cell {
        case .number(let value): .scalar(ChartCell.plain(value), quoted: false)
        case .text(let text): .scalar(text, quoted: ChartYAML.needsQuotes(text, inFlow: true))
        }
    }
    
    /// A field's lines, as `make_chart` writes them.
    private static func lines(_ key: String, of draft: ChartDraft) -> [String]? {
        guard let value = part(key, of: draft) else { return nil }
        switch (key, value) {
        case ("data", .map(let entries)), ("source", .map(let entries)):
            var lines = [key + ":"]
            for entry in entries {
                if entry.key == "rows", case .list(let rows) = entry.value {
                    lines.append("  rows:")
                    lines += rows.map { "    - " + ChartYAML.inline($0) }
                } else {
                    lines.append("  " + entry.key + ": " + ChartYAML.inline(entry.value))
                }
            }
            return lines
        default:
            return [key + ": " + ChartYAML.inline(value)]
        }
    }
    
    // MARK: - Reading
    
    private static func draft(_ entries: [YAMLEntry]) throws(ChartFileError) -> ChartDraft {
        let fields = YAMLValue.map(entries)
        func text(_ key: String) throws(ChartFileError) -> String {
            guard let value = fields[key] else { return "" }
            guard let text = value.text else { throw .unexpectedShape(key) }
            return text
        }
        func texts(_ key: String) throws(ChartFileError) -> [String] {
            guard let value = fields[key], value != .null else { return [] }
            guard let items = value.list, case let texts = items.compactMap(\.text), texts.count == items.count else { throw .unexpectedShape(key) }
            return texts
        }
        var draft = try ChartDraft(title: text("title"), type: text("type").isEmpty ? ChartType.bar.rawValue : text("type"),
                                   unit: text("unit"), caption: text("caption"), colors: texts("colors"),
                                   comparesPrevious: text("compare") == "previous", series: texts("series"))
        if fields["compare"] != nil, !draft.comparesPrevious, try !text("compare").isEmpty {
            // Some other comparison: the form can't show it, the text can.
            throw .unexpectedShape("compare")
        }
        if let source = fields["source"], source != .null {
            guard source.entries != nil else { throw .unexpectedShape("source") }
            func sourceText(_ key: String) throws(ChartFileError) -> String {
                guard let value = source[key] else { return "" }
                guard let text = value.text else { throw .unexpectedShape("source") }
                return text
            }
            var filters: [ChartFilter] = []
            if let filter = source["where"], filter != .null {
                guard let entries = filter.entries else { throw .unexpectedShape("source") }
                for entry in entries {
                    guard let value = entry.value.text else { throw .unexpectedShape("source") }
                    filters.append(ChartFilter(field: entry.key, value: value))
                }
            }
            draft.mode = .source
            draft.source = try ChartSource(records: sourceText("records"), filters: filters, period: sourceText("period"),
                                           x: sourceText("x"), y: sourceText("y"), group: sourceText("group"))
        } else if let data = fields["data"], data != .null {
            guard data.entries != nil else { throw .unexpectedShape("data") }
            let columns = data["columns"]?.list ?? []
            guard case let names = columns.compactMap(\.text), names.count == columns.count else { throw .unexpectedShape("data") }
            let rows = data["rows"]?.list ?? []
            draft.columns = names
            draft.rows = try rows.map { row throws(ChartFileError) in
                guard let cells = row.list else { throw .unexpectedShape("data") }
                return cells.enumerated().map { index, cell in index == 0 ? .text(cell.text ?? "") : cell.cell }
            }
        }
        return draft
    }
    
    private static func segments(_ text: String) -> [Segment] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        var segments: [Segment] = []
        for line in lines {
            let content = ChartYAML.Line(number: 0, raw: line).content
            let isTopLevelKey = !line.hasPrefix(" ") && !content.isEmpty && !content.hasPrefix("- ") && content != "-"
            if isTopLevelKey, let (key, _) = ChartYAML.BlockReader.keyAndRest(content) {
                segments.append(Segment(key: key, lines: [line]))
            } else if segments.isEmpty {
                segments.append(Segment(key: nil, lines: [line]))
            } else {
                segments[segments.count - 1].lines.append(line)
            }
        }
        // Comments and blank lines at the end of a field's block stay where they are if the field is rewritten.
        var result: [Segment] = []
        for segment in segments {
            guard segment.key != nil else {
                result.append(segment)
                continue
            }
            var lines = segment.lines
            var trailing: [String] = []
            while lines.count > 1, let last = lines.last, ChartYAML.Line(number: 0, raw: last).content.isEmpty {
                trailing.insert(lines.removeLast(), at: 0)
            }
            result.append(Segment(key: segment.key, lines: lines))
            if !trailing.isEmpty {
                result.append(Segment(key: nil, lines: trailing))
            }
        }
        return result
    }
}
