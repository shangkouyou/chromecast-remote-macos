import AppKit
import CoreFoundation
import Foundation

enum SelfTest {
    static func runIfRequested() {
        if CommandLine.arguments.contains("--hud-test") {
            _ = NSApplication.shared
            VoiceHUD.shared.show(name: "Chromecast Remote")
            let timer = CFRunLoopTimerCreateWithHandler(
                kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1.2, 0, 0, 0
            ) { _ in CFRunLoopStop(CFRunLoopGetCurrent()) }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
            CFRunLoopRun()
            VoiceHUD.shared.hide()
            print("HUD OK")
            exit(0)
        }
        guard CommandLine.arguments.contains("--selftest") else { return }
        let ok = run()
        exit(ok ? 0 : 1)
    }

    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print(condition ? "  ✓ \(name)" : "  ✗ \(name)")
            if !condition { failures += 1 }
        }

        print("gvtv-remote app selftest")

        let hex = "050c0901a10185010a9e0109cd0942094309440945094109e2"
            + "0a21020a23020a240209e909ea0977097809790989150125"
            + "11950275088100c0"
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<next], radix: 16) { data.append(byte) }
            index = next
        }
        let descriptor = HIDDescriptor(data: data)
        let fields = descriptor.fields[1] ?? []
        check("描述符解析出 report 1", !fields.isEmpty)
        check("17 个用法", fields.first?.usages.count == 17)
        check("值 9 -> 0x221", descriptor.decode(reportID: 1, payload: [9, 0]).first?.usage == 0x221)
        check("值 3/4 -> 0x42/0x43",
              descriptor.decode(reportID: 1, payload: [3, 4]).map(\.usage) == [0x42, 0x43])
        check("值 17 -> 0x89", descriptor.decode(reportID: 1, payload: [17, 0]).first?.usage == 0x89)

        check("动作解析 key", ActionSpec(string: "key:cmd+space")?.chord == "cmd+space")
        check("动作解析 media", ActionSpec(string: "media:play_pause")?.media == "play_pause")
        check("动作解析 voice", ActionSpec(string: "voice")?.kind == .voice)
        check("动作解析非法值", ActionSpec(string: "key:notakey") == nil)
        check("动作编码往返",
              ActionSpec(string: "key:ctrl+cmd+q,hold=30")?.encoded == "key:ctrl+cmd+q,hold=30")

        check("默认配置 17 条", AppConfig.defaultMapping.count == 17)
        check("别名解析", RemoteButtons.canonical("assistant") == "c:0x221")

        let config = ConfigStore.load()
        check("配置加载", !config.mapping.isEmpty)

        print("  权限: 辅助功能=\(Permissions.accessibilityGranted ? "✓" : "✗") "
              + "输入监控=\(Permissions.inputMonitoringGranted ? "✓" : "✗")")

        let controller = HIDController(vendorID: 0x18D1, productID: 0x9450, seize: false)
        var deviceName = ""
        controller.onDevice = { info in deviceName = info.product }
        do {
            try controller.start()
            let timer = CFRunLoopTimerCreateWithHandler(
                kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.6, 0, 0, 0
            ) { _ in CFRunLoopStop(CFRunLoopGetCurrent()) }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
            CFRunLoopRun()
            controller.stop()
        } catch {
            print("  ⚠ 设备探测失败：\(error.localizedDescription)")
        }
        check("识别到 Chromecast Remote", deviceName == "Chromecast Remote")

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0
    }
}
