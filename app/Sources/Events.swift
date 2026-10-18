import AppKit
import CoreGraphics
import Foundation

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    static func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum Events {
    static let source = CGEventSource(stateID: .hidSystemState)

    private static let modifierKeyCodes: [(CGEventFlags, CGKeyCode)] = [
        (.maskShift, 56), (.maskControl, 59), (.maskAlternate, 58),
        (.maskCommand, 55), (.maskSecondaryFn, 63),
    ]

    static func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
            return
        }
        if !flags.isEmpty { event.flags = flags }
        event.post(tap: .cghidEventTap)
    }

    static func tap(_ code: CGKeyCode, flags: CGEventFlags = [], holdMS: Int = 12) {
        var held: [CGKeyCode] = []
        for (flag, keyCode) in modifierKeyCodes where flags.contains(flag) {
            post(keyCode, down: true, flags: flags)
            held.append(keyCode)
        }
        post(code, down: true, flags: flags)
        usleep(useconds_t(max(1, holdMS) * 1000))
        post(code, down: false, flags: flags)
        for keyCode in held.reversed() {
            post(keyCode, down: false, flags: [])
        }
        usleep(8_000)
    }

    static func chord(_ text: String, holdMS: Int = 12) throws {
        let (code, flags) = try KeyChord.parse(text)
        tap(code, flags: flags, holdMS: holdMS)
    }

    static func media(_ name: String) {
        guard let key = MediaKey.codes[name] else { return }
        for state in [0x0A, 0x0B] {
            guard let event = CGEvent(source: nil) else { return }
            event.type = CGEventType(rawValue: 14)!
            event.setIntegerValueField(.eventSourceUserData, value: Int64((key << 16) | (state << 8)))
            event.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    static func fn(down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 63, keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = down ? .maskSecondaryFn : []
        event.post(tap: .cghidEventTap)
        usleep(10_000)
    }

    static func fnTap(holdMS: Int = 40) {
        fn(down: true)
        usleep(useconds_t(max(10, holdMS) * 1000))
        fn(down: false)
    }

    static func typeText(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 20, units.count)])
            chunk.withUnsafeBufferPointer { buffer in
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let base = buffer.baseAddress else { return }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: base)
                event.post(tap: .cghidEventTap)
            }
            index += 20
            usleep(5_000)
        }
    }
}
