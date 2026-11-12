import AppKit
import AVFoundation
import Darwin
import CoreAudio
import Foundation

// MARK: - CoreAudio helpers

func deviceName(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
    return status == noErr ? (name as String) : "?"
}

func allDevices() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
        return []
    }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
        return []
    }
    return ids
}

func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
        return 0
    }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func findDevice(contains needle: String) -> AudioDeviceID? {
    for id in allDevices() {
        let name = deviceName(id)
        if name.localizedCaseInsensitiveContains(needle) {
            return id
        }
    }
    return nil
}

// MARK: - ATVV decoder (IMA/DVI ADPCM)

final class ATVVDecoder {
    private let stepTable: [Int] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
        34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
        143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
        494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
        1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
        4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
        11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623,
        27086, 29794, 32767,
    ]
    private let indexTable = [-1, -1, -1, -1, 2, 4, 6, 8]

    private var predictor = 0
    private var stepIndex = 0
    private var pending = [UInt8]()
    private var previousInput: Double = 0
    private var previousOutput: Double = 0
    private var filterInitialized = false
    private let alpha: Double
    let frameSize: Int

    init(frameSize: Int = 120, sampleRate: Double = 16000) {
        self.frameSize = frameSize
        self.alpha = exp(-2.0 * Double.pi * 20.0 / sampleRate)
    }

    func reset(predictor: Int = 0, stepIndex: Int = 0) {
        self.predictor = min(32767, max(-32768, predictor))
        self.stepIndex = min(88, max(0, stepIndex))
        pending.removeAll()
        previousInput = 0
        previousOutput = 0
        filterInitialized = false
    }

    func feed(_ data: [UInt8]) -> [Int16] {
        pending.append(contentsOf: data)
        var samples: [Int16] = []
        while pending.count >= frameSize {
            let frame = Array(pending[0..<frameSize])
            pending.removeFirst(frameSize)
            samples.append(contentsOf: decodeFrame(frame))
        }
        return samples
    }

    private func decodeFrame(_ frame: [UInt8]) -> [Int16] {
        var out: [Int16] = []
        out.reserveCapacity(frame.count * 2)
        for byte in frame {
            out.append(decodeNibble(Int(byte >> 4)))
            out.append(decodeNibble(Int(byte & 0x0F)))
        }
        return postprocess(out)
    }

    private func decodeNibble(_ nibble: Int) -> Int16 {
        let step = stepTable[stepIndex]
        var difference = step >> 3
        if nibble & 1 != 0 { difference += step >> 2 }
        if nibble & 2 != 0 { difference += step >> 1 }
        if nibble & 4 != 0 { difference += step }

        if nibble & 8 != 0 {
            predictor -= difference
        } else {
            predictor += difference
        }
        predictor = min(32767, max(-32768, predictor))
        stepIndex += indexTable[nibble & 7]
        stepIndex = min(88, max(0, stepIndex))
        return Int16(predictor)
    }

    private func postprocess(_ input: [Int16]) -> [Int16] {
        guard !input.isEmpty else { return [] }
        if !filterInitialized {
            previousInput = Double(input[0])
            filterInitialized = true
        }
        let gain = pow(10.0, 10.0 / 20.0)
        var filtered = [Double]()
        filtered.reserveCapacity(input.count)
        for sample in input {
            let current = Double(sample)
            let output = current - previousInput + alpha * previousOutput
            previousInput = current
            previousOutput = output
            filtered.append(output * gain)
        }
        // 3-tap smoothing, same idea as the reference postprocessor.
        var result = filtered
        if filtered.count >= 3 {
            for i in 1..<(filtered.count - 1) {
                result[i] = (filtered[i - 1] + 2 * filtered[i] + filtered[i + 1]) / 4
            }
        }
        return result.map { Int16(min(32767, max(-32768, Int($0.rounded())))) }
    }
}

// MARK: - Audio output to BlackHole

