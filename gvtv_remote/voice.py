"""云键 / 语音键：把遥控器的话筒键变成 Fn(Globe) 键，驱动 macOS 听写。

三种工作方式：

* ``hold``   按住说话：按下发 Fn down，松开发 Fn up（对应“按住 Fn 听写”）。
* ``toggle`` 按一下开始，再按一下结束（对应“按一下 Fn 听写”）。
* ``double`` 每次按下连发两次 Fn，对应系统里“按两次 Fn”的听写快捷键。

macOS 的听写在静音一段时间后会自动结束，因此 hold 模式天然满足
“按下说话 → 说完自动断开 → 录音结束”。
"""
from __future__ import annotations

import queue
import shutil
import subprocess
import threading
import time
from typing import Callable

from .actions import ActionRunner, parse_action


class VoiceController:
    def __init__(
        self,
        cfg: dict,
        sink,
        runner: ActionRunner,
        log: Callable[[str], None],
    ) -> None:
        self.cfg = cfg or {}
        self.sink = sink
        self.runner = runner
        self.log = log

        self.mode = str(self.cfg.get("mode", "hold")).lower()
        if self.mode not in ("hold", "toggle", "double"):
            raise ValueError(f"voice.mode 必须是 hold/toggle/double: {self.mode!r}")
        self.max_session_s = float(self.cfg.get("max_session_s", 60))
        self.release_delay_ms = int(self.cfg.get("release_delay_ms", 150))
        self.end_actions = [parse_action(a) for a in self.cfg.get("end_actions", [])]
        self.disconnect = bool(self.cfg.get("disconnect_bluetooth", False))
        self.address = str(self.cfg.get("bluetooth_address", "") or "")

        self._queue: queue.Queue = queue.Queue()
        self._worker = threading.Thread(target=self._loop, name="voice", daemon=True)
        self._worker.start()

        self._active = False
        self._token = 0
        self._timer: threading.Timer | None = None

    # ------------------------------------------------------------------ api
    def press(self) -> None:
        self._queue.put(("press",))

    def release(self) -> None:
        self._queue.put(("release",))

    def close(self) -> None:
        self._queue.put(("close",))
        self._worker.join(timeout=2.0)

    # --------------------------------------------------------------- worker
    def _loop(self) -> None:
        while True:
            try:
                event, *rest = self._queue.get(timeout=0.5)
            except queue.Empty:
                continue
            if event == "close":
                if self._active:
                    self._stop("退出")
                return
            if event == "press":
                self._on_press()
            elif event == "release":
                self._on_release()
            elif event == "timeout" and rest and rest[0] == self._token:
                if self._active:
                    self.log("语音超时，自动结束")
                    self._stop("超时")

    def _on_press(self) -> None:
        if self.mode == "hold":
            if not self._active:
                self._start()
            return
        if self.mode == "toggle":
            if self._active:
                self._stop("再次按下")
            else:
                self._start()
            return
        # double
        if self._active:
            self._stop("再次按下")
        else:
            self._start()

    def _on_release(self) -> None:
        if self.mode == "hold" and self._active:
            self._stop("松开")

    # -------------------------------------------------------------- helpers
    def _start(self) -> None:
        self._active = True
        self._token += 1
        token = self._token
        if self.mode == "hold":
            self.sink.fn_down()
            self.log("语音键按下：Fn↓（开始听写）")
        elif self.mode == "toggle":
            self.sink.fn_tap()
            self.log("语音键：Fn 轻按（开始/停止听写）")
        else:
            self._double_tap()
            self.log("语音键：Fn ×2（开始/停止听写）")

        self._cancel_timer()
        self._timer = threading.Timer(self.max_session_s, self._timeout, args=(token,))
        self._timer.daemon = True
        self._timer.start()

    def _stop(self, reason: str) -> None:
        self._active = False
        self._cancel_timer()
        if self.mode == "hold":
            self.sink.fn_up()
            self.log(f"语音键结束（{reason}）：Fn↑（结束听写）")
        elif self.mode == "toggle":
            self.sink.fn_tap()
            self.log(f"语音键结束（{reason}）：Fn 轻按")
        else:
            self._double_tap()
            self.log(f"语音键结束（{reason}）：Fn ×2")

        if self.release_delay_ms > 0:
            time.sleep(self.release_delay_ms / 1000.0)

        for action in self.end_actions:
            try:
                self.runner.run(action)
            except Exception as exc:  # pragma: no cover
                self.log(f"结束动作失败: {exc}")

        if self.disconnect:
            self._disconnect_bluetooth()

    def _double_tap(self) -> None:
        self.sink.fn_tap()
        time.sleep(0.08)
        self.sink.fn_tap()

    def _timeout(self, token: int) -> None:
        self._queue.put(("timeout", token))

    def _cancel_timer(self) -> None:
        if self._timer is not None:
            self._timer.cancel()
            self._timer = None

    def _disconnect_bluetooth(self) -> None:
        if not self.address:
            self.log("未配置 voice.bluetooth_address，跳过断开蓝牙")
            return
        blueutil = shutil.which("blueutil")
        if not blueutil:
            self.log("未安装 blueutil，跳过断开蓝牙（brew install blueutil）")
            return
        cmd = [blueutil, "--disconnect", self.address]
        self.log(f"断开蓝牙: {' '.join(cmd)}")
        try:
            subprocess.run(cmd, check=False, capture_output=True, timeout=5)
        except Exception as exc:  # pragma: no cover
            self.log(f"断开蓝牙失败: {exc}")
