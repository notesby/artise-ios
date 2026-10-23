//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// A chart's editor: a form over its file (never the text unless asked), with the table or the records it reads, and a
/// live picture of the unsaved chart. It makes the server's checks as the person types, so a chart that can't be
/// drawn can't be saved; what it can't show as fields opens as text. Saving keeps the file's other lines as they were.
struct NoteChartEditorScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    /// A new chart's title: nothing is written before the first Save.
    var newTitle: String?
    /// `true` when it was saved.
    let onDone: (Bool) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @State private var file: ChartFile?
    @State private var draft = ChartDraft()
    /// The file's text, when it's shown as text.
    @State private var text = ""
    @State private var originalText = ""
    @State private var showsFile = false
    /// The file can't be shown as fields: only as text.
    @State private var isTextOnly = false
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var showsDiscard = false
    @State private var recordTypes: [NotesRecordType] = []
    @State private var preview: UIImage?
    /// The server's sentence about the unsaved chart, when it can't draw it.
    @State private var serverProblem: String?
    @State private var previewOffline = false
    
    var body: some View {
        ElementNavigationStack {
            Form {
                previewSection
                if showsFile || isTextOnly {
                    textSection
                } else if isLoaded {
                    fieldsSections
                }
            }
            .compoundList()
            .navigationTitle(ArtiseNotesL10n.text("screen_notes_chart_editor_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(L10n.dialogUnsavedChangesTitle, isPresented: $showsDiscard, titleVisibility: .visible) {
                if problem == nil {
                    Button(L10n.actionSave) { save() }
                }
                Button(L10n.actionDiscard, role: .destructive) { onDone(false) }
            } message: {
                Text(L10n.dialogUnsavedChangesDescriptionIos)
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .task { await load() }
        .task(id: PreviewKey(text: currentText, mode: mode)) { await drawPreview() }
    }
    
    // MARK: - Sections
    
    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .opacity(problemText == nil ? 1 : 0.3)
                    } else {
                        CompoundIcon(\.chart, size: .custom(40), relativeTo: .compound.headingLGBold)
                            .foregroundStyle(.compound.iconTertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .accessibilityHidden(true)
                if let message = problemText {
                    Label {
                        Text(message)
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textCriticalPrimary)
                    } icon: {
                        CompoundIcon(\.error, size: .small, relativeTo: .compound.bodySM)
                            .foregroundStyle(.compound.iconCriticalPrimary)
                    }
                } else if previewOffline {
                    Text(ArtiseNotesL10n.text("screen_notes_chart_preview_offline"))
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
            }
        } header: {
            Text(ArtiseNotesL10n.text("screen_notes_chart_preview"))
                .compoundListSectionHeader()
        }
    }
    
    private var textSection: some View {
        Section {
            TextEditor(text: $text)
                .font(.compound.bodyMD.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: 320)
        } footer: {
            if isTextOnly {
                Text(ArtiseNotesL10n.text("screen_notes_chart_text_only"))
                    .compoundListSectionFooter()
            }
        }
    }
    
    @ViewBuilder
    private var fieldsSections: some View {
        Section {
            TextField(ArtiseNotesL10n.text("screen_notes_chart_field_title"), text: $draft.title)
            Picker(ArtiseNotesL10n.text("screen_notes_chart_field_type"), selection: typeSelection) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Label(ArtiseNotesL10n.text("screen_notes_chart_type_" + type.rawValue), systemImage: Self.symbol(type))
                        .tag(type)
                }
            }
            TextField(ArtiseNotesL10n.text("screen_notes_chart_field_unit"), text: $draft.unit)
            TextField(ArtiseNotesL10n.text("screen_notes_chart_field_caption"), text: $draft.caption, axis: .vertical)
            if draft.chartType == .kpi || draft.comparesPrevious {
                Toggle(ArtiseNotesL10n.text("screen_notes_chart_field_compare"), isOn: $draft.comparesPrevious)
            }
        }
        
        if draft.mode == .data, !draft.drawnSeries.isEmpty {
            ChartColorsSection(draft: $draft)
        }
        
        Section {
            Picker(selection: $draft.mode) {
                Text(ArtiseNotesL10n.text("screen_notes_chart_data")).tag(ChartDraft.Mode.data)
                Text(ArtiseNotesL10n.text("screen_notes_chart_source")).tag(ChartDraft.Mode.source)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
        }
        
        if draft.mode == .data {
            ChartTableSection(draft: $draft, locale: locale)
        } else {
            ChartSourceSection(source: $draft.source, recordTypes: recordTypes)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.actionCancel) {
                if hasChanges {
                    showsDiscard = true
                } else {
                    onDone(false)
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionSave) { save() }
                .disabled(!isLoaded || isSaving || problem != nil || !hasChanges)
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: showsFileBinding) {
                Label(ArtiseNotesL10n.text("screen_notes_chart_show_file"), systemImage: "curlybraces")
            }
            .toggleStyle(.button)
            .disabled(isTextOnly || !isLoaded)
        }
    }
    
    // MARK: - State
    
    private var mode: NoteDrawingMode {
        colorScheme == .dark ? .dark : .light
    }
    
    /// The file as it would be saved now.
    private var currentText: String {
        if showsFile || isTextOnly {
            return text
        }
        return (file ?? ChartFile.blank).writing(draft)
    }
    
    private var hasChanges: Bool {
        newTitle != nil || currentText != originalText
    }
    
    /// What the checks say about the chart as it is; text that can't be read as fields is left to the server's answer.
    private var problem: ChartProblem? {
        if showsFile || isTextOnly {
            guard let read = try? ChartFile.read(text) else { return nil }
            return ChartChecks.problem(read.original, fileText: text)
        }
        return ChartChecks.problem(draft, fileText: currentText)
    }
    
    private var problemText: String? {
        problem.map(ChartProblemText.text) ?? serverProblem
    }
    
    private var typeSelection: Binding<ChartType> {
        Binding(get: { draft.chartType ?? .bar }, set: { draft.type = $0.rawValue })
    }
    
    /// Turning the file view on shows the fields as text; off, the text is read back as fields (when it can be).
    private var showsFileBinding: Binding<Bool> {
        Binding(get: { showsFile }, set: { shows in
            if shows {
                text = currentText
                showsFile = true
            } else if let read = try? ChartFile.read(text) {
                file = read
                draft = read.original
                showsFile = false
            }
        })
    }
    
    private func load() async {
        let repository = service.repository
        if let newTitle {
            text = ChartFile.new(title: newTitle, labelsColumn: ArtiseNotesL10n.text("screen_notes_chart_column_labels"),
                                 valuesColumn: ArtiseNotesL10n.text("screen_notes_chart_column_values"))
            originalText = ""
        } else {
            text = await (try? repository.file(roomID: roomID, path: path)?.content) ?? ""
            originalText = text
        }
        do {
            let read = try ChartFile.read(text)
            file = read
            draft = read.original
        } catch {
            MXLog.info("Notes: chart shown as text: \(error)")
            isTextOnly = true
        }
        isLoaded = true
        recordTypes = await (try? repository.recordTypes(roomID: roomID)) ?? []
    }
    
    /// The unsaved chart's picture, 600 ms after the last change: each new version is a drawing on the server.
    private func drawPreview() async {
        guard isLoaded else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, problem == nil else { return }
        do {
            let data = try await service.repository.chartPreview(roomID: roomID, content: currentText, size: 512, mode: mode)
            guard !Task.isCancelled else { return }
            preview = UIImage(data: data)
            serverProblem = nil
            previewOffline = false
        } catch NotesError.badChart(let message) {
            serverProblem = message
        } catch {
            previewOffline = true
        }
    }
    
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let repository = service.repository
        let content = currentText
        Task {
            do {
                if newTitle != nil {
                    try await repository.createNote(roomID: roomID, path: path, content: content)
                } else {
                    try await repository.editNote(roomID: roomID, path: path, content: content)
                }
                repository.syncInBackground(roomID: roomID)
                onDone(true)
            } catch {
                MXLog.error("Notes: chart not saved: \(error)")
                isSaving = false
            }
        }
    }
    
    static func symbol(_ type: ChartType) -> String {
        switch type {
        case .bar: "chart.bar"
        case .line: "chart.xyaxis.line"
        case .area: "chart.line.uptrend.xyaxis"
        case .pie: "chart.pie"
        case .donut: "circle.circle"
        case .stacked: "chart.bar.doc.horizontal"
        case .kpi: "number"
        case .table: "tablecells"
        }
    }
    
    struct PreviewKey: Equatable {
        let text: String
        let mode: NoteDrawingMode
    }
}