final class VirtualMicOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let queue = DispatchQueue(label: "remote-mic.audio")
    private var started = false
    private var prebuffer: [Int16] = []
    private let prebufferFrames = 4800  // 300 ms @ 16 kHz
    private(set) var deviceID: AudioDeviceID = 0
    private(set) var totalSamples = 0
    var isRunning: Bool { engine.isRunning }

    @discardableResult
    func repinDevice() -> OSStatus {
        var dev = deviceID
        return AudioUnitSetProperty(
            engine.outputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0,
            &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    init(device: AudioDeviceID) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16000, channels: 1,
                                         interleaved: false) else {
            throw NSError(domain: "RemoteMic", code: 1)
        }
        self.format = format
        self.deviceID = device
        log("audio: attach")
        engine.attach(player)
        log("audio: set device (before connect)")
        let unit = engine.outputNode.audioUnit
        log("audio: unit=\(unit != nil)")
        var dev = device
        let status = AudioUnitSetProperty(
            unit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0,
            &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        log("audio: set device status=\(status)")
        if status != noErr {
            throw NSError(domain: "RemoteMic", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "无法把音频输出切到虚拟设备（\(status)）"])
        }
        engine.prepare()
        log("audio: connect")
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        log("audio: prepared")
        try engine.start()
        log("audio: started")
        started = true
        player.play()
    }

    func push(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.totalSamples += samples.count
            if !self.player.isPlaying {
                self.player.play()
            }
            self.prebuffer.append(contentsOf: samples)
            if self.prebuffer.count >= self.prebufferFrames {
                let chunk = self.prebuffer
                self.prebuffer.removeAll(keepingCapacity: true)
                self.schedule(chunk)
            }
        }
    }

    func flush() {
        queue.async { [weak self] in
            guard let self, !self.prebuffer.isEmpty else { return }
            let chunk = self.prebuffer
            self.prebuffer.removeAll(keepingCapacity: true)
            self.schedule(chunk)
        }
    }

    private func schedule(_ samples: [Int16]) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channel[index] = Float(sample) / 32768.0
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        queue.sync {
            flush()
        }
        player.stop()
        engine.stop()
        started = false
    }
}

// MARK: - Log capture

final class VoiceLogSource {
    var onControl: (([UInt8]) -> Void)?
    var onAudio: (([UInt8]) -> Void)?
    private var process: Process?
    private var buffer = ""
    private var shouldRun = false
    private let pattern = try! NSRegularExpression(
        pattern: #"0x(003C|003F) Characteristic Value \[\s*([0-9A-Fa-f ]+?)\s*\]"#)

    func start() {
        shouldRun = true
        guard process == nil else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "stream", "--style", "compact", "--predicate",
            "subsystem == \"com.apple.bluetooth\" AND (eventMessage CONTAINS \"0x003C Characteristic Value\" OR eventMessage CONTAINS \"0x003F Characteristic Value\")",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.feed(text)
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.shouldRun else { return }
                self.process = nil
                self.start()
            }
        }
        try? task.run()
        process = task
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        shouldRun = false
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        buffer = ""
    }

    private func feed(_ text: String) {
        buffer += text
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            parse(line)
        }
        if buffer.count > 16384 { buffer = "" }
    }

    private func parse(_ line: String) {
        let text = line as NSString
        guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else {
            return
        }
        let handle = text.substring(with: match.range(at: 1))
        let hex = text.substring(with: match.range(at: 2))
        let bytes = hex.split(whereSeparator: { $0 == " " }).compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else { return }
        if handle == "003C" {
            onAudio?(bytes)
        } else {
            onControl?(bytes)
        }
    }
}

// MARK: - Routing helpers

func deviceUID(_ id: AudioDeviceID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var s: CFString = "" as CFString; var sz = UInt32(MemoryLayout<CFString>.size)
    AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &s); return s as String
}

func deviceID(uid: String) -> AudioDeviceID? {
    for id in allDevices() where deviceUID(id) == uid { return id }
    return nil
}

func defaultDevice(_ sel: AudioObjectPropertySelector) -> AudioDeviceID {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var d = AudioDeviceID(0); var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &d); return d
}

@discardableResult
func setDefaultDevice(_ sel: AudioObjectPropertySelector, _ id: AudioDeviceID) -> OSStatus {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var d = id
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &d)
}

func isVirtualName(_ name: String) -> Bool {
    name.contains("Google TV") || name.contains("BlackHole") || name.contains("MiRemoteV")
}

let lastOutputURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/gvtv-remote/last-output-uid.txt")

// MARK: - Mic gain / postprocess (对齐无线麦)

struct MicSettings {
    var gainDB: Double = 10.0
}

let micConfigURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/gvtv-remote/mic-config.json")

func loadMicSettings() -> MicSettings {
    guard let data = try? Data(contentsOf: micConfigURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let number = object["gain_db"] as? NSNumber else {
        return MicSettings()
    }
    return MicSettings(gainDB: min(24.0, max(-24.0, number.doubleValue)))
}

/// 20 Hz 一阶高通去 DC 偏置 + [1,2,1]/4 三点平滑 + dB 增益 + int16 削波。
/// 参数与无线麦的 DCHighPassFilter / postprocess 一致（默认 +10 dB）。
final class PCMPostprocessor {
    private let alpha: Double
    private var previousInput = 0.0
    private var previousOutput = 0.0
    private var initialized = false
    var gainDB: Double

    init(sampleRate: Double = 16000, cutoffHz: Double = 20, gainDB: Double = 10) {
        self.alpha = exp(-2.0 * Double.pi * cutoffHz / sampleRate)
        self.gainDB = min(24.0, max(-24.0, gainDB))
    }

    func reset() {
        previousInput = 0
        previousOutput = 0
        initialized = false
    }

    func process(_ samples: [Int16]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        if !initialized {
            previousInput = Double(samples[0])
            initialized = true
        }

        var centered = [Int](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let current = Double(samples[i])
            let output = current - previousInput + alpha * previousOutput
            previousInput = current
            previousOutput = output
            centered[i] = min(32767, max(-32768, Int(output.rounded())))
        }

        var smoothed = centered
        if centered.count >= 3 {
            for i in 1..<(centered.count - 1) {
                smoothed[i] = (centered[i - 1] + 2 * centered[i] + centered[i + 1]) >> 2
            }
        }

        let gain = pow(10.0, min(24.0, max(-24.0, gainDB)) / 20.0)
        var result = [Int16](repeating: 0, count: smoothed.count)
        for i in 0..<smoothed.count {
            let scaled = Int((Double(smoothed[i]) * gain).rounded())
            result[i] = Int16(min(32767, max(-32768, scaled)))
        }
        return result
    }
}

// MARK: - Main

struct Options {
    var list = false
    var tone = false
    var fixRouting = false
    var gainDB: Double? = nil
    var duration: Double = 0
    var deviceName = "BlackHole 2ch"
}

func parseOptions() -> Options {
    var options = Options()
    let args = CommandLine.arguments
    var index = 1
    while index < args.count {
        switch args[index] {
        case "--list": options.list = true
        case "--tone": options.tone = true
        case "--fix-routing": options.fixRouting = true
        case "--gain-db": index += 1; options.gainDB = Double(args[index])
        case "--duration": index += 1; options.duration = Double(args[index]) ?? 0
        case "--device": index += 1; options.deviceName = args[index]
        default: break
        }
        index += 1
    }
    return options
}

func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

func log(_ message: String) {
    let line = "[\(timestamp())] \(message)"
    print(line)
    fflush(stdout)
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/RemoteMic.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write((line + "\n").data(using: .utf8)!)
        try? handle.close()
    } else {
        try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

func serviceRestartCount() -> UInt32 {
    var a = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyServiceRestarted,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var v: UInt32 = 0
    var sz = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &v)
    return v
}

var suppressOutputListener = false
var lastRoutingFixAt = Date.distantPast

func fixRouting() {
    guard options.fixRouting else { return }
    lastRoutingFixAt = Date()
    suppressOutputListener = true
    defer { suppressOutputListener = false }
    let out = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
    let outName = deviceName(out)
    if isVirtualName(outName) {
        var restored = false
        if let saved = try? String(contentsOf: lastOutputURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let id = deviceID(uid: saved), !isVirtualName(deviceName(id)) {
            setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, id)
            setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, id)
            log("路由修复：输出从虚拟设备切回 \(deviceName(id))")
            restored = true
        }
        if !restored,
           let real = allDevices().first(where: { channelCount($0, scope: kAudioObjectPropertyScopeOutput) > 0 && !isVirtualName(deviceName($0)) }) {
            setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, real)
            setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, real)
            log("路由修复：输出切到 \(deviceName(real))")
        }
    } else {
        let uid = deviceUID(out)
        try? FileManager.default.createDirectory(at: lastOutputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? uid.write(to: lastOutputURL, atomically: true, encoding: .utf8)
    }
    if let gtv = findDevice(contains: options.deviceName) {
        if defaultDevice(kAudioHardwarePropertyDefaultInputDevice) != gtv {
            setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, gtv)
            log("路由修复：输入切到 \(deviceName(gtv))")
        }
    }
}

