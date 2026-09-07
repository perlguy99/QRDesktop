//
//  PeekOverlay.swift
//  QRDesktop
//

import AppKit

/// Floats each screen's current sheet on top of everything else - a
/// borderless, click-through window per screen at a very high window level,
/// showing the exact same image already sitting in the desktop picture.
@MainActor
final class PeekOverlayController {
    private var windows: [NSWindow] = []

    func show(library: ReferenceLibrary) {
        hide()

        for screen in NSScreen.screens {
            guard let url = library.previewImageURL(for: screen) else {
                print("[Peek] no board/preview for screen \(screen.localizedName)")
                continue
            }
            guard let image = NSImage(contentsOf: url) else {
                print("[Peek] found URL but couldn't load image: \(url.path)")
                continue
            }
            print("[Peek] showing \(url.lastPathComponent) on \(screen.localizedName)")

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = image
            imageView.imageScaling = .scaleAxesIndependently
            window.contentView = imageView

            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    var isVisible: Bool {
        !windows.isEmpty
    }
}

/// Ties the hotkey to peek-vs-pin behavior: press-and-hold shows the overlay
/// only while held, hiding the instant you release. Two presses in quick
/// succession (a double-tap) latches it open instead; a single tap while
/// latched dismisses it.
@MainActor
final class PeekCoordinator {
    private let hotKey = PeekHotKey()
    private let overlay = PeekOverlayController()
    private let library: ReferenceLibrary
    private var isPinned = false
    private var lastReleaseAt: Date?
    private let doubleTapWindow: TimeInterval = 0.35

    init(library: ReferenceLibrary, keyCode: UInt32, modifiers: UInt32 = 0) {
        self.library = library
        hotKey.onPressed = { [weak self] in self?.handlePressed() }
        hotKey.onReleased = { [weak self] in self?.handleReleased() }
        hotKey.register(keyCode: keyCode, modifiers: modifiers)
    }

    private func handlePressed() {
        if isPinned {
            // A tap while pinned dismisses it.
            isPinned = false
            lastReleaseAt = nil
            overlay.hide()
            return
        }

        if let lastReleaseAt, Date().timeIntervalSince(lastReleaseAt) < doubleTapWindow {
            // Second press of a double-tap - latch it open.
            isPinned = true
            self.lastReleaseAt = nil
        }

        overlay.show(library: library)
    }

    private func handleReleased() {
        guard !isPinned else { return }
        overlay.hide()
        lastReleaseAt = Date()
    }
}
