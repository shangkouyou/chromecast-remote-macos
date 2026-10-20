import SwiftUI
import Foundation

@main
struct MicGainApp: App {
    var body: some Scene {
        WindowGroup("遥控器麦克风增益") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var gain: Double = 10
    @State private var status = ""
    private let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/gvtv-remote/mic-config.json")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Google TV 遥控器麦克风增益").font(.title3).bold()
            Text("默认 +10 dB（与无线麦一致）。修改后下一次按住语音键生效。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("增益")
                Slider(value: $gain, in: 0...24, step: 1)
                Text(String(format: "%+.0f dB", gain))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }

            HStack(spacing: 8) {
                ForEach([0, 6, 10, 14, 18, 24], id: \.self) { value in
                    Button("+\(value)") {
                        gain = Double(value)
                        save()
                    }
                }
            }

            HStack {
                Button("保存") { save() }
                Button("恢复默认 +10 dB") {
                    gain = 10
                    save()
                }
                Spacer()
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            Text("配置文件：~/Library/Application Support/gvtv-remote/mic-config.json")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: load)
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["gain_db"] as? NSNumber else { return }
        gain = min(24, max(0, number.doubleValue))
    }

    private func save() {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let object: [String: Any] = ["gain_db": gain]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            status = "保存失败"
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            status = "已保存，下一次按住语音键生效"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }
}
