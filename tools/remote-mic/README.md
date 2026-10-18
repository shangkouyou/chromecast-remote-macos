# RemoteMic — 遥控器麦克风 → BlackHole 2ch

独立后台桥，不需要辅助功能/输入监控权限。

## 原理

- 蓝牙日志里抓 `0x003C Characteristic Value`（ATVV 音频，160 字节/包）；
- IMA/DVI ADPCM 解码 → 16 kHz 单声道 PCM → 直流滤波/增益；
- 用 AVAudioEngine 播放到虚拟声卡 **BlackHole 2ch** 的输出端；
- 输入法选择 **BlackHole 2ch** 作为麦克风即可。

同时监听 `0x003F` 控制通道（04=开始、00=停止）来开关会话。

## 构建 / 运行

```bash
./build.sh
./RemoteMic --device "Google TV"          # 常驻
./RemoteMic --list                        # 列出音频设备
./RemoteMic --tone --device "Google TV"   # 播放 1 秒测试音
```

推荐用 `../../scripts/install-mic.sh` 安装成 LaunchAgent。

## 虚拟声卡

`BlackHole 2ch` 是默认使用 BlackHole 2ch（`../scripts/install-blackhole.sh` 安装）。如果运行 `create-gtv-device.sh`，会得到独立的 “Google TV 2ch”。

## 已知限制

- 音频来自系统蓝牙日志，任何订阅 ATVV 的 CoreBluetooth 客户端都会让日志消失，
  语音键随之失灵；恢复方法：关闭再打开 Mac 蓝牙。
- 遥控器语音键的按下沿来自日志（04 03 02 xx），目前按“按住说话”使用。
