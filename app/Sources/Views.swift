import AppKit
import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var engine: RemoteEngine
    @State private var tab: Tab = .status

    enum Tab: String, CaseIterable, Identifiable {
        case status, mapping, test, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .status: return "运行状态"
            case .mapping: return "按键映射"
            case .test: return "按键测试"
            case .settings: return "设置"
            }
        }
        var icon: String {
            switch self {
            case .status: return "gauge.with.dots.needle.50percent"
            case .mapping: return "keyboard"
            case .test: return "waveform"
            case .settings: return "gearshape"
            }
        }
    }

    init() {
        let initial = ProcessInfo.processInfo.environment["GVTV_TAB"]
            .flatMap(Tab.init(rawValue:)) ?? .status
        _tab = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            if !engine.isRunning { engine.start() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.10, green: 0.45, blue: 0.91),
                                 Color(red: 0.20, green: 0.66, blue: 0.33)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                Image(systemName: "av.remote.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Google TV Remote")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(engine.deviceName) · \(engine.deviceIdentity) · 虚拟设备 \(engine.config.virtualName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            StatusPill(running: engine.isRunning, connected: engine.deviceConnected)
            Button(engine.isRunning ? "停止" : "启动") {
                engine.toggleRunning()
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isRunning ? .red : .accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).frame(width: 20)
                        Text(item.title).font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tab == item ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("权限")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                PermissionDot(title: "输入监控", ok: engine.inputMonitoring)
                PermissionDot(title: "辅助功能", ok: engine.accessibility)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .padding(.top, 12)
        .frame(width: 190)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .status: StatusView()
        case .mapping: MappingView()
        case .test: TestView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Status

struct StatusView: View {
    @EnvironmentObject var engine: RemoteEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    statusCard
                    permissionsCard
                }
                statsGrid
                logsCard
            }
            .padding(20)
        }
    }

    private var statusCard: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(engine.isRunning ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: engine.isRunning ? "checkmark.seal.fill" : "pause.circle")
                        .font(.system(size: 24))
                        .foregroundColor(engine.isRunning ? .green : .secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.isRunning ? "映射服务正在运行" : "映射服务已停止")
                        .font(.system(size: 16, weight: .semibold))
                    Text(engine.isRunning
                         ? "\(engine.deviceConnected ? "已连接" : "等待") \(engine.deviceName)，\(engine.seized ? "独占" : "共享")模式"
                         : "点击右侧按钮启动，或按 ⌘R")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(spacing: 6) {
                    Button(engine.isRunning ? "停止" : "启动") { engine.toggleRunning() }
                        .buttonStyle(.borderedProminent)
                        .tint(engine.isRunning ? .red : .accentColor)
                    Button("重新连接") { engine.reconnect() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            Divider()
            HStack(spacing: 24) {
                Label(engine.deviceConnected ? "遥控器在线" : "遥控器未连接",
                      systemImage: engine.deviceConnected ? "dot.radiowaves.left.and.right" : "wifi.slash")
                    .foregroundColor(engine.deviceConnected ? .green : .orange)
                Label(engine.seized ? "独占设备" : "共享设备",
                      systemImage: engine.seized ? "lock.fill" : "lock.open")
                    .foregroundColor(.secondary)
                Spacer()
                Text(engine.statusMessage).font(.system(size: 11)).foregroundColor(.secondary)
            }
            .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionsCard: some View {
        Card("权限") {
            PermissionRow(
                icon: "eye.fill",
                title: "输入监控",
                detail: "读取遥控器按键",
                granted: engine.inputMonitoring,
                action: { Permissions.openInputMonitoringSettings() }
            )
            PermissionRow(
                icon: "hand.raised.fill",
                title: "辅助功能",
                detail: "向系统发送按键",
                granted: engine.accessibility,
                action: { Permissions.openAccessibilitySettings() }
            )
            HStack {
                if engine.inputMonitoring && engine.accessibility {
                    Label("权限已就绪，按遥控器即可工作", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                } else {
                    Label("授权后自动生效；若仍无反应请重启 App", systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("请求权限") { engine.requestPermissions() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
        .frame(width: 330)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatTile(title: "已收报告", value: "\(engine.reportCount)")
            StatTile(title: "按键次数", value: "\(engine.pressCount)")
            StatTile(title: "运行时长", value: formatUptime(engine.uptime))
            StatTile(title: "设备", value: engine.deviceIdentity)
            StatTile(title: "最近按键", value: engine.lastButton ?? "—")
            StatTile(title: "最近动作", value: engine.lastAction ?? "—")
            StatTile(title: "原始报告", value: engine.lastReport)
            StatTile(title: "描述符", value: "17 个用法 / report 1")
        }
    }

    private var logsCard: some View {
        Card("事件日志") {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(engine.logs.suffix(80)) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text(line.time)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(line.isError ? .red : .primary)
                            }
                            .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(height: 190)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
                .cornerRadius(8)
                .onChange(of: engine.logs.count) { _ in
                    if let last = engine.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Button("打开设置", action: action)
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
    }
}

// MARK: - Mapping

struct MappingView: View {
    @EnvironmentObject var engine: RemoteEngine
    @State private var selectedID: String? = "c:0x42"
    @State private var draft = ActionSpec()
    @State private var recorder = KeyRecorder()
    @State private var showAddSheet = false

    var body: some View {
        HStack(spacing: 0) {
            list
            Divider()
            editor
        }
        .onAppear { loadDraft() }
        .onChange(of: selectedID) { _ in loadDraft() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("遥控器按键").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加自定义按键")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(engine.buttons) { button in
                        Button {
                            selectedID = button.id
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(button.label)
                                        .font(.system(size: 12, weight: selectedID == button.id ? .semibold : .regular))
                                    Text(button.id)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(engine.action(for: button.id).summary)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(selectedID == button.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 330)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
        .sheet(isPresented: $showAddSheet) {
            AddButtonSheet { id, label in
                engine.addCustomButton(id: id, label: label)
                selectedID = RemoteButtons.canonical(id)
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let id = selectedID, let button = engine.buttons.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(button.label).font(.system(size: 20, weight: .semibold))
                            Text("\(button.id) · usage \(button.usageHex)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if button.isCustom {
                            Button("删除") { engine.removeCustomButton(button.id) }
                                .buttonStyle(.link)
                                .foregroundColor(.red)
                        }
                    }

                    if id == engine.voiceButtonID {
                        voiceBanner
                    }

                    Card("动作") {
                        Picker("类型", selection: $draft.kind) {
                            ForEach(ActionKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)

                        actionFields
                    }

                    HStack {
                        Button("保存") {
                            engine.setAction(draft, for: id)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!draftValid)

                        Button("恢复默认") {
                            if let value = AppConfig.defaultMapping[id], let action = ActionSpec(string: value) {
                                draft = action
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                        if !draftValid {
                            Text("请补全动作参数").font(.system(size: 11)).foregroundColor(.red)
                        }
                    }
                }
                .padding(20)
                .onChange(of: draft.kind) { kind in
                    switch kind {
                    case .key: if draft.chord.isEmpty { draft.chord = "cmd+space" }
                    case .media: if draft.media.isEmpty { draft.media = "play_pause" }
                    default: break
                    }
                }
            }
        } else {
            Text("请选择一个按键").foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var voiceBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text("此键固定为语音云键：按下发送 Fn（Globe），驱动 macOS 听写")
                    .font(.system(size: 11))
                Text("触发方式与听写设置请在「设置 → 语音」里调整")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.10)))
    }

    @ViewBuilder
    private var actionFields: some View {
        switch draft.kind {
        case .none:
            Text("按下此键不做任何事").font(.system(size: 11)).foregroundColor(.secondary)
        case .voice:
            Text("语音键由引擎接管").font(.system(size: 11)).foregroundColor(.secondary)
        case .key:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("例如 cmd+space", text: $draft.chord)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    Button(recorder.isRecording ? "请按下…" : "录制") {
                        recorder.toggle()
                    }
                    .buttonStyle(.bordered)
                }
                Text("支持 cmd / ctrl / alt / shift + 键名，如 cmd+shift+4")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                HStack {
                    Text("按住时长").font(.system(size: 11)).foregroundColor(.secondary)
                    Stepper("\(draft.holdMS) ms", value: $draft.holdMS, in: 1...500, step: 5)
                        .font(.system(size: 11))
                }
            }
            .onChange(of: recorder.chord) { value in
                if !value.isEmpty { draft.chord = value; recorder.chord = "" }
            }
        case .media:
            Picker("媒体键", selection: $draft.media) {
                ForEach(MediaKey.all, id: \.self) { name in
                    Text(MediaKey.title(name)).tag(name)
                }
            }
        case .app:
            TextField("App 名称，如 Safari", text: $draft.value)
                .textFieldStyle(.roundedBorder)
        case .url:
            TextField("https://…", text: $draft.value)
                .textFieldStyle(.roundedBorder)
        case .shell:
            TextField("/bin/bash -lc 命令", text: $draft.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        case .text:
            TextField("要输入的文本", text: $draft.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var draftValid: Bool {
        switch draft.kind {
        case .none, .voice: return true
        case .key: return (try? KeyChord.parse(draft.chord)) != nil
        case .media: return !draft.media.isEmpty
        case .app, .url, .shell, .text: return !draft.value.isEmpty
        }
    }

    private func loadDraft() {
        guard let id = selectedID else { return }
        draft = engine.action(for: id)
        if draft.kind == .media && draft.media.isEmpty { draft.media = "play_pause" }
        if draft.kind == .key && draft.chord.isEmpty { draft.chord = "cmd+space" }
    }
}

struct AddButtonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var id = "c:0x30"
    @State private var label = ""
    let onAdd: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加自定义按键").font(.headline)
            Text("填写 HID usage（例如 c:0x30 或 k:0x28），名称可留空。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("usage，如 c:0x30", text: $id)
                .textFieldStyle(.roundedBorder)
            TextField("名称，如 自定义键", text: $label)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    onAdd(id, label.isEmpty ? id : label)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidUsage)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var isValidUsage: Bool {
        let text = id.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, ["c", "k"].contains(parts[0]) else { return false }
        let number = parts[1].replacingOccurrences(of: "0x", with: "")
        return UInt32(number, radix: 16) != nil
    }
}

// MARK: - Test

struct TestView: View {
    @EnvironmentObject var engine: RemoteEngine
    @StateObject private var recorder = KeyRecorder()
    @State private var chord = "cmd+space"

    private let presets: [(String, String, String)] = [
        ("聚焦搜索", "cmd+space", "magnifyingglass"),
        ("切换 App", "cmd+tab", "rectangle.on.rectangle"),
        ("锁屏", "ctrl+cmd+q", "lock.fill"),
        ("区域截图", "cmd+shift+4", "crop"),
        ("强制退出", "cmd+alt+escape", "xmark.octagon"),
        ("调度中心", "ctrl+up", "rectangle.3.group"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                liveCard
                comboCard
                presetsCard
                outputCard
                diagnosticsCard
            }
            .padding(20)
        }
    }

    private var liveCard: some View {
        Card("实时按键（遥控器）") {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.lastButton ?? "等待按键…")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(engine.lastAction ?? "按一下遥控器，这里会显示解析结果")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("原始报告").font(.system(size: 10)).foregroundColor(.secondary)
                    Text(engine.lastReport)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            Divider()
            HStack {
                Label("共 \(engine.pressCount) 次按键 / \(engine.reportCount) 条报告",
                      systemImage: "number.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(engine.inputMonitoring ? "输入监控已授权" : "缺少输入监控权限")
                    .font(.system(size: 11))
                    .foregroundColor(engine.inputMonitoring ? .green : .red)
            }
        }
    }

    private var comboCard: some View {
        Card("组合键测试") {
            HStack(spacing: 10) {
                TextField("例如 cmd+shift+4", text: $chord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                Button(recorder.isRecording ? "请按下…" : "录制") { recorder.toggle() }
                    .buttonStyle(.bordered)
                Button("发送到系统") { engine.testChord(chord) }
                    .buttonStyle(.borderedProminent)
                Button("Fn") { engine.testFn() }
                    .buttonStyle(.bordered)
            }
            Text("把光标放到任意输入框后点「发送」，可验证辅助功能权限与合成链路。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            TextField("在这里试输入…", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
                .help("占位输入框：实际测试请用其他 App 的输入框")
        }
        .onChange(of: recorder.chord) { value in
            if !value.isEmpty { chord = value; recorder.chord = "" }
        }
    }

    private var presetsCard: some View {
        Card("组合键预设") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(presets, id: \.0) { preset in
                    Button {
                        chord = preset.1
                        engine.testChord(preset.1)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.0).font(.system(size: 12, weight: .medium))
                                Text(prettyChord(preset.1))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        Card("语音诊断") {
            HStack {
                Text("HID 语音键报告：\(engine.voiceReportCount) 条")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(engine.lastFnEvent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("GATT 监听：\(engine.gattRunning ? "运行中" : "未运行") · 事件 \(engine.gattEventCount)")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(engine.lastGATTEvent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                Button("模拟一次语音键") { engine.pressVoice() }
                    .buttonStyle(.bordered)
                Toggle("记录原始报告", isOn: Binding(
                    get: { engine.config.logReports },
                    set: { engine.setLogReports($0) }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11))
                Spacer()
                Text("模式：\(engine.modeTitle)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if engine.reportLog.isEmpty {
                        Text("还没有收到报告。按遥控器任意键，这里会显示 report ID、原始字节、解析结果。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    ForEach(engine.reportLog.suffix(20)) { line in
                        HStack(spacing: 8) {
                            Text(line.time).foregroundColor(.secondary)
                            Text("r\(line.reportID)")
                            Text(line.hex).frame(width: 60, alignment: .leading)
                            Text(line.decoded).foregroundColor(.secondary)
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 150)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
            .cornerRadius(8)
        }
    }

    private var outputCard: some View {
        Card("输出自检") {
            HStack(spacing: 10) {
                Button("音量 +") { engine.testMedia("volume_up") }
                Button("音量 −") { engine.testMedia("volume_down") }
                Button("静音") { engine.testMedia("mute") }
                Button("播放/暂停") { engine.testMedia("play_pause") }
                Spacer()
                Text(engine.accessibility ? "辅助功能已授权" : "缺少辅助功能权限")
                    .font(.system(size: 11))
                    .foregroundColor(engine.accessibility ? .green : .red)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var engine: RemoteEngine
    @State private var virtualName = ""
    @State private var endActions = ""
    @State private var address = ""
    @State private var micGainDB = 10.0
    @State private var gainStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                deviceCard
                voiceCard
                micGainCard
                namingCard
                configCard
                aboutCard
            }
            .padding(20)
        }
        .onAppear {
            virtualName = engine.config.virtualName
            endActions = engine.config.voice.endActions.joined(separator: ", ")
            address = engine.config.voice.bluetoothAddress
            micGainDB = MicGainStore.load()
        }
    }

    private var deviceCard: some View {
        Card("设备") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(engine.deviceName).font(.system(size: 13, weight: .medium))
                    Text(engine.deviceIdentity)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("独占设备（接管全部按键）", isOn: Binding(
                    get: { engine.config.device.seize },
                    set: { engine.setSeize($0) }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 12))
            }
            Text("独占后 macOS 不再处理遥控器原始按键，避免与自定义映射重复触发。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var voiceCard: some View {
        Card("语音键（Fn 云键）") {
            HStack {
                Text("触发方式").font(.system(size: 12))
                Picker("", selection: Binding(
                    get: { engine.config.voice.mode },
                    set: { value in engine.updateVoice { $0.mode = value } }
                )) {
                    Text("按一次开始 / 再按一次结束（latch，推荐）").tag("latch")
                    Text("按住说话（hold）").tag("hold")
                    Text("每次轻按 Fn（toggle）").tag("toggle")
                    Text("双次 Fn（double）").tag("double")
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer()
                Text("系统听写快捷键需匹配").font(.system(size: 10)).foregroundColor(.secondary)
            }
            HStack {
                Text("Fn 最短保持").font(.system(size: 12))
                Stepper("\(engine.config.voice.minHoldMS) ms", value: Binding(
                    get: { engine.config.voice.minHoldMS },
                    set: { engine.setMinHold($0) }
                ), in: 0...2000, step: 50)
                .font(.system(size: 12))
                Spacer()
                Toggle("记录原始 HID 报告", isOn: Binding(
                    get: { engine.config.logReports },
                    set: { engine.setLogReports($0) }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11))
            }
            HStack {
                Text("最长会话").font(.system(size: 12))
                Stepper("\(Int(engine.config.voice.maxSessionS)) 秒", value: Binding(
                    get: { engine.config.voice.maxSessionS },
                    set: { engine.setMaxSession($0) }
                ), in: 5...300, step: 5)
                .font(.system(size: 12))
                Spacer()
            }
            HStack {
                Text("结束后动作").font(.system(size: 12))
                TextField("可选，如 key:escape", text: $endActions)
                    .textFieldStyle(.roundedBorder)
                Button("保存") {
                    let actions = endActions
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    engine.updateVoice { $0.endActions = actions }
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Toggle("结束后断开蓝牙", isOn: Binding(
                    get: { engine.config.voice.disconnectBluetooth },
                    set: { val in engine.updateVoice { $0.disconnectBluetooth = val } }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 12))
                TextField("遥控器蓝牙地址", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                Button("保存") {
                    let value = address
                    engine.updateVoice { $0.bluetoothAddress = value }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var micGainCard: some View {
        Card("麦克风增益") {
            HStack(spacing: 12) {
                Text("增益").font(.system(size: 12))
                Slider(value: $micGainDB, in: 0...24, step: 1, onEditingChanged: { editing in
                    if !editing { saveMicGain() }
                })
                Text(String(format: "%+.0f dB", micGainDB))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 60, alignment: .trailing)
            }
            HStack(spacing: 8) {
                ForEach([6, 10, 13, 16, 18], id: \.self) { value in
                    Button("+\(value)") {
                        micGainDB = Double(value)
                        saveMicGain()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Text(gainStatus).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Text("默认 +10 dB（20 Hz 高通 + 三点平滑 + 增益 + 削波，对齐无线麦）。建议 6–14 dB；过高会放大底噪/削波。下一次按住语音键生效。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func saveMicGain() {
        _ = MicGainStore.save(micGainDB)
        gainStatus = "已保存，下次按键生效"
    }

    private var namingCard: some View {
        Card("虚拟窗口 / 设备命名") {
            HStack {
                Text("名称").font(.system(size: 12))
                TextField("Chromecast Remote", text: $virtualName)
                    .textFieldStyle(.roundedBorder)
                Button("保存") { engine.setVirtualName(virtualName) }
                    .buttonStyle(.bordered)
            }
            Text("命名沿用设备的既有规则：Google Inc. / Chromecast Remote（VID:PID 18d1:9450）。创建虚拟键盘或云端语音窗口时使用同一名称。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var configCard: some View {
        Card("配置文件") {
            HStack {
                Text(ConfigStore.fileURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            HStack {
                Button("恢复默认键位") { engine.resetMapping() }
                    .buttonStyle(.bordered)
                Button("重新加载配置") { engine.reloadConfig() }
                    .buttonStyle(.bordered)
                Spacer()
                Text("快捷键、语音、命名都会写入此文件").font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    private var aboutCard: some View {
        Card("关于") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Google TV Remote 1.0").font(.system(size: 12, weight: .medium))
                    Text("Chromecast 蓝牙遥控器 → macOS 按键映射 · Fn 云键")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("日志：~/Library/Logs/GoogleTVRemote.log")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Components

struct Card<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct StatusPill: View {
    let running: Bool
    let connected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(running ? (connected ? Color.green : Color.orange) : Color.secondary)
                .frame(width: 8, height: 8)
            Text(running ? (connected ? "运行中" : "等待设备") : "已停止")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

struct PermissionDot: View {
    let title: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundColor(ok ? .green : .secondary)
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - Helpers

final class KeyRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var chord = ""
    private var monitor: Any?

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard monitor == nil else { isRecording = true; return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 && flags.isEmpty {
                self.stop()
                return nil
            }
            var pieces: [String] = []
            if flags.contains(.control) { pieces.append("ctrl") }
            if flags.contains(.option) { pieces.append("alt") }
            if flags.contains(.shift) { pieces.append("shift") }
            if flags.contains(.command) { pieces.append("cmd") }
            pieces.append(KeyChord.name(for: CGKeyCode(event.keyCode)))
            self.chord = pieces.joined(separator: "+")
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    deinit { stop() }
}

func prettyChord(_ chord: String) -> String {
    let map: [String: String] = [
        "cmd": "⌘", "command": "⌘", "shift": "⇧", "ctrl": "⌃", "control": "⌃",
        "alt": "⌥", "option": "⌥", "return": "↩", "enter": "↩", "escape": "⎋",
        "space": "Space", "tab": "Tab", "up": "↑", "down": "↓", "left": "←", "right": "→",
    ]
    return chord
        .split(separator: "+")
        .map { map[String($0).lowercased()] ?? String($0) }
        .joined(separator: " ")
}

func formatUptime(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%02d:%02d", m, s)
}
