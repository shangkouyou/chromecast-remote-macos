import AppKit
import Combine
import Foundation

struct ReportLine: Identifiable {
    let id = UUID()
    let time: String
    let reportID: UInt32
    let hex: String
    let decoded: String
}

struct LogLine: Identifiable {
    let id = UUID()
    let time: String
    let text: String
    let isError: Bool

    init(_ text: String, isError: Bool = false) {
        self.time = ConfigStore.timestamp()
        self.text = text
        self.isError = isError
    }
}

final class RemoteEngine: ObservableObject {
    @Published var config: AppConfig
    @Published var isRunning = false
    @Published var deviceConnected = false
    @Published var deviceName = "Chromecast Remote"
    @Published var deviceIdentity = "18d1:9450"
    @Published var seized = false
    @Published var accessibility = Permissions.accessibilityGranted
    @Published var inputMonitoring = Permissions.inputMonitoringGranted
    @Published var reportCount = 0
    @Published var pressCount = 0
    @Published var lastReport = "—"
    @Published var lastButton: String?
    @Published var lastAction: String?
    @Published var statusMessage = "未启动"
    @Published var logs: [LogLine] = []
    @Published var uptime: TimeInterval = 0
    @Published var buttons: [RemoteButton] = RemoteButtons.defaults
    @Published var reportLog: [ReportLine] = []
    @Published var voiceReportCount = 0
    @Published var lastFnEvent = "—"
    @Published var gattRunning = false
    @Published var gattEventCount = 0
    @Published var lastGATTEvent = "—"

    private var hid: HIDController?
    private var pressed: Set<String> = []
    private var permissionTimer: Timer?
    private var uptimeTimer: Timer?
    private var startedAt: Date?
    private var voiceActive = false
    private var voiceGeneration = 0
    private var fnDown = false
    private var voiceDownAt: Date?
    private var loggedUnknownReports: Set<UInt32> = []
    private var voiceLog: VoiceLogMonitor?
    private var gattSeen = false
    private var didPromptPermissions = false

    var voiceButtonID: String {
        RemoteButtons.canonical(config.voice.button)
    }

    init() {
        config = ConfigStore.load()
        canonicalizeMapping()
        rebuildButtons()
        startTimers()
        ConfigStore.log("应用启动，配置：\(ConfigStore.fileURL.path)")
    }

    deinit {
        permissionTimer?.invalidate()
        uptimeTimer?.invalidate()
        voiceLog?.stop()
        hid?.stop()
    }

    // MARK: - lifecycle

    func start() {
        guard !isRunning else { return }
        // 权限未就绪时不要独占：否则遥控器既收不到报告、系统也用不了。
        addLog("权限状态：辅助功能=\(Permissions.accessibilityGranted ? "✓" : "✗") 输入监控=\(Permissions.inputMonitoringGranted ? "✓" : "✗")")
        let permissionsReady = Permissions.inputMonitoringGranted && Permissions.accessibilityGranted
        let wantSeize = config.device.seize && permissionsReady
        let controller = HIDController(
            vendorID: config.device.vendorID,
            productID: config.device.productID,
            product: config.device.vendorID == 0 ? config.device.product : nil,
            seize: wantSeize
        )
        controller.onDevice = { [weak self] info in
            self?.handleDevice(info)
        }
        controller.onRemove = { [weak self] in
            self?.deviceConnected = false
            self?.deviceName = "等待遥控器…"
            self?.addLog("遥控器已断开")
        }
        controller.onReport = { [weak self] reportID, payload in
            self?.handleReport(reportID: reportID, payload: payload)
        }

        do {
            try controller.start()
        } catch {
            addLog("启动失败：\(error.localizedDescription)", isError: true)
            statusMessage = "启动失败"
            return
        }
        hid = controller
        startVoiceLogMonitor()
        isRunning = true
        startedAt = Date()
        uptime = 0
        statusMessage = "正在运行"
        addLog("映射服务已启动（\(controller.seized ? "独占" : "共享")模式）")
        if config.device.seize && !permissionsReady {
            addLog("权限未就绪，暂用共享模式，避免遥控器失效；授权后自动切换为独占")
        }
        if (!accessibility || !inputMonitoring), !didPromptPermissions,
           ProcessInfo.processInfo.environment["GVTV_NO_PROMPT"] == nil {
            didPromptPermissions = true
            requestPermissions()
        }
    }

