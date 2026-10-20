import Foundation

/// 遥控器麦克风增益设置。写入与音频桥共用的 mic-config.json。
enum MicGainStore {
    static let defaultGainDB: Double = 10

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/gvtv-remote/mic-config.json")
    }

    static func load() -> Double {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["gain_db"] as? NSNumber else {
            return defaultGainDB
        }
        return min(24, max(-24, number.doubleValue))
    }

    @discardableResult
    static func save(_ gainDB: Double) -> Bool {
        let value = min(24, max(-24, gainDB))
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let object: [String: Any] = ["gain_db": value]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
