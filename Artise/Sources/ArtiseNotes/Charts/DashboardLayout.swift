//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A dashboard's own colours, from its header's `theme`; what's unset follows the workspace.
public struct DashboardTheme: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case light
        case dark
        /// Follows the device.
        case auto
    }
    
    /// `#RRGGBB`: the headings' rule and the first series.
    public var accent: String?
    /// Up to 8 series colours, in order.
    public var palette: [String]
    public var mode: Mode?
    
    public init(accent: String? = nil, palette: [String] = [], mode: Mode? = nil) {
        self.accent = accent
        self.palette = palette
        self.mode = mode
    }
    
    public var isEmpty: Bool {
        accent == nil && palette.isEmpty && mode == nil
    }
}

/// What the server would say is wrong with a dashboard (`dashboards.check`), each where it is.
public enum DashboardProblem: Equatable, Sendable {
    case themeAccent(String)
    case themePalette
    case themeMode(String)
    /// A `::: columns` inside another, at this line (from 0).
    case nestedColumns(line: Int)
    /// A `::: columns` that's never closed, opened at this line.
    case unclosedColumns(line: Int)
    /// `![[ref]]` at this line names a chart the chat doesn't have.
    case missingChart(ref: String, line: Int)
    /// More charts than a dashboard draws; the rest are left out.
    case tooManyCharts(Int)
    
    /// The line it's on, when it's on one.
    public var line: Int? {
        switch self {
        case .nestedColumns(let line), .unclosedColumns(let line), .missingChart(_, let line): line
        case .themeAccent, .themePalette, .themeMode, .tooManyCharts: nil
        }
    }
}

/// A dashboard note read as its parts: text, charts (`![[charts/ventas.chart]]`) and side-by-side groups
/// (`::: columns` … `:::`), each with its lines in the note, so the editor can show them as a layout and change the
/// text underneath. The same reading as the server's `dashboards.parse`.
public struct DashboardLayout: Equatable, Sendable {
    public enum Item: Equatable, Sendable {
        /// Lines of Markdown (from 0, in the whole note).
        case text(ClosedRange<Int>)
        /// A chart, as written, on this line.
        case chart(ref: String, line: Int)
    }
    
    public enum Block: Equatable, Sendable {
        case item(Item)
        /// A columns block from its `::: columns` line to its `:::` (`nil` when it isn't closed).
        case columns(open: Int, close: Int?, items: [Item])
        
        /// The note's lines this block takes.
        public var lines: ClosedRange<Int> {
            switch self {
            case .item(.text(let range)): range
            case .item(.chart(_, let line)): line...line
            case .columns(let open, let close, let items): open...(close ?? items.map(\.lastLine).max() ?? open)
            }
        }
    }
    
    public static let maxCharts = 24
    public static let chartsFolder = "charts"
    
    public let title: String?
    public let theme: DashboardTheme
    public let blocks: [Block]
    /// Problems found by reading alone; `problems(chartPaths:)` adds the missing charts.
    public let layoutProblems: [DashboardProblem]
    /// Whether it's Ari's business report (`type: report`): read-only.
    public let isReport: Bool
    
    /// The layout of a note whose header says `type: dashboard` (or `report`); `nil` for any other note.
    public static func parse(_ text: String) -> DashboardLayout? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let header = Header(lines: lines) else { return nil }
        let type = (header.fields["type"]?.text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard type == "dashboard" || type == "report" else { return nil }
        
        let (theme, themeProblems) = Self.theme(header.fields["theme"])
        var problems: [DashboardProblem] = themeProblems
        var blocks: [Block] = []
        var group: (open: Int, items: [Item])?
        var paragraph: [Int] = []
        
        func flush() {
            let lines = paragraph
            paragraph = []
            guard let first = lines.first, let last = lines.last,
                  lines.contains(where: { !lineText($0).trimmingCharacters(in: .whitespaces).isEmpty }) else { return }
            if group != nil {
                group?.items.append(.text(first...last))
            } else {
                blocks.append(.item(.text(first...last)))
            }
        }
        func lineText(_ line: Int) -> String {
            lines[line]
        }
        
        for index in header.bodyStart..<lines.count {
            let line = lines[index]
            if Self.isColumnsOpen(line) {
                flush()
                if group != nil {
                    problems.append(.nestedColumns(line: index))
                    continue
                }
                group = (index, [])
            } else if Self.isColumnsClose(line), let open = group {
                flush()
                if !open.items.isEmpty {
                    blocks.append(.columns(open: open.open, close: index, items: open.items))
                }
                group = nil
            } else if let ref = Self.chartRef(line) {
                flush()
                if group != nil {
                    group?.items.append(.chart(ref: ref, line: index))
                } else {
                    blocks.append(.item(.chart(ref: ref, line: index)))
                }
            } else {
                paragraph.append(index)
            }
        }
        flush()
        if let open = group {
            problems.append(.unclosedColumns(line: open.open))
            if !open.items.isEmpty {
                blocks.append(.columns(open: open.open, close: nil, items: open.items))
            }
        }
        let title = header.fields["title"]?.text?.trimmingCharacters(in: .whitespaces)
        return DashboardLayout(title: title?.isEmpty == false ? title : nil, theme: theme, blocks: blocks, layoutProblems: problems,
                               isReport: type == "report")
    }
    
