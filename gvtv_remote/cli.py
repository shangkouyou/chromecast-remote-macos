"""命令行入口。"""
from __future__ import annotations

import argparse
import json
import platform
import signal
import sys
import time
from pathlib import Path

from . import __version__
from . import config as config_mod
from .actions import ActionRunner, describe_action, parse_action
from .descriptor import decode, parse, summarize, usage_id, usage_name
from .events import (
    EventSink,
    ax_trusted,
    listen_event_access,
    open_privacy_pane,
    post_event_access,
)
from .hid import DeviceInfo, HIDMonitor, enumerate_devices, hid_listen_access
from .mapper import Mapper, _split_id, canonical_id
from .voice import VoiceController


def log(message: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


# --------------------------------------------------------------------- list
def cmd_list(args) -> int:
    cfg, path = config_mod.load_config(args.config)
    device = cfg.get("device", {})
    infos = _find_devices(device)
    if not infos:
        log("没有找到匹配的 HID 设备。确认遥控器已连接，或检查 device 匹配条件。")
        return 1
    for info in infos:
        print(f"设备      : {info.product or '<unnamed>'}")
        print(f"VID:PID   : {info.vid_pid}")
        print(f"厂商      : {info.manufacturer}")
        print(f"传输      : {info.transport}")
        print(f"序列号    : {info.serial}")
        print(f"用途页    : 0x{info.usage_page:02X} / 0x{info.usage:02X}")
        print(f"报告上限  : {info.max_input_report} 字节")
        if info.descriptor:
            print(f"描述符    : {info.descriptor.hex()}")
            print(summarize(info.descriptor))
        print("-" * 60)
    return 0


def _find_devices(device: dict) -> list[DeviceInfo]:
    vendor_id = device.get("vendor_id")
    product_id = device.get("product_id")
    product = device.get("product")
    infos = []
    if vendor_id or product_id:
        infos = enumerate_devices(vendor_id=vendor_id, product_id=product_id)
    if not infos and product:
        infos = enumerate_devices(product=product)
    return infos


# ------------------------------------------------------------------- buttons
def cmd_buttons(args) -> int:
    cfg, _ = config_mod.load_config(args.config)
    infos = _find_devices(cfg.get("device", {}))
    if not infos:
        log("没有找到遥控器。")
        return 1
    info = infos[0]
    if not info.descriptor:
        log("设备没有提供 Report Descriptor。")
        return 1
    fields = parse(info.descriptor)
    for report_id, items in sorted(fields.items()):
        for item in items:
            print(f"report {report_id}: {item.report_count} 个槽位 × {item.report_size} bit")
            for index, usage in enumerate(item.usages, start=1):
                marker = "  " if index < 10 else " "
                print(
                    f"  值 {index:>2}{marker} {usage_id(item.usage_page, usage):<9} "
                    f"{usage_name(item.usage_page, usage)}"
                )
    return 0


# --------------------------------------------------------------------- sniff
def cmd_sniff(args) -> int:
    cfg, _ = config_mod.load_config(args.config)
    device = cfg.get("device", {})
    fields: dict = {}

    def on_device(info: DeviceInfo) -> None:
        nonlocal fields
        log(f"已连接: {info}")
        if info.descriptor:
            fields = parse(info.descriptor)
            print(summarize(info.descriptor))

    def on_report(report_id: int, payload: bytes) -> None:
        usages = decode(fields, report_id, payload) if fields else []
        decoded = ", ".join(
            f"{usage_id(page, usage)} {usage_name(page, usage)}" for page, usage in usages
        )
        log(f"report {report_id}: {payload.hex(' '):<16} -> {decoded or '-'}")

    def on_value(page: int, usage: int, amount: int) -> None:
        if args.values:
            log(f"value page=0x{page:02x} usage=0x{usage:02x} amount={amount}")

    monitor = HIDMonitor(
        vendor_id=device.get("vendor_id"),
        product_id=device.get("product_id"),
        product=None if device.get("vendor_id") else device.get("product"),
        seize=False,
        on_device=on_device,
        on_report=on_report,
        on_value=on_value,
    )
    monitor.open()
    log(f"嗅探 {args.seconds:g} 秒（共享模式，不抢占系统处理），请按遥控器按键…")
    try:
        monitor.run(args.seconds)
    except KeyboardInterrupt:
        pass
    finally:
        monitor.close()
    return 0


# ----------------------------------------------------------------------- run
def cmd_run(args) -> int:
    cfg, path = config_mod.load_config(args.config)
    if args.no_seize:
        cfg.setdefault("device", {})["seize"] = False
    if args.dry_run:
        log("dry-run：只打印动作，不发送系统事件")

    sink = EventSink(dry_run=args.dry_run)
    runner = ActionRunner(sink, log=log, dry_run=args.dry_run)
    voice = VoiceController(cfg["voice"], sink, runner, log)

    state: dict = {"mapper": None, "monitor": None, "fields": {}}

    def on_device(info: DeviceInfo) -> None:
        if not info.descriptor:
            log("警告：设备没有 Report Descriptor，无法解码按键")
            return
        state["fields"] = parse(info.descriptor)
        mapper = Mapper(cfg, state["fields"], runner, voice, log)
        state["mapper"] = mapper
        log(f"已连接: {info}")
        log("按键映射：\n" + mapper.describe())
        if not args.dry_run and not post_event_access():
            log("⚠️ 没有辅助功能（Accessibility）权限，合成按键会被系统忽略。")
            log("   系统设置 → 隐私与安全性 → 辅助功能，添加你运行本程序的终端/Python。")

    def on_report(report_id: int, payload: bytes) -> None:
        mapper = state["mapper"]
        if mapper is not None:
            if args.verbose:
                usages = decode(state["fields"], report_id, payload)
                log(
                    f"report {report_id}: {payload.hex(' ')} -> "
                    + ", ".join(usage_id(p, u) for p, u in usages)
                )
            mapper.handle_report(report_id, payload)

    def on_remove(info: DeviceInfo) -> None:
        state["mapper"] = None
        log(f"设备断开: {info}")

    monitor = HIDMonitor(
        vendor_id=cfg["device"].get("vendor_id"),
        product_id=cfg["device"].get("product_id"),
        product=None if cfg["device"].get("vendor_id") else cfg["device"].get("product"),
        seize=bool(cfg["device"].get("seize", True)),
        on_device=on_device,
        on_remove=on_remove,
        on_report=on_report,
    )
    state["monitor"] = monitor

    def stop(_signum, _frame):
        log("收到退出信号，正在停止…")
        monitor.stop()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    log(f"配置: {path}")
    log(f"辅助功能: {'✓' if post_event_access() else '✗'}   输入监控: {'✓' if listen_event_access() else '✗'}")
    monitor.open()
    if not listen_event_access():
        log("⚠️ 没有输入监控（Input Monitoring）权限，按键报告会被系统拦截。")
        log("   系统设置 → 隐私与安全性 → 输入监控，添加你运行本程序的终端/Python。")
    if cfg["device"].get("seize", True) and not monitor.seized:
        log("⚠️ 独占失败，已退回共享模式：系统可能同时响应部分按键。")
    log(
        f"监听中（{'独占' if monitor.seized else '共享'}模式），Ctrl-C 退出…"
    )
    try:
        monitor.run()
    except KeyboardInterrupt:
        pass
    finally:
        try:
            voice.close()
        finally:
            monitor.close()
    log("已退出。")
    return 0


# --------------------------------------------------------------------- learn
def cmd_learn(args) -> int:
    cfg, path = config_mod.load_config(args.config)
    cfg.setdefault("device", {})["seize"] = True
    sink = EventSink(dry_run=True)
    runner = ActionRunner(sink, log=log, dry_run=True)
    voice = VoiceController(cfg["voice"], sink, runner, log)
    fields: dict = {}

    bind_action = None
    if args.bind:
        bind_action = parse_action(args.bind)

    def on_device(info: DeviceInfo) -> None:
        nonlocal fields
        if not info.descriptor:
            log("设备没有 Report Descriptor")
            return
        fields = parse(info.descriptor)
        mapper = state["mapper"]
        mapper.fields = fields
        log(f"已连接 {info}。请按键（Ctrl-C 结束）…")

    def on_report(report_id: int, payload: bytes) -> None:
        if state["mapper"]:
            state["mapper"].handle_report(report_id, payload)

    def on_press(binding_id: str, label: str) -> None:
        page, usage = _split_id(binding_id)
        print()
        log(f"按键: {binding_id}  ({label})")
        current = cfg.get("mapping", {}).get(binding_id)
        if current:
            try:
                log(f"当前绑定: {describe_action(parse_action(current))}")
            except Exception:
                pass
        else:
            log("当前绑定: 无")
        if bind_action is not None:
            cfg.setdefault("mapping", {})[binding_id] = args.bind
            config_mod.save_config(cfg, path)
            log(f"已保存: {binding_id} -> {args.bind}  ({path})")
        else:
            example = f"gvtv-remote learn --bind 'key:cmd+space'"
            log(f"如需绑定，重跑并加 --bind，例如：{example}")

    state = {"mapper": None}
    monitor = HIDMonitor(
        vendor_id=cfg["device"].get("vendor_id"),
        product_id=cfg["device"].get("product_id"),
        product=None if cfg["device"].get("vendor_id") else cfg["device"].get("product"),
        seize=True,
        on_device=on_device,
        on_report=on_report,
    )
    state["monitor"] = monitor

    # 先建一个空 mapper，on_device 时补 fields
    state["mapper"] = Mapper(cfg, {}, runner, voice, log)
    state["mapper"].learning = True
    state["mapper"].learn_callback = on_press

    def stop(_signum, _frame):
        monitor.stop()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    monitor.open()
    log("独占模式学习按键；学习模式不会触发任何系统动作。")
    try:
        monitor.run()
    except KeyboardInterrupt:
        pass
    finally:
        voice.close()
        monitor.close()
    return 0


# -------------------------------------------------------------------- doctor
def cmd_doctor(args) -> int:
    cfg, path = config_mod.load_config(args.config)
    print(f"gvtv-remote {__version__}  macOS {platform.mac_ver()[0]}  Python {platform.python_version()}")
    source = path if path.exists() else config_mod.REPO_CONFIG
    suffix = "" if path.exists() or not source.exists() else f"（回退 {source}）"
    print(f"配置: {path}  (存在: {path.exists()}){suffix}")

    print("\n[权限]")
    ax = post_event_access()
    listen = listen_event_access()
    print(f"  辅助功能（合成按键）: {'✓ 已授权' if ax else '✗ 未授权'}")
    print(f"  输入监控（读取 HID） : {'✓ 已授权' if listen else '✗ 未授权'}")
    print(f"  IOHIDCheckAccess     : {hid_listen_access()}")

    print("\n[设备]")
    infos = _find_devices(cfg.get("device", {}))
    if not infos:
        print("  ✗ 未找到匹配设备")
    for info in infos:
        print(f"  ✓ {info}")
        print(f"    用途页 0x{info.usage_page:02X}:0x{info.usage:02X}  报告上限 {info.max_input_report}")
        if info.descriptor:
            fields = parse(info.descriptor)
            report_ids = ", ".join(str(k) for k in sorted(fields))
            total = sum(len(f.usages) for items in fields.values() for f in items)
            print(f"    描述符 {len(info.descriptor)} 字节，report {report_ids or '-'}，共 {total} 个用法")

    print("\n[独占打开测试]")
    try:
        probe = HIDMonitor(
            vendor_id=cfg["device"].get("vendor_id"),
            product_id=cfg["device"].get("product_id"),
            seize=True,
        )
        probe.open()
        print(f"  独占: {'✓ 成功' if probe.seized else '✗ 失败（已退回共享）'}")
        probe.close()
    except Exception as exc:
        print(f"  ✗ 失败: {exc}")

    print("\n[映射]")
    try:
        fields = parse(infos[0].descriptor) if infos and infos[0].descriptor else {}
        dummy_sink = EventSink(dry_run=True)
        dummy_runner = ActionRunner(dummy_sink, dry_run=True)
        dummy_voice = VoiceController(cfg["voice"], dummy_sink, dummy_runner, lambda _m: None)
        mapper = Mapper(cfg, fields, dummy_runner, dummy_voice, lambda _m: None)
        print(mapper.describe())
        dummy_voice.close()
    except Exception as exc:
        print(f"  ✗ 配置有误: {exc}")

    print("\n[语音键]")
    voice = cfg.get("voice", {})
    print(f"  按钮: {voice.get('button')}  模式: {voice.get('mode')}  上限: {voice.get('max_session_s')}s")

    print("\n[建议]")
    if not ax:
        print("  · 到 系统设置 → 隐私与安全性 → 辅助功能 勾选你的终端（或 /usr/bin/python3）")
    if not listen:
        print("  · 到 系统设置 → 隐私与安全性 → 输入监控 勾选同一个程序")
    if not infos:
        print("  · 先让遥控器处于已连接状态；必要时在蓝牙设置里重新连接")
    if ax and listen and infos:
        print("  · 一切就绪：gvtv-remote run")
    return 0


# ---------------------------------------------------------------- test tools
def cmd_test_key(args) -> int:
    sink = EventSink()
    sink.press_name(args.key, hold_ms=args.hold_ms)
    print(f"已发送按键 {args.key}（需要辅助功能权限才会生效）")
    return 0


def cmd_test_media(args) -> int:
    sink = EventSink()
    sink.media(args.name)
    print(f"已发送媒体键 {args.name}（需要辅助功能权限才会生效）")
    return 0


def cmd_test_fn(args) -> int:
    sink = EventSink()
    if args.hold_ms:
        sink.fn_down()
        time.sleep(args.hold_ms / 1000.0)
        sink.fn_up()
    else:
        sink.fn_tap()
    print("已发送 Fn(Globe) 键。若系统听写快捷键设为 Fn，应看到听写界面。")
    return 0


def cmd_permissions(args) -> int:
    print(f"辅助功能: {'✓' if post_event_access() else '✗'}")
    print(f"输入监控: {'✓' if listen_event_access() else '✗'}")
    print(f"AXIsProcessTrusted: {'✓' if ax_trusted() else '✗'}")
    if args.open:
        open_privacy_pane("Privacy_Accessibility")
    return 0


# ----------------------------------------------------------------------- main
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gvtv-remote",
        description="把 Google TV / Chromecast 蓝牙遥控器映射成 macOS 系统操作",
    )
    parser.add_argument("--version", action="version", version=f"gvtv-remote {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    def add_common(p):
        p.add_argument("--config", help="配置文件路径（默认 ~/.config/gvtv-remote/mapping.json）")

    p = sub.add_parser("list", help="列出匹配的 HID 设备")
    add_common(p)
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("buttons", help="打印遥控器支持的全部按键表")
    add_common(p)
    p.set_defaults(func=cmd_buttons)

    p = sub.add_parser("sniff", help="嗅探按键报告（不改变系统行为）")
    add_common(p)
    p.add_argument("--seconds", type=float, default=30)
    p.add_argument("--values", action="store_true", help="同时打印 IOHIDValue 回调")
    p.set_defaults(func=cmd_sniff)

    p = sub.add_parser("run", help="启动按键映射服务")
    add_common(p)
    p.add_argument("--dry-run", action="store_true", help="只打印动作，不发送事件")
    p.add_argument("--no-seize", action="store_true", help="不独占设备")
    p.add_argument("--verbose", action="store_true", help="打印每条 HID 报告")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("learn", help="学习按键：按一下即可查看 / 绑定")
    add_common(p)
    p.add_argument("--bind", help="把按到的键绑定到动作，例如 'key:cmd+space'")
    p.set_defaults(func=cmd_learn)

    p = sub.add_parser("doctor", help="体检：权限、设备、描述符、配置")
    add_common(p)
    p.set_defaults(func=cmd_doctor)

    p = sub.add_parser("test-key", help="发送一个组合键")
    p.add_argument("key")
    p.add_argument("--hold-ms", type=int, default=40)
    p.set_defaults(func=cmd_test_key)

    p = sub.add_parser("test-media", help="发送一个媒体键")
    p.add_argument("name", choices=["volume_up", "volume_down", "mute", "play_pause", "next", "previous"])
    p.set_defaults(func=cmd_test_media)

    p = sub.add_parser("test-fn", help="发送 Fn(Globe) 键")
    p.add_argument("--hold-ms", type=int, default=0)
    p.set_defaults(func=cmd_test_fn)

    p = sub.add_parser("permissions", help="查看 / 打开权限设置")
    p.add_argument("--open", action="store_true", help="打开辅助功能设置面板")
    p.set_defaults(func=cmd_permissions)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
