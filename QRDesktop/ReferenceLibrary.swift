//
//  ReferenceLibrary.swift
//  QRDesktop
//

import AppKit
import CoreImage
import CryptoKit
import Foundation
import PDFKit

struct ReferenceImage: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var customName: String?

    var displayName: String {
        customName?.isEmpty == false ? customName! : sourceURL.deletingPathExtension().lastPathComponent
    }
}

private struct StoredImage: Codable {
    var path: String
    var customName: String?
}

extension NSScreen {
    /// A stable-enough identifier for a physical display across app launches
    /// (tied to the port/display it's connected through).
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let rgbValue = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rgbValue & 0x0000FF) / 255,
            alpha: 1.0
        )
    }

    var hexString: String {
        // ColorPicker-produced colors can come back in color spaces (P3, catalog,
        // dynamic system colors) where usingColorSpace(.deviceRGB) returns nil -
        // CIColor reliably normalizes any of those to plain RGB components.
        let ciColor = CIColor(color: self) ?? CIColor(red: 0, green: 0, blue: 0)
        return String(
            format: "#%02X%02X%02X",
            Int(ciColor.red * 255),
            Int(ciColor.green * 255),
            Int(ciColor.blue * 255)
        )
    }
}

@Observable
class ReferenceLibrary {
    private(set) var images: [ReferenceImage] = []
    private(set) var boards: [ReferenceBoard] = []

    /// Which board is currently showing, keyed by display + the current Space
    /// on that display (falls back to display-only if the Space can't be
    /// determined), so different virtual desktops on the same monitor can
    /// each remember their own sheet.
    private var currentBoardIDByKey: [String: String] = [:]

    private func boardKey(for screen: NSScreen) -> String? {
        guard let displayID = screen.displayID else { return nil }
        if let spaceID = screen.currentSpaceID {
            print("[Spaces] \(screen.localizedName) is currently on space \(spaceID)")
            return "\(displayID):\(spaceID)"
        }
        print("[Spaces] could not determine current space for \(screen.localizedName), falling back to display-only")
        return "\(displayID)"
    }

    private let defaults = UserDefaults.standard
    private let imagesKey = "QRDesktop.images"
    private let legacyPathsKey = "QRDesktop.imagePaths"
    private let boardsKey = "QRDesktop.boards"
    private let currentBoardsKey = "QRDesktop.currentBoardsByDisplay"

    private let renderedBoardsDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QRDesktop/RenderedBoards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        if let data = defaults.data(forKey: imagesKey),
           let stored = try? JSONDecoder().decode([StoredImage].self, from: data) {
            images = stored.compactMap { item in
                guard FileManager.default.fileExists(atPath: item.path) else { return nil }
                return ReferenceImage(id: UUID(), sourceURL: URL(fileURLWithPath: item.path), customName: item.customName)
            }
        } else {
            let legacyPaths = defaults.stringArray(forKey: legacyPathsKey) ?? []
            images = legacyPaths.compactMap { path in
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return ReferenceImage(id: UUID(), sourceURL: URL(fileURLWithPath: path), customName: nil)
            }
        }

        if let data = defaults.data(forKey: boardsKey),
           let decoded = try? JSONDecoder().decode([ReferenceBoard].self, from: data) {
            boards = decoded
        }

