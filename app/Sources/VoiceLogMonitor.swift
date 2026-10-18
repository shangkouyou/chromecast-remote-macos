import Foundation

/// 通过系统蓝牙日志旁路监听遥控器语音键。
///
/// 这颗遥控器的语音键不走 HID report，而是通过 BLE GATT 的 0x003F 特征发
/// indication（04 03 02 xx / 08 / 00 02）。macOS 没有订阅者时会把值丢进
/// 系统日志（"Dropping value ... 0x003F Characteristic Value [ ... ]"）。
/// 这里用 `log stream` 读取这些日志行，低延迟地还原按下/松开。
final class VoiceLogMonitor {
    var onEvent: (([UInt8]) -> Void)?
    var onStatus: ((String) -> Void)?

    private var process: Process?
    private var pipe: Pipe?
    private var buffer = ""
    private(set) var running = false

    private let pattern = try! NSRegularExpression(
        pattern: #"Characteristic Value \[\s*([0-9A-Fa-f ]+?)\s*\]"#
    )

    func start() {
        guard process == nil else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "stream", "--style", "compact", "--predicate",
            "subsystem == \"com.apple.bluetooth\" AND eventMessage CONTAINS \"0x003F Characteristic Value\"",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.feed(text)
        }
        do {
            try task.run()
            self.process = task
            self.pipe = pipe
            running = true
            onStatus?("运行中")
        } catch {
            running = false
            onStatus?("启动失败：\(error.localizedDescription)")
        }
    }

    func stop() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        pipe = nil
        buffer = ""
        running = false
        onStatus?("已停止")
    }

    private func feed(_ text: String) {
        buffer += text
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            parse(line)
        }
        if buffer.count > 8192 { buffer = "" }
    }

    private func parse(_ line: String) {
        guard line.contains("0x003F") else { return }
        let text = line as NSString
        guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else {
            return
        }
        let hex = text.substring(with: match.range(at: 1))
        let bytes = hex.split(whereSeparator: { $0 == " " }).compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else { return }
        onEvent?(bytes)
    }
}
