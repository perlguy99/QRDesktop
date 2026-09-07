//
//  QRDesktopApp.swift
//  QRDesktop
//

import Carbon.HIToolbox
import SwiftUI

@main
struct QRDesktopApp: App {
    @State private var library: ReferenceLibrary
    private let peekCoordinator: PeekCoordinator

    init() {
        setbuf(stdout, nil) // so console/log redirection shows print() output immediately
        let library = ReferenceLibrary()
        _library = State(initialValue: library)
        // Plain F6, no modifier - Brent doesn't use function keys for anything
        // else and prefers a single bare key over a modifier combo.
        peekCoordinator = PeekCoordinator(library: library, keyCode: UInt32(kVK_F6))
        library.reapplyCurrentBoards()
    }

    var body: some Scene {
        MenuBarExtra("QR Desktop", systemImage: "photo.on.rectangle.angled") {
            ReferenceListView(library: library)
        }
        .menuBarExtraStyle(.window)
    }
}