    func stop() {
        endVoice(reason: "停止服务")
        VoiceHUD.shared.hide()
        voiceLog?.stop()
        voiceLog = nil
        gattRunning = false
        hid?.stop()
        hid = nil
        isRunning = false
        deviceConnected = false
        startedAt = nil
        statusMessage = "已停止"
        addLog("映射服务已停止")
    }

    func toggleRunning() {
        isRunning ? stop() : start()
    }

    func reconnect() {
        let wasRunning = isRunning
        stop()
        if wasRunning { start() }
    }

    // MARK: - device / reports

    private func handleDevice(_ info: HIDController.DeviceInfo) {
        deviceConnected = true
        deviceName = info.product.isEmpty ? "Chromecast Remote" : info.product
        deviceIdentity = "\(info.vidPid) · \(info.manufacturer)"
        seized = hid?.seized ?? false
        rebuildButtons()
        addLog("已连接 \(deviceName)（\(info.vidPid)），\(seized ? "独占" : "共享")模式")
        addLog("描述符：\(hid?.descriptor?.summary ?? "无")")
    }

    private func handleReport(reportID: UInt32, payload: [UInt8]) {
        reportCount += 1
        let hex = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        lastReport = hex
        guard let descriptor = hid?.descriptor else { return }

        var usages = descriptor.decode(reportID: reportID, payload: payload)

        // 有些固件会把语音键放在描述符之外的 report ID 上。这里兜底：
        // 未知 report ID 一律记录，并尝试按默认的 17 键表（首字节 1..17）解码。
        if descriptor.fields[reportID] == nil {
            if let first = payload.first, first >= 1, Int(first) <= RemoteButtons.defaults.count {
                let button = RemoteButtons.defaults[Int(first) - 1]
                usages = [(0x0C, button.usage)]
            }
            if !loggedUnknownReports.contains(reportID) {
                loggedUnknownReports.insert(reportID)
                addLog("收到描述符外的 report \(reportID)：\(hex)（已按默认键表尝试解析）")
            }
        }

        let identifiers = usages.map { Self.bindingID(page: $0.page, usage: $0.usage) }
        let decodedText = identifiers.isEmpty ? "—" : identifiers.joined(separator: ", ")
        if hex != "00 00" {
            reportLog.append(ReportLine(time: ConfigStore.timestamp(), reportID: reportID,
                                        hex: hex, decoded: decodedText))
            if reportLog.count > 80 { reportLog.removeFirst(reportLog.count - 80) }
            if config.logReports {
                ConfigStore.log("report \(reportID) \(hex) -> \(decodedText)")
            }
        }
        if identifiers.contains(voiceButtonID) {
            voiceReportCount += 1
            lastFnEvent = "收到语音键报告 \(ConfigStore.timestamp())"
        }

        let current = Set(identifiers)
        for identifier in current.subtracting(pressed) {
            handlePress(identifier)
        }
        for identifier in pressed.subtracting(current) {
            handleRelease(identifier)
        }
        pressed = current
    }

    private func handlePress(_ identifier: String) {
        pressCount += 1
        let label = RemoteButtons.label(for: identifier, extra: customButtons)
        lastButton = "\(label)  \(identifier)"

        if identifier == voiceButtonID {
            if gattSeen {
                addLog("收到 HID 语音键，但 GATT 通道已接管，忽略以避免重复")
                return
            }
            lastAction = "语音键（Fn）"
            addLog("语音键按下")
            pressVoice()
            return
        }

        let mapping = canonicalMapping()
        guard let raw = mapping[identifier], let action = ActionSpec(string: raw) else {
            addLog("未绑定按键：\(label) \(identifier)")
            return
        }
        lastAction = action.summary
        execute(action, label: label)
    }

    private func handleRelease(_ identifier: String) {
        if identifier == voiceButtonID {
            releaseVoice()
        }
    }

    // MARK: - GATT voice log

