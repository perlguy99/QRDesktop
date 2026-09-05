//
//  ReferenceListView.swift
//  QRDesktop
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReferenceListView: View {
    var library: ReferenceLibrary
    @State private var statusMessage: String?
    @State private var selectedDisplayID: UInt32?

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

            if library.images.isEmpty {
                Text("No reference images yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                List(library.images) { image in
                    HStack {
                        Text(image.displayName)
                            .fontWeight(isCurrent(image) ? .bold : .regular)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            library.remove(image)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        select(image)
                    }
                }
                .frame(minHeight: 160, maxHeight: 260)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            HStack {
                Button("Previous") { advance(by: -1) }
                Button("Next") { advance(by: 1) }
                Spacer()
                Button("Add Images…") { chooseFiles() }
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 320)
        .onAppear {
            if selectedDisplayID == nil {
                selectedDisplayID = NSScreen.main?.displayID ?? screens.first?.displayID
            }
        }
    }

    private func isCurrent(_ image: ReferenceImage) -> Bool {
        guard let targetScreen else { return false }
        return library.currentImage(for: targetScreen)?.id == image.id
    }

    private func select(_ image: ReferenceImage) {
        guard let targetScreen else { return }
        if library.select(image, for: targetScreen) {
            statusMessage = "Set \"\(image.displayName)\" on \(targetScreen.localizedName)."
        } else {
            statusMessage = "Couldn't use \"\(image.displayName)\" as a desktop background."
        }
    }

    private func advance(by delta: Int) {
        guard let targetScreen else { return }
        library.advance(by: delta, for: targetScreen)
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
            if let firstNew = library.images.last {
                select(firstNew)
            }
        }
    }
}
