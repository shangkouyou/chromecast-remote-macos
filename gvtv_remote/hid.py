"""IOHIDManager 的 ctypes 封装：枚举 / 监听 / 独占蓝牙 HID 遥控器。"""
from __future__ import annotations

import ctypes
import threading
import time
from ctypes import (
    CFUNCTYPE,
    POINTER,
    byref,
    c_char,
    c_int32,
    c_long,
    c_uint8,
    c_uint32,
    c_void_p,
)
from dataclasses import dataclass
from typing import Callable

from . import cf

IOKIT = ctypes.CDLL("/System/Library/Frameworks/IOKit.framework/IOKit")

kIOHIDOptionsTypeNone = 0
kIOHIDOptionsTypeSeizeDevice = 1

IOKIT.IOHIDManagerCreate.argtypes = [c_void_p, c_uint32]
IOKIT.IOHIDManagerCreate.restype = c_void_p

IOKIT.IOHIDManagerSetDeviceMatching.argtypes = [c_void_p, c_void_p]
IOKIT.IOHIDManagerSetDeviceMatching.restype = None

IOKIT.IOHIDManagerScheduleWithRunLoop.argtypes = [c_void_p, c_void_p, c_void_p]
IOKIT.IOHIDManagerScheduleWithRunLoop.restype = None

IOKIT.IOHIDManagerUnscheduleFromRunLoop.argtypes = [c_void_p, c_void_p, c_void_p]
IOKIT.IOHIDManagerUnscheduleFromRunLoop.restype = None

IOKIT.IOHIDManagerOpen.argtypes = [c_void_p, c_uint32]
IOKIT.IOHIDManagerOpen.restype = c_int32

IOKIT.IOHIDManagerClose.argtypes = [c_void_p, c_uint32]
IOKIT.IOHIDManagerClose.restype = c_int32

IOKIT.IOHIDManagerCopyDevices.argtypes = [c_void_p]
IOKIT.IOHIDManagerCopyDevices.restype = c_void_p

IOKIT.IOHIDDeviceGetProperty.argtypes = [c_void_p, c_void_p]
IOKIT.IOHIDDeviceGetProperty.restype = c_void_p

IOKIT.IOHIDValueGetIntegerValue.argtypes = [c_void_p]
IOKIT.IOHIDValueGetIntegerValue.restype = c_long

IOKIT.IOHIDValueGetElement.argtypes = [c_void_p]
IOKIT.IOHIDValueGetElement.restype = c_void_p

IOKIT.IOHIDElementGetUsagePage.argtypes = [c_void_p]
IOKIT.IOHIDElementGetUsagePage.restype = c_uint32

IOKIT.IOHIDElementGetUsage.argtypes = [c_void_p]
IOKIT.IOHIDElementGetUsage.restype = c_uint32

try:
    IOKIT.IOHIDCheckAccess.argtypes = [c_uint32]
    IOKIT.IOHIDCheckAccess.restype = c_int32
except AttributeError:  # pragma: no cover - 旧系统
    pass

# IOHIDDeviceCallback: (context, result, sender, device)
DEVICE_CB = CFUNCTYPE(None, c_void_p, c_int32, c_void_p, c_void_p)
# IOHIDReportCallback: (context, result, sender, type, reportID, report, length)
REPORT_CB = CFUNCTYPE(
    None, c_void_p, c_int32, c_void_p, c_uint32, c_uint32, POINTER(c_uint8), c_long
)
# IOHIDValueCallback: (context, result, sender, value)
VALUE_CB = CFUNCTYPE(None, c_void_p, c_int32, c_void_p, c_void_p)
# CFRunLoopTimerCallback: (timer, info)
TIMER_CB = CFUNCTYPE(None, c_void_p, c_void_p)

IOKIT.IOHIDManagerRegisterDeviceMatchingCallback.argtypes = [c_void_p, DEVICE_CB, c_void_p]
IOKIT.IOHIDManagerRegisterDeviceMatchingCallback.restype = None
IOKIT.IOHIDManagerRegisterDeviceRemovalCallback.argtypes = [c_void_p, DEVICE_CB, c_void_p]
IOKIT.IOHIDManagerRegisterDeviceRemovalCallback.restype = None
IOKIT.IOHIDManagerRegisterInputReportCallback.argtypes = [c_void_p, REPORT_CB, c_void_p]
IOKIT.IOHIDManagerRegisterInputReportCallback.restype = None
IOKIT.IOHIDManagerRegisterInputValueCallback.argtypes = [c_void_p, VALUE_CB, c_void_p]
IOKIT.IOHIDManagerRegisterInputValueCallback.restype = None

IOKIT.CFRunLoopTimerCreate.argtypes = [c_void_p, ctypes.c_double, ctypes.c_double, ctypes.c_uint64, c_long, TIMER_CB, c_void_p]
IOKIT.CFRunLoopTimerCreate.restype = c_void_p
IOKIT.CFRunLoopAddTimer.argtypes = [c_void_p, c_void_p, c_void_p]
IOKIT.CFRunLoopAddTimer.restype = None
IOKIT.CFRunLoopTimerInvalidate.argtypes = [c_void_p]
IOKIT.CFRunLoopTimerInvalidate.restype = None
IOKIT.CFAbsoluteTimeGetCurrent.argtypes = []
IOKIT.CFAbsoluteTimeGetCurrent.restype = ctypes.c_double

