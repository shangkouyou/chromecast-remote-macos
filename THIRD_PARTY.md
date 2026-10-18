# 第三方组件与致谢

本项目自己的代码以 MIT 发布。以下组件/资料按各自许可证使用；仓库**不包含**任何
GPL 二进制，虚拟声卡由脚本在用户本机安装。

## 直接使用 / 可选安装

| 组件 | 作者 | 许可证 | 用途 |
| --- | --- | --- | --- |
| [BlackHole](https://github.com/ExistentialAudio/BlackHole) | Existential Audio Inc. | GPL-3.0 | 可选虚拟声卡（`scripts/install-blackhole.sh` 安装；`create-gtv-device.sh` 仅在本机改名，不随仓库分发） |

## 协议与按键表参考（未复制代码）

| 项目 | 许可证 | 参考内容 |
| --- | --- | --- |
| [ZSTDJan/windows-remote-mic-app](https://github.com/ZSTDJan/windows-remote-mic-app) | GPL-3.0 | Chromecast 遥控器物理按键码（`01/03/…/11`）、ATVV 控制序列（`04 03 02 xx` / `08` / `00 02`）、音频特征 `0x003C` 的事实描述；本项目的 Swift/Python 实现为独立编写 |
| [LiveNL/ack05d](https://github.com/LiveNL/ack05d) | MIT | macOS userspace BLE 遥控器驱动的架构参考（未使用其代码） |
| [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) | Unlicense/部分 GPL | 调研阶段参考其改键思路；未使用 |

## 标准与文档

- HID Usage Tables（Consumer Page `0x0C`、Keyboard Page `0x07`）
- IMA/DVI ADPCM 算法（公开标准）
- Apple Developer：IOHIDManager、CoreGraphics Events、SwiftUI、AVFoundation、CoreAudio

## 致谢

感谢上述项目的作者与维护者把协议细节、驱动和工具公开出来；感谢参与实测的遥控器使用者。
若你认为某处署名不准确，请开 issue，我们会尽快修正。
