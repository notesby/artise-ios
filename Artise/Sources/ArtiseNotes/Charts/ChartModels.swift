//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Light or dark: how the server draws a chart or dashboard, to match the screen it shows on.
public enum NoteDrawingMode: String, Hashable, Sendable, CaseIterable {
    case light
    case dark
}

/// What a file is exported as for the share sheet.
public enum NoteExportFormat: String, Hashable, Sendable {
    /// A chart's picture.
    case png
    /// A chart, a note or a dashboard as a document.
    case pdf
}

/// A file made by the server for the share sheet, with the name to give it.
public struct NotesExport: Equatable, Sendable {
    public let data: Data
    public let fileName: String
    
    public init(data: Data, fileName: String) {
        self.data = data
        self.fileName = fileName
    }
}

/// One record type a chat keeps (payments, bookings…), with the fields a chart's `source` may name.
public struct NotesRecordType: Equatable, Sendable, Identifiable {
    public let type: String
    public let fields: [String]
    /// The field that dates a record, for `x: month` and periods.
    public let dateField: String?
    /// The field `sum(…)` usually adds up.
    public let amountField: String?
    
    public var id: String {
        type
    }
    
    public init(type: String, fields: [String], dateField: String?, amountField: String?) {
        self.type = type
        self.fields = fields
        self.dateField = dateField
        self.amountField = amountField
    }
}

/// A value in a chart's table: a number, or a label (text, a date…). Empty cells are empty text.
public enum ChartCell: Hashable, Sendable, Decodable {
    case number(Double)
    case text(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .text("")
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let flag = try? container.decode(Bool.self) {
            self = .text(flag ? "true" : "false")
        } else {
            self = try .text(container.decode(String.self))
        }
    }
    
    public var number: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }
    
    /// As the file writes it: `12000`, `1234.5`, or the label.
    public var plain: String {
        switch self {
        case .number(let value): Self.plain(value)
        case .text(let text): text
        }
    }
    
    /// `12000.0` → "12000", `1234.5` → "1234.5": no exponent, no grouping, a dot for decimals.
    public static func plain(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(format: "%.10f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}

/// A chart as the server reads it (`GET /chart`): its fields, its rows (a sourced chart's as of today), and its
/// drawing as SVG.
public struct NotesChart: Equatable, Sendable {
    public let path: String
    public let version: String
    public let title: String
    /// bar, line, area, pie, donut, stacked, kpi or table.
    public let type: String
    public let columns: [String]
    public let rows: [[ChartCell]]
    public let series: [String]
    public let unit: String
    public let caption: String
    public let colors: [String]
    public let compare: String
    /// The day a sourced chart's records were read; empty for a chart with its own numbers.
    public let asOf: String
    public let svg: String
    
    public init(path: String, version: String, title: String, type: String, columns: [String], rows: [[ChartCell]], series: [String],
                unit: String, caption: String, colors: [String], compare: String, asOf: String, svg: String) {
        self.path = path
        self.version = version
        self.title = title
        self.type = type
        self.columns = columns
        self.rows = rows
        self.series = series
        self.unit = unit
        self.caption = caption
        self.colors = colors
        self.compare = compare
        self.asOf = asOf
        self.svg = svg
    }
    
    /// What a screen reader says for the picture: the title, then the caption.
    public var accessibilityText: String {
        [title, caption].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}