_PRODUCT_KEYS = (
    "Product",
    "Manufacturer",
    "SerialNumber",
    "Transport",
    "VendorID",
    "ProductID",
    "LocationID",
    "PrimaryUsagePage",
    "PrimaryUsage",
    "MaxInputReportSize",
)


@dataclass
class DeviceInfo:
    product: str = ""
    manufacturer: str = ""
    serial: str = ""
    transport: str = ""
    vendor_id: int = 0
    product_id: int = 0
    location_id: int = 0
    usage_page: int = 0
    usage: int = 0
    max_input_report: int = 0
    descriptor: bytes = b""

    @property
    def vid_pid(self) -> str:
        return f"{self.vendor_id:04x}:{self.product_id:04x}"

    def __str__(self) -> str:
        return (
            f"{self.product or '<unnamed>'} [{self.vid_pid}] "
            f"{self.transport or '?'} usage={self.usage_page:02x}:{self.usage:02x}"
        )


def _prop(device: int, key: str):
    return cf.to_py(IOKIT.IOHIDDeviceGetProperty(device, cf.cfstr(key)))


def device_info(device: int) -> DeviceInfo:
    info = DeviceInfo()
    for key in _PRODUCT_KEYS:
        value = _prop(device, key)
        if value is None:
            continue
        attr = {
            "Product": "product",
            "Manufacturer": "manufacturer",
            "SerialNumber": "serial",
            "Transport": "transport",
            "VendorID": "vendor_id",
            "ProductID": "product_id",
            "LocationID": "location_id",
            "PrimaryUsagePage": "usage_page",
            "PrimaryUsage": "usage",
            "MaxInputReportSize": "max_input_report",
        }[key]
        setattr(info, attr, value)
    descriptor = _prop(device, "ReportDescriptor")
    if isinstance(descriptor, bytes):
        info.descriptor = descriptor
    return info


