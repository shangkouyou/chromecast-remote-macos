# 通用使用手册

本手册面向“换一台 Mac / 换一个遥控器”的场景。项目不是为某一台机器写死的：
设备通过 VID/PID 或产品名匹配，按键由 HID Report Descriptor 动态解析。

---

## 1. 适用范围（先看这一节）

| 能用 | 说明 |
| --- | --- |
| **macOS 13+**（Intel / Apple Silicon） | App 与命令行都依赖 IOKit / CoreGraphics / AVFoundation |
| **任何 BLE / USB HID 遥控器** | 只要 macOS 在“系统信息 → 蓝牙”或 `hidutil list` 里把它识别为键盘 / Consumer Control，就能映射 |
| 已实测 | Google Chromecast Voice Remote（`18d1:9450`，BLE，17 键） |
| 未逐一实测 | 小米蓝牙语音遥控器、Apple TV Remote、各类 Android TV / 投影仪遥控器——原理相同，用 `learn` 学键即可 |

| 不能用 | 原因 |
| --- | --- |
| **iPhone / iPad** | iOS 不允许第三方 App 做系统级按键注入；遥控器能配对成键盘，但本软件无法在 iOS 上运行 |
| Windows / Linux | 本项目使用 macOS 私有/系统 API；Windows 可参考上游 `windows-remote-mic-app`，Linux 可用 `keyd`/`hid-remapper` |
| 红外-only 遥控器 | 没有蓝牙 HID 连接，系统收不到按键 |

> 本项目与 Google 无关联；Google TV、Chromecast 是 Google LLC 的商标。

---

## 2. 前置条件

- macOS 13+；构建 App 需要 Xcode Command Line Tools：`xcode-select --install`
- Python 3.9+（系统自带 `/usr/bin/python3` 即可，用于命令行/测试）
- 可选：Homebrew（安装 BlackHole 用；没有也能用脚本下载官方 pkg）

## 3. 配对与识别设备

1. 系统设置 → 蓝牙，把遥控器配对并连接。
2. 查看它是不是 HID 设备：

```bash
./bin/gvtv-remote list          # 按配置匹配
hidutil list | grep -i remote  # 系统视角
```

记下 **VendorID / ProductID**（例如 `18d1:9450`）和产品名。

3. 修改配置 `~/.config/gvtv-remote/mapping.json`：

```json
"device": {
  "vendor_id": 6353,
  "product_id": 37968,
  "product": "Chromecast Remote",
  "seize": true
}
```

- 知道 VID/PID：填这两个即可（十进制，`0x18d1 = 6353`）。
- 不知道 VID/PID：把 `vendor_id` / `product_id` 设为 `0`，只填 `product`
  （必须和系统里的产品名完全一致）。
- 同一台 Mac 接多个遥控器：切换配置里的 `device`，重启 App/服务即可。

4. 先确认能收到按键：

```bash
./bin/gvtv-remote sniff --seconds 30
```

按遥控器，终端应打印 `report ... -> c:0x...`。没有输出就检查权限（下一节）。

---

## 4. 权限（macOS 必做）

| 权限 | 用途 | 给谁 |
| --- | --- | --- |
| **输入监控** | 读取遥控器 HID 报告 | App 或你的终端 |
| **辅助功能** | 合成键盘 / 媒体 / Fn 事件 | App 或你的终端 |

App 方式：系统设置 → 隐私与安全性 → 对应页面勾选 **Google TV Remote**。
命令行方式：勾选你用的终端（Terminal / iTerm）。

> App 是 ad-hoc 签名，**重新构建/安装后系统可能要求重新授权一次**；把 App 固定在
> `/Applications` 使用。授权后若仍无反应，重启一次 App。

---

## 5. 安装与启动

### 4.1 原生 App（推荐）

```bash
./scripts/install-app.sh          # 构建并复制到 /Applications
./scripts/install-app-login.sh    # 可选：登录自动打开
```

### 4.2 命令行

```bash
./bin/gvtv-remote doctor          # 体检
./bin/gvtv-remote run             # 前台运行，Ctrl-C 退出
./scripts/install.sh              # 可选：LaunchAgent 常驻
```

> App 与命令行不要同时运行，会争抢“独占”设备。

---

## 6. 按键映射

- App：左侧按键列表 → 右侧选择动作类型（键盘 / 媒体 / App / 网址 / Shell / 文本 / 语音）。
- 命令行学习：

