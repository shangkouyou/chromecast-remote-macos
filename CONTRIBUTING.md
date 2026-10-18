# Contributing

- 新遥控器适配：请附上 `./bin/gvtv-remote list` 的输出（VID/PID、产品名、描述符 hex）
  以及 `sniff` 的按键报告，注明哪些键有效、哪些无效。
- 语音键：注明遥控器型号、是否走 HID `0x221`、是否在蓝牙日志里出现 `0x003F`
  （`log show --last 5m --predicate 'subsystem == "com.apple.bluetooth"' | grep 0x003F`）。
- 提交前跑：

```bash
./scripts/verify.sh
```

- 不要提交个人设备地址、日志、构建产物（`.gitignore` 已覆盖）。