class HIDMonitor:
    """监听（可选独占）一个 HID 设备。"""

    def __init__(
        self,
        *,
        vendor_id: int | None = None,
        product_id: int | None = None,
        product: str | None = None,
        seize: bool = False,
        on_device: Callable[[DeviceInfo], None] | None = None,
        on_remove: Callable[[DeviceInfo], None] | None = None,
        on_report: Callable[[int, bytes], None] | None = None,
        on_value: Callable[[int, int, int], None] | None = None,
    ) -> None:
        self._match: dict[str, object] = {}
        if vendor_id is not None:
            self._match["VendorID"] = int(vendor_id)
        if product_id is not None:
            self._match["ProductID"] = int(product_id)
        if product is not None:
            self._match["Product"] = product

        self.seize = seize
        self.on_device = on_device
        self.on_remove = on_remove
        self.on_report = on_report
        self.on_value = on_value

        self.device: int = 0
        self.info: DeviceInfo | None = None
        self.seized = False
        self._manager = ctypes.c_void_p()
        self._mode = cf.cfstr("kCFRunLoopDefaultMode")
        self._running = False

        self._tick_cb = TIMER_CB(self._tick)
        self._timer = 0
        self._run_loop = 0
        self._device_cb = DEVICE_CB(self._handle_device)
        self._remove_cb = DEVICE_CB(self._handle_remove)
        self._report_cb = REPORT_CB(self._handle_report)
        self._value_cb = VALUE_CB(self._handle_value)

    # ------------------------------------------------------------------ setup
    def open(self) -> None:
        manager = IOKIT.IOHIDManagerCreate(None, 0)
        if not manager:
            raise OSError("IOHIDManagerCreate failed")
        self._manager = ctypes.c_void_p(manager)

        matching = cf.cfdict(self._match)
        if not isinstance(matching, int):  # pragma: no cover
            raise OSError("failed to build matching dictionary")
        IOKIT.IOHIDManagerSetDeviceMatching(manager, matching)
        cf.release(matching)  # manager 会 retain，自己的引用可以放掉

        IOKIT.IOHIDManagerRegisterDeviceMatchingCallback(manager, self._device_cb, None)
        IOKIT.IOHIDManagerRegisterDeviceRemovalCallback(manager, self._remove_cb, None)
        IOKIT.IOHIDManagerRegisterInputReportCallback(manager, self._report_cb, None)
        IOKIT.IOHIDManagerRegisterInputValueCallback(manager, self._value_cb, None)

        run_loop = cf.run_loop_current()
        IOKIT.IOHIDManagerScheduleWithRunLoop(manager, run_loop, self._mode)

        options = kIOHIDOptionsTypeSeizeDevice if self.seize else kIOHIDOptionsTypeNone
        result = IOKIT.IOHIDManagerOpen(manager, options)
        if result != 0 and self.seize:
            # 独占失败（没有输入监控/辅助功能权限，或设备被系统占用）时退回共享模式。
            self.seize = False
            result = IOKIT.IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone)
            self.seized = False
        else:
            self.seized = bool(self.seize)
        if result != 0:
            raise OSError(f"IOHIDManagerOpen failed: 0x{result & 0xFFFFFFFF:08x}")

    # ------------------------------------------------------------------ events
    def _handle_device(self, _ctx, _result, _sender, device) -> None:
        if not device:
            return
        self.device = device
        self.info = device_info(device)
        if self.on_device:
            self.on_device(self.info)

    def _handle_remove(self, _ctx, _result, _sender, device) -> None:
        info = self.info
        self.device = 0
        self.info = None
        if info and self.on_remove:
            self.on_remove(info)

    def _handle_report(self, _ctx, _result, _sender, _rtype, report_id, report, length) -> None:
        if not self.on_report or not report or length <= 0:
            return
        data = bytes(report[:length])
        # 不同版本的 IOHIDFamily 对“缓冲区是否包含 report ID”并不一致：
        # MaxInputReportSize 含 ID，因此用长度判断，避免把值 1（电源键）误当 ID 剥掉。
        expected = None
        if self.info and self.info.max_input_report:
            expected = self.info.max_input_report - 1
        if (
            report_id
            and len(data) > 1
            and data[0] == report_id
            and (expected is None or len(data) == expected + 1)
        ):
            data = data[1:]
        self.on_report(int(report_id), data)

    def _handle_value(self, _ctx, _result, _sender, value) -> None:
        if not self.on_value or not value:
            return
        element = IOKIT.IOHIDValueGetElement(value)
        if not element:
            return
        page = int(IOKIT.IOHIDElementGetUsagePage(element))
        usage = int(IOKIT.IOHIDElementGetUsage(element))
        amount = int(IOKIT.IOHIDValueGetIntegerValue(value))
        self.on_value(page, usage, amount)

    # ------------------------------------------------------------------ loop
    def _tick(self, _timer, _info) -> None:
        # 让 Python 解释器有机会运行信号处理器（CFRunLoop 阻塞期间不会自动运行）。
        pass

    def _arm_tick_timer(self) -> None:
        mode = self._mode
        timer = IOKIT.CFRunLoopTimerCreate(
            None,
            IOKIT.CFAbsoluteTimeGetCurrent() + 0.1,
            0.2,
            0,
            0,
            self._tick_cb,
            None,
        )
        if timer:
            IOKIT.CFRunLoopAddTimer(self._run_loop, timer, mode)
            self._timer = timer

    def run(self, seconds: float | None = None) -> None:
        self._running = True
        self._run_loop = cf.run_loop_current()
        self._arm_tick_timer()
        if seconds is not None:
            def _stop_later() -> None:
                time.sleep(max(0.05, seconds))
                self._running = False
                cf.run_loop_stop(self._run_loop)

            threading.Thread(target=_stop_later, daemon=True).start()
        try:
            cf.run_loop_run()
        finally:
            self._running = False
            self._disarm_tick_timer()

    def stop(self) -> None:
        self._running = False
        loop = getattr(self, "_run_loop", 0) or cf.run_loop_current()
        cf.run_loop_stop(loop)

    def _disarm_tick_timer(self) -> None:
        if self._timer:
            IOKIT.CFRunLoopTimerInvalidate(self._timer)
            cf.release(self._timer)
            self._timer = 0

    def close(self) -> None:
        if self._manager:
            run_loop = cf.run_loop_current()
            try:
                IOKIT.IOHIDManagerUnscheduleFromRunLoop(self._manager, run_loop, self._mode)
                IOKIT.IOHIDManagerClose(self._manager, 0)
            finally:
                cf.release(self._manager.value)
                self._manager = ctypes.c_void_p()
                self.device = 0


def enumerate_devices(
    *, vendor_id: int | None = None, product_id: int | None = None, product: str | None = None
) -> list[DeviceInfo]:
    """同步枚举匹配的设备（最多等 0.5 秒）。"""
    monitor = HIDMonitor(
        vendor_id=vendor_id, product_id=product_id, product=product, seize=False
    )
    monitor.open()
    try:
        monitor.run(0.5)
        devices = IOKIT.IOHIDManagerCopyDevices(monitor._manager)
        if not devices:
            return []
        try:
            count = cf.CF.CFSetGetCount(devices)
            if count <= 0:
                return []
            array = (c_void_p * count)()
            cf.CF.CFSetGetValues(devices, array)
            return [device_info(int(ref)) for ref in array if ref]
        finally:
            cf.release(devices)
    finally:
        monitor.close()


def hid_listen_access() -> str:
    """返回输入监控权限状态：granted / denied / unknown / unsupported。"""
    if not hasattr(IOKIT, "IOHIDCheckAccess"):
        return "unsupported"
    try:
        code = int(IOKIT.IOHIDCheckAccess(1))  # kIOHIDRequestTypeListenEvent
    except Exception:
        return "unknown"
    return {0: "granted", 1: "denied"}.get(code, "unknown")
