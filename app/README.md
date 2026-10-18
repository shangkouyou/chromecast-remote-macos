# Google TV Remote（原生 App）

SwiftUI 原生应用，封装了 HID 读取、描述符解码、按键映射、Fn 云键与测试界面。

## 构建

```bash
./build.sh
open "dist/Google TV Remote.app"
```

产物：`dist/Google TV Remote.app`（ad-hoc 签名，无第三方依赖，最低 macOS 13）。

## 自检

```bash
"dist/Google TV Remote.app/Contents/MacOS/GoogleTVRemote" --selftest
```

覆盖：描述符解析、17 个用法、数组下标解码、动作解析、配置加载、设备识别。

## 结构

| 文件 | 作用 |
| --- | --- |
| `Sources/App.swift` | `@main`、窗口、菜单栏、快捷键 |
| `Sources/Models.swift` | 配置、动作、按键表、配置文件读写 |
| `Sources/KeyCodes.swift` | 虚拟键码、修饰键、媒体键 |
| `Sources/Events.swift` | CGEvent 合成、Fn、媒体键、权限 |
| `Sources/Descriptor.swift` | HID Report Descriptor 解析与报告解码 |
| `Sources/HID.swift` | IOHIDManager 封装（独占/共享） |
| `Sources/Engine.swift` | 映射差分、动作执行、语音状态机、状态 |
| `Sources/Views.swift` | 运行状态 / 按键映射 / 按键测试 / 设置 |
| `Sources/VoiceHUD.swift` | 语音会话悬浮窗（不抢焦点，按虚拟设备名显示） |
| `Sources/SelfTest.swift` | `--selftest` |

## 权限

首次启动会请求：

* 输入监控（读取 HID 报告）
* 辅助功能（CGEvent 合成）

在 系统设置 → 隐私与安全性 中勾选 `Google TV Remote`。授权后 App 会自动重连设备。

## 配置

与命令行共用 `~/.config/gvtv-remote/mapping.json`。
