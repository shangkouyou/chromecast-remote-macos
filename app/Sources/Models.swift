import Foundation

// MARK: - Action

enum ActionKind: String, CaseIterable, Identifiable {
    case none
    case key
    case media
    case app
    case url
    case shell
    case text
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无动作"
        case .key: return "键盘快捷键"
        case .media: return "媒体键"
        case .app: return "打开 App"
        case .url: return "打开网址"
        case .shell: return "运行 Shell"
        case .text: return "输入文本"
        case .voice: return "语音键（Fn / 云键）"
        }
    }
}

struct ActionSpec: Equatable {
    var kind: ActionKind = .none
    var chord: String = ""
    var media: String = ""
    var value: String = ""
    var holdMS: Int = 12

    init(kind: ActionKind = .none, chord: String = "", media: String = "",
         value: String = "", holdMS: Int = 12) {
        self.kind = kind
        self.chord = chord
        self.media = media
        self.value = value
        self.holdMS = holdMS
    }

    init?(string raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "none" || text == "null" {
            self.kind = .none
            return
        }
        if text == "voice" {
            self.kind = .voice
            return
        }
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let kindText = String(text[text.startIndex..<colon]).lowercased()
        var rest = String(text[text.index(after: colon)...])
        guard let kind = ActionKind(rawValue: kindText), kind != .none else { return nil }

        self.kind = kind
        switch kind {
        case .key:
            var hold = 12
            if let comma = rest.firstIndex(of: ",") {
                let options = String(rest[rest.index(after: comma)...])
                rest = String(rest[rest.startIndex..<comma])
                for option in options.split(separator: ",") {
                    let piece = option.trimmingCharacters(in: .whitespaces)
                    if piece.hasPrefix("hold="), let v = Int(piece.dropFirst(5)) { hold = v }
                }
            }
            guard (try? KeyChord.parse(rest)) != nil else { return nil }
            self.chord = rest.trimmingCharacters(in: .whitespaces)
            self.holdMS = hold
        case .media:
            guard MediaKey.all.contains(rest) else { return nil }
            self.media = rest
        case .app, .url, .shell, .text:
            guard !rest.isEmpty else { return nil }
            self.value = rest
        case .voice, .none:
            break
        }
    }

    var encoded: String {
        switch kind {
        case .none: return "none"
        case .voice: return "voice"
        case .key: return holdMS == 12 ? "key:\(chord)" : "key:\(chord),hold=\(holdMS)"
        case .media: return "media:\(media)"
        case .app: return "app:\(value)"
        case .url: return "url:\(value)"
        case .shell: return "shell:\(value)"
        case .text: return "text:\(value)"
        }
    }

    var summary: String {
        switch kind {
        case .none: return "无动作"
        case .voice: return "语音键（Fn）"
        case .key: return "按键 \(chord)"
        case .media: return "媒体键 \(MediaKey.title(media))"
        case .app: return "打开 \(value)"
        case .url: return "打开 \(value)"
        case .shell: return "shell: \(value)"
        case .text: return "输入「\(value.prefix(12))」"
        }
    }
}

// MARK: - Buttons

struct RemoteButton: Identifiable, Hashable {
    let id: String
    let page: UInt32
    let usage: UInt32
    let label: String
    var isCustom: Bool = false

    var usageHex: String { String(format: "0x%02X", usage) }
}

