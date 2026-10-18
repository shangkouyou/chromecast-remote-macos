import AppKit
import SwiftUI

/// 语音会话的悬浮窗（不抢焦点）。命名沿用设备的既有规则，例如 Chromecast Remote。
final class VoiceHUD {
    static let shared = VoiceHUD()
    private var panel: NSPanel?

    func show(name: String, hint: String = "说完自动结束") {
        let host = NSHostingView(rootView: VoiceHUDView(name: name, hint: hint))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 84)

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 84),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        panel?.contentView = host

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: frame.midX - 150, y: frame.maxY - 130))
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

struct VoiceHUDView: View {
    let name: String
    let hint: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(Color(red: 0.10, green: 0.45, blue: 0.91))
            VStack(alignment: .leading, spacing: 2) {
                Text("正在听写…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(name) · \(hint)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 300, height: 84)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
