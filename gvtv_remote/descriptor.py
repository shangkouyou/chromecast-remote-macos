"""HID Report Descriptor 解析与输入报告解码。

只关心“数组型输入字段”（Data,Array），因为蓝牙遥控器的按键几乎都以
数组报告上报：报告里放的是数组下标/用法号，而不是每个键一个 bit。

这个模块不依赖 IOKit，可以直接用十六进制描述符做单元测试。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterator

# HID Usage Tables 里常用的一小部分名字，够把遥控器按键打印得可读即可。
CONSUMER_NAMES: dict[int, str] = {
    0x01: "Consumer Control",
    0x30: "Power",
    0x32: "Sleep",
    0x40: "Menu",
    0x41: "Menu Pick (OK)",
    0x42: "Menu Up",
    0x43: "Menu Down",
    0x44: "Menu Left",
    0x45: "Menu Right",
    0x46: "Menu Escape",
    0x60: "Data On Screen",
    0x65: "Snapshot",
    0x6F: "Media Select Computer",
    0x70: "Media Select TV",
    0x71: "Media Select WWW",
    0x72: "Media Select DVD",
    0x74: "Media Select Program Guide",
    0x76: "Media Select Games",
    0x77: "Media Select Messages",
    0x78: "Media Select CD",
    0x79: "Media Select VCR",
    0x7A: "Media Select Tuner",
    0x89: "Media Select Home",
    0x8A: "Media Select Back",
    0x8B: "Media Select Forward",
    0x8C: "Media Select Stop",
    0x8D: "Media Select Find",
    0x8E: "Media Select Scroll Up",
    0x8F: "Media Select Scroll Down",
    0x90: "Media Select Edit",
    0x91: "Media Select Network",
    0x92: "Media Select Browser",
    0xB0: "Play",
    0xB1: "Pause",
    0xB2: "Record",
    0xB3: "Fast Forward",
    0xB4: "Rewind",
    0xB5: "Scan Next Track",
    0xB6: "Scan Previous Track",
    0xB7: "Stop",
    0xB8: "Eject",
    0xCD: "Play/Pause",
    0xE2: "Mute",
    0xE9: "Volume Increment",
    0xEA: "Volume Decrement",
    0x19E: "AL Task/Project Manager",
    0x221: "AC Search (Voice Assistant)",
    0x223: "AC Home",
    0x224: "AC Back",
    0x225: "AC Forward",
    0x226: "AC Stop",
    0x227: "AC Refresh",
    0x228: "AC Bookmarks",
}

KEYBOARD_NAMES: dict[int, str] = {
    0x28: "Return",
    0x29: "Escape",
    0x2C: "Space",
    0x2B: "Tab",
    0x4F: "Right Arrow",
    0x50: "Left Arrow",
    0x51: "Down Arrow",
    0x52: "Up Arrow",
    0x4A: "Home",
    0x4D: "End",
    0x4B: "Page Up",
    0x4E: "Page Down",
    0x49: "Insert",
    0x4C: "Delete",
    0x39: "Caps Lock",
    0xE0: "Left Control",
    0xE1: "Left Shift",
    0xE2: "Left Alt",
    0xE3: "Left GUI",
    0xE4: "Right Control",
    0xE5: "Right Shift",
    0xE6: "Right Alt",
    0xE7: "Right GUI",
}

_PAGE_NAMES = {0x0C: CONSUMER_NAMES, 0x07: KEYBOARD_NAMES}

# 这块遥控器（Google Chromecast Voice Remote, 18d1:9450）实测按键表。
# 依据：ZSTDJan/windows-remote-mic-app 的 Chromecast 专项文档 + 本机 HID 描述符。
REMOTE_LABELS: dict[int, str] = {
    0x19E: "电源 Power",
    0xCD: "播放/暂停 Play/Pause",
    0x42: "方向上 D-pad Up",
    0x43: "方向下 D-pad Down",
    0x44: "方向左 D-pad Left",
    0x45: "方向右 D-pad Right",
    0x41: "确定 OK",
    0xE2: "静音 Mute",
    0x221: "语音 Assistant",
    0x223: "首页 Home",
    0x224: "返回 Back",
    0xE9: "音量加 Volume +",
    0xEA: "音量减 Volume −",
    0x77: "YouTube",
    0x78: "Netflix",
    0x79: "待学习 App 4",
    0x89: "输入源 Input",
}


def usage_name(page: int, usage: int) -> str:
    if page == 0x0C and usage in REMOTE_LABELS:
        return REMOTE_LABELS[usage]
    table = _PAGE_NAMES.get(page, {})
    return table.get(usage, f"usage 0x{usage:02X}")


def usage_id(page: int, usage: int) -> str:
    """配置里使用的规范 ID，例如 ``c:0x221`` / ``k:0x28``。"""
    prefix = {0x0C: "c", 0x07: "k"}.get(page, f"p{page:02x}")
    return f"{prefix}:0x{usage:02X}"


@dataclass
class ArrayField:
    report_id: int
    bit_offset: int
    report_size: int
    report_count: int
    usage_page: int
    logical_min: int
    logical_max: int
    usages: list[int] = field(default_factory=list)
    usage_min: int | None = None
    usage_max: int | None = None

    def resolve(self, value: int) -> int | None:
        """把报告里的原始值翻译成 usage。

        - 枚举用法（本遥控器）：逻辑值 1..N 是数组下标；
        - 范围用法（普通键盘）：逻辑值就是 usage 本身。
        """
        if self.usages:
            if 0 <= value < len(self.usages) and self.logical_min == 0:
                return self.usages[value]
            if 1 <= value <= len(self.usages) and self.logical_min >= 1:
                return self.usages[value - 1]
            if value in self.usages:
                return value
        if self.usage_min is not None and self.usage_min <= value <= self.usage_max:
            return value
        return None

    @property
    def bits(self) -> int:
        return self.report_size * self.report_count


def _iter_items(data: bytes) -> Iterator[tuple[int, int, int]]:
    """产出 (type, tag, value)。type: 0=Main 1=Global 2=Local。"""
    i = 0
    n = len(data)
    while i < n:
        prefix = data[i]
        i += 1
        size = (0, 1, 2, 4)[prefix & 0x03]
        typ = (prefix >> 2) & 0x03
        tag = (prefix >> 4) & 0x0F
        if size:
            raw = data[i:i + size]
            if len(raw) < size:
                break
            value = int.from_bytes(raw, "little")
            i += size
        else:
            value = 0
        yield typ, tag, value


def parse(descriptor: bytes) -> dict[int, list[ArrayField]]:
    """解析描述符，返回 report_id -> 数组字段列表（按报告内顺序）。"""
    fields: dict[int, list[ArrayField]] = {}
    bit_offsets: dict[int, int] = {}

    stack: list[dict] = []
    g = {
        "usage_page": 0,
        "logical_min": 0,
        "logical_max": 0,
        "report_size": 0,
        "report_count": 0,
        "report_id": 0,
    }
    usages: list[int] = []
    usage_min: int | None = None
    usage_max: int | None = None

    for typ, tag, value in _iter_items(descriptor):
        if typ == 1:  # Global
            if tag == 0x0:
                g["usage_page"] = value
            elif tag == 0x1:
                g["logical_min"] = _signed(value)
            elif tag == 0x2:
                g["logical_max"] = _signed(value)
            elif tag == 0x7:
                g["report_size"] = value
            elif tag == 0x8:
                g["report_id"] = value
                bit_offsets.setdefault(value, 0)
            elif tag == 0x9:
                g["report_count"] = value
            elif tag == 0xA:
                stack.append(dict(g))
                stack.append({"usages": list(usages), "usage_min": usage_min, "usage_max": usage_max})
            elif tag == 0xB and stack:
                loc = stack.pop()
                usages = list(loc["usages"])
                usage_min = loc["usage_min"]
                usage_max = loc["usage_max"]
                g = stack.pop()
        elif typ == 2:  # Local
            if tag == 0x0:
                usages.append(value & 0xFFFF if value > 0xFFFF else value)
                if value > 0xFFFF:  # 扩展用法：高 16 位是 usage page
                    g["usage_page"] = (value >> 16) & 0xFFFF
            elif tag == 0x1:
                usage_min = value
            elif tag == 0x2:
                usage_max = value
        else:  # Main
            report_id = g["report_id"]
            if tag == 0x8:  # Input
                flags = value
                is_constant = bool(flags & 0x01)
                is_variable = bool(flags & 0x02)
                bits = g["report_size"] * g["report_count"]
                if not is_constant and not is_variable and g["report_count"]:
                    field = ArrayField(
                        report_id=report_id,
                        bit_offset=bit_offsets.get(report_id, 0),
                        report_size=g["report_size"],
                        report_count=g["report_count"],
                        usage_page=g["usage_page"],
                        logical_min=g["logical_min"],
                        logical_max=g["logical_max"],
                        usages=list(usages),
                        usage_min=usage_min,
                        usage_max=usage_max,
                    )
                    fields.setdefault(report_id, []).append(field)
                bit_offsets[report_id] = bit_offsets.get(report_id, 0) + bits
            usages = []
            usage_min = None
            usage_max = None
    return fields


def _signed(value: int, bits: int = 32) -> int:
    if value & (1 << (bits - 1)):
        return value - (1 << bits)
    return value


def _get_bits(data: bytes, bit_offset: int, size: int) -> int:
    value = 0
    for i in range(size):
        bit = bit_offset + i
        byte_index = bit // 8
        if byte_index >= len(data):
            return value
        value |= ((data[byte_index] >> (bit % 8)) & 1) << i
    return value


def decode(fields: dict[int, list[ArrayField]], report_id: int, payload: bytes) -> list[tuple[int, int]]:
    """把一条输入报告解码成 [(usage_page, usage), ...]（仅非零项）。"""
    found: list[tuple[int, int]] = []
    for f in fields.get(report_id, []):
        for slot in range(f.report_count):
            raw = _get_bits(payload, f.bit_offset + slot * f.report_size, f.report_size)
            if raw == 0:
                continue
            usage = f.resolve(raw)
            if usage is not None:
                found.append((f.usage_page, usage))
    return found


def summarize(descriptor: bytes) -> str:
    """给 CLI 用的可读摘要。"""
    fields = parse(descriptor)
    lines = []
    for report_id, items in sorted(fields.items()):
        for f in items:
            if f.usages:
                names = ", ".join(
                    f"{usage_id(f.usage_page, u)} {usage_name(f.usage_page, u)}"
                    for u in f.usages[:6]
                )
                more = "" if len(f.usages) <= 6 else f" (+{len(f.usages) - 6})"
                lines.append(
                    f"report {report_id}: {f.report_count}x{f.report_size}bit array, "
                    f"{len(f.usages)} usages -> {names}{more}"
                )
            else:
                lines.append(
                    f"report {report_id}: {f.report_count}x{f.report_size}bit array, "
                    f"usage range 0x{f.usage_min or 0:02X}..0x{f.usage_max or 0:02X}"
                )
    return "\n".join(lines)
