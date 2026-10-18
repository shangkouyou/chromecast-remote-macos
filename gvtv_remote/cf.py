"""CoreFoundation 的极简 ctypes 绑定（不依赖 PyObjC）。

只实现本工程用到的部分：CFString / CFNumber / CFData / CFDictionary /
CFArray / CFSet，以及 CFRunLoop。所有对象都显式释放，避免常驻进程泄漏。
"""
from __future__ import annotations

import ctypes
from ctypes import (
    POINTER,
    byref,
    c_bool,
    c_char_p,
    c_double,
    c_int32,
    c_int64,
    c_long,
    c_uint8,
    c_uint32,
    c_void_p,
)

CF = ctypes.CDLL(
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
)

kCFStringEncodingUTF8 = 0x08000100
kCFNumberSInt32Type = 3
kCFNumberSInt64Type = 4
kCFNumberDoubleType = 13

# ---------------------------------------------------------------- signatures
CF.CFRelease.argtypes = [c_void_p]
CF.CFRelease.restype = None

CF.CFStringCreateWithCString.argtypes = [c_void_p, c_char_p, c_uint32]
CF.CFStringCreateWithCString.restype = c_void_p

CF.CFStringGetCString.argtypes = [c_void_p, c_char_p, c_long, c_uint32]
CF.CFStringGetCString.restype = c_bool

CF.CFStringGetLength.argtypes = [c_void_p]
CF.CFStringGetLength.restype = c_long

CF.CFNumberCreate.argtypes = [c_void_p, c_int32, c_void_p]
CF.CFNumberCreate.restype = c_void_p

CF.CFNumberGetValue.argtypes = [c_void_p, c_int32, c_void_p]
CF.CFNumberGetValue.restype = c_bool

CF.CFDataGetLength.argtypes = [c_void_p]
CF.CFDataGetLength.restype = c_long

CF.CFDataGetBytePtr.argtypes = [c_void_p]
CF.CFDataGetBytePtr.restype = POINTER(c_uint8)

CF.CFGetTypeID.argtypes = [c_void_p]
CF.CFGetTypeID.restype = c_long

CF.CFStringGetTypeID.argtypes = []
CF.CFStringGetTypeID.restype = c_long

CF.CFNumberGetTypeID.argtypes = []
CF.CFNumberGetTypeID.restype = c_long

CF.CFDataGetTypeID.argtypes = []
CF.CFDataGetTypeID.restype = c_long

CF.CFDictionaryCreate.argtypes = [
    c_void_p,
    POINTER(c_void_p),
    POINTER(c_void_p),
    c_long,
    c_void_p,
    c_void_p,
]
CF.CFDictionaryCreate.restype = c_void_p

CF.CFDictionarySetValue.argtypes = [c_void_p, c_void_p, c_void_p]
CF.CFDictionarySetValue.restype = None

CF.CFArrayCreate.argtypes = [c_void_p, POINTER(c_void_p), c_long, c_void_p]
CF.CFArrayCreate.restype = c_void_p

CF.CFSetGetCount.argtypes = [c_void_p]
CF.CFSetGetCount.restype = c_long

CF.CFSetGetValues.argtypes = [c_void_p, POINTER(c_void_p)]
CF.CFSetGetValues.restype = None

CF.CFRunLoopGetCurrent.argtypes = []
CF.CFRunLoopGetCurrent.restype = c_void_p

CF.CFRunLoopRunInMode.argtypes = [c_void_p, c_double, c_bool]
CF.CFRunLoopRunInMode.restype = c_int32

CF.CFRunLoopStop.argtypes = [c_void_p]
CF.CFRunLoopStop.restype = None

CF.CFRunLoopRun.argtypes = []
CF.CFRunLoopRun.restype = None


def _sym_addr(name: str) -> int:
    """取 CoreFoundation 导出结构体符号的地址。"""
    return ctypes.addressof(ctypes.c_char.in_dll(CF, name))


kCFTypeDictionaryKeyCallBacks = _sym_addr("kCFTypeDictionaryKeyCallBacks")
kCFTypeDictionaryValueCallBacks = _sym_addr("kCFTypeDictionaryValueCallBacks")
kCFTypeArrayCallBacks = _sym_addr("kCFTypeArrayCallBacks")

_string_cache: dict[str, int] = {}


def cfstr(value: str) -> int:
    """创建（并缓存）一个 CFStringRef。"""
    cached = _string_cache.get(value)
    if cached is not None:
        return cached
    ref = CF.CFStringCreateWithCString(None, value.encode("utf-8"), kCFStringEncodingUTF8)
    if not ref:
        raise MemoryError("CFStringCreateWithCString failed")
    _string_cache[value] = ref
    return ref


def cfnum(value: int) -> int:
    v = c_int64(int(value))
    return CF.CFNumberCreate(None, kCFNumberSInt64Type, byref(v))


def cfdict(items: dict) -> int:
    n = len(items)
    keys = (c_void_p * n)()
    values = (c_void_p * n)()
    for i, (k, v) in enumerate(items.items()):
        keys[i] = cfstr(k) if isinstance(k, str) else k
        if isinstance(v, str):
            values[i] = cfstr(v)
        elif isinstance(v, int):
            values[i] = cfnum(v)
        else:
            values[i] = v
    return CF.CFDictionaryCreate(
        None,
        keys,
        values,
        n,
        kCFTypeDictionaryKeyCallBacks,
        kCFTypeDictionaryValueCallBacks,
    )


def cfarray(values: list[int]) -> int:
    n = len(values)
    arr = (c_void_p * n)()
    for i, v in enumerate(values):
        arr[i] = v
    return CF.CFArrayCreate(None, arr, n, kCFTypeArrayCallBacks)


def release(ref: int | None) -> None:
    if ref:
        CF.CFRelease(ref)


def to_py(ref: int):
    """把 CFString / CFNumber / CFData 转成 Python 值，其它返回 None。"""
    if not ref:
        return None
    tid = CF.CFGetTypeID(ref)
    if tid == CF.CFStringGetTypeID():
        length = CF.CFStringGetLength(ref)
        buf = ctypes.create_string_buffer(max(8, length * 4 + 1))
        if CF.CFStringGetCString(ref, buf, len(buf), kCFStringEncodingUTF8):
            return buf.value.decode("utf-8", "replace")
        return None
    if tid == CF.CFNumberGetTypeID():
        num = c_int64(0)
        if CF.CFNumberGetValue(ref, kCFNumberSInt64Type, byref(num)):
            return num.value
        return None
    if tid == CF.CFDataGetTypeID():
        length = CF.CFDataGetLength(ref)
        ptr = CF.CFDataGetBytePtr(ref)
        return bytes(ptr[:length])
    return None


# ------------------------------------------------------- run loop helpers
def run_loop_current() -> int:
    return CF.CFRunLoopGetCurrent()


def run_loop_run_in_mode(mode: int, seconds: float, return_after: bool = False) -> int:
    return CF.CFRunLoopRunInMode(mode, seconds, return_after)


def run_loop_run() -> None:
    CF.CFRunLoopRun()


def run_loop_stop(loop: int) -> None:
    CF.CFRunLoopStop(loop)