enum RemoteButtons {
    /// Google Chromecast Voice Remote (18d1:9450) 实测按键表。
    static let defaults: [RemoteButton] = [
        .init(id: "c:0x19E", page: 0x0C, usage: 0x19E, label: "电源"),
        .init(id: "c:0xCD", page: 0x0C, usage: 0xCD, label: "播放 / 暂停"),
        .init(id: "c:0x42", page: 0x0C, usage: 0x42, label: "方向上"),
        .init(id: "c:0x43", page: 0x0C, usage: 0x43, label: "方向下"),
        .init(id: "c:0x44", page: 0x0C, usage: 0x44, label: "方向左"),
        .init(id: "c:0x45", page: 0x0C, usage: 0x45, label: "方向右"),
        .init(id: "c:0x41", page: 0x0C, usage: 0x41, label: "确定"),
        .init(id: "c:0xE2", page: 0x0C, usage: 0xE2, label: "静音"),
        .init(id: "c:0x221", page: 0x0C, usage: 0x221, label: "语音 Assistant"),
        .init(id: "c:0x223", page: 0x0C, usage: 0x223, label: "首页"),
        .init(id: "c:0x224", page: 0x0C, usage: 0x224, label: "返回"),
        .init(id: "c:0xE9", page: 0x0C, usage: 0xE9, label: "音量加"),
        .init(id: "c:0xEA", page: 0x0C, usage: 0xEA, label: "音量减"),
        .init(id: "c:0x77", page: 0x0C, usage: 0x77, label: "YouTube"),
        .init(id: "c:0x78", page: 0x0C, usage: 0x78, label: "Netflix"),
        .init(id: "c:0x79", page: 0x0C, usage: 0x79, label: "App 4（待学习）"),
        .init(id: "c:0x89", page: 0x0C, usage: 0x89, label: "输入源"),
    ]

    static let aliases: [String: String] = [
        "assistant": "c:0x221", "voice": "c:0x221", "mic": "c:0x221",
        "home": "c:0x223", "back": "c:0x224",
        "dpad_up": "c:0x42", "dpad_down": "c:0x43",
        "dpad_left": "c:0x44", "dpad_right": "c:0x45",
        "ok": "c:0x41", "select": "c:0x41", "enter": "c:0x41",
        "mute": "c:0xE2", "volume_up": "c:0xE9", "volume_down": "c:0xEA",
        "play_pause": "c:0xCD", "power": "c:0x19E",
    ]

    static func canonical(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let alias = aliases[text] { return alias }
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let number = UInt32(parts[1].replacingOccurrences(of: "0x", with: ""), radix: 16) {
            return "\(parts[0]):0x" + String(format: "%02X", number)
        }
        return text
    }

    static let usageNames: [UInt32: String] = [
        0x19E: "电源 / Power", 0xCD: "播放暂停 / Play Pause",
        0x42: "方向上 / Up", 0x43: "方向下 / Down",
        0x44: "方向左 / Left", 0x45: "方向右 / Right",
        0x41: "确定 / OK", 0xE2: "静音 / Mute",
        0x221: "语音 / Assistant", 0x223: "首页 / Home",
        0x224: "返回 / Back", 0xE9: "音量加 / Volume +",
        0xEA: "音量减 / Volume −", 0x77: "YouTube",
        0x78: "Netflix", 0x79: "App 4", 0x89: "输入源 / Input",
        0x40: "菜单 / Menu", 0x46: "退出 / Escape",
        0x30: "电源 / Power", 0x32: "睡眠 / Sleep",
        0xB0: "播放 / Play", 0xB1: "暂停 / Pause",
        0xB3: "快进 / Fast Forward", 0xB4: "快退 / Rewind",
        0xB5: "下一首 / Next", 0xB6: "上一首 / Previous",
    ]

    static func usage(from id: String) -> UInt32 {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return 0 }
        return UInt32(parts[1].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
    }

    static func label(for id: String, extra: [RemoteButton]) -> String {
        if let known = (defaults + extra).first(where: { $0.id == id }) {
            return known.label
        }
        let usage = usage(from: id)
        if let name = usageNames[usage] { return name }
        if id.hasPrefix("k:") {
            return "键盘键 \(id)"
        }
        return "按键 \(String(format: "0x%02X", usage))"
    }
}

// MARK: - Config

struct DeviceConfig: Codable, Equatable {
    var vendorID: Int = 0x18D1
    var productID: Int = 0x9450
    var product: String = "Chromecast Remote"
    var seize: Bool = true

    enum CodingKeys: String, CodingKey {
        case vendorID = "vendor_id"
        case productID = "product_id"
        case product
        case seize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try c.decodeIfPresent(Int.self, forKey: .vendorID) ?? vendorID
        productID = try c.decodeIfPresent(Int.self, forKey: .productID) ?? productID
        product = try c.decodeIfPresent(String.self, forKey: .product) ?? product
        seize = try c.decodeIfPresent(Bool.self, forKey: .seize) ?? seize
    }
}

