//
//  ReferenceListView.swift
//  QRDesktop
//

import AppKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// NSColorPanel reports color changes to a target/action pair, not a closure -
/// this just adapts that to the closure the view wants, and needs to be
/// retained (via @State) for as long as the panel might call back into it.
private class ColorPanelHandler: NSObject {
    let onChange: (NSColor) -> Void

    init(onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        onChange(sender.color)
    }
}

/// QLPreviewPanel needs a data source object to hand it the item to preview -
/// same retained-handler pattern as ColorPanelHandler above.
private class QuickLookHandler: NSObject, QLPreviewPanelDataSource {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL
    }
}

struct ReferenceListView: View {
    var library: ReferenceLibrary
    @State private var statusMessage: String?
    @State private var selectedDisplayID: UInt32?
    @State private var expandedBoardID: UUID?
    @State private var colorPanelHandler: ColorPanelHandler?
    @State private var quickLookHandler: QuickLookHandler?
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var previewOverlay = PeekOverlayController()
    @State private var previewedBoardID: UUID?

    private var sortedBoards: [ReferenceBoard] {
        library.boards.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { newValue in
                LaunchAtLogin.setEnabled(newValue)
                launchAtLoginEnabled = LaunchAtLogin.isEnabled
            }
        )
    }

    private var screens: [NSScreen] { NSScreen.screens }

    private var targetScreen: NSScreen? {
        screens.first { $0.displayID == selectedDisplayID } ?? screens.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Reference Desktop")
                .font(.headline)
                .padding([.horizontal, .top])

            if screens.count > 1 {
                Picker("Screen", selection: $selectedDisplayID) {
                    ForEach(screens, id: \.displayID) { screen in
                        Text(screen.localizedName).tag(screen.displayID)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
            }

            sheetsSection
            imagesSection

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            HStack {
                Button("Previous") { advanceBoard(by: -1) }
                Button("Next") { advanceBoard(by: 1) }
            }
            .padding(.horizontal)

            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .padding([.horizontal, .bottom])
        }
        .frame(width: 340)
        // MenuBarExtra's .window style defaults to a translucent/vibrant
        // background that samples whatever's behind it - with a busy desktop
        // picture that can wash out our own UI to the point of being
        // unreadable. Force a fully opaque background so nothing behind the
        // popover can ever show through.
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedDisplayID == nil {
                selectedDisplayID = NSScreen.main?.displayID ?? screens.first?.displayID
            }
        }
        .onDisappear {
            previewOverlay.hide()
            previewedBoardID = nil
        }
    }

    // MARK: - Sheets (boards)

    private var sheetsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sheets").font(.subheadline).bold()
                Spacer()
                Button("+1") { addBoard(layoutCount: 1) }
                Button("+2") { addBoard(layoutCount: 2) }
                Button("+3") { addBoard(layoutCount: 3) }
            }
            .padding(.horizontal)

            if library.boards.isEmpty {
                Text("No sheets yet. Add one above.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                List(sortedBoards) { board in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button {
                                previewBoard(board)
                            } label: {
                                Text(board.displayName)
                                    .fontWeight(isCurrent(board) ? .bold : .regular)
                                    .foregroundStyle(previewedBoardID == board.id ? Color.accentColor : Color.primary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .help("Click to preview on \(targetScreen?.localizedName ?? "screen")")
                            Spacer()
                            Button("Apply") { applyBoard(board) }
                                .buttonStyle(.borderless)
                            Button("Edit") {
                                expandedBoardID = expandedBoardID == board.id ? nil : board.id
                            }
                            .buttonStyle(.borderless)
                            Button("Delete", role: .destructive) {
                                if previewedBoardID == board.id {
                                    previewOverlay.hide()
                                    previewedBoardID = nil
                                }
                                library.deleteBoard(board)
                            }
                            .buttonStyle(.borderless)
                        }

                        if expandedBoardID == board.id {
                            TextField("Sheet name", text: nameBinding(for: board))
                                .textFieldStyle(.plain)
                                .font(.caption)

                            ForEach(0..<board.layoutCount, id: \.self) { slot in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Slot \(slot + 1)").font(.caption).bold()

                                    HStack {
                                        Picker("Image", selection: slotPathBinding(board: board, slot: slot)) {
                                            Text("None").tag("")
                                            ForEach(library.images) { image in
                                                Label {
                                                    Text(image.displayName)
                                                } icon: {
                                                    if let thumb = library.thumbnail(for: image) {
                                                        Image(nsImage: thumb)
                                                            .resizable()
                                                            .scaledToFit()
                                                            .frame(width: 16, height: 16)
                                                    }
                                                }
                                                .tag(image.sourceURL.path)
                                            }
                                        }
                                        .font(.caption)

                                        if let selectedImage = library.images.first(where: { $0.sourceURL.path == board.slots[slot].path }),
                                           let thumb = library.thumbnail(for: selectedImage) {
                                            Image(nsImage: thumb)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 24, height: 24)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }

                                    Picker("Scale", selection: slotScaleModeBinding(board: board, slot: slot)) {
                                        Text("Fit").tag(BoardScaleMode.fit)
                                        Text("Fill").tag(BoardScaleMode.fill)
                                    }
                                    .pickerStyle(.segmented)

                                    HStack {
                                        Text("Background").font(.caption)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(nsColor: NSColor(hex: board.slots[slot].backgroundColorHex) ?? .black))
                                            .frame(width: 20, height: 14)
                                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary, lineWidth: 0.5))
                                        Button("Choose…") { chooseBackgroundColor(board: board, slot: slot) }
                                            .buttonStyle(.borderless)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 2)

                                if slot < board.layoutCount - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
            }
        }
    }

    private func nameBinding(for board: ReferenceBoard) -> Binding<String> {
        Binding(
            get: { board.name ?? "" },
            set: { newValue in library.setBoardName(boardID: board.id, name: newValue) }
        )
    }

    /// Floats the sheet on the currently targeted screen without applying it -
    /// tap again (or tap a different sheet, or close the menu) to dismiss.
    private func previewBoard(_ board: ReferenceBoard) {
        guard let targetScreen else { return }

        if previewedBoardID == board.id {
            previewOverlay.hide()
            previewedBoardID = nil
            return
        }

        guard let url = library.previewImageURL(for: board, screen: targetScreen),
              let image = NSImage(contentsOf: url) else {
            statusMessage = "Couldn't preview that sheet - assign at least one image to a slot."
            return
        }
        previewOverlay.show(image: image, on: targetScreen)
        previewedBoardID = board.id
    }

    private func slotPathBinding(board: ReferenceBoard, slot: Int) -> Binding<String> {
        Binding(
            get: { board.slots[slot].path ?? "" },
            set: { newValue in
                library.setSlotPath(boardID: board.id, slotIndex: slot, path: newValue.isEmpty ? nil : newValue)
                reapply(boardID: board.id)
            }
        )
    }

    private func slotScaleModeBinding(board: ReferenceBoard, slot: Int) -> Binding<BoardScaleMode> {
        Binding(
            get: { board.slots[slot].scaleMode },
            set: { newValue in
                library.setSlotScaleMode(boardID: board.id, slotIndex: slot, scaleMode: newValue)
                reapply(boardID: board.id)
            }
        )
    }

    /// SwiftUI's ColorPicker drives NSColorPanel internally, which - like
    /// .fileImporter - doesn't reliably surface from a MenuBarExtra popover.
    /// Driving NSColorPanel directly (same fix as chooseFiles) works instead.
    private func chooseBackgroundColor(board: ReferenceBoard, slot: Int) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSColorPanel.shared
        panel.color = NSColor(hex: board.slots[slot].backgroundColorHex) ?? .black
        panel.showsAlpha = false

        let handler = ColorPanelHandler { [self] newColor in
            library.setSlotBackgroundColor(boardID: board.id, slotIndex: slot, hex: newColor.hexString)
            reapply(boardID: board.id)
        }
        colorPanelHandler = handler
        panel.setTarget(handler)
        panel.setAction(#selector(ColorPanelHandler.colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    private func reapply(boardID: UUID) {
        if let updated = library.boards.first(where: { $0.id == boardID }) {
            applyBoard(updated)
        }
    }

    private func isCurrent(_ board: ReferenceBoard) -> Bool {
        guard let targetScreen else { return false }
        return library.currentBoard(for: targetScreen)?.id == board.id
    }

    private func addBoard(layoutCount: Int) {
        let board = library.createBoard(layoutCount: layoutCount)
        expandedBoardID = board.id
    }

    private func applyBoard(_ board: ReferenceBoard) {
        guard let targetScreen else { return }
        if library.selectBoard(board, for: targetScreen) {
            statusMessage = "Set \"\(board.summary)\" on \(targetScreen.localizedName)."
        } else {
            statusMessage = "Couldn't apply that sheet - assign at least one image to a slot."
        }
    }

    private func advanceBoard(by delta: Int) {
        guard let targetScreen else { return }
        library.advanceBoard(by: delta, for: targetScreen)
    }

    // MARK: - Image pool

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Images").font(.subheadline).bold()
                Spacer()
                Button("Add Images…") { chooseFiles() }
            }
            .padding(.horizontal)

            if library.images.isEmpty {
                Text("No images yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                List(library.images) { image in
                    HStack {
                        Button {
                            quickLook(image)
                        } label: {
                            if let thumb = library.thumbnail(for: image) {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Click to preview")

                        TextField("Name", text: nameBinding(for: image))
                            .textFieldStyle(.plain)

                        Spacer()
                        Button("Remove", role: .destructive) {
                            library.remove(image)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
            }
        }
    }

    private func nameBinding(for image: ReferenceImage) -> Binding<String> {
        Binding(
            get: { image.displayName },
            set: { newValue in library.setCustomName(for: image, name: newValue) }
        )
    }

    /// QLPreviewPanel is a shared system panel, same "drive it directly" fix
    /// as the color and open panels above.
    private func quickLook(_ image: ReferenceImage) {
        NSApp.activate(ignoringOtherApps: true)
        guard let panel = QLPreviewPanel.shared() else { return }
        let handler = QuickLookHandler(url: image.sourceURL)
        quickLookHandler = handler
        panel.dataSource = handler
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    private func chooseFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .pdf]

        panel.begin { response in
            guard response == .OK, panel.urls.isEmpty == false else { return }
            library.addImages(at: panel.urls)
            statusMessage = "Added \(panel.urls.count) file\(panel.urls.count == 1 ? "" : "s")."
        }
    }
}
