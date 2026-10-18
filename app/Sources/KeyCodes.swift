import CoreGraphics
import Foundation

enum ChordError: LocalizedError {
    case empty
    case unknownModifier(String)
    case unknownKey(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "快捷键为空"
        case .unknownModifier(let m): return "未知修饰键：\(m)"
        case .unknownKey(let k): return "未知按键：\(k)"
        }
    }
}

enum KeyChord {
    /// macOS 虚拟键码（kVK_*）
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
        "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24,
        "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29, "rightbracket": 30,
        "o": 31, "u": 32, "leftbracket": 33, "i": 34, "p": 35, "return": 36,
        "enter": 36, "l": 37, "j": 38, "quote": 39, "k": 40, "semicolon": 41,
        "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47,
        "tab": 48, "space": 49, "grave": 50, "backspace": 51, "delete": 51,
        "escape": 53, "esc": 53, "rightcommand": 54, "command": 55, "cmd": 55,
        "shift": 56, "capslock": 57, "option": 58, "alt": 58, "control": 59,
        "ctrl": 59, "rightshift": 60, "rightoption": 61, "rightcontrol": 62,
        "fn": 63, "globe": 63, "f17": 64, "keypaddecimal": 65, "keypadmultiply": 67,
        "keypadplus": 69, "keypadclear": 71, "volumeup": 72, "volumedown": 73,
        "mute": 74, "keypaddivide": 75, "keypadenter": 76, "keypadminus": 78,
        "f18": 79, "f19": 80, "keypadequals": 81, "keypad0": 82, "keypad1": 83,
        "keypad2": 84, "keypad3": 85, "keypad4": 86, "keypad5": 87, "keypad6": 88,
        "keypad7": 89, "f20": 90, "keypad8": 91, "keypad9": 92, "f5": 96,
        "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101, "f11": 103,
        "f13": 105, "f16": 106, "f14": 107, "f10": 109, "f12": 111, "f15": 113,
        "help": 114, "home": 115, "pageup": 116, "forwarddelete": 117, "f4": 118,
        "end": 119, "f2": 120, "pagedown": 121, "f1": 122, "left": 123,
        "right": 124, "down": 125, "up": 126,
    ]

    static let modifiers: [String: CGEventFlags] = [
        "shift": .maskShift,
        "ctrl": .maskControl,
        "control": .maskControl,
        "alt": .maskAlternate,
        "opt": .maskAlternate,
        "option": .maskAlternate,
        "cmd": .maskCommand,
        "command": .maskCommand,
        "fn": .maskSecondaryFn,
    ]

    static func parse(_ chord: String) throws -> (CGKeyCode, CGEventFlags) {
        let parts = chord
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard let key = parts.last else { throw ChordError.empty }
        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            guard let flag = modifiers[modifier] else { throw ChordError.unknownModifier(modifier) }
            flags.insert(flag)
        }
        guard let code = keyCodes[key] else { throw ChordError.unknownKey(key) }
        return (code, flags)
    }

    static func describe(keyCode: CGKeyCode, flags: CGEventFlags) -> String {
        var pieces: [String] = []
        if flags.contains(.maskControl) { pieces.append("ctrl") }
        if flags.contains(.maskAlternate) { pieces.append("alt") }
        if flags.contains(.maskShift) { pieces.append("shift") }
        if flags.contains(.maskCommand) { pieces.append("cmd") }
        if flags.contains(.maskSecondaryFn) { pieces.append("fn") }
        pieces.append(name(for: keyCode))
        return pieces.joined(separator: "+")
    }

    static func name(for keyCode: CGKeyCode) -> String {
        if let pair = keyCodes.first(where: { $0.value == keyCode }) {
            switch pair.key {
            case "return", "enter": return "return"
            case "delete": return "backspace"
            case "esc": return "escape"
            default: return pair.key
            }
        }
        return "#\(keyCode)"
    }
}

enum MediaKey {
    static let all: [String] = [
        "volume_up", "volume_down", "mute", "play_pause", "next", "previous",
    ]

    static let codes: [String: Int] = [
        "volume_up": 0, "volume_down": 1, "mute": 7, "play_pause": 16,
        "next": 17, "previous": 18, "fast_forward": 19, "rewind": 20,
    ]

    static func title(_ name: String) -> String {
        switch name {
        case "volume_up": return "音量 +"
        case "volume_down": return "音量 −"
        case "mute": return "静音"
        case "play_pause": return "播放 / 暂停"
        case "next": return "下一首"
        case "previous": return "上一首"
        default: return name
        }
    }
}
