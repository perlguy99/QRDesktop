//
//  PeekHotKey.swift
//  QRDesktop
//

import Carbon.HIToolbox
import Foundation

/// A single global keyboard shortcut, delivered even when another app has
/// focus. Uses the Carbon Event Manager's dedicated hot-key registration -
/// distinct from watching raw keystrokes (which needs Input Monitoring
/// permission) - so this needs no special permission at all.
final class PeekHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x51524446), id: 1) // 'QRDF'

    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32 = 0) {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            let hotKey = Unmanaged<PeekHotKey>.fromOpaque(userData).takeUnretainedValue()
            let kind = GetEventKind(eventRef)
            if kind == UInt32(kEventHotKeyPressed) {
                hotKey.onPressed?()
            } else if kind == UInt32(kEventHotKeyReleased) {
                hotKey.onReleased?()
            }
            return noErr
        }, eventTypes.count, &eventTypes, selfPtr, &handlerRef)

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            print("[Peek] hotkey registered OK (keyCode=\(keyCode), modifiers=\(modifiers))")
        } else {
            print("[Peek] hotkey registration FAILED, status=\(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
