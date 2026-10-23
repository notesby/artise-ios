//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI
import WebKit

/// A chart's or dashboard's picture as the server draws it, in the screen's light or dark: the phone's last copy at
/// once, then the server's current one (an unchanged picture costs a `304`). The kind's icon until there's one.
struct NoteDrawingImage: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    /// 128 or 256 in lists, 512 on cards, 1024 on the chart's screen.
    let size: Int
    var fill = false
    var icon: KeyPath<CompoundIcons, Image> = \.chart
    var iconSize: CGFloat = 24
    /// Changed to ask the server again (pull to refresh, the chart edited).
    var reload = 0
    var onFailure: ((Bool) -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image {
                if fill {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                CompoundIcon(icon, size: .custom(iconSize), relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(path)|\(size)|\(mode.rawValue)|\(reload)") { await load() }
    }
    
    private var mode: NoteDrawingMode {
        colorScheme == .dark ? .dark : .light
    }
    
    private func load() async {
        let repository = service.repository
        if image == nil, let cached = await repository.cachedDrawing(roomID: roomID, path: path, size: size, mode: mode) {
            image = await Self.picture(cached)
        }
        let current = try? await repository.drawing(roomID: roomID, path: path, size: size, mode: mode)
        guard !Task.isCancelled else { return }
        if let current {
            image = await Self.picture(current)
        }
        onFailure?(image == nil)
    }
    
    nonisolated static func picture(_ url: URL) async -> UIImage? {
        await Task.detached { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
    }
}

/// A chart on its own: as wide as the screen, with its title, caption and the day its records were read, Edit and
/// Share. Pulling down asks the server again, since a chart that reads records changes.
struct NoteChartScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var chart: NotesChart?
    @State private var file: LocalFile?
    @State private var failed = false
    @State private var reload = 0
    @State private var isEditing = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                NoteDrawingImage(service: service, roomID: roomID, path: path, size: 1024, iconSize: 48, reload: reload) { failed in
                    self.failed = failed
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityElement()
                .accessibilityLabel(String(format: ArtiseNotesL10n.text("a11y_notes_chart"), accessibilityText))
                .accessibilityAddTraits(.isImage)
                if failed {
                    // Offline before it was ever drawn here, or a chart the server can't draw now.
                    Text(ArtiseNotesL10n.text("screen_notes_chart_failed"))
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                if let caption = chart?.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                }
                if let asOf = chart?.asOf, !asOf.isEmpty {
                    Text(String(format: ArtiseNotesL10n.text("screen_notes_chart_as_of"), Self.day(asOf)))
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
            }
            .padding(16)
        }
        .background(.compound.bgCanvasDefault)
        .navigationTitle(NotesFolderEntries.fileName(path))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(again: true) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.actionEdit) { isEditing = true }
                    .disabled(file?.content == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                NoteShareMenu(service: service, roomID: roomID, path: path, title: title, formats: [.png, .pdf])
            }
        }
        .fullScreenCover(isPresented: $isEditing, onDismiss: { Task { await load(again: true) } }) {
            NoteChartEditorScreen(service: service, roomID: roomID, path: path) { _ in isEditing = false }
        }
        .task(id: colorScheme) { await load(again: false) }
    }
    
    private var title: String {
        chart?.title.isEmpty == false ? chart?.title ?? "" : file?.title ?? NotesFolderEntries.fileName(path)
    }
    
    private var accessibilityText: String {
        chart?.accessibilityText ?? title
    }
    
    private func load(again: Bool) async {
        let repository = service.repository
        file = try? await repository.file(roomID: roomID, path: path)
        if again {
            _ = try? await repository.sync(roomID: roomID)
            file = try? await repository.file(roomID: roomID, path: path)
            reload += 1
        }
        do {
            chart = try await repository.chart(roomID: roomID, path: path, mode: colorScheme == .dark ? .dark : .light)
        } catch {
            // Offline, the phone's last picture still shows; the title comes from the tree.
            MXLog.info("Notes: chart not read: \(error)")
        }
    }
    
    /// "2026-10-23" as the person's language writes a day.
    static func day(_ text: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(text.prefix(10))) else { return text }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// A dashboard: the server's page of its text and charts, in a web view that follows the device's light or dark.
