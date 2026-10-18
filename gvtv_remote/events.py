"""把动作变成 macOS 系统事件：键盘、媒体键、Fn（Globe）键、文本输入。"""
from __future__ import annotations

import ctypes
import subprocess
import time
from ctypes import POINTER, c_bool, c_char_p, c_uint16, c_uint32, c_uint64, c_void_p

from . import cf

CG = ctypes.CDLL(
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
)
AS = ctypes.CDLL(
    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
)

kCGHIDEventTap = 0
kCGEventSourceStateHIDSystemState = 1
kCGEventFlagsChanged = 12
kNXSystemDefined = 14

kCGEventFlagMaskShift = 0x20000
kCGEventFlagMaskControl = 0x40000
kCGEventFlagMaskAlternate = 0x80000
kCGEventFlagMaskCommand = 0x100000
kCGEventFlagMaskSecondaryFn = 0x800000

CG.CGEventCreateKeyboardEvent.argtypes = [c_void_p, c_uint16, c_bool]
CG.CGEventCreateKeyboardEvent.restype = c_void_p
CG.CGEventCreate.argtypes = [c_void_p]
CG.CGEventCreate.restype = c_void_p
CG.CGEventSetType.argtypes = [c_void_p, c_uint32]
CG.CGEventSetFlags.argtypes = [c_void_p, c_uint64]
CG.CGEventSetIntegerValueField.argtypes = [c_void_p, c_uint32, ctypes.c_int64]
CG.CGEventPost.argtypes = [c_uint32, c_void_p]
CG.CGEventKeyboardSetUnicodeString.argtypes = [c_void_p, c_uint32, POINTER(c_uint16)]
CG.CGEventSourceCreate.argtypes = [c_uint32]
CG.CGEventSourceCreate.restype = c_void_p

AS.AXIsProcessTrusted.restype = c_bool

try:
    CG.CGPreflightPostEventAccess.restype = c_bool
except AttributeError:  # pragma: no cover
    pass

try:
    CG.CGPreflightListenEventAccess.restype = c_bool
except AttributeError:  # pragma: no cover
    pass

# macOS 虚拟键码（kVK_*）
KEYCODES: dict[str, int] = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
    "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24,
    "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29, "rightbracket": 30,
    "o": 31, "u": 32, "leftbracket": 33, "i": 34, "p": 35, "return": 36,
    "enter": 36, "l": 37, "j": 38, "quote": 39, "k": 40, "semicolon": 41,
    "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47,
    "tab": 48, "space": 49, "grave": 50, "backspace": 51, "delete": 51,
    "escape": 53, "esc": 53, "rightcommand": 54, "command": 55, "cmd": 55,
    "shift": 56, "capslock": 57, "option": 58, "alt": 58, "control": 59,
    "ctrl": 59, "rightshift": 60, "rightoption": 61, "rightcontrol": 62,
    "fn": 63, "globe": 63, "f17": 64, "keypaddecimal": 65, "keypadmultiply": 67,
    "keypadplus": 69, "keypadclear": 71, "volumeup": 72, "volumedown": 73,
    "mute": 74, "keypaddivide": 75, "keypadenter": 76, "keypadminus": 78,
    "f18": 79, "f19": 80, "keypadequals": 81, "keypad0": 82, "keypad1": 83,
    "keypad2": 84, "keypad3": 85, "keypad4": 86, "keypad5": 87, "keypad6": 88,
    "keypad7": 89, "f20": 90, "keypad8": 91, "keypad9": 92, "f5": 96,
    "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101, "f11": 103,
    "f13": 105, "f16": 106, "f14": 107, "f10": 109, "f12": 111, "f15": 113,
    "help": 114, "home": 115, "pageup": 116, "forwarddelete": 117, "f4": 118,
    "end": 119, "f2": 120, "pagedown": 121, "f1": 122, "left": 123,
    "right": 124, "down": 125, "up": 126,
}

MODIFIERS: dict[str, int] = {
    "shift": kCGEventFlagMaskShift,
    "ctrl": kCGEventFlagMaskControl,
    "control": kCGEventFlagMaskControl,
    "alt": kCGEventFlagMaskAlternate,
    "opt": kCGEventFlagMaskAlternate,
    "option": kCGEventFlagMaskAlternate,
    "cmd": kCGEventFlagMaskCommand,
    "command": kCGEventFlagMaskCommand,
    "fn": kCGEventFlagMaskSecondaryFn,
}

# NX_KEYTYPE_*
MEDIA_KEYS: dict[str, int] = {
    "volume_up": 0,
    "volume_down": 1,
    "brightness_up": 2,
    "brightness_down": 3,
    "power": 6,
    "mute": 7,
    "eject": 14,
    "play_pause": 16,
    "next": 17,
    "previous": 18,
    "fast_forward": 19,
    "rewind": 20,
}


def parse_chord(spec: str) -> tuple[int, tuple[int, ...]]:
    """解析 ``cmd+shift+4`` / ``f5`` / ``media:play_pause``。"""
    parts = [p.strip().lower() for p in spec.split("+") if p.strip()]
    if not parts:
        raise ValueError(f"无法解析按键: {spec!r}")
    key = parts[-1]
    mods: list[int] = []
    for part in parts[:-1]:
        if part not in MODIFIERS:
            raise ValueError(f"未知修饰键: {part!r}")
        mods.append(MODIFIERS[part])
    if key not in KEYCODES:
        raise ValueError(f"未知按键: {key!r}")
    return KEYCODES[key], tuple(mods)


def ax_trusted() -> bool:
    try:
        return bool(AS.AXIsProcessTrusted())
    except Exception:
        return False


