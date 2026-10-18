"""配置加载 / 保存 / 默认值。"""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
from typing import Any

APP_DIR = Path.home() / ".config" / "gvtv-remote"
DEFAULT_PATH = APP_DIR / "mapping.json"
REPO_CONFIG = Path(__file__).resolve().parent.parent / "config" / "mapping.json"

DEFAULT_CONFIG: dict[str, Any] = {
    "version": 1,
    "device": {
        "vendor_id": 6353,   # 0x18D1 Google
        "product_id": 37968,  # 0x9450 Chromecast Remote
        "product": "Chromecast Remote",
        "seize": True,
    },
    "logging": {"reports": False},
    "mapping": {
        "c:0x19E": "key:ctrl+cmd+q",
        "c:0x42": "key:up",
        "c:0x43": "key:down",
        "c:0x44": "key:left",
        "c:0x45": "key:right",
        "c:0x41": "key:return",
        "c:0x224": "key:escape",
        "c:0x223": "key:ctrl+up",
        "c:0x221": "voice",
        "c:0xE2": "media:mute",
        "c:0xE9": "media:volume_up",
        "c:0xEA": "media:volume_down",
        "c:0xCD": "media:play_pause",
        "c:0x77": "url:https://www.youtube.com",
        "c:0x78": "url:https://www.netflix.com",
        "c:0x79": "none",
        "c:0x89": "key:cmd+tab",
    },
    "voice": {
        "button": "assistant",
        "mode": "hold",
        "max_session_s": 60,
        "release_delay_ms": 150,
        "end_actions": [],
        "disconnect_bluetooth": False,
        "bluetooth_address": "",
    },
}


def resolve_path(explicit: str | os.PathLike | None = None) -> Path:
    if explicit:
        return Path(explicit).expanduser()
    env = os.environ.get("GVTV_REMOTE_CONFIG")
    if env:
        return Path(env).expanduser()
    return DEFAULT_PATH


def _deep_merge(base: dict, override: dict) -> dict:
    result = copy.deepcopy(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(explicit: str | os.PathLike | None = None) -> tuple[dict, Path]:
    path = resolve_path(explicit)
    source = path
    if not source.exists() and REPO_CONFIG.exists():
        source = REPO_CONFIG
    if source.exists():
        with open(source, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        cfg = _deep_merge(DEFAULT_CONFIG, data)
    else:
        cfg = copy.deepcopy(DEFAULT_CONFIG)
    validate(cfg)
    return cfg, path


def save_config(cfg: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    to_write = {k: v for k, v in cfg.items() if not k.startswith("_")}
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(to_write, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def ensure_config_file(path: Path) -> None:
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    save_config(DEFAULT_CONFIG, path)


def validate(cfg: dict) -> None:
    device = cfg.get("device")
    if not isinstance(device, dict):
        raise ValueError("配置缺少 device 段")
    if not device.get("vendor_id") and not device.get("product"):
        raise ValueError("device 至少需要 vendor_id 或 product")
    voice = cfg.get("voice")
    if not isinstance(voice, dict):
        raise ValueError("配置缺少 voice 段")
    if str(voice.get("mode", "hold")) not in ("hold", "toggle", "double"):
        raise ValueError("voice.mode 只能是 hold / toggle / double")
    if not isinstance(cfg.get("mapping"), dict):
        raise ValueError("配置缺少 mapping 段")
