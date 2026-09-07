//
//  CGSSpaces.swift
//  QRDesktop
//

import AppKit
import CoreGraphics
import Foundation

// Private, undocumented WindowServer API for reading which virtual desktop
// (Space) is currently active on each display. There is no public API for
// this. These symbols are already loaded in every process via CoreGraphics/
// SkyLight, so declaring their signatures ourselves is enough to call them -
// no header exists because Apple doesn't publish or support this. A future
// macOS release could change or remove this without notice.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

enum CGSSpaces {
    /// The current Space's identifier for the display with this UUID, or nil
    /// if it can't be determined (wrong dictionary shape, API gone, etc.) -
    /// callers should treat nil as "fall back to one board per screen."
    static func currentSpaceID(forDisplayUUID uuid: String) -> UInt64? {
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else {
            print("[Spaces] CGSCopyManagedDisplaySpaces returned an unexpected shape")
            return nil
        }
        for display in displays {
            guard let displayUUID = display["Display Identifier"] as? String, displayUUID == uuid else { continue }
            guard let current = display["Current Space"] as? [String: Any] else { continue }
            if let id64 = current["id64"] as? UInt64 {
                return id64
            }
            if let id64 = current["ManagedSpaceID"] as? UInt64 {
                return id64
            }
        }
        return nil
    }
}

extension NSScreen {
    /// The persistent hardware UUID for this display - stable across
    /// launches/reboots the same way displayID mostly is, used to match this
    /// screen up against CGSCopyManagedDisplaySpaces's per-display entries.
    var displayUUIDString: String? {
        guard let id = displayID,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cfUUID) as String?
    }

    /// Which Space is currently active on this screen, or nil if that can't
    /// be determined right now.
    var currentSpaceID: UInt64? {
        guard let uuid = displayUUIDString else { return nil }
        return CGSSpaces.currentSpaceID(forDisplayUUID: uuid)
    }
}
