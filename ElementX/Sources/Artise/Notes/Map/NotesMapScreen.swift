//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// The chat's notes as a map, built on the phone: pinch to zoom around the fingers, drag to move, double tap to
/// zoom in, tap a note to open it, and buttons to zoom and go back to the whole map, as in the Android app.
/// Pages (people, places and things with a note of their own) are drawn with a ring around them.
struct NotesMapScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    
    @State private var map = NotesMapModel(nodes: [], edges: [])
    @State private var hasLoaded = false
    @State private var viewport = MapViewport.reset
    /// The viewport when a pinch or drag started; gestures change it from there.
    @State private var gestureStart: MapViewport?
    @State private var route: NotesRoute?
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .bottomTrailing) {
                if hasLoaded, map.nodes.isEmpty {
                    Text(ArtiseNotesL10n.text("screen_notes_map_empty"))
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    canvas(size: size)
                        .gesture(gestures(size: size))
                        .onTapGesture(count: 2) { location in
                            viewport = viewport.zoomed(by: MapViewport.step, focusX: location.x, focusY: location.y,
                                                       centerX: size.width / 2, centerY: size.height / 2)
                        }
                        .onTapGesture { location in openNote(at: location, size: size) }
                        .accessibilityElement(children: .contain)
                    zoomControls(size: size)
                }
            }
        }
        .background(.compound.bgCanvasDefault)
        .onAppear { ArtiseAnalyticsClient.shared.screen(.notesMap) }
        .navigationTitle(ArtiseNotesL10n.text("screen_notes_map"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { route in
            NotesDestination(service: service, route: route)
        }
        .task {
            let files = await (try? service.repository.files(roomID: roomID)) ?? []
            let pages = await (try? service.repository.pages(roomID: roomID)) ?? []
            map = await Task.detached { NotesMapBuilder.build(files, pages: pages) }.value
            hasLoaded = true
        }
    }
    
    private func canvas(size: CGSize) -> some View {
        Canvas { context, size in
            let points = map.nodes.map { screenPoint($0, size: size) }
            let edgeColor = Color.compound.borderInteractiveSecondary
            for edge in map.edges {
                var path = Path()
                path.move(to: points[edge.from])
                path.addLine(to: points[edge.to])
                context.stroke(path, with: .color(edgeColor), lineWidth: 1.5)
            }
            for (index, node) in map.nodes.enumerated() {
                let radius = nodeRadius(node)
                let point = points[index]
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(node.isPage ? .compound.iconAccentPrimary : .compound.iconAccentTertiary))
                if node.isPage {
                    let ring = radius + 3
                    context.stroke(Path(ellipseIn: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2)),
                                   with: .color(.compound.iconAccentPrimary), lineWidth: 1.5)
                }
                let label = context.resolve(Text(node.name).font(.compound.bodySM).foregroundStyle(Color.compound.textSecondary))
                let labelSize = label.measure(in: CGSize(width: 120, height: 40))
                context.draw(label, in: CGRect(x: point.x - labelSize.width / 2, y: point.y + radius + 2, width: labelSize.width, height: labelSize.height))
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }
    
    private func zoomControls(size: CGSize) -> some View {
        let center = (x: size.width / 2, y: size.height / 2)
        return VStack(spacing: 8) {
            Button {
                viewport = viewport.zoomed(by: MapViewport.step, focusX: center.x, focusY: center.y, centerX: center.x, centerY: center.y)
            } label: {
                CompoundIcon(\.zoomIn)
            }
            .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_map_zoom_in"))
            Button {
                viewport = viewport.zoomed(by: 1 / MapViewport.step, focusX: center.x, focusY: center.y, centerX: center.x, centerY: center.y)
            } label: {
                CompoundIcon(\.zoomOut)
            }
            .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_map_zoom_out"))
            Button { viewport = .reset } label: {
                CompoundIcon(\.locationNavigatorCentred)
            }
            .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_map_reset"))
            .disabled(viewport.isReset)
        }
        .buttonStyle(.compound(.secondary, size: .toolbarIcon))
        .padding(16)
    }
    
    /// Pinch zooms around the point between the fingers; a drag moves the map.
    private func gestures(size: CGSize) -> some Gesture {
        let center = (x: size.width / 2, y: size.height / 2)
        let magnify = MagnifyGesture()
            .onChanged { value in
                let start = gestureStart ?? viewport
                gestureStart = start
                viewport = start.zoomed(by: value.magnification, focusX: value.startLocation.x, focusY: value.startLocation.y,
                                        centerX: center.x, centerY: center.y)
            }
            .onEnded { _ in gestureStart = nil }
        let drag = DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = gestureStart ?? viewport
                gestureStart = start
                viewport = start.panned(byX: value.translation.width, y: value.translation.height)
            }
            .onEnded { _ in gestureStart = nil }
        return magnify.simultaneously(with: drag)
    }
    
    /// A note's 0…1 position on the map, in a square centered on the screen, zoomed and moved.
    private func screenPoint(_ node: MapNode, size: CGSize) -> CGPoint {
        let side = min(size.width, size.height)
        let baseX = (size.width - side) / 2 + node.x * side
        let baseY = (size.height - side) / 2 + node.y * side
        let point = viewport.toScreen(x: baseX, y: baseY, centerX: size.width / 2, centerY: size.height / 2)
        return CGPoint(x: point.x, y: point.y)
    }
    
    /// Notes linked with more notes are bigger.
    private func nodeRadius(_ node: MapNode) -> Double {
        6 * (1 + Double(min(node.degree, 5)) / 5)
    }
    
    /// Opens the note nearest the tap, if the tap is on or close to its dot or name.
    private func openNote(at location: CGPoint, size: CGSize) {
        let nearest = map.nodes.min { lhs, rhs in
            distance(screenPoint(lhs, size: size), location) < distance(screenPoint(rhs, size: size), location)
        }
        guard let nearest, distance(screenPoint(nearest, size: size), location) < 32 else { return }
        route = .note(roomID: roomID, path: nearest.path)
    }
    
    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
