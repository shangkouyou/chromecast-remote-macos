"""按键映射引擎：把 HID 报告差分成按下/松开，再分发动作。"""
from __future__ import annotations

from typing import Callable

from .actions import ActionRunner, describe_action, parse_action
from .descriptor import decode, usage_id, usage_name

ALIASES: dict[str, str] = {
    "assistant": "c:0x221",
    "voice": "c:0x221",
    "mic": "c:0x221",
    "search": "c:0x221",
    "home": "c:0x223",
    "back": "c:0x224",
    "dpad_up": "c:0x42",
    "dpad_down": "c:0x43",
    "dpad_left": "c:0x44",
    "dpad_right": "c:0x45",
    "ok": "c:0x41",
    "select": "c:0x41",
    "enter": "c:0x41",
    "mute": "c:0xE2",
    "volume_up": "c:0xE9",
    "volume_down": "c:0xEA",
    "play_pause": "c:0xCD",
    "menu": "c:0x40",
    "power": "c:0x30",
}


def canonical_id(value: str) -> str:
    text = str(value).strip().lower()
    if text in ALIASES:
        return ALIASES[text]
    if text.startswith("c:") or text.startswith("k:") or text.startswith("p"):
        prefix, _, number = text.partition(":")
        if number:
            try:
                return f"{prefix}:0x{int(number, 0):02X}"
            except ValueError:
                pass
    raise ValueError(f"无法识别的按键 ID: {value!r}")


class Mapper:
    def __init__(
        self,
        cfg: dict,
        fields: dict,
        runner: ActionRunner,
        voice,
        log: Callable[[str], None],
    ) -> None:
        self.cfg = cfg
        self.fields = fields
        self.runner = runner
        self.voice = voice
        self.log = log

        self.bindings: dict[str, dict] = {}
        for key, value in (cfg.get("mapping") or {}).items():
            try:
                binding_id = canonical_id(key)
                self.bindings[binding_id] = parse_action(value)
            except Exception as exc:
                self.log(f"忽略无效映射 {key!r}: {exc}")

        voice_cfg = cfg.get("voice") or {}
        self.voice_button = canonical_id(voice_cfg.get("button", "assistant"))
        self.voice_action = {"type": "voice"}

        self._pressed: set[str] = set()
        self._unknown_reported: set[str] = set()
        self.learn_callback: Callable[[str, str], None] | None = None
        self.learning = False
        self.stats = {"reports": 0, "presses": 0}

    # ------------------------------------------------------------------ feed
    def handle_report(self, report_id: int, payload: bytes) -> None:
        self.stats["reports"] += 1
        usages = decode(self.fields, report_id, payload)
        current = {usage_id(page, usage) for page, usage in usages}
        pressed = current - self._pressed
        released = self._pressed - current
        self._pressed = current

        for binding_id in sorted(pressed):
            self._on_press(binding_id)
        for binding_id in sorted(released):
            self._on_release(binding_id)

    # --------------------------------------------------------------- dispatch
    def _on_press(self, binding_id: str) -> None:
        self.stats["presses"] += 1
        page, usage = _split_id(binding_id)
        label = usage_name(page, usage)
        if self.learning:
            if self.learn_callback:
                self.learn_callback(binding_id, label)
            return

        action = self.bindings.get(binding_id)
        if binding_id == self.voice_button:
            action = self.voice_action

        if action is None:
            if binding_id not in self._unknown_reported:
                self._unknown_reported.add(binding_id)
                self.log(f"未绑定按键: {binding_id} ({label})")
            return

        if action["type"] == "voice":
            self.voice.press()
            self.log(f"语音键按下 ({binding_id})")
            return

        if action.get("on") == "release":
            return

        try:
            self.runner.run(action)
            self.log(f"{label} -> {describe_action(action)}")
        except Exception as exc:
            self.log(f"动作执行失败 {binding_id}: {exc}")

    def _on_release(self, binding_id: str) -> None:
        action = self.bindings.get(binding_id)
        if binding_id == self.voice_button:
            self.voice.release()
            self.log("语音键松开")
            return
        if action is None:
            return
        if action.get("on") == "release":
            try:
                self.runner.run(action)
            except Exception as exc:
                self.log(f"动作执行失败 {binding_id}: {exc}")

    # ---------------------------------------------------------------- status
    def describe(self) -> str:
        lines = []
        for binding_id, action in sorted(self.bindings.items()):
            page, usage = _split_id(binding_id)
            lines.append(
                f"  {binding_id:<9} {usage_name(page, usage):<28} -> {describe_action(action)}"
            )
        return "\n".join(lines)


def _split_id(binding_id: str) -> tuple[int, int]:
    prefix, _, number = binding_id.partition(":")
    page = {"c": 0x0C, "k": 0x07}.get(prefix, int(prefix[1:], 16) if prefix.startswith("p") else 0x0C)
    return page, int(number, 0)