        currentBoardIDByKey = defaults.dictionary(forKey: currentBoardsKey) as? [String: String] ?? [:]
    }

    // MARK: - Image pool

    private func persistLibrary() {
        let stored = images.map { StoredImage(path: $0.sourceURL.path, customName: $0.customName) }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: imagesKey)
        }
    }

    func addImages(at urls: [URL]) {
        let newImages = urls.map { ReferenceImage(id: UUID(), sourceURL: $0, customName: nil) }
        images.append(contentsOf: newImages)
        persistLibrary()
    }

    func setCustomName(for image: ReferenceImage, name: String) {
        guard let index = images.firstIndex(where: { $0.id == image.id }) else { return }
        images[index].customName = name.isEmpty ? nil : name
        persistLibrary()
    }

    /// Small preview for picking images out of a list where filenames alone
    /// (often just "Image 1", "Screenshot...") aren't enough to tell them apart.
    func thumbnail(for image: ReferenceImage) -> NSImage? {
        let thumbnailSize = CGSize(width: 40, height: 40)
        if image.sourceURL.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: image.sourceURL), let page = document.page(at: 0) else { return nil }
            return page.thumbnail(of: thumbnailSize, for: .mediaBox)
        }
        // NSImage(contentsOfFile:) returns the image at full source resolution -
        // a full-size screenshot rendered unconstrained inside a menu/picker item
        // blows the menu open to that image's actual pixel size, not just a preview.
        guard let fullSize = NSImage(contentsOfFile: image.sourceURL.path) else { return nil }
        return resized(fullSize, toFit: thumbnailSize)
    }

    private func resized(_ image: NSImage, toFit targetSize: CGSize) -> NSImage {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        let scale = min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        let thumbnail = NSImage(size: scaledSize)
        thumbnail.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: scaledSize), from: .zero, operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }

    func remove(_ image: ReferenceImage) {
        images.removeAll { $0.id == image.id }
        persistLibrary()

        for index in boards.indices {
            for slotIndex in boards[index].slots.indices
            where boards[index].slots[slotIndex].path == image.sourceURL.path {
                boards[index].slots[slotIndex].path = nil
                invalidateRenderCache(for: boards[index].id)
            }
        }
        persistBoards()
    }

    // MARK: - Boards (sheets)

    private func persistBoards() {
        if let data = try? JSONEncoder().encode(boards) {
            defaults.set(data, forKey: boardsKey)
        }
    }

    private func persistCurrentBoards() {
        defaults.set(currentBoardIDByKey, forKey: currentBoardsKey)
    }

    @discardableResult
    func createBoard(layoutCount: Int) -> ReferenceBoard {
        let board = ReferenceBoard(layoutCount: layoutCount)
        boards.append(board)
        persistBoards()
        return board
    }

    func updateBoard(_ board: ReferenceBoard) {
        guard let index = boards.firstIndex(where: { $0.id == board.id }) else { return }
        boards[index] = board
        persistBoards()
        invalidateRenderCache(for: board.id)
    }

    func setSlotPath(boardID: UUID, slotIndex: Int, path: String?) {
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        guard boards[index].slots.indices.contains(slotIndex) else { return }
        boards[index].slots[slotIndex].path = path
        persistBoards()
        invalidateRenderCache(for: boardID)
    }

    func setSlotScaleMode(boardID: UUID, slotIndex: Int, scaleMode: BoardScaleMode) {
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        guard boards[index].slots.indices.contains(slotIndex) else { return }
        boards[index].slots[slotIndex].scaleMode = scaleMode
        persistBoards()
        invalidateRenderCache(for: boardID)
    }

    func setSlotBackgroundColor(boardID: UUID, slotIndex: Int, hex: String) {
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        guard boards[index].slots.indices.contains(slotIndex) else { return }
        boards[index].slots[slotIndex].backgroundColorHex = hex
        persistBoards()
        invalidateRenderCache(for: boardID)
    }

    func deleteBoard(_ board: ReferenceBoard) {
        boards.removeAll { $0.id == board.id }
        currentBoardIDByKey = currentBoardIDByKey.filter { $0.value != board.id.uuidString }
        persistBoards()
        persistCurrentBoards()
        invalidateRenderCache(for: board.id)
    }

    func currentBoard(for screen: NSScreen) -> ReferenceBoard? {
        guard let key = boardKey(for: screen),
              let idString = currentBoardIDByKey[key],
              let id = UUID(uuidString: idString) else { return nil }
        return boards.first { $0.id == id }
    }

    /// The already-rendered image for whatever sheet is currently showing on
    /// this screen - used by the peek overlay, which needs the same pixels
    /// that are already sitting in the desktop picture, just floated on top.
    func previewImageURL(for screen: NSScreen) -> URL? {
        guard let board = currentBoard(for: screen) else { return nil }
        return renderedImageURL(for: board, screen: screen)
    }

    /// Re-applies whatever board is already recorded as current for each
    /// connected screen. Self-healing for the render cache being wiped or
    /// going stale (e.g. after a fix that changes how cache files are named) -
    /// without this, a saved selection could silently point at a file that no
    /// longer exists until the user manually reselects it.
    func reapplyCurrentBoards() {
        for screen in NSScreen.screens {
            if let board = currentBoard(for: screen) {
                selectBoard(board, for: screen)
            }
        }
    }

    @discardableResult
    func selectBoard(_ board: ReferenceBoard, for screen: NSScreen) -> Bool {
        guard let key = boardKey(for: screen) else { return false }
        currentBoardIDByKey[key] = board.id.uuidString
        persistCurrentBoards()

        guard let renderedURL = renderedImageURL(for: board, screen: screen) else { return false }
        return applyToDesktop(renderedURL, screen: screen)
    }

    func advanceBoard(by delta: Int, for screen: NSScreen) {
        guard boards.isEmpty == false else { return }
        let startIndex = currentBoard(for: screen).flatMap { boards.firstIndex(of: $0) } ?? -1
        let nextIndex = (startIndex + delta + boards.count) % boards.count
        selectBoard(boards[nextIndex], for: screen)
    }

    // MARK: - Rendering

    private func invalidateRenderCache(for boardID: UUID) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: renderedBoardsDirectory.path)) ?? []
        for file in files where file.hasPrefix(boardID.uuidString) {
            try? FileManager.default.removeItem(at: renderedBoardsDirectory.appendingPathComponent(file))
        }
    }

    private func renderedImageURL(for board: ReferenceBoard, screen: NSScreen) -> URL? {
        let scale = screen.backingScaleFactor
        let pixelSize = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)

        // macOS silently ignores setDesktopImageURL if the URL matches what's already
        // set for that screen, even if the file's contents changed - so the cache
        // filename has to change whenever the board's actual content changes, not
        // just live at a fixed per-board path. Swift's Hasher is deliberately
        // randomized per process launch (not stable across relaunches), so it was
        // silently regenerating and orphaning a "new" cache file every single time
        // the app started even when nothing about the board had changed - use a
        // real content hash (SHA256) instead, which is the same on every run.
        let fingerprint = board.slots
            .map { "\($0.path ?? "")|\($0.scaleMode.rawValue)|\($0.backgroundColorHex)" }
            .joined(separator: ";")
        let contentHash = SHA256.hash(data: Data(fingerprint.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)

        let cacheURL = renderedBoardsDirectory
            .appendingPathComponent("\(board.id.uuidString)-\(contentHash)-\(Int(pixelSize.width))x\(Int(pixelSize.height))")
            .appendingPathExtension("png")

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let composed = compositeImage(for: board, pixelSize: pixelSize)
        guard let tiffData = composed.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        do {
            try pngData.write(to: cacheURL)
            return cacheURL
        } catch {
            return nil
        }
    }

    /// Lays the board's slots out as equal-width columns and draws each
    /// slot's image aspect-filled into its column so there's no letterboxing.
    private func compositeImage(for board: ReferenceBoard, pixelSize: CGSize) -> NSImage {
        let canvas = NSImage(size: pixelSize)
        canvas.lockFocus()

        let columnWidth = pixelSize.width / CGFloat(board.layoutCount)
        for (index, slot) in board.slots.enumerated() {
            let columnRect = CGRect(x: CGFloat(index) * columnWidth, y: 0, width: columnWidth, height: pixelSize.height)

            (NSColor(hex: slot.backgroundColorHex) ?? .black).setFill()
            columnRect.fill()

            guard let path = slot.path, let sourceImage = rasterImage(forSourcePath: path) else { continue }
            switch slot.scaleMode {
            case .fit:
                drawAspectFit(sourceImage, in: columnRect)
            case .fill:
                drawAspectFill(sourceImage, in: columnRect)
            }
        }

        canvas.unlockFocus()
        return canvas
    }

    /// Scales the image up to the larger dimension of the rect and crops the overflow -
    /// fills the whole area but can cut off part of the image.
    private func drawAspectFill(_ image: NSImage, in rect: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - scaledSize.width / 2,
            y: rect.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Scales the image to fit entirely inside the rect without cropping -
    /// shows the whole image, leaving background-color bars on the shorter axis.
    private func drawAspectFit(_ image: NSImage, in rect: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - scaledSize.width / 2,
            y: rect.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    /// Loads a source file as a raster NSImage, rasterizing the first page for PDFs.
    private func rasterImage(forSourcePath path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "pdf" else {
            return NSImage(contentsOfFile: path)
        }

        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }

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
        return image
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