/// The person's language's words for a chart's problem.
enum ChartProblemText {
    static func text(_ problem: ChartProblem) -> String {
        func string(_ key: String) -> String {
            ArtiseNotesL10n.text("screen_notes_chart_problem_" + key)
        }
        switch problem {
        case .title: return string("title")
        case .titleTooLong: return string("title_long")
        case .unknownType: return string("type")
        case .compareNotKPI: return string("compare")
        case .badColor(let color): return String(format: string("color"), color)
        case .source: return string("source")
        case .columns: return string("columns")
        case .names: return string("names")
        case .noRows: return string("no_rows")
        case .tooManyRows: return string("rows")
        case .rowLength(let row, let expected): return String(format: string("row_length"), row, expected)
        case .tooManySeries: return string("series")
        case .unknownSeries(let name): return String(format: string("unknown_series"), name)
        case .oneSeries: return string("one_series")
        case .notANumber(let row, let column, let value): return String(format: string("number"), row, column, value)
        case .negative: return string("negative")
        case .tooBig: return string("too_big")
        }
    }
}

/// One colour per series: the workspace's palette a tap away, or any colour; none set uses the workspace's.
private struct ChartColorsSection: View {
    @Binding var draft: ChartDraft
    
    var body: some View {
        Section {
            ForEach(Array(draft.drawnSeries.enumerated()), id: \.offset) { index, series in
                HStack {
                    Text(series)
                        .lineLimit(1)
                    Spacer()
                    Menu {
                        ForEach(palette, id: \.self) { hex in
                            Button { setColor(hex, at: index) } label: {
                                Label { Text(hex) } icon: { Image(systemName: "circle.fill").foregroundStyle(Color(artiseHex: hex) ?? .gray) }
                            }
                        }
                    } label: {
                        Image(systemName: "swatchpalette")
                    }
                    .disabled(palette.isEmpty)
                    ColorPicker(String(format: ArtiseNotesL10n.text("screen_notes_chart_color_for"), series),
                                selection: colorBinding(at: index), supportsOpacity: false)
                        .labelsHidden()
                }
                .accessibilityElement(children: .contain)
            }
            if !draft.colors.isEmpty {
                Button(ArtiseNotesL10n.text("screen_notes_chart_color_workspace")) { draft.colors = [] }
            }
        } header: {
            Text(ArtiseNotesL10n.text("screen_notes_chart_field_colors"))
                .compoundListSectionHeader()
        }
    }
    
