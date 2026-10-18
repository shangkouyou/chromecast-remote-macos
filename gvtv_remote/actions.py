"""动作解析与执行。配置里既可以写短字符串，也可以写结构化对象。"""
from __future__ import annotations

import shlex
import subprocess
from typing import Any, Callable

from .events import EventSink, MEDIA_KEYS, MODIFIERS, KEYCODES, parse_chord


class ActionError(ValueError):
    pass


def parse_action(value: Any) -> dict:
    """把配置值统一成 ``{"type": ...}`` 形式。

    支持的短写法::

        key:cmd+space          # 组合键
        key:f5,hold=60         # 可选按住毫秒数
        media:play_pause
        app:Safari
        url:https://example.com
        shell:say hello
        text:你好
        voice
        none
    """
    if isinstance(value, dict):
        action = dict(value)
        kind = action.get("type") or action.get("action")
        if not kind:
            raise ActionError(f"动作缺少 type: {value!r}")
        action["type"] = kind
        return action
    if not isinstance(value, str):
        raise ActionError(f"无法识别的动作: {value!r}")

    text = value.strip()
    if text in ("none", "null", ""):
        return {"type": "none"}
    if text == "voice":
        return {"type": "voice"}

    if ":" not in text:
        raise ActionError(f"动作需要形如 type:value，得到 {value!r}")
    kind, _, rest = text.partition(":")
    kind = kind.strip().lower()
    rest = rest.strip()

    if kind == "key":
        hold_ms = 12
        if "," in rest:
            rest, _, options = rest.partition(",")
            for option in options.split(","):
                option = option.strip()
                if option.startswith("hold="):
                    hold_ms = int(option.split("=", 1)[1])
        chord = rest.strip()
        try:  # 提前校验，配置写错时立刻报错
            parse_chord(chord)
        except ValueError as exc:
            raise ActionError(str(exc)) from exc
        return {"type": "key", "chord": chord, "hold_ms": hold_ms}
    if kind == "media":
        if rest not in MEDIA_KEYS:
            raise ActionError(f"未知媒体键: {rest!r}")
        return {"type": "media", "name": rest}
    if kind in ("app", "url", "shell", "text"):
        if not rest:
            raise ActionError(f"{kind} 动作缺少参数")
        return {"type": kind, "value": rest}
    raise ActionError(f"未知动作类型: {kind!r}")


def describe_action(action: dict) -> str:
    kind = action.get("type")
    if kind == "key":
        chord = action.get("chord")
        if chord is None and action.get("key"):
            mods = action.get("modifiers") or []
            chord = "+".join([*mods, action["key"]])
        return f"键 {chord}"
    if kind == "media":
        return f"媒体键 {action.get('name')}"
    if kind == "app":
        return f"打开 App {action.get('value') or action.get('name')}"
    if kind == "url":
        return f"打开网址 {action.get('value') or action.get('url')}"
    if kind == "shell":
        return f"执行 shell: {action.get('value') or action.get('cmd')}"
    if kind == "text":
        return f"输入文本"
    if kind == "voice":
        return "语音键（Fn / 云键）"
    return "无动作"


class ActionRunner:
    def __init__(
        self,
        sink: EventSink,
        log: Callable[[str], None] | None = None,
        dry_run: bool = False,
    ) -> None:
        self.sink = sink
        self.log = log or (lambda _msg: None)
        self.dry_run = dry_run

    def run(self, action: dict) -> None:
        kind = action["type"]
        if kind == "none":
            return
        if kind == "key":
            self._run_key(action)
        elif kind == "media":
            self._guard(lambda: self.sink.media(action["name"]))
        elif kind in ("app", "url"):
            target = action.get("value") or action.get("name") or action.get("url")
            if not target:
                raise ActionError(f"{kind} 动作缺少目标")
            cmd = ["open", "-a", target] if kind == "app" else ["open", target]
            if action.get("args"):
                cmd.extend([str(a) for a in action["args"]])
            self._spawn(cmd)
        elif kind == "shell":
            command = action.get("value") or action.get("cmd")
            if not command:
                raise ActionError("shell 动作缺少命令")
            self._spawn(["/bin/bash", "-lc", command])
        elif kind == "text":
            text = action.get("value") or action.get("text") or ""
            if not self.dry_run:
                self.sink.type_text(text)
            self.log(f"输入文本: {text!r}")
        elif kind == "voice":
            raise ActionError("voice 动作由 Mapper 处理")
        else:
            raise ActionError(f"未知动作: {kind!r}")

    # ------------------------------------------------------------------ key
    def _run_key(self, action: dict) -> None:
        hold_ms = int(action.get("hold_ms", 12))
        if action.get("chord"):
            keycode, mods = parse_chord(action["chord"])
            if not self.dry_run:
                self.sink.tap_key(keycode, mods, hold_ms)
            self.log(f"按键 {action['chord']}")
            return

        name = action.get("key")
        if not name:
            raise ActionError("key 动作缺少 key")
        name = str(name).lower()
        if name not in KEYCODES:
            raise ActionError(f"未知按键: {name!r}")
        mods = tuple(
            MODIFIERS[m.lower()]
            for m in (action.get("modifiers") or [])
            if m.lower() in MODIFIERS
        )
        if not self.dry_run:
            self.sink.tap_key(KEYCODES[name], mods, hold_ms)
        self.log(f"按键 {name}")

    def _guard(self, fn: Callable[[], None]) -> None:
        try:
            fn()
        except Exception as exc:  # pragma: no cover - 运行期日志
            self.log(f"执行失败: {exc}")

    def _spawn(self, cmd: list[str]) -> None:
        printable = " ".join(shlex.quote(part) for part in cmd)
        self.log(f"运行 {printable}")
        if self.dry_run:
            return
        try:
            subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            self.log(f"启动失败: {exc}")
