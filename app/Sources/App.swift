import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct GoogleTVRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = RemoteEngine()

    init() {
        SelfTest.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Google TV Remote") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("启动 / 停止映射") { engine.toggleRunning() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("重新连接遥控器") { engine.reconnect() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            Text(engine.isRunning ? "映射服务：运行中" : "映射服务：已停止")
            Text(engine.deviceConnected ? "设备：\(engine.deviceName)" : "设备：未连接")
            Divider()
            Button(engine.isRunning ? "停止" : "启动") { engine.toggleRunning() }
            Button("显示主窗口") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: engine.isRunning ? "av.remote.fill" : "av.remote")
        }
        .menuBarExtraStyle(.menu)
    }
}
