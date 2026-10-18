import CoreFoundation
import Foundation
import IOKit
import IOKit.hid

enum HIDError: LocalizedError {
    case createFailed
    case openFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .createFailed: return "无法创建 IOHIDManager"
        case .openFailed(let code):
            return String(format: "IOHIDManagerOpen 失败：0x%08X", UInt32(bitPattern: code))
        }
    }
}

final class HIDController {
    struct DeviceInfo {
        var product: String = ""
        var manufacturer: String = ""
        var serial: String = ""
        var transport: String = ""
        var vendorID: Int = 0
        var productID: Int = 0
        var maxInputReport: Int = 0
        var descriptorData: Data?

        var vidPid: String { String(format: "%04x:%04x", vendorID, productID) }
    }

    var onDevice: ((DeviceInfo) -> Void)?
    var onRemove: (() -> Void)?
    var onReport: ((UInt32, [UInt8]) -> Void)?

    private(set) var seized = false
    private(set) var info: DeviceInfo?
    private(set) var descriptor: HIDDescriptor?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    private let vendorID: Int
    private let productID: Int
    private let productName: String?
    private var prefersSeize: Bool

    init(vendorID: Int, productID: Int, product: String? = nil, seize: Bool) {
        self.vendorID = vendorID
        self.productID = productID
        self.productName = product
        self.prefersSeize = seize
    }

    func start() throws {
        stop()
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        var matching: [String: Any] = [:]
        if vendorID != 0 { matching[kIOHIDVendorIDKey] = vendorID }
        if productID != 0 { matching[kIOHIDProductIDKey] = productID }
        if matching.isEmpty, let productName, !productName.isEmpty {
            matching[kIOHIDProductKey] = productName
        }
        if matching.isEmpty {
            throw HIDError.createFailed
        }
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, hidDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, hidDeviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(mgr, hidInputReport, context)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        var result = IOHIDManagerOpen(
            mgr, IOOptionBits(prefersSeize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess && prefersSeize {
            prefersSeize = false
            result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            manager = nil
            throw HIDError.openFailed(result)
        }
        seized = prefersSeize
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        device = nil
        info = nil
        descriptor = nil
        seized = false
    }

    fileprivate func handleDevice(_ device: IOHIDDevice) {
        self.device = device
        var deviceInfo = DeviceInfo()
        deviceInfo.product = stringProperty(device, kIOHIDProductKey)
        deviceInfo.manufacturer = stringProperty(device, kIOHIDManufacturerKey)
        deviceInfo.serial = stringProperty(device, kIOHIDSerialNumberKey)
        deviceInfo.transport = stringProperty(device, kIOHIDTransportKey)
        deviceInfo.vendorID = numberProperty(device, kIOHIDVendorIDKey)
        deviceInfo.productID = numberProperty(device, kIOHIDProductIDKey)
        deviceInfo.maxInputReport = numberProperty(device, kIOHIDMaxInputReportSizeKey)
        if let data = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data {
            deviceInfo.descriptorData = data
            descriptor = HIDDescriptor(data: data)
        }
        info = deviceInfo
        onDevice?(deviceInfo)
    }

    fileprivate func handleRemoval() {
        info = nil
        descriptor = nil
        device = nil
        onRemove?()
    }

    fileprivate func handleReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        var bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
        if reportID != 0, bytes.count > 1, bytes[0] == UInt8(reportID & 0xFF) {
            if info?.maxInputReport == 0 || bytes.count == (info?.maxInputReport ?? 0) {
                bytes.removeFirst()
            }
        }
        onReport?(reportID, bytes)
    }

    private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
        IOHIDDeviceGetProperty(device, key as CFString) as? String ?? ""
    }

    private func numberProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }
}

private func hidDeviceMatched(context: UnsafeMutableRawPointer?, result: IOReturn,
                              sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    Unmanaged<HIDController>.fromOpaque(context).takeUnretainedValue().handleDevice(device)
}

private func hidDeviceRemoved(context: UnsafeMutableRawPointer?, result: IOReturn,
                              sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    Unmanaged<HIDController>.fromOpaque(context).takeUnretainedValue().handleRemoval()
}

private func hidInputReport(context: UnsafeMutableRawPointer?, result: IOReturn,
                            sender: UnsafeMutableRawPointer?, type: IOHIDReportType,
                            reportID: UInt32, report: UnsafeMutablePointer<UInt8>,
                            reportLength: CFIndex) {
    guard let context else { return }
    Unmanaged<HIDController>.fromOpaque(context).takeUnretainedValue()
        .handleReport(reportID: reportID, report: report, length: reportLength)
}
