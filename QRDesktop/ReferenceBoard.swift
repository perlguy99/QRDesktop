//
//  ReferenceBoard.swift
//  QRDesktop
//

import Foundation

enum BoardScaleMode: String, Codable, Hashable {
    case fit
    case fill
}

struct BoardSlot: Codable, Equatable, Hashable {
    var path: String?
    var scaleMode: BoardScaleMode
    var backgroundColorHex: String
}

/// A "sheet" - one to three reference images arranged in equal-width columns
/// and composited into a single desktop picture. Each slot scales and
/// backgrounds independently, so a cropped photo and a full-page PDF with a
/// white letterbox can share a sheet.
struct ReferenceBoard: Identifiable, Equatable {
    let id: UUID
    var layoutCount: Int
    var slots: [BoardSlot]
    var name: String?

    init(layoutCount: Int) {
        self.id = UUID()
        self.layoutCount = layoutCount
        self.slots = Array(repeating: BoardSlot(path: nil, scaleMode: .fit, backgroundColorHex: "#000000"), count: layoutCount)
        self.name = nil
    }

    var summary: String {
        let names = slots.map { slot -> String in
            guard let path = slot.path else { return "empty" }
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        return "\(layoutCount)-up: " + names.joined(separator: " + ")
    }

    /// The name shown in the Rolodex list - a user-given name if there is one,
    /// otherwise the auto-generated slot summary, same fallback pattern as
    /// ReferenceImage.displayName.
    var displayName: String {
        name?.isEmpty == false ? name! : summary
    }
}

// Custom Codable so boards saved before this shape existed still decode instead
// of silently vanishing - older formats had a single shared scaleMode and/or
// backgroundColorHex for the whole sheet and a bare slotPaths array; that gets
// migrated into per-slot data.
extension ReferenceBoard: Codable {
    enum CodingKeys: String, CodingKey {
        case id, layoutCount, slots, name
        case legacySlotPaths = "slotPaths"
        case legacyScaleMode = "scaleMode"
        case legacyBackgroundColorHex = "backgroundColorHex"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layoutCount = try container.decode(Int.self, forKey: .layoutCount)
        name = try container.decodeIfPresent(String.self, forKey: .name)

        if let decodedSlots = try? container.decode([BoardSlot].self, forKey: .slots) {
            slots = decodedSlots
        } else {
            let legacyPaths = try container.decodeIfPresent([String?].self, forKey: .legacySlotPaths)
                ?? Array(repeating: nil, count: layoutCount)
            let legacyScaleMode = try container.decodeIfPresent(BoardScaleMode.self, forKey: .legacyScaleMode) ?? .fit
            let legacyBackground = try container.decodeIfPresent(String.self, forKey: .legacyBackgroundColorHex) ?? "#000000"
            slots = legacyPaths.map { BoardSlot(path: $0, scaleMode: legacyScaleMode, backgroundColorHex: legacyBackground) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layoutCount, forKey: .layoutCount)
        try container.encode(slots, forKey: .slots)
        try container.encodeIfPresent(name, forKey: .name)
    }
}
