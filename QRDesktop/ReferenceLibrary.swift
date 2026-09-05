//
//  ReferenceLibrary.swift
//  QRDesktop
//

import AppKit
import Foundation
import PDFKit

struct ReferenceImage: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL

    var displayName: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }

    var isPDF: Bool {
        sourceURL.pathExtension.lowercased() == "pdf"
    }
}

extension NSScreen {
    /// A stable-enough identifier for a physical display across app launches
    /// (tied to the port/display it's connected through).
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@Observable
class ReferenceLibrary {
    private(set) var images: [ReferenceImage] = []

    /// Which image path is currently set on each display, keyed by display ID.
    private var currentPathsByDisplay: [UInt32: String] = [:]

    private let defaults = UserDefaults.standard
    private let pathsKey = "QRDesktop.imagePaths"
    private let selectionsKey = "QRDesktop.screenSelections"

    private let renderedPagesDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QRDesktop/RenderedPages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        let paths = defaults.stringArray(forKey: pathsKey) ?? []
        images = paths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return ReferenceImage(id: UUID(), sourceURL: URL(fileURLWithPath: path))
        }

        let savedSelections = defaults.dictionary(forKey: selectionsKey) as? [String: String] ?? [:]
        for (displayIDString, path) in savedSelections {
            if let displayID = UInt32(displayIDString) {
                currentPathsByDisplay[displayID] = path
            }
        }
    }

    private func persistLibrary() {
        defaults.set(images.map { $0.sourceURL.path }, forKey: pathsKey)
    }

    private func persistSelections() {
        let asStrings = Dictionary(uniqueKeysWithValues: currentPathsByDisplay.map { (String($0.key), $0.value) })
        defaults.set(asStrings, forKey: selectionsKey)
    }

    func currentImage(for screen: NSScreen) -> ReferenceImage? {
        guard let displayID = screen.displayID, let path = currentPathsByDisplay[displayID] else { return nil }
        return images.first { $0.sourceURL.path == path }
    }

    func addImages(at urls: [URL]) {
        let newImages = urls.map { ReferenceImage(id: UUID(), sourceURL: $0) }
        images.append(contentsOf: newImages)
        persistLibrary()
    }

    func remove(_ image: ReferenceImage) {
        images.removeAll { $0.id == image.id }
        currentPathsByDisplay = currentPathsByDisplay.filter { $0.value != image.sourceURL.path }
        persistLibrary()
        persistSelections()
    }

    @discardableResult
    func select(_ image: ReferenceImage, for screen: NSScreen) -> Bool {
        guard let displayID = screen.displayID else { return false }
        currentPathsByDisplay[displayID] = image.sourceURL.path
        persistSelections()

        guard let desktopURL = desktopImageURL(for: image) else { return false }
        return applyToDesktop(desktopURL, screen: screen)
    }

    func advance(by delta: Int, for screen: NSScreen) {
        guard images.isEmpty == false else { return }
        let startIndex = currentImage(for: screen).flatMap { current in images.firstIndex(of: current) } ?? -1
        let nextIndex = (startIndex + delta + images.count) % images.count
        select(images[nextIndex], for: screen)
    }

    /// Returns a URL macOS can actually use as a desktop picture - the source
    /// image itself, or a rasterized first-page PNG when the source is a PDF.
    private func desktopImageURL(for image: ReferenceImage) -> URL? {
        guard image.isPDF else { return image.sourceURL }

        let cachedURL = renderedPagesDirectory
            .appendingPathComponent(image.id.uuidString)
            .appendingPathExtension("png")

        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        return renderFirstPage(ofPDFAt: image.sourceURL, to: cachedURL)
    }

    private func renderFirstPage(ofPDFAt pdfURL: URL, to outputURL: URL) -> URL? {
        guard let document = PDFDocument(url: pdfURL), let page = document.page(at: 0) else { return nil }

        let pageBounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 4.0
        let renderSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)

        let image = NSImage(size: renderSize)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: renderSize))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        do {
            try pngData.write(to: outputURL)
            return outputURL
        } catch {
            return nil
        }
    }

    @discardableResult
    private func applyToDesktop(_ url: URL, screen: NSScreen) -> Bool {
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            return true
        } catch {
            print("Failed to set desktop image for \(screen): \(error)")
            return false
        }
    }
}