var lastHeartbeat = Date()

// 独立心跳：主线程卡在 CoreAudio 调用里时，LaunchAgent 的 KeepAlive 不会生效，
// 这里主动退出，让 launchd 重新拉起一个干净进程。
DispatchQueue.global().async {
    while true {
        Thread.sleep(forTimeInterval: 5)
        if Date().timeIntervalSince(lastHeartbeat) > 12 {
            log("心跳超时（主线程卡住），退出以便重启")
            exit(1)
        }
    }
}

let options = parseOptions()
if options.list {
    for id in allDevices() {
        let input = channelCount(id, scope: kAudioObjectPropertyScopeInput)
        let output = channelCount(id, scope: kAudioObjectPropertyScopeOutput)
        if input > 0 || output > 0 {
            print(String(format: "%7u  in:%d out:%d  %@", id, input, output, deviceName(id)))
        }
    }
    exit(0)
}

// 单实例锁必须在任何 CoreAudio 设备访问之前获取，避免第二个实例卡在设备初始化。
let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/gvtv-remote", isDirectory: true)
try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
let lockPath = supportDir.appendingPathComponent("remote-mic.lock").path
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    log("已有另一个麦克风桥在运行，本实例退出")
    exit(0)
}
// 清理上一次异常退出留下的 log stream 子进程（避免重复处理日志）。
let cleaner = Process()
cleaner.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
cleaner.arguments = ["-f", "log stream.*0x003C"]
try? cleaner.run()
cleaner.waitUntilExit()
Thread.sleep(forTimeInterval: 1.5)

guard let device = findDevice(contains: options.deviceName) else {
    log("找不到虚拟音频设备（名称包含 \(options.deviceName)）。用 --list 查看。")
    exit(1)
}
log("虚拟设备：\(deviceName(device)) (id \(device))")

func makeOutput(_ id: AudioDeviceID) -> VirtualMicOutput? {
    do {
        return try VirtualMicOutput(device: id)
    } catch {
        log("音频输出启动失败：\(error.localizedDescription)")
        return nil
    }
}

var currentDeviceID = device
// 参考“无线麦”的按需管道：不再常驻占用虚拟设备，每次按住语音键才创建输出。
var output: VirtualMicOutput? = nil
fixRouting()
DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { fixRouting() }

if options.tone {
    let seconds = options.duration > 0 ? options.duration : 1.5
    let count = Int(16000 * seconds)
    var tone = [Int16](repeating: 0, count: count)
    for i in 0..<count {
        tone[i] = Int16(6000 * sin(2 * Double.pi * 440 * Double(i) / 16000))
    }
    guard let out = makeOutput(device) else { exit(1) }
    log("播放 \(seconds) 秒 440Hz 测试音到 \(deviceName(device))，同时请用输入设备监听…")
    // 直接按 20ms 一块送入
    var index = 0
    while index < tone.count {
        let end = min(index + 320, tone.count)
        out.push(Array(tone[index..<end]))
        Thread.sleep(forTimeInterval: 0.02)
        index = end
    }
    out.flush()
    Thread.sleep(forTimeInterval: 0.8)
    out.stop()
    log("测试音结束")
    exit(0)
}

let decoder = ATVVDecoder()
var micSettings = loadMicSettings()
if let override = options.gainDB { micSettings.gainDB = min(24.0, max(-24.0, override)) }
let pcm = PCMPostprocessor(gainDB: micSettings.gainDB)
let source = VoiceLogSource()
var sessionOpen = false
var packets = 0
var samplesTotal = 0
var lastReport = Date()
var pendingSync: (Int, Int)?

