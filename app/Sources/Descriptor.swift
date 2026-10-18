import Foundation

struct HIDArrayField {
    var reportID: UInt32
    var bitOffset: Int
    var reportSize: Int
    var reportCount: Int
    var usagePage: UInt32
    var logicalMin: Int
    var logicalMax: Int
    var usages: [UInt32]
    var usageMin: UInt32?
    var usageMax: UInt32?

    /// 报告原始值 -> usage。枚举用法时 1..N 是下标；范围用法时值就是 usage。
    func resolve(_ value: Int) -> UInt32? {
        if !usages.isEmpty {
            if logicalMin == 0, value >= 0, value < usages.count { return usages[value] }
            if logicalMin >= 1, value >= 1, value <= usages.count { return usages[value - 1] }
            if let exact = usages.first(where: { Int($0) == value }) { return exact }
        }
        if let minValue = usageMin, let maxValue = usageMax,
           value >= Int(minValue), value <= Int(maxValue) {
            return UInt32(value)
        }
        return nil
    }
}

final class HIDDescriptor {
    private(set) var fields: [UInt32: [HIDArrayField]] = [:]

    init(data: Data) {
        parse(data)
    }

    private struct Globals {
        var usagePage: UInt32 = 0
        var logicalMin: Int = 0
        var logicalMax: Int = 0
        var reportSize: Int = 0
        var reportCount: Int = 0
        var reportID: UInt32 = 0
    }

    private func parse(_ data: Data) {
        var globals = Globals()
        var usages: [UInt32] = []
        var usageMin: UInt32?
        var usageMax: UInt32?
        var bitOffsets: [UInt32: Int] = [:]
        var stack: [(Globals, [UInt32], UInt32?, UInt32?)] = []

        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            let prefix = bytes[index]
            index += 1
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            let type = (prefix >> 2) & 0x03
            let tag = (prefix >> 4) & 0x0F
            var value = 0
            if size > 0 {
                guard index + size <= bytes.count else { break }
                for i in 0..<size {
                    value |= Int(bytes[index + i]) << (8 * i)
                }
                index += size
            }

            switch type {
            case 1: // Global
                switch tag {
                case 0x0: globals.usagePage = UInt32(value)
                case 0x1: globals.logicalMin = signed(value, bits: size * 8)
                case 0x2: globals.logicalMax = signed(value, bits: size * 8)
                case 0x7: globals.reportSize = value
                case 0x8:
                    globals.reportID = UInt32(value)
                    if bitOffsets[globals.reportID] == nil { bitOffsets[globals.reportID] = 0 }
                case 0x9: globals.reportCount = value
                case 0xA: stack.append((globals, usages, usageMin, usageMax))
                case 0xB:
                    if let saved = stack.popLast() {
                        globals = saved.0
                        usages = saved.1
                        usageMin = saved.2
                        usageMax = saved.3
                    }
                default: break
                }
            case 2: // Local
                switch tag {
                case 0x0:
                    let usage = UInt32(value & 0xFFFF)
                    usages.append(usage)
                    if value > 0xFFFF { globals.usagePage = UInt32((value >> 16) & 0xFFFF) }
                case 0x1: usageMin = UInt32(value)
                case 0x2: usageMax = UInt32(value)
                default: break
                }
            default: // Main
                let reportID = globals.reportID
                if tag == 0x8 { // Input
                    let isConstant = (value & 0x01) != 0
                    let isVariable = (value & 0x02) != 0
                    let bits = globals.reportSize * globals.reportCount
                    if !isConstant && !isVariable && globals.reportCount > 0 {
                        let field = HIDArrayField(
                            reportID: reportID,
                            bitOffset: bitOffsets[reportID] ?? 0,
                            reportSize: globals.reportSize,
                            reportCount: globals.reportCount,
                            usagePage: globals.usagePage,
                            logicalMin: globals.logicalMin,
                            logicalMax: globals.logicalMax,
                            usages: usages,
                            usageMin: usageMin,
                            usageMax: usageMax
                        )
                        fields[reportID, default: []].append(field)
                    }
                    bitOffsets[reportID] = (bitOffsets[reportID] ?? 0) + bits
                }
                usages = []
                usageMin = nil
                usageMax = nil
            }
        }
    }

    private func signed(_ value: Int, bits: Int) -> Int {
        guard bits > 0, bits < 64 else { return value }
        let signBit = 1 << (bits - 1)
        return (value & signBit) != 0 ? value - (1 << bits) : value
    }

    func decode(reportID: UInt32, payload: [UInt8]) -> [(page: UInt32, usage: UInt32)] {
        var result: [(UInt32, UInt32)] = []
        for field in fields[reportID] ?? [] {
            for slot in 0..<field.reportCount {
                let raw = bits(payload, offset: field.bitOffset + slot * field.reportSize,
                               size: field.reportSize)
                guard raw != 0, let usage = field.resolve(raw) else { continue }
                result.append((field.usagePage, usage))
            }
        }
        return result
    }

    private func bits(_ payload: [UInt8], offset: Int, size: Int) -> Int {
        var value = 0
        for i in 0..<size {
            let bit = offset + i
            let byteIndex = bit / 8
            guard byteIndex < payload.count else { return value }
            if (payload[byteIndex] >> UInt8(bit % 8)) & 1 == 1 {
                value |= 1 << i
            }
        }
        return value
    }

    var summary: String {
        var lines: [String] = []
        for (reportID, items) in fields.sorted(by: { $0.key < $1.key }) {
            for item in items {
                if item.usages.isEmpty {
                    lines.append("report \(reportID)：\(item.reportCount)×\(item.reportSize)bit，usage 范围")
                } else {
                    lines.append("report \(reportID)：\(item.reportCount)×\(item.reportSize)bit，\(item.usages.count) 个用法")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
