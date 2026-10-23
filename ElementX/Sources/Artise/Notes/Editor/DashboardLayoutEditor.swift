//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// A dashboard in the editor as its layout: its text, its charts' pictures and its side-by-side groups, in order.
/// Drag to reorder, long-press a chart to take it out, add one of the chat's charts, and set the colours. Everything
/// changes the note's text underneath (one undo step each), which the Text tab shows as it is. The problems the server
/// would tell Ari about are marked where they are.
struct DashboardLayoutEditor: View {
    let service: ArtiseNotesService
    let roomID: String
    @Binding var model: NoteEditorModel
    /// The chat's charts, for "Add chart" and to tell an embed that names none.
    let charts: [LocalFile]
    /// Shows the text with the cursor on this line (a tap on a block of text).
    let onShowText: (Int) -> Void
    
    @State private var isPickingChart = false
    @State private var isEditingTheme = false
    @State private var openChart: String?
    
    var body: some View {
        let layout = DashboardLayout.parse(model.text)
        let problems = layout?.problems(chartPaths: chartPaths) ?? []
        List {
            let general = problems.filter { $0.line == nil }
            if !general.isEmpty {
                Section {
                    ForEach(Array(general.enumerated()), id: \.offset) { _, problem in
                        DashboardProblemRow(problem: problem)
                    }
                }
            }
            Section {
                if let layout {
                    ForEach(Array(layout.blocks.enumerated()), id: \.offset) { _, block in
                        blockRow(block, problems: problems)
                    }
                    .onMove { from, to in move(from: from, to: to, in: layout) }
                }
            }
            Section {
                Button { isPickingChart = true } label: {
                    Label(ArtiseNotesL10n.text("screen_notes_dashboard_add_chart"), icon: \.plus)
                }
                Button { isEditingTheme = true } label: {
                    Label(ArtiseNotesL10n.text("screen_notes_dashboard_theme"), systemImage: "paintpalette")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .sheet(isPresented: $isPickingChart) {
            DashboardChartPicker(charts: charts) { path in
                isPickingChart = false
                model.replaceText(DashboardEdits.insertingChart(path, in: model.text), now: .now)
            }
        }
        .sheet(isPresented: $isEditingTheme) {
            DashboardThemeSheet(theme: layout?.theme ?? DashboardTheme()) { theme in
                isEditingTheme = false
                model.replaceText(DashboardEdits.settingTheme(theme, in: model.text), now: .now)
            }
        }
        .sheet(item: Binding(get: { openChart.map(ChartToOpen.init) }, set: { openChart = $0?.path })) { chart in
            ElementNavigationStack {
                NoteChartScreen(service: service, roomID: roomID, path: chart.path)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.actionClose) { openChart = nil }
                        }
                    }
            }
        }
    }
    
    private var chartPaths: Set<String> {
        Set(charts.map(\.path))
    }
    