def post_event_access() -> bool:
    try:
        return bool(CG.CGPreflightPostEventAccess())
    except Exception:
        return False


def listen_event_access() -> bool:
    """输入监控权限（CGEventTap / 读取 HID 输入用）。"""
    try:
        return bool(CG.CGPreflightListenEventAccess())
    except Exception:
        return False


def open_privacy_pane(anchor: str = "Privacy_Accessibility") -> None:
    url = f"x-apple.systempreferences:com.apple.preference.security?{anchor}"
    subprocess.run(["open", url], check=False)


class EventSink:
    """所有输出事件都从这里走，便于 dry-run 和测试替换。"""

    def __init__(self, dry_run: bool = False) -> None:
        self.dry_run = dry_run
        self.source = CG.CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
        self.last_error: str | None = None

    # ---------------------------------------------------------------- helpers
    def _post_key(self, keycode: int, down: bool, flags: int = 0) -> None:
        event = CG.CGEventCreateKeyboardEvent(self.source, keycode, bool(down))
        if not event:
            self.last_error = "CGEventCreateKeyboardEvent failed"
            return
        if flags:
            CG.CGEventSetFlags(event, flags)
        if not self.dry_run:
            CG.CGEventPost(kCGHIDEventTap, event)
        cf.release(event)

    # ------------------------------------------------------------------ keys
    def key_down(self, keycode: int, flags: int = 0) -> None:
        self._post_key(keycode, True, flags)

    def key_up(self, keycode: int, flags: int = 0) -> None:
        self._post_key(keycode, False, flags)

    def tap_key(self, keycode: int, modifiers: tuple[int, ...] = (), hold_ms: int = 12) -> None:
        """按下组合键再松开。修饰键会同时出现在事件 flags 里，兼容性最好。"""
        flags = 0
        for modifier in modifiers:
            flags |= modifier
        held: list[int] = []
        for modifier in modifiers:
            vk = _MODIFIER_KEYCODE.get(modifier)
            if vk is None:
                continue
            self._post_key(vk, True, flags)
            held.append(vk)
        self._post_key(keycode, True, flags)
        time.sleep(max(1, hold_ms) / 1000.0)
        self._post_key(keycode, False, flags)
        for vk in reversed(held):
            self._post_key(vk, False, 0)
        time.sleep(0.01)

    def press_name(self, spec: str, hold_ms: int = 12) -> None:
        keycode, mods = parse_chord(spec)
        self.tap_key(keycode, mods, hold_ms)

    # ----------------------------------------------------------------- media
    def media(self, name: str) -> None:
        if name not in MEDIA_KEYS:
            raise ValueError(f"未知媒体键: {name!r}")
        key = MEDIA_KEYS[name]
        for state in (0x0A, 0x0B):  # NX_KEYDOWN / NX_KEYUP
            event = CG.CGEventCreate(None)
            if not event:
                self.last_error = "CGEventCreate failed"
                return
            CG.CGEventSetType(event, kNXSystemDefined)
            CG.CGEventSetIntegerValueField(event, 42, (key << 16) | (state << 8))
            if not self.dry_run:
                CG.CGEventPost(kCGHIDEventTap, event)
            cf.release(event)
            time.sleep(0.02)

    # -------------------------------------------------------------------- fn
    def fn_down(self) -> None:
        """发送 Fn(Globe) 按下。用 flagsChanged 事件，最接近真实按键。"""
        event = CG.CGEventCreateKeyboardEvent(self.source, KEYCODES["fn"], True)
        if not event:
            self.last_error = "CGEventCreateKeyboardEvent failed"
            return
        CG.CGEventSetType(event, kCGEventFlagsChanged)
        CG.CGEventSetFlags(event, kCGEventFlagMaskSecondaryFn)
        if not self.dry_run:
            CG.CGEventPost(kCGHIDEventTap, event)
        cf.release(event)
        time.sleep(0.01)

    def fn_up(self) -> None:
        event = CG.CGEventCreateKeyboardEvent(self.source, KEYCODES["fn"], False)
        if not event:
            self.last_error = "CGEventCreateKeyboardEvent failed"
            return
        CG.CGEventSetType(event, kCGEventFlagsChanged)
        CG.CGEventSetFlags(event, 0)
        if not self.dry_run:
            CG.CGEventPost(kCGHIDEventTap, event)
        cf.release(event)
        time.sleep(0.01)

    def fn_tap(self) -> None:
        self.fn_down()
        time.sleep(0.04)
        self.fn_up()

    # ------------------------------------------------------------------ text
    def type_text(self, text: str) -> None:
        encoded = text.encode("utf-16-le")
        units = [int.from_bytes(encoded[i:i + 2], "little") for i in range(0, len(encoded), 2)]
        for start in range(0, len(units), 20):
            chunk = units[start:start + 20]
            buffer = (c_uint16 * len(chunk))(*chunk)
            event = CG.CGEventCreateKeyboardEvent(self.source, 0, True)
            if not event:
                self.last_error = "CGEventCreateKeyboardEvent failed"
                return
            CG.CGEventKeyboardSetUnicodeString(event, len(chunk), buffer)
            if not self.dry_run:
                CG.CGEventPost(kCGHIDEventTap, event)
            cf.release(event)
            time.sleep(0.005)


_MODIFIER_KEYCODE = {
    kCGEventFlagMaskShift: KEYCODES["shift"],
    kCGEventFlagMaskControl: KEYCODES["control"],
    kCGEventFlagMaskAlternate: KEYCODES["option"],
    kCGEventFlagMaskCommand: KEYCODES["command"],
    kCGEventFlagMaskSecondaryFn: KEYCODES["fn"],
}
