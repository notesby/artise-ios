//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import AVFoundation
import Compound
import SwiftUI
import UniformTypeIdentifiers

/// "Sound" in a chat's notification settings: Default (the app's), one of Element's or the phone's sounds, an audio
/// file from the phone, or no sound. On this phone only.
struct ArtiseChatSoundSection: View {
    let roomID: String
    @State private var sound: ChatSound?
    @State private var isPicking = false
    
    var body: some View {
        if let userID = ArtiseWorkspaces.shared.userID {
            Section {
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_chat_sound"), icon: \.notifications),
                        details: .title(label(for: sound)),
                        kind: .navigationLink { isPicking = true })
            } footer: {
                Text(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_footer"))
                    .compoundListSectionFooter()
            }
            .onAppear { sound = ArtiseChatSounds.store.sound(userID: userID, roomID: roomID) }
            .sheet(isPresented: $isPicking, onDismiss: {
                sound = ArtiseChatSounds.store.sound(userID: userID, roomID: roomID)
            }, content: {
                ArtiseChatSoundPicker(userID: userID, roomID: roomID)
            })
        }
    }
    
    private func label(for sound: ChatSound?) -> String {
        switch sound {
        case .file(_, let label): label
        case .silent: ArtiseWorkspacesL10n.text("screen_artise_chat_sound_none")
        case nil: ArtiseWorkspacesL10n.text("screen_artise_chat_sound_default")
        }
    }
}

struct ArtiseChatSoundPicker: View {
    let userID: String
    let roomID: String
    
    @State private var current: ChatSound?
    @State private var customTones: [NotificationTone] = []
    @State private var isImporting = false
    @State private var pendingLongFile: (url: URL, minutes: String)?
    @State private var errorMessage: String?
    @State private var player: AVAudioPlayer?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    row(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_default"), isSelected: current == nil) {
                        ArtiseChatSounds.reset(userID: userID, roomID: roomID)
                        current = nil
                    }
                }
                Section {
                    ForEach(customTones, id: \.self) { tone in
                        toneRow(tone)
                            .swipeActions {
                                Button(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_remove"), role: .destructive) { remove(tone) }
                            }
                            .contextMenu {
                                Button(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_remove"), role: .destructive) { remove(tone) }
                            }
                    }
                    ListRow(label: .action(title: ArtiseWorkspacesL10n.text("screen_artise_chat_sound_pick_file"), icon: \.plus),
                            kind: .button { isImporting = true })
                } header: {
                    Text(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_yours"))
                        .compoundListSectionHeader()
                }
                Section {
                    ForEach(NotificationToneManager.allDefaultAlerts, id: \.self) { tone in
                        toneRow(tone)
                    }
                }
                Section {
                    row(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_none"), isSelected: current == .silent) {
                        ArtiseChatSounds.silence(userID: userID, roomID: roomID)
                        current = .silent
                    }
                }
            }
            .compoundList()
            .navigationTitle(ArtiseWorkspacesL10n.text("screen_artise_chat_sound"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone) { dismiss() }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.audioTypes) { result in
                if case .success(let url) = result {
                    check(url)
                }
            }
            .alert(longFileTitle, isPresented: isAskingAboutLongFile) {
                Button(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_long_use")) {
                    if let url = pendingLongFile?.url {
                        Task { await importFile(url) }
                    }
                }
                Button(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_long_other")) { isImporting = true }
                Button(L10n.actionCancel, role: .cancel) { }
            } message: {
                Text(ArtiseWorkspacesL10n.text("screen_artise_chat_sound_long_message"))
            }
            .alert(errorMessage ?? "", isPresented: .init(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })) {
                Button(L10n.actionOk) { }
            }
        }
        .onAppear {
            current = ArtiseChatSounds.store.sound(userID: userID, roomID: roomID)
            customTones = ArtiseChatSounds.toneManager.customTones()
        }
    }
    
    // MARK: - Rows
    
    private func toneRow(_ tone: NotificationTone) -> some View {
        row(tone.label, isSelected: {
            if case .file(_, tone.label) = current {
                true
            } else {
                false
            }
        }()) {
            do {
                try ArtiseChatSounds.choose(tone, userID: userID, roomID: roomID)
                current = ArtiseChatSounds.store.sound(userID: userID, roomID: roomID)
                play(NotificationToneManager.toneLocation(for: tone))
            } catch {
                MXLog.error("Couldn't set the chat's sound: \(error)")
                errorMessage = ArtiseWorkspacesL10n.text("screen_artise_chat_sound_error")
            }
        }
    }
    
    /// Takes a picked file out of "Your sounds"; chats that used it go back to Default.
    private func remove(_ tone: NotificationTone) {
        do {
            try ArtiseChatSounds.removeFromYourSounds(tone, userID: userID)
        } catch {
            MXLog.error("Couldn't remove the sound: \(error)")
            errorMessage = ArtiseWorkspacesL10n.text("screen_artise_chat_sound_error")
        }
        customTones = ArtiseChatSounds.toneManager.customTones()
        current = ArtiseChatSounds.store.sound(userID: userID, roomID: roomID)
    }
    
    private func row(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        ListRow(label: .plain(title: title), kind: .selection(isSelected: isSelected, action: action))
    }
    
    // MARK: - Picking a file
    
    private static let audioTypes: [UTType] = [.mp3, .aiff, .wav, UTType("com.apple.m4a-audio"), UTType("com.apple.coreaudio-format"),
                                               UTType("public.mpeg-4-audio")].compactMap(\.self)
    
    private var isAskingAboutLongFile: Binding<Bool> {
        .init(get: { pendingLongFile != nil }, set: {
            if !$0 {
                pendingLongFile = nil
            }
        })
    }
    
    private var longFileTitle: String {
        String(format: ArtiseWorkspacesL10n.text("screen_artise_chat_sound_long_title"), pendingLongFile?.minutes ?? "")
    }
    
    /// Refuses big files, and warns before a long one is cut to 30 seconds.
    private func check(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = ArtiseWorkspacesL10n.text("screen_artise_chat_sound_error")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= ArtiseChatSounds.maxBytes else {
            errorMessage = ArtiseWorkspacesL10n.text("screen_artise_chat_sound_too_big")
            return
        }
        if let seconds = ArtiseChatSounds.duration(of: url), seconds > ArtiseChatSounds.maxSeconds {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .short
            formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
            pendingLongFile = (url, formatter.string(from: seconds) ?? "")
        } else {
            Task { await importFile(url) }
        }
    }
    
    /// Adds the file to "Your sounds" (converted, cut to 30 seconds) and picks it for this chat.
    private func importFile(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            try await ArtiseChatSounds.toneManager.addNewToneToLibrary(from: url)
        } catch NotificationToneManager.ManagerError.fileAlreadyExists {
            // Picked before: it's already in "Your sounds".
        } catch {
            MXLog.error("Couldn't add the picked sound: \(error)")
            errorMessage = ArtiseWorkspacesL10n.text("screen_artise_chat_sound_error")
            return
        }
        customTones = ArtiseChatSounds.toneManager.customTones()
        let name = url.deletingPathExtension().lastPathComponent
        if let tone = customTones.first(where: { $0.label == name }) {
            try? ArtiseChatSounds.choose(tone, userID: userID, roomID: roomID)
            current = ArtiseChatSounds.store.sound(userID: userID, roomID: roomID)
        }
    }
    
    private func play(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