/// Edit opens the note in the editor, where its charts show as a layout; a business report Ari rewrites each period is
/// only shared.
struct NoteDashboardScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    /// Opens the editor right away, for a dashboard just created.
    var startsEditing = false
    
    @State private var html: String?
    @State private var file: LocalFile?
    @State private var failed = false
    @State private var isEditing = false
    
    var body: some View {
        VStack(spacing: 0) {
            if file?.isReadOnly == true {
                Text(ArtiseNotesL10n.text("screen_notes_readonly"))
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.compound.bgSubtleSecondary)
            }
            if let html {
                NoteDashboardWebView(html: html) { await load(syncingFirst: true) }
            } else if failed {
                Text(ArtiseNotesL10n.text("screen_notes_dashboard_failed"))
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.compound.bgCanvasDefault)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if file?.isReadOnly != true {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.actionEdit) { isEditing = true }
                        .disabled(file?.content == nil)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NoteShareMenu(service: service, roomID: roomID, path: path, title: title, formats: [.pdf])
            }
        }
        .fullScreenCover(isPresented: $isEditing, onDismiss: { Task { await load(syncingFirst: true) } }) {
            NoteEditorScreen(service: service, roomID: roomID, path: path) { isEditing = false }
        }
        .task {
            if startsEditing {
                isEditing = true
            }
            await load(syncingFirst: startsEditing)
        }
    }
    
    private var title: String {
        file?.title ?? NotesFolderEntries.noteName(path)
    }
    
    /// After an edit, the edit is sent first so the page drawn is the new one.
    private func load(syncingFirst: Bool = false) async {
        let repository = service.repository
        if syncingFirst {
            _ = try? await repository.sync(roomID: roomID)
        }
        file = try? await repository.file(roomID: roomID, path: path)
        do {
            html = try await repository.dashboard(roomID: roomID, path: path)
            failed = false
        } catch {
            MXLog.info("Notes: dashboard not read: \(error)")
            failed = html == nil
        }
    }
}

/// The dashboard's page. It has no scripts and no links into the app: any link it might hold stays put. Pulling down
/// fetches it again.
struct NoteDashboardWebView: UIViewRepresentable {
    let html: String
    let onRefresh: () async -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onRefresh: onRefresh)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        view.scrollView.refreshControl = refresh
        return view
    }
    
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onRefresh = onRefresh
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(html, baseURL: nil)
    }
    
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onRefresh: () async -> Void
        var loaded: String?
        
        init(onRefresh: @escaping () async -> Void) {
            self.onRefresh = onRefresh
        }
        
        @objc func refresh(_ control: UIRefreshControl) {
            Task { @MainActor in
                await onRefresh()
                control.endRefreshing()
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .other ? .allow : .cancel
        }
    }
}

/// Share for a chart, a dashboard or a note: the file the server makes now (a chart's picture or PDF, a page's PDF),
/// fetched only when chosen, handed to the share sheet (WhatsApp, Mail, Files…); and asking Ari for a link, since only
/// Ari can make one.
struct NoteShareMenu: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    let title: String
    let formats: [NoteExportFormat]
    
    @State private var isExporting = false
    @State private var shared: SharedFile?
    @State private var asksForLink = false
    @State private var message: String?
    
    var body: some View {
        Menu {
            ForEach(formats, id: \.self) { format in
                Button { export(format) } label: {
                    Label(ArtiseNotesL10n.text(format == .png ? "screen_notes_share_picture" : "screen_notes_share_pdf"),
                          icon: format == .png ? \.image : \.document)
                }
            }
            Button { asksForLink = true } label: {
                Label(ArtiseNotesL10n.text("screen_notes_ask_link"), icon: \.link)
            }
        } label: {
            if isExporting {
                ProgressView()
                    .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_exporting"))
            } else {
                CompoundIcon(\.shareIos)
            }
        }
        .disabled(isExporting)
        .accessibilityLabel(ArtiseNotesL10n.text("screen_notes_share"))
        .sheet(item: $shared) { file in
            NoteActivitySheet(url: file.url)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(ArtiseNotesL10n.text("screen_notes_ask_link"), isPresented: $asksForLink, titleVisibility: .visible) {
            Button(ArtiseNotesL10n.text("screen_notes_ask_link")) { askForLink() }
            Button(L10n.actionCancel, role: .cancel) { }
        } message: {
            Text(ArtiseNotesL10n.text("screen_notes_ask_link_note"))
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: {
            if !$0 {
                message = nil
            }
        })) {
            Button(L10n.actionOk) { }
        }
    }
    
    private func export(_ format: NoteExportFormat) {
        isExporting = true
        let repository = service.repository
        Task {
            defer { isExporting = false }
            do {
                shared = try await SharedFile(url: repository.export(roomID: roomID, path: path, format: format))
            } catch {
                MXLog.error("Notes: export failed: \(error)")
                message = ArtiseNotesL10n.text("screen_notes_export_failed")
            }
        }
    }
    
    private func askForLink() {
        Task {
            let sent = await service.askForLink(roomID: roomID, title: title)
            message = ArtiseNotesL10n.text(sent ? "screen_notes_ask_link_sent" : "screen_notes_ask_link_failed")
        }
    }
    
    struct SharedFile: Identifiable {
        let url: URL
        
        var id: URL {
            url
        }
    }
}

/// The system share sheet for one file.
struct NoteActivitySheet: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