```bash
./bin/gvtv-remote learn                    # 按一下，打印按键 ID
./bin/gvtv-remote learn --bind 'key:cmd+space'
```

- 动作写法：`key:cmd+shift+4`、`media:volume_up`、`app:Safari`、`url:https://…`、
  `shell:…`、`text:…`、`voice`、`none`。
- 未知按键会显示 `usage 0xXX`，用 `learn` 绑定即可；App 的「+」也能添加自定义 usage。

---

## 7. 语音键（Fn / 云键）

语音键映射为 `voice` 动作：按下发 Fn（Globe），松开释放；系统听写或第三方语音输入法
（如 Chatterfly）收到 Fn 后开始/结束录音。

- **按住说话**：`voice.mode = "hold"`（默认，最稳，尤其配合遥控器麦克风）。
- **按一次开/再按一次关**：`voice.mode = "latch"`；需要能持续收到按下沿。
- **按两次 Fn**：`voice.mode = "double"`，适配系统“按两次 Fn”的快捷键。

macOS 设置：系统设置 → 键盘 → 听写 / “按下 🌐 键” → 开始听写；
或在第三方输入法里把语音快捷键设为 Fn。

> Chromecast 遥控器的语音键**不在 HID 报告里**，而是 BLE GATT `0x003F`
> （`04 03 02 xx` / `08` / `00 02`）。本项目通过系统蓝牙日志旁路识别。
> 一旦有其它程序用 CoreBluetooth 订阅了该特征，日志消失、语音键会“失灵”：
> **把 Mac 蓝牙关掉再打开**即可恢复。不要同时跑其它 GATT 调试工具。

---

## 8. 遥控器麦克风（仅部分遥控器）

Chromecast 遥控器的麦克风走 BLE ATVV（GATT `0x003C`，IMA ADPCM，16 kHz），
macOS 不会把它暴露成音频输入。需要三步：

### 7.1 安装虚拟声卡

```bash
./scripts/install-blackhole.sh     # BlackHole 2ch（GPL-3.0，Existential Audio）
# 可选：复制成独立名字 "Google TV 2ch"
./scripts/create-gtv-device.sh
```

### 7.2 启动音频桥

```bash
./scripts/install-mic.sh
# 如果创建了独立声卡：
GVTV_AUDIO_DEVICE="Google TV 2ch" ./scripts/install-mic.sh
```

### 7.3 在输入法里选麦克风

把语音输入法的麦克风选为 **BlackHole 2ch** 或 **Google TV 2ch**，按住遥控器语音键
说话即可。音频桥日志：`~/Library/Logs/RemoteMic.log`。

> 音频桥只针对 ATVV 遥控器（Chromecast / 部分 Android TV 遥控器）。小米等其它型号的
> 麦克风链路不同，需单独适配。没有麦克风需求时完全可以不装 BlackHole。

---

## 9. 常见问题

| 现象 | 处理 |
| --- | --- |
| 终端/日志没有按键 | 输入监控权限；`sniff` 确认；换 USB 口/重连 |
| 有按键但系统没动作 | 辅助功能权限；动作是否 `none`；是否与其它改键软件冲突 |
| 语音键突然失灵 | 蓝牙关/开（清 GATT 订阅会话）；确认没有其它 GATT 客户端 |
| 音量/静音无效 | 先 `test-media volume_up`；仍无效改用 `shell:osascript …` |
| 重新构建 App 后权限失效 | ad-hoc 签名导致，重新勾选一次；固定放在 /Applications |
| 多个遥控器 | 改配置 `device` 后重启；一次只接管一个 |
| 与 UURemote/小米遥控器冲突 | 两条虚拟声卡相互独立；不要同时占用同一个虚拟设备 |

日志：

- App：`~/Library/Logs/GoogleTVRemote.log`
- 麦克风桥：`~/Library/Logs/RemoteMic.log`
- 命令行：终端输出

---

## 10. 卸载

```bash
./scripts/uninstall.sh                        # 命令行 LaunchAgent
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.gvtv.app.plist 2>/dev/null
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.gvtv.remote-mic.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.gvtv.app.plist ~/Library/LaunchAgents/com.gvtv.remote-mic.plist
rm -rf "/Applications/Google TV Remote.app"
# 可选：删除虚拟声卡（需要管理员）
sudo rm -rf /Library/Audio/Plug-Ins/HAL/GoogleTV2ch.driver && sudo killall coreaudiod
```

配置在 `~/.config/gvtv-remote/`，可保留。