    private func startVoiceLogMonitor() {
        let monitor = VoiceLogMonitor()
        monitor.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.gattRunning = (status == "运行中")
                self.addLog("语音键 GATT 监听：\(status)")
            }
        }
        monitor.onEvent = { [weak self] bytes in
            DispatchQueue.main.async { self?.handleGATTVoice(bytes) }
        }
        monitor.start()
        voiceLog = monitor
        gattRunning = monitor.running
    }

    private func handleGATTVoice(_ bytes: [UInt8]) {
        guard let first = bytes.first else { return }
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        gattSeen = true
        gattEventCount += 1
        lastGATTEvent = "\(hex)  \(ConfigStore.timestamp())"
        if config.logReports {
            ConfigStore.log("gatt voice \(hex)")
        }
        addLog("语音键 GATT：\(hex)")

        switch first {
        case 0x04: // 语音会话开始 / 按键按下
            if config.voice.mode == "hold" {
                if !voiceActive { pressVoice() }
            } else {
                pressVoice()  // latch/toggle/double：按一次切换
            }
        case 0x00: // 会话停止 / 松开
            if config.voice.mode == "hold" {
                releaseVoice()
            }
        default:
            break
        }
    }

    // MARK: - actions

    func execute(_ action: ActionSpec, label: String? = nil) {
        switch action.kind {
        case .none:
            return
        case .key:
            do {
                try Events.chord(action.chord, holdMS: action.holdMS)
                addLog("\(label ?? "") → 按键 \(action.chord)")
            } catch {
                addLog("快捷键无效：\(action.chord)", isError: true)
            }
        case .media:
            Events.media(action.media)
            addLog("\(label ?? "") → \(action.summary)")
        case .app:
            runProcess("/usr/bin/open", ["-a", action.value])
            addLog("\(label ?? "") → 打开 \(action.value)")
        case .url:
            if let url = URL(string: action.value) {
                NSWorkspace.shared.open(url)
                addLog("\(label ?? "") → 打开 \(action.value)")
            }
        case .shell:
            runProcess("/bin/bash", ["-lc", action.value])
            addLog("\(label ?? "") → shell")
        case .text:
            Events.typeText(action.value)
            addLog("\(label ?? "") → 输入文本")
        case .voice:
            pressVoice()
        }
    }

    private func runProcess(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - voice

    private var minHoldSeconds: Double { Double(max(0, config.voice.minHoldMS)) / 1000.0 }

    func pressVoice() {
        switch config.voice.mode {
        case "latch":
            if voiceActive { endVoice(reason: "再次按下") } else { beginVoice(kind: .latch) }
        case "toggle":
            if voiceActive { endVoice(reason: "再次按下") } else { beginVoice(kind: .tap) }
        case "double":
            if voiceActive { endVoice(reason: "再次按下") } else { beginVoice(kind: .double) }
        default:
            if !voiceActive { beginVoice(kind: .hold) }
        }
    }

    private func releaseVoice() {
        guard config.voice.mode == "hold", voiceActive, fnDown else { return }
        let elapsed = Date().timeIntervalSince(voiceDownAt ?? Date())
        let remaining = max(0, minHoldSeconds - elapsed)
        let generation = voiceGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.voiceActive, self.voiceGeneration == generation else { return }
            self.endVoice(reason: "松开")
        }
        addLog(String(format: "语音键松开：Fn 至少保持 %.0f ms", minHoldSeconds * 1000))
    }

    private enum VoiceStart { case latch, hold, tap, double }

    private func beginVoice(kind: VoiceStart) {
        voiceActive = true
        voiceGeneration += 1
        let generation = voiceGeneration

        switch kind {
        case .latch, .hold:
            fnDown = true
            voiceDownAt = Date()
            Events.fn(down: true)
            lastFnEvent = "Fn↓ \(ConfigStore.timestamp())"
        case .tap:
            Events.fnTap(holdMS: config.voice.minHoldMS)
            lastFnEvent = "Fn 轻按 \(ConfigStore.timestamp())"
        case .double:
            Events.fnTap(holdMS: 40)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Events.fnTap(holdMS: 40) }
            lastFnEvent = "Fn ×2 \(ConfigStore.timestamp())"
        }

        let hint = kind == .latch ? "再按一次结束" : "松开结束"
        addLog("语音键开始（\(modeTitle)）：\(kind == .tap || kind == .double ? "Fn 轻按" : "Fn↓")")
        VoiceHUD.shared.show(name: config.virtualName, hint: hint)

        DispatchQueue.main.asyncAfter(deadline: .now() + max(5, config.voice.maxSessionS)) { [weak self] in
            guard let self, self.voiceActive, self.voiceGeneration == generation else { return }
            self.addLog("语音超时，自动结束")
            self.endVoice(reason: "超时")
        }
    }

    private func endVoice(reason: String) {
        guard voiceActive else { return }
        voiceActive = false
        voiceGeneration += 1

        switch config.voice.mode {
        case "latch", "hold":
            if fnDown {
                fnDown = false
                Events.fn(down: false)
                lastFnEvent = "Fn↑ \(ConfigStore.timestamp())"
            }
        case "double":
            Events.fnTap(holdMS: 40)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Events.fnTap(holdMS: 40) }
            lastFnEvent = "Fn ×2 \(ConfigStore.timestamp())"
        default:
            Events.fnTap(holdMS: config.voice.minHoldMS)
            lastFnEvent = "Fn 轻按 \(ConfigStore.timestamp())"
        }

        addLog("语音键结束（\(reason)）")
        VoiceHUD.shared.hide()

        let delay = Double(max(0, config.voice.releaseDelayMS)) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            for raw in self.config.voice.endActions {
                if let action = ActionSpec(string: raw) { self.execute(action, label: "语音收尾") }
            }
            if self.config.voice.disconnectBluetooth {
                self.disconnectBluetooth()
            }
        }
    }

    var modeTitle: String {
        switch config.voice.mode {
        case "latch": return "latch 按一次开/再按一次关"
        case "toggle": return "toggle 每次轻按"
        case "double": return "double 双 Fn"
        default: return "hold 按住"
        }
    }

    private func disconnectBluetooth() {
        let address = config.voice.bluetoothAddress
        guard !address.isEmpty else { return }
        let candidates = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]
        guard let blueutil = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            addLog("未安装 blueutil，跳过断开蓝牙", isError: true)
            return
        }
        runProcess(blueutil, ["--disconnect", address])
        addLog("已请求断开蓝牙 \(address)")
    }

    // MARK: - config

    var customButtons: [RemoteButton] {
        config.extraButtons.map {
            RemoteButton(id: RemoteButtons.canonical($0.id), page: 0x0C,
                         usage: RemoteButtons.usage(from: $0.id), label: $0.label, isCustom: true)
        }
    }

    func canonicalMapping() -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in config.mapping {
            result[RemoteButtons.canonical(key)] = value
        }
        return result
    }

    func action(for identifier: String) -> ActionSpec {
        if identifier == voiceButtonID { return ActionSpec(kind: .voice) }
        if let raw = canonicalMapping()[identifier], let action = ActionSpec(string: raw) {
            return action
        }
        return ActionSpec(kind: .none)
    }

    func setAction(_ action: ActionSpec, for identifier: String) {
        var updated = config
        updated.mapping[identifier] = action.encoded
        config = updated
        save()
        addLog("已保存映射：\(RemoteButtons.label(for: identifier, extra: customButtons)) → \(action.summary)")
    }

    func setVoiceMode(_ mode: String) {
        var updated = config
        updated.voice.mode = mode
        config = updated
        save()
    }

    func setSeize(_ on: Bool) {
        var updated = config
        updated.device.seize = on
        config = updated
        save()
        if isRunning { reconnect() }
    }

    func setLogReports(_ on: Bool) {
        var updated = config
        updated.logReports = on
        config = updated
        save()
    }

    func setMinHold(_ ms: Int) {
        var updated = config
        updated.voice.minHoldMS = max(0, ms)
        config = updated
        save()
    }

    func setMaxSession(_ seconds: Double) {
        var updated = config
        updated.voice.maxSessionS = seconds
        config = updated
        save()
    }

    func addCustomButton(id: String, label: String) {
        var updated = config
        updated.extraButtons.append(ExtraButton(id: RemoteButtons.canonical(id), label: label))
        config = updated
        save()
        rebuildButtons()
    }

    func removeCustomButton(_ id: String) {
        var updated = config
        updated.extraButtons.removeAll { RemoteButtons.canonical($0.id) == id }
        updated.mapping[id] = nil
        config = updated
        save()
        rebuildButtons()
    }

    func resetMapping() {
        var updated = config
        updated.mapping = AppConfig.defaultMapping
        config = updated
        save()
        addLog("已恢复默认键位")
    }

    func updateVoice(_ mutate: (inout VoiceConfig) -> Void) {
        var updated = config
        mutate(&updated.voice)
        config = updated
        save()
    }

    func setVirtualName(_ name: String) {
        var updated = config
        updated.virtualName = name
        config = updated
        save()
    }

    func reloadConfig() {
        config = ConfigStore.load()
        canonicalizeMapping()
        rebuildButtons()
        addLog("配置已重新加载")
    }

    func save() {
        if ConfigStore.save(config) {
            addLog("配置已保存")
        } else {
            addLog("配置保存失败：\(ConfigStore.fileURL.path)", isError: true)
        }
    }

    private func canonicalizeMapping() {
        var updated = config
        var mapping: [String: String] = [:]
        for (key, value) in updated.mapping {
            mapping[RemoteButtons.canonical(key)] = value
        }
        updated.mapping = mapping
        config = updated
    }

    private func rebuildButtons() {
        var result: [RemoteButton] = []
        var seen = Set<String>()
        if let fields = hid?.descriptor?.fields, !fields.isEmpty {
            for reportID in fields.keys.sorted() {
                for field in fields[reportID] ?? [] {
                    for usage in field.usages {
                        let id = Self.bindingID(page: field.usagePage, usage: usage)
                        guard seen.insert(id).inserted else { continue }
                        result.append(RemoteButton(
                            id: id, page: field.usagePage, usage: usage,
                            label: RemoteButtons.label(for: id, extra: customButtons)
                        ))
                    }
                }
            }
        }
        if result.isEmpty {
            result = RemoteButtons.defaults
            seen = Set(result.map(\.id))
        }
        for extra in config.extraButtons {
            let id = RemoteButtons.canonical(extra.id)
            guard seen.insert(id).inserted else { continue }
            result.append(RemoteButton(
                id: id, page: 0x0C, usage: RemoteButtons.usage(from: id),
                label: extra.label, isCustom: true
            ))
        }
        buttons = result
    }

    // MARK: - permissions / timers

    func requestPermissions() {
        if !Permissions.accessibilityGranted { Permissions.requestAccessibilityPrompt() }
        if !Permissions.inputMonitoringGranted { Permissions.requestInputMonitoring() }
        refreshPermissions()
    }

    func refreshPermissions() {
        accessibility = Permissions.accessibilityGranted
        inputMonitoring = Permissions.inputMonitoringGranted
    }

    private func startTimers() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let ax = Permissions.accessibilityGranted
            let im = Permissions.inputMonitoringGranted
            if ax != self.accessibility {
                self.accessibility = ax
                if ax && im && self.isRunning {
                    self.addLog("权限已就绪，切换为独占模式")
                    self.reconnect()
                }
            }
            if im != self.inputMonitoring {
                self.inputMonitoring = im
                if im && ax && self.isRunning {
                    self.addLog("权限已就绪，切换为独占模式")
                    self.reconnect()
                }
            }
        }
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            self.uptime = Date().timeIntervalSince(startedAt)
        }
    }

    // MARK: - test helpers

    func testChord(_ chord: String) {
        do {
            try Events.chord(chord, holdMS: 40)
            addLog("测试：发送 \(chord)")
        } catch {
            addLog("测试失败：\(error.localizedDescription)", isError: true)
        }
    }

    func testMedia(_ name: String) {
        Events.media(name)
        addLog("测试：媒体键 \(name)")
    }

    func testFn() {
        Events.fnTap()
        addLog("测试：Fn（应触发听写）")
    }

    func addLog(_ text: String, isError: Bool = false) {
        let line = LogLine(text, isError: isError)
        logs.append(line)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        ConfigStore.log(text)
    }

    // MARK: - helpers

    private static func bindingID(page: UInt32, usage: UInt32) -> String {
        let prefix = page == 0x07 ? "k" : "c"
        return "\(prefix):0x" + String(format: "%02X", usage)
    }

    static func usage(from identifier: String) -> UInt32 {
        let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return 0 }
        return UInt32(parts[1].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
    }
}