    /// Every chart, in reading order.
    public var charts: [(ref: String, line: Int)] {
        blocks.flatMap { block -> [Item] in
            switch block {
            case .item(let item): [item]
            case .columns(_, _, let items): items
            }
        }
        .compactMap {
            if case .chart(let ref, let line) = $0 {
                return (ref, line)
            }
            return nil
        }
    }
    
    /// Every problem, the charts the chat doesn't have included.
    public func problems(chartPaths: Set<String>) -> [DashboardProblem] {
        let charts = charts
        var problems = layoutProblems
        problems += charts.filter { Self.chartPath($0.ref, in: chartPaths) == nil }.map { .missingChart(ref: $0.ref, line: $0.line) }
        if charts.count > Self.maxCharts {
            problems.append(.tooManyCharts(charts.count))
        }
        return problems
    }
    
    /// The chart an embed names: the path as written, else `charts/<name>` for a bare name.
    public static func chartPath(_ ref: String, in paths: Set<String>) -> String? {
        let plain = ref.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if paths.contains(plain) {
            return plain
        }
        let inFolder = chartsFolder + "/" + plain
        return !plain.contains("/") && paths.contains(inFolder) ? inFolder : nil
    }
    
    // MARK: - Lines
    
    /// `![[charts/ventas.chart]]` (or `![[ventas.chart|…]]`) alone on its line → `charts/ventas.chart`.
    public static func chartRef(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") else { return nil }
        let inner = trimmed.dropFirst(3).dropLast(2)
        guard !inner.contains("]"), !inner.contains("["),
              let ref = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init),
              !ref.contains("#") else { return nil }
        let name = ref.trimmingCharacters(in: .whitespaces)
        return name.lowercased().hasSuffix(".chart") && !name.isEmpty ? name : nil
    }
    
    static func isColumnsOpen(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "").lowercased() == ":::columns"
    }
    
    static func isColumnsClose(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == ":::"
    }
    
    // MARK: - Header
    
    /// The note's header: its fields and where the text after it starts.
    struct Header {
        let fields: YAMLValue
        /// The closing `---` line.
        let close: Int
        
        var bodyStart: Int {
            close + 1
        }
        
        init?(lines: [String]) {
            guard lines.first?.trimmingCharacters(in: .whitespaces) == "---", lines.count > 1,
                  let close = lines[1...].firstIndex(where: { ["---", "..."].contains($0.trimmingCharacters(in: .whitespaces)) }) else {
                return nil
            }
            self.close = close
            // A header this reader can't follow still has a type line that tells a dashboard.
            let text = lines[1..<close].joined(separator: "\n")
            if let entries = try? ChartYAML.parse(text) {
                fields = .map(entries)
            } else {
                let typeLine = lines[1..<close].first { $0.lowercased().hasPrefix("type:") }
                let type = typeLine.map { String($0.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) } ?? ""
                fields = .map([YAMLEntry("type", .scalar(type, quoted: false))])
            }
        }
    }
    
    static func theme(_ value: YAMLValue?) -> (DashboardTheme, [DashboardProblem]) {
        guard let value, value != .null else { return (DashboardTheme(), []) }
        var theme = DashboardTheme()
        var problems: [DashboardProblem] = []
        if let accent = value["accent"]?.text?.trimmingCharacters(in: .whitespaces), !accent.isEmpty {
            if Self.isColor(accent) {
                theme.accent = accent.uppercased()
            } else {
                problems.append(.themeAccent(accent))
            }
        }
        if let palette = value["palette"], palette != .null {
            let colors = (palette.list ?? []).compactMap { $0.text?.trimmingCharacters(in: .whitespaces) }
            if palette.list != nil, colors.count == palette.list?.count, colors.allSatisfy(Self.isColor) {
                theme.palette = Array(colors.map { $0.uppercased() }.prefix(ChartChecks.maxSeries))
            } else {
                problems.append(.themePalette)
            }
        }
        if let mode = value["mode"]?.text?.trimmingCharacters(in: .whitespaces).lowercased(), !mode.isEmpty {
            if let known = DashboardTheme.Mode(rawValue: mode) {
                theme.mode = known
            } else {
                problems.append(.themeMode(mode))
            }
        }
        return (theme, problems)
    }
    
    public static func isColor(_ text: String) -> Bool {
        text.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }
}