    /// The admin's chart palette, else the workspace's accent.
    private var palette: [String] {
        let branding = ArtiseWorkspaces.shared.branding
        return branding?.chartPalette ?? [branding?.accentHex].compactMap { $0 }
    }
    
    /// Colours go in order, one per series: setting the third fills the first two with the palette's.
    private func setColor(_ hex: String, at index: Int) {
        var colors = draft.colors
        while colors.count < index {
            colors.append(palette.indices.contains(colors.count) ? palette[colors.count] : "#888888")
        }
        if colors.count == index {
            colors.append(hex)
        } else {
            colors[index] = hex
        }
        draft.colors = Array(colors.prefix(ChartChecks.maxSeries))
    }
    
    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding(get: {
            let hex = draft.colors.indices.contains(index) ? draft.colors[index] : (palette.indices.contains(index) ? palette[index] : "#888888")
            return Color(artiseHex: hex) ?? .gray
        }, set: { color in
            setColor(ChartColorHex.hex(color), at: index)
        })
    }
}

/// The chart's own numbers as a grid: column names on top, a row per label, numbers typed the person's way.
private struct ChartTableSection: View {
    @Binding var draft: ChartDraft
    let locale: Locale
    
    static let cellWidth: CGFloat = 110
    
    var body: some View {
        Section {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.frame(width: 24, height: 1)
                        ForEach(draft.columns.indices, id: \.self) { column in
                            TextField("", text: Binding(get: { draft.columns[column] }, set: { draft.renameColumn(at: column, to: $0) }))
                                .font(.compound.bodyMDSemibold)
                                .frame(width: Self.cellWidth)
                                .contextMenu {
                                    if column > 0, draft.columns.count > 2 {
                                        Button(ArtiseNotesL10n.text("screen_notes_chart_remove_column"), role: .destructive) {
                                            draft.removeColumn(at: column)
                                        }
                                    }
                                }
                        }
                    }
                    ForEach(draft.rows.indices, id: \.self) { row in
                        GridRow {
                            Button {
                                draft.rows.remove(at: row)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.compound.iconCriticalPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ArtiseNotesL10n.text("screen_notes_chart_remove_row"))
                            ForEach(draft.columns.indices, id: \.self) { column in
                                if draft.rows[row].indices.contains(column) {
                                    ChartCellField(cell: cellBinding(row: row, column: column), isLabel: column == 0, locale: locale)
                                        .frame(width: Self.cellWidth)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Button {
                draft.addRow()
            } label: {
                Label(ArtiseNotesL10n.text("screen_notes_chart_add_row"), systemImage: "plus")
            }
            Button {
                draft.addColumn(named: String(format: ArtiseNotesL10n.text("screen_notes_chart_column_new"), draft.columns.count))
            } label: {
                Label(ArtiseNotesL10n.text("screen_notes_chart_add_column"), systemImage: "plus.square.on.square")
            }
            .disabled(draft.columns.count > ChartChecks.maxSeries)
            Button {
                if let text = UIPasteboard.general.string {
                    draft.paste(text, locale: locale)
                }
            } label: {
                Label(ArtiseNotesL10n.text("screen_notes_chart_paste"), systemImage: "doc.on.clipboard")
            }
        } header: {
            Text(ArtiseNotesL10n.text("screen_notes_chart_data"))
                .compoundListSectionHeader()
        }
    }
    
    private func cellBinding(row: Int, column: Int) -> Binding<ChartCell> {
        Binding(get: {
            draft.rows.indices.contains(row) && draft.rows[row].indices.contains(column) ? draft.rows[row][column] : .text("")
        }, set: { cell in
            guard draft.rows.indices.contains(row), draft.rows[row].indices.contains(column) else { return }
            draft.rows[row][column] = cell
        })
    }
}

/// One cell. What's typed stays as typed while the field has focus (so "1,0" isn't turned into "1" mid-number); the
/// cell gets a number whenever the text reads as one in the person's language.
private struct ChartCellField: View {
    @Binding var cell: ChartCell
    let isLabel: Bool
    let locale: Locale
    
    @State private var text = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("", text: $text)
            .keyboardType(isLabel ? .default : .numbersAndPunctuation)
            .multilineTextAlignment(isLabel ? .leading : .trailing)
            .focused($isFocused)
            .onAppear { text = display(cell) }
            .onChange(of: text) { _, typed in
                if isLabel {
                    cell = .text(typed)
                } else {
                    cell = ChartNumbers.parse(typed, locale: locale).map(ChartCell.number) ?? .text(typed)
                }
            }
            .onChange(of: cell) { _, new in
                if !isFocused {
                    text = display(new)
                }
            }
    }
    
    private func display(_ cell: ChartCell) -> String {
        switch cell {
        case .number(let value): ChartNumbers.format(value, locale: locale)
        case .text(let text): text
        }
    }
}

/// Where a sourced chart reads its numbers: the record type, filters, the period, how they're grouped and what's shown.
private struct ChartSourceSection: View {
    @Binding var source: ChartSource
    let recordTypes: [NotesRecordType]
    
    var body: some View {
        Section {
            if recordTypes.isEmpty {
                Text(ArtiseNotesL10n.text("screen_notes_chart_records_none"))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            Picker(ArtiseNotesL10n.text("screen_notes_chart_records"), selection: $source.records) {
                ForEach(withCurrent(recordTypes.map(\.type), source.records), id: \.self) { type in
                    Text(ArtiseNotesL10n.pageType(type)).tag(type)
                }
            }
            Picker(ArtiseNotesL10n.text("screen_notes_chart_period"), selection: $source.period) {
                ForEach(withCurrent(ChartSource.periods, source.period), id: \.self) { period in
                    Text(Self.periodName(period)).tag(period)
                }
            }
            Picker(ArtiseNotesL10n.text("screen_notes_chart_x"), selection: $source.x) {
                ForEach(withCurrent(ChartSource.steps + fields, source.x), id: \.self) { step in
                    Text(Self.stepName(step)).tag(step)
                }
            }
            Picker(ArtiseNotesL10n.text("screen_notes_chart_y"), selection: $source.y) {
                ForEach(withCurrent(yOptions, source.y), id: \.self) { value in
                    Text(Self.valueName(value)).tag(value)
                }
            }
            Picker(ArtiseNotesL10n.text("screen_notes_chart_group"), selection: $source.group) {
                Text(ArtiseNotesL10n.text("screen_notes_chart_none")).tag("")
                ForEach(withCurrent(fields, source.group).filter { !$0.isEmpty }, id: \.self) { field in
                    Text(field).tag(field)
                }
            }
        } header: {
            Text(ArtiseNotesL10n.text("screen_notes_chart_source"))
                .compoundListSectionHeader()
        }
        
        Section {
            ForEach(source.filters.indices, id: \.self) { index in
                HStack {
                    Picker(ArtiseNotesL10n.text("screen_notes_chart_filter_field"), selection: $source.filters[index].field) {
                        ForEach(withCurrent(fields, source.filters[index].field), id: \.self) { field in
                            Text(field).tag(field)
                        }
                    }
                    .labelsHidden()
                    TextField(ArtiseNotesL10n.text("screen_notes_chart_filter_value"), text: $source.filters[index].value)
                        .multilineTextAlignment(.trailing)
                }
                .swipeActions {
                    Button(role: .destructive) { source.filters.remove(at: index) } label: {
                        Label(L10n.actionRemove, systemImage: "trash")
                    }
                }
            }
            Button {
                source.filters.append(ChartFilter(field: fields.first ?? "", value: ""))
            } label: {
                Label(ArtiseNotesL10n.text("screen_notes_chart_filter_add"), systemImage: "line.3.horizontal.decrease")
            }
            .disabled(fields.isEmpty)
        } header: {
            Text(ArtiseNotesL10n.text("screen_notes_chart_filter"))
                .compoundListSectionHeader()
        }
    }
    
    private var fields: [String] {
        recordTypes.first { $0.type == source.records }?.fields ?? []
    }
    
    /// Count, then sum/avg/min/max of each field, the amount field first.
    private var yOptions: [String] {
        let type = recordTypes.first { $0.type == source.records }
        let ordered = [type?.amountField].compactMap { $0 } + fields.filter { $0 != type?.amountField }
        return ["count"] + ordered.flatMap { field in ChartSource.aggregates.map { "\($0)(\(field))" } }
    }
    
    /// The options, with the file's own value kept when it isn't one of them.
    private func withCurrent(_ options: [String], _ current: String) -> [String] {
        current.isEmpty || options.contains(current) ? options : [current] + options
    }
    
    static func periodName(_ period: String) -> String {
        let key = "screen_notes_chart_period_" + period.replacingOccurrences(of: " ", with: "_")
        let text = ArtiseNotesL10n.text(key)
        return text == key ? period : text
    }
    
    static func stepName(_ step: String) -> String {
        guard ChartSource.steps.contains(step) else { return step }
        return ArtiseNotesL10n.text("screen_notes_chart_step_" + step)
    }
    
    /// "count" → "How many"; "sum(amount)" → "Sum of amount".
    static func valueName(_ value: String) -> String {
        if value == "count" {
            return ArtiseNotesL10n.text("screen_notes_chart_y_count")
        }
        guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else { return value }
        let function = String(value[..<open])
        let field = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
        guard ChartSource.aggregates.contains(function) else { return value }
        return String(format: ArtiseNotesL10n.text("screen_notes_chart_y_" + function), field)
    }
}