func handleControl(_ bytes: [UInt8]) {
    guard let first = bytes.first else { return }
    switch first {
    case 0x04:
        // 0x08 已预打开时直接复用，避免 IME 先开麦、桥后开管道造成的首句丢失。
        if output == nil, let id = findDevice(contains: options.deviceName) {
            output = makeOutput(id)
            currentDeviceID = id
        }
        if options.fixRouting,
           let gtv = findDevice(contains: options.deviceName),
           defaultDevice(kAudioHardwarePropertyDefaultInputDevice) != gtv {
            setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, gtv)
            log("语音开始前输入切回 \(deviceName(gtv))")
        }
        micSettings = loadMicSettings()
        if let override = options.gainDB { micSettings.gainDB = min(24.0, max(-24.0, override)) }
        pcm.gainDB = micSettings.gainDB
        pcm.reset()
        decoder.reset()
        pendingSync = nil
        sessionOpen = true
        log(String(format: "语音会话开始（ATVV），已打开按需虚拟管道，增益 %+.1f dB", micSettings.gainDB))
    case 0x08:
        if output == nil, let id = findDevice(contains: options.deviceName) {
            output = makeOutput(id)
            currentDeviceID = id
            log("语音键 0x08：预打开虚拟管道")
        }
    case 0x0A:
        if bytes.count >= 7 {
            let raw = Int16(bitPattern: UInt16(bytes[4]) << 8 | UInt16(bytes[5]))
            let step = Int(bytes[6])
            pendingSync = (Int(raw), step)
            if sessionOpen {
                decoder.reset(predictor: Int(raw), stepIndex: step)
            }
        }
    case 0x00:
        sessionOpen = false
        output?.flush()
        output?.stop()
        output = nil
        log("语音会话停止，关闭按需虚拟管道")
    default:
        break
    }
}

source.onControl = { handleControl($0) }
source.onAudio = { bytes in
    guard sessionOpen else { return }
    packets += 1
    if let sync = pendingSync {
        decoder.reset(predictor: sync.0, stepIndex: sync.1)
        pendingSync = nil
    }
    let decoded = decoder.feed(bytes)
    guard !decoded.isEmpty else { return }
    let samples = pcm.process(decoded)
    samplesTotal += samples.count
    output?.push(samples)
}
func restartBridge(_ reason: String) -> Never {
    log("重启音频桥（\(reason)）：退出后由 LaunchAgent 拉起")
    output?.stop()
    source.stop()
    exit(0)
}

signal(SIGTERM, SIG_IGN)
let sigTerm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigTerm.setEventHandler {
    log("收到 SIGTERM，停止音频/日志源")
    output?.stop()
    source.stop()
    exit(0)
}
sigTerm.resume()

source.start()
log("已启动：监听遥控器语音键 + 麦克风音频，输出到 \(deviceName(device))")

let wakeNames = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification]
for name in wakeNames {
    NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
        log("系统唤醒：重启日志源并检查路由")
        source.restart()
        fixRouting()
    }
}
DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name("com.gvtv.remote-mic.restart"), object: nil, queue: .main
) { _ in
    log("收到重启通知：检查路由后重启音频桥")
    fixRouting()
    restartBridge("手动重启")
}

let appStart = Date()
NotificationCenter.default.addObserver(
    forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
) { _ in
    if Date().timeIntervalSince(appStart) > 3.0 {
        let st = output?.repinDevice() ?? -1
        log("音频配置变化，虚拟管道重新绑定 status=\(st)")
    }
}



// 设备 ID 会随 coreaudiod 重启变化；引擎也可能因默认设备切换而停止。
// 每 2 秒自检一次，必要时重建音频输出，避免“解码正常但虚拟麦克风没声音”。
log("在输入法/会议软件里把麦克风选为 \(deviceName(device))")

if options.duration > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + options.duration) {
        log("到达运行时长，退出")
        source.stop()
        output?.stop()
        exit(0)
    }
}

let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    let rms: Double = 0
    _ = rms
    lastHeartbeat = Date()
    log("状态：会话=\(sessionOpen ? "开" : "关") 音频包=\(packets) 采样=\(samplesTotal)")
}
RunLoop.main.run()
_ = timer
