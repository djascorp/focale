import AppKit
import Carbon

// MARK: - Raccourcis claviers globaux (F1) via Carbon, sans dépendance ni permission Accessibilité.

@MainActor
final class HotKeyService {
    private var registrations: [UInt32: EventHotKeyRef?] = [:]
    private var callbacks: [UInt32: (@MainActor () -> Void)] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// Convertit les modificateurs Cocoa vers Carbon (couvert par tests).
    nonisolated static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    /// Enregistre un raccourci global. Retourne false si le système le refuse.
    @discardableResult
    func register(shortcut: Shortcut, onFire: @escaping @MainActor () -> Void) -> Bool {
        installHandlerIfNeeded()
        var hotKeyRef: EventHotKeyRef?
        let keyID = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x464F4341), id: keyID) // 'FOCA'
        let flags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(for: flags),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { return false }
        registrations[keyID] = hotKeyRef
        callbacks[keyID] = onFire
        return true
    }

    func unregisterAll() {
        for (_, ref) in registrations {
            if let ref { UnregisterEventHotKey(ref) }
        }
        registrations.removeAll()
        callbacks.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, userData, nil)
    }

    /// Appelé par Carbon sur le thread principal.
    nonisolated fileprivate func fire(id: UInt32) {
        MainActor.assumeIsolated {
            callbacks[id]?()
        }
    }
}

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, let userData else { return OSStatus(eventNotHandledErr) }
    let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
    service.fire(id: hotKeyID.id)
    return noErr
}