    @ViewBuilder
    private func blockRow(_ block: DashboardLayout.Block, problems: [DashboardProblem]) -> some View {
        let here = problems.filter { problem in problem.line.map { block.lines.contains($0) } ?? false }
        VStack(alignment: .leading, spacing: 8) {
            switch block {
            case .item(let item):
                itemView(item)
            case .columns(_, _, let items):
                Text(ArtiseNotesL10n.text("screen_notes_dashboard_columns"))
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textSecondary)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        itemView(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            ForEach(Array(here.enumerated()), id: \.offset) { _, problem in
                DashboardProblemRow(problem: problem)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func itemView(_ item: DashboardLayout.Item) -> some View {
        switch item {
        case .text(let range):
            Button { onShowText(range.lowerBound) } label: {
                Text(Self.summary(of: range, in: model.text))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        case .chart(let ref, let line):
            let path = DashboardLayout.chartPath(ref, in: chartPaths)
            Button { openChart = path } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let path {
                        NoteDrawingImage(service: service, roomID: roomID, path: path, size: 256)
                            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 140)
                    }
                    Text(path.flatMap { path in charts.first { $0.path == path }?.title } ?? ref)
                        .font(.compound.bodySMSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .disabled(path == nil)
            .contextMenu {
                Button(ArtiseNotesL10n.text("screen_notes_dashboard_remove"), role: .destructive) {
                    model.replaceText(DashboardEdits.removing(line...line, from: model.text), now: .now)
                }
            }
        }
    }
    
    /// A drag in the list puts the block's lines before the block it's dropped on (or after the last one).
    private func move(from: IndexSet, to: Int, in layout: DashboardLayout) {
        guard let index = from.first, layout.blocks.indices.contains(index) else { return }
        let target = to < layout.blocks.count ? layout.blocks[to].lines.lowerBound : (layout.blocks.last?.lines.upperBound ?? 0) + 1
        model.replaceText(DashboardEdits.moving(block: layout.blocks[index].lines, before: target, in: model.text), now: .now)
    }
    
    /// A text block's first lines as they read, without Markdown's heading and list marks.
    static func summary(of range: ClosedRange<Int>, in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines[max(0, range.lowerBound)...min(range.upperBound, lines.count - 1)]
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#>-* ")) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
    
    struct ChartToOpen: Identifiable {
        let path: String
        
        var id: String {
            path
        }
    }
}

/// One problem, in the person's words, marked as one.
struct DashboardProblemRow: View {
    let problem: DashboardProblem
    
    var body: some View {
        Label {
            Text(Self.text(problem))
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textCriticalPrimary)
        } icon: {
            CompoundIcon(\.error, size: .small, relativeTo: .compound.bodySM)
                .foregroundStyle(.compound.iconCriticalPrimary)
        }
    }
    
    static func text(_ problem: DashboardProblem) -> String {
        switch problem {
        case .themeAccent(let color): String(format: ArtiseNotesL10n.text("screen_notes_chart_problem_color"), color)
        case .themePalette: ArtiseNotesL10n.text("screen_notes_dashboard_problem_palette")
        case .themeMode(let mode): String(format: ArtiseNotesL10n.text("screen_notes_dashboard_problem_mode"), mode)
        case .nestedColumns: ArtiseNotesL10n.text("screen_notes_dashboard_problem_nested")
        case .unclosedColumns: ArtiseNotesL10n.text("screen_notes_dashboard_problem_unclosed")
        case .missingChart(let ref, _): String(format: ArtiseNotesL10n.text("screen_notes_dashboard_problem_missing"), ref)
        case .tooManyCharts: ArtiseNotesL10n.text("screen_notes_dashboard_problem_too_many")
        }
    }
}

/// "Add chart": the chat's charts by title, searchable; the one chosen is added at the end.
struct DashboardChartPicker: View {
    let charts: [LocalFile]
    let onPick: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    var body: some View {
        ElementNavigationStack {
            Form {
                if charts.isEmpty {
                    Text(ArtiseNotesL10n.text("screen_notes_dashboard_no_charts"))
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                } else {
                    ForEach(found, id: \.path) { chart in
                        ListRow(label: .default(title: Self.title(chart), description: chart.path, icon: \.chart),
                                kind: .button { onPick(chart.path) })
                    }
                }
            }
            .compoundList()
            .searchable(text: $query, prompt: ArtiseNotesL10n.text("screen_notes_dashboard_search_charts"))
            .navigationTitle(ArtiseNotesL10n.text("screen_notes_dashboard_pick_chart"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { dismiss() }
                }
            }
        }
    }
    
    /// Titles first, then paths; case and accents don't matter.
    private var found: [LocalFile] {
        let sorted = charts.sorted { Self.title($0).localizedCaseInsensitiveCompare(Self.title($1)) == .orderedAscending }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { !DocumentSearch.ranges(of: needle, in: Self.title($0) + " " + $0.path).isEmpty }
    }
    
    static func title(_ chart: LocalFile) -> String {
        chart.title ?? NotesFolderEntries.fileName(chart.path)
    }
}

/// A dashboard's colours: the main colour, the series' colours (up to 8) and light or dark. Done writes them in the
/// note's header; "Use the workspace's colours" takes them out.
struct DashboardThemeSheet: View {
    let onDone: (DashboardTheme) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var theme: DashboardTheme
    
    init(theme: DashboardTheme, onDone: @escaping (DashboardTheme) -> Void) {
        self.onDone = onDone
        _theme = State(initialValue: theme)
    }
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ColorPicker(ArtiseNotesL10n.text("screen_notes_dashboard_theme_accent"),
                                selection: color(get: { theme.accent }, set: { theme.accent = $0 }), supportsOpacity: false)
                }
                Section {
                    ForEach(theme.palette.indices, id: \.self) { index in
                        ColorPicker(String(format: ArtiseNotesL10n.text("screen_notes_chart_column_new"), index + 1),
                                    selection: color(get: { theme.palette.indices.contains(index) ? theme.palette[index] : nil },
                                                     set: { hex in
                                                         if let hex, theme.palette.indices.contains(index) {
                                                             theme.palette[index] = hex
                                                         }
                                                     }),
                                    supportsOpacity: false)
                    }
                    .onDelete { theme.palette.remove(atOffsets: $0) }
                    if theme.palette.count < ChartChecks.maxSeries {
                        Button {
                            theme.palette.append(theme.palette.last ?? theme.accent ?? "#22408A")
                        } label: {
                            Label(ArtiseNotesL10n.text("screen_notes_dashboard_theme_add_color"), icon: \.plus)
                        }
                    }
                } header: {
                    Text(ArtiseNotesL10n.text("screen_notes_dashboard_theme_palette"))
                        .compoundListSectionHeader()
                }
                Section {
                    Picker(ArtiseNotesL10n.text("screen_notes_dashboard_theme_mode"), selection: modeBinding) {
                        ForEach(DashboardTheme.Mode.allCases, id: \.self) { mode in
                            Text(ArtiseNotesL10n.text("screen_notes_dashboard_theme_mode_" + mode.rawValue)).tag(mode)
                        }
                    }
                }
                Section {
                    Button(ArtiseNotesL10n.text("screen_notes_dashboard_theme_workspace")) {
                        theme = DashboardTheme()
                    }
                    .disabled(theme.isEmpty)
                }
            }
            .compoundList()
            .navigationTitle(ArtiseNotesL10n.text("screen_notes_dashboard_theme"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone) { onDone(theme) }
                }
            }
        }
    }
    
    /// Unset reads as following the device, and stays unset until another is chosen.
    private var modeBinding: Binding<DashboardTheme.Mode> {
        Binding(get: { theme.mode ?? .auto }, set: { mode in
            theme.mode = mode == .auto && theme.mode == nil ? nil : mode
        })
    }
    
    /// A colour field over a `#RRGGBB` value; unset shows the workspace's accent.
    private func color(get: @escaping () -> String?, set: @escaping (String?) -> Void) -> Binding<Color> {
        Binding(get: {
            get().flatMap(Color.init(artiseHex:)) ?? ArtiseWorkspaces.shared.accent ?? .accentColor
        }, set: { color in
            set(ChartColorHex.hex(color))
        })
    }
}

/// `#RRGGBB` for a colour the person picked.
enum ChartColorHex {
    static func hex(_ color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
