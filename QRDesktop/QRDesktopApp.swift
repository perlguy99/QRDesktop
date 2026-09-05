//
//  QRDesktopApp.swift
//  QRDesktop
//

import SwiftUI

@main
struct QRDesktopApp: App {
    @State private var library = ReferenceLibrary()

    var body: some Scene {
        MenuBarExtra("QR Desktop", systemImage: "photo.on.rectangle.angled") {
            ReferenceListView(library: library)
        }
        .menuBarExtraStyle(.window)
    }
}