struct VoiceConfig: Codable, Equatable {
    var button: String = "assistant"
    var mode: String = "latch"
    var maxSessionS: Double = 60
    var minHoldMS: Int = 350
    var releaseDelayMS: Int = 150
    var endActions: [String] = []
    var disconnectBluetooth: Bool = false
    var bluetoothAddress: String = ""

    enum CodingKeys: String, CodingKey {
        case button, mode
        case maxSessionS = "max_session_s"
        case minHoldMS = "min_hold_ms"
        case releaseDelayMS = "release_delay_ms"
        case endActions = "end_actions"
        case disconnectBluetooth = "disconnect_bluetooth"
        case bluetoothAddress = "bluetooth_address"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        button = try c.decodeIfPresent(String.self, forKey: .button) ?? button
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? mode
        maxSessionS = try c.decodeIfPresent(Double.self, forKey: .maxSessionS) ?? maxSessionS
        minHoldMS = try c.decodeIfPresent(Int.self, forKey: .minHoldMS) ?? minHoldMS
        releaseDelayMS = try c.decodeIfPresent(Int.self, forKey: .releaseDelayMS) ?? releaseDelayMS
        endActions = try c.decodeIfPresent([String].self, forKey: .endActions) ?? endActions
        disconnectBluetooth = try c.decodeIfPresent(Bool.self, forKey: .disconnectBluetooth) ?? disconnectBluetooth
        bluetoothAddress = try c.decodeIfPresent(String.self, forKey: .bluetoothAddress) ?? bluetoothAddress
    }
}

struct ExtraButton: Codable, Hashable {
    var id: String
    var label: String
}

struct AppConfig: Codable, Equatable {
    var version: Int = 1
    var device: DeviceConfig = DeviceConfig()
    var mapping: [String: String] = AppConfig.defaultMapping
    var voice: VoiceConfig = VoiceConfig()
    var virtualName: String = "Chromecast Remote"
    var extraButtons: [ExtraButton] = []
    var logReports: Bool = false

    enum CodingKeys: String, CodingKey {
        case version, device, mapping, voice
        case virtualName = "virtual_name"
        case extraButtons = "extra_buttons"
        case logReports = "log_reports"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? version
        device = try c.decodeIfPresent(DeviceConfig.self, forKey: .device) ?? device
        let incoming = try c.decodeIfPresent([String: String].self, forKey: .mapping) ?? [:]
        mapping = AppConfig.defaultMapping.merging(incoming) { _, new in new }
        voice = try c.decodeIfPresent(VoiceConfig.self, forKey: .voice) ?? voice
        virtualName = try c.decodeIfPresent(String.self, forKey: .virtualName) ?? virtualName
        extraButtons = try c.decodeIfPresent([ExtraButton].self, forKey: .extraButtons) ?? extraButtons
        logReports = try c.decodeIfPresent(Bool.self, forKey: .logReports) ?? logReports
    }

    static let defaultMapping: [String: String] = [
        "c:0x19E": "key:ctrl+cmd+q",
        "c:0x42": "key:up",
        "c:0x43": "key:down",
        "c:0x44": "key:left",
        "c:0x45": "key:right",
        "c:0x41": "key:return",
        "c:0x224": "key:escape",
        "c:0x223": "key:ctrl+up",
        "c:0x221": "voice",
        "c:0xE2": "media:mute",
        "c:0xE9": "media:volume_up",
        "c:0xEA": "media:volume_down",
        "c:0xCD": "media:play_pause",
        "c:0x77": "url:https://www.youtube.com",
        "c:0x78": "url:https://www.netflix.com",
        "c:0x79": "none",
        "c:0x89": "key:cmd+tab",
    ]
}

// MARK: - Config store

enum ConfigStore {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gvtv-remote", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("mapping.json") }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GoogleTVRemote.log")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    @discardableResult
    static func save(_ config: AppConfig) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func log(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)\n"
        let url = logURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
