//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The editor's attach button: a photo from the library, a file, or a new photo from the camera.
/// The file is added to the chat's `attachments/` at once (it uploads with the next sync) and embedded where the cursor is.
struct NoteAttachMenu: View {
    let service: ArtiseNotesService
    let roomID: String
    @Binding var model: NoteEditorModel
    
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var showsFileImporter = false
    @State private var showsCamera = false
    @State private var isAttaching = false
    @State private var problem: String?
    
    /// The server takes files up to 50 MB.
    static let maxBytes = 50 * 1024 * 1024
    
    var body: some View {
        Menu {
            Button { showsPhotoPicker = true } label: {
                Label(ArtiseNotesL10n.text("screen_notes_attach_photo"), systemImage: "photo")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showsCamera = true } label: {
                    Label(ArtiseNotesL10n.text("screen_notes_attach_take_photo"), systemImage: "camera")
                }
            }
            Button { showsFileImporter = true } label: {
                Label(ArtiseNotesL10n.text("screen_notes_attach_file"), systemImage: "doc")
            }
        } label: {
            Group {
                if isAttaching {
                    ProgressView()
                } else {
                    Image(systemName: "paperclip")
                }
            }
            .frame(width: 44, height: 44)
        }
        .foregroundStyle(.compound.iconPrimary)
        .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_attach"))
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await attachPhoto(item) }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.item]) { result in
            guard case let .success(url) = result else { return }
            Task { await attachFile(url) }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            NoteCameraView { image in
                guard let data = image.jpegData(compressionQuality: NotesPhotoConverter.jpegQuality) else { return }
                Task { await attach(data: data, fileName: Self.cameraFileName(), contentType: "image/jpeg") }
            }
            .ignoresSafeArea()
        }
        .alert(problem ?? "", isPresented: Binding(get: { problem != nil }, set: {
            if !$0 {
                problem = nil
            }
        })) {
            Button(L10n.actionOk) { }
        }
    }
    
    private func attachPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            problem = ArtiseNotesL10n.text("screen_notes_attach_failed")
            return
        }
        let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
        let name = "IMG_" + Self.timestamp() + "." + (type.preferredFilenameExtension ?? "jpg")
        await attach(data: data, fileName: name, contentType: type.preferredMIMEType ?? "image/jpeg")
    }
    
    private func attachFile(_ url: URL) async {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            problem = ArtiseNotesL10n.text("screen_notes_attach_failed")
            return
        }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        await attach(data: data, fileName: url.lastPathComponent, contentType: type)
    }
    
    private func attach(data: Data, fileName: String, contentType: String) async {
        guard data.count <= Self.maxBytes else {
            problem = ArtiseNotesL10n.text("screen_notes_attach_too_big")
            return
        }
        isAttaching = true
        defer { isAttaching = false }
        do {
            let path = try await service.repository.addAttachment(roomID: roomID, fileName: fileName, data: data, contentType: contentType)
            model.insert(Self.embed(for: path, in: model), now: .now)
            // Upload now if there's a connection; otherwise it waits in the queue.
            service.repository.syncInBackground(roomID: roomID)
        } catch {
            problem = ArtiseNotesL10n.text("screen_notes_attach_failed")
        }
    }
    
    /// `![[name]]` on its own line, with blank lines around it, which every Markdown app reads as its own paragraph.
    static func embed(for path: String, in model: NoteEditorModel) -> String {
        let text = model.text
        let at = model.selection.upperBound
        let before = text.utf16Prefix(at)
        let after = text.utf16Suffix(from: at)
        let leading = at == 0 || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        let trailing = after.hasPrefix("\n\n") ? "" : "\n\n"
        return leading + "![[" + NotesFolderEntries.fileName(path) + "]]" + trailing
    }
    
    private static func cameraFileName() -> String {
        "IMG_" + timestamp() + ".jpg"
    }
    
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: .now)
    }
}

private extension String {
    func utf16Prefix(_ length: Int) -> String {
        NSString(string: self).substring(to: min(length, utf16.count))
    }
    
    func utf16Suffix(from offset: Int) -> String {
        NSString(string: self).substring(from: min(offset, utf16.count))
    }
}

/// The camera, for taking a photo straight into a note.
struct NoteCameraView: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ picker: UIImagePickerController, context: Context) { }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NoteCameraView
        
        init(parent: NoteCameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPhoto(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