private extension DashboardLayout.Item {
    var lastLine: Int {
        switch self {
        case .text(let range): range.upperBound
        case .chart(_, let line): line
        }
    }
}

/// Changes to a dashboard's text that the layout makes: each returns the whole note, ready for the editor.
public enum DashboardEdits {
    /// A new dashboard's text.
    public static func new(title: String) -> String {
        "---\ntype: dashboard\ntitle: " + ChartYAML.inline(ChartYAML.text(title, inFlow: false)) + "\n---\n"
    }
    
    /// `![[path]]` on its own line at the end of the note (or of a columns block, when `inColumnsClosingAt` is its
    /// closing line).
    public static func insertingChart(_ path: String, in text: String, before line: Int? = nil) -> String {
        var lines = text.components(separatedBy: "\n")
        let embed = "![[" + path + "]]"
        if let line, lines.indices.contains(line) {
            lines.insert(embed, at: line)
            return lines.joined(separator: "\n")
        }
        while lines.count > 1, lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        lines.append(embed)
        return lines.joined(separator: "\n") + "\n"
    }
    
    /// The note without these lines (a chart's line, or a whole block).
    public static func removing(_ range: ClosedRange<Int>, from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard range.lowerBound >= 0, range.upperBound < lines.count else { return text }
        lines.removeSubrange(range)
        return lines.joined(separator: "\n")
    }
    
    /// Moves the lines of one block to where another starts (or to the end with `before` past the last block), as a
    /// drag in the layout does. Blocks are the layout's, from `DashboardLayout.parse(text)`.
    public static func moving(block: ClosedRange<Int>, before target: Int, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard block.lowerBound >= 0, block.upperBound < lines.count, target >= 0, target <= lines.count,
              !(block.lowerBound...block.upperBound + 1).contains(target) else { return text }
        let moved = Array(lines[block])
        lines.removeSubrange(block)
        let destination = target > block.upperBound ? target - moved.count : target
        lines.insert(contentsOf: moved, at: min(destination, lines.count))
        return lines.joined(separator: "\n")
    }
    
    /// The header with `theme` written as one line (`theme: {accent: "#22408A", palette: […], mode: auto}`), replacing
    /// the one there (and its indented lines); an empty theme removes it.
    public static func settingTheme(_ theme: DashboardTheme, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let header = DashboardLayout.Header(lines: lines) else { return text }
        var end = header.close
        if let start = (1..<header.close).first(where: { lines[$0].hasPrefix("theme:") }) {
            var stop = start + 1
            while stop < header.close, lines[stop].hasPrefix(" ") || lines[stop].hasPrefix("-") {
                stop += 1
            }
            lines.removeSubrange(start..<stop)
            end -= stop - start
            if !theme.isEmpty {
                lines.insert(line(theme), at: start)
            }
        } else if !theme.isEmpty {
            lines.insert(line(theme), at: end)
        }
        return lines.joined(separator: "\n")
    }
    
    static func line(_ theme: DashboardTheme) -> String {
        var entries: [YAMLEntry] = []
        if let accent = theme.accent {
            entries.append(YAMLEntry("accent", .scalar(accent, quoted: true)))
        }
        if !theme.palette.isEmpty {
            entries.append(YAMLEntry("palette", .list(theme.palette.prefix(ChartChecks.maxSeries).map { .scalar($0, quoted: true) })))
        }
        if let mode = theme.mode {
            entries.append(YAMLEntry("mode", .scalar(mode.rawValue, quoted: false)))
        }
        return "theme: " + ChartYAML.inline(.map(entries))
    }
}
