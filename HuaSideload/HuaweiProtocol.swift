import Foundation

// Huawei watch protocol.
// Ported to Swift from Gadgetbridge's (AGPL-3.0) Huawei code:
// codeberg.org/Freeyourgadget/Gadgetbridge: devices/huawei/HuaweiPacket.java, HuaweiTLV.java

enum HuaweiUUID {
    static let service = "FE86"
    static let write = "FE01"
    static let notify = "FE02"
}

enum HuaweiError: Error, CustomStringConvertible {
    case badMagic(UInt8)
    case badLength(Int)
    case badChecksum(expected: UInt16, actual: UInt16)
    case malformedTLV

    var description: String {
        switch self {
        case .badMagic(let b): return String(format: L("Bad magic byte: 0x%02X (expected 0x5A)", "Magic byte hatalı: 0x%02X (0x5A bekleniyordu)"), b)
        case .badLength(let n): return L("Bad packet length: \(n)", "Paket uzunluğu hatalı: \(n)")
        case .badChecksum(let e, let a): return String(format: L("Bad CRC: expected 0x%04X, computed 0x%04X", "CRC hatalı: beklenen 0x%04X, hesaplanan 0x%04X"), e, a)
        case .malformedTLV: return L("Malformed TLV", "TLV çözülemedi")
        }
    }
}

enum LogKind { case info, sent, received, success, error }

extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
    var hexCompact: String { map { String(format: "%02X", $0) }.joined() }

    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(decoding: chars[i..<(i + 2)], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(b)
            i += 2
        }
        self = bytes
    }

    static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        Swift.withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }
}

// CheckSums.getCRC16(seq, 0x0000) — CRC-16/XMODEM
enum CRC16 {
    static func compute<S: Sequence>(_ data: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt32 = 0
        for b in data {
            crc = ((crc >> 8) | (crc << 8)) & 0xFFFF
            crc ^= UInt32(b)
            crc ^= (crc & 0xFF) >> 4
            crc ^= (crc << 12) & 0xFFFF
            crc ^= ((crc & 0xFF) << 5) & 0xFFFF
        }
        return UInt16(crc & 0xFFFF)
    }
}

// Big-endian variable-length integer, 7 bits per byte
enum VarInt {
    static func encode(_ value: Int) -> [UInt8] {
        var size = 0
        var v = value
        repeat { size += 1; v >>= 7 } while v != 0

        var out = [UInt8](repeating: 0, count: size)
        v = value
        out[size - 1] = UInt8(v & 0x7F)
        var i = size - 2
        while i >= 0 {
            v >>= 7
            out[i] = UInt8((v & 0x7F) | 0x80)
            i -= 1
        }
        return out
    }

    static func decode(_ bytes: [UInt8], at offset: Int) -> (value: Int, size: Int)? {
        var result = 0
        var i = offset
        while i < bytes.count {
            let b = bytes[i]
            result += Int(b & 0x7F)
            if b & 0x80 == 0 { return (result, i - offset + 1) }
            result <<= 7
            i += 1
        }
        return nil
    }
}

struct HuaweiTLV {
    private(set) var items: [(tag: UInt8, value: [UInt8])] = []

    func with(_ tag: UInt8, _ value: [UInt8] = []) -> HuaweiTLV {
        var copy = self
        copy.items.append((tag, value))
        return copy
    }

    func serialize() -> [UInt8] {
        items.flatMap { [$0.tag] + VarInt.encode($0.value.count) + $0.value }
    }

    static func parse(_ bytes: [UInt8]) throws -> HuaweiTLV {
        var tlv = HuaweiTLV()
        var i = 0
        while i < bytes.count {
            let tag = bytes[i]
            i += 1
            // Encrypted payloads may end with one extra 0x00
            if i == bytes.count && tag == 0 { break }
            guard let size = VarInt.decode(bytes, at: i) else { throw HuaweiError.malformedTLV }
            i += size.size
            guard size.value >= 0, size.value <= bytes.count - i else { throw HuaweiError.malformedTLV }
            tlv.items.append((tag, Array(bytes[i..<(i + size.value)])))
            i += size.value
        }
        return tlv
    }

    func value(_ tag: UInt8) -> [UInt8]? {
        items.first { $0.tag == tag }?.value
    }

    func int(_ tag: UInt8) -> Int? {
        guard let v = value(tag), !v.isEmpty, v.count <= 8 else { return nil }
        return v.reduce(0) { $0 << 8 | Int($1) }
    }

    var description: String {
        items.map { String(format: "%02X=", $0.tag) + ($0.value.isEmpty ? "∅" : $0.value.hexCompact) }
            .joined(separator: " ")
    }
}

struct HuaweiPacket {
    static let magic: UInt8 = 0x5A
    static let resultSuccess = 0x186A0

    // Commands whose body is not TLV (HuaweiPacket.parseData)
    private static let nonTLVCommands: Set<[UInt8]> = [[0x0A, 0x05], [0x28, 0x06], [0x2C, 0x05], [0x1C, 0x05]]

    let serviceId: UInt8
    let commandId: UInt8
    let body: [UInt8]
    let tlv: HuaweiTLV?

    init(serviceId: UInt8, commandId: UInt8, body: [UInt8]) {
        self.serviceId = serviceId
        self.commandId = commandId
        self.body = body
        self.tlv = Self.nonTLVCommands.contains([serviceId, commandId]) ? nil : try? HuaweiTLV.parse(body)
    }

    var isEncrypted: Bool { tlv?.value(0x7C)?.first == 1 }
    var resultCode: Int? { tlv?.int(0x7F) }

    // HuaweiPacket.serializeUnsliced
    static func serialize(serviceId: UInt8, commandId: UInt8, body: [UInt8]) -> [UInt8] {
        let length = UInt16(2 + body.count + 1)
        var bytes: [UInt8] = [magic, UInt8(length >> 8), UInt8(length & 0xFF), 0x00, serviceId, commandId] + body
        let crc = CRC16.compute(bytes)
        bytes += [UInt8(crc >> 8), UInt8(crc & 0xFF)]
        return bytes
    }

    // HuaweiPacket.serializeSliced: every slice is at most sliceSize bytes
    static func serializeSliced(serviceId: UInt8, commandId: UInt8, body: [UInt8], sliceSize: Int) -> [[UInt8]] {
        let headerLength = 5
        let footerLength = 2
        let maxBodySize = sliceSize - headerLength - footerLength
        let packetCount = (body.count + 2 + maxBodySize - 1) / maxBodySize
        if packetCount <= 1 {
            return [serialize(serviceId: serviceId, commandId: commandId, body: body)]
        }

        var frames: [[UInt8]] = []
        var offset = 0
        var slice: UInt8 = 0x01
        var flag: UInt8 = 0x00
        for i in 0..<packetCount {
            let packetSize = min(sliceSize, body.count - offset + headerLength + footerLength)
            var contentSize = packetSize - headerLength - footerLength
            if i == packetCount - 1 { slice = 0x03 }

            var frame: [UInt8] = [magic] + .bigEndian(UInt16(packetSize - headerLength)) + [slice, flag]
            flag &+= 1
            if slice == 0x01 {
                frame += [serviceId, commandId]
                slice = 0x02
                contentSize -= 2
            }
            frame += body[offset..<(offset + contentSize)]
            offset += contentSize

            let crc = CRC16.compute(frame)
            frames.append(frame + .bigEndian(crc))
        }
        return frames
    }
}

// Reassembles notification bytes into complete packets (HuaweiPacket.parseData)
final class HuaweiPacketParser {
    private var pending: [UInt8] = []
    private var slices: [UInt8] = []

    func reset() {
        pending.removeAll()
        slices.removeAll()
    }

    func feed(_ data: [UInt8]) -> [Result<HuaweiPacket, HuaweiError>] {
        pending += data
        var results: [Result<HuaweiPacket, HuaweiError>] = []

        while !pending.isEmpty {
            guard pending[0] == HuaweiPacket.magic else {
                results.append(.failure(.badMagic(pending[0])))
                reset()
                break
            }
            guard pending.count >= 3 else { break }

            let expected = Int(pending[1]) << 8 | Int(pending[2])
            guard expected >= 1, expected <= 0x7FFF else {
                results.append(.failure(.badLength(expected)))
                reset()
                break
            }
            let frameLength = 3 + expected + 2
            guard pending.count >= frameLength else { break }

            let frame = Array(pending[0..<frameLength])
            pending.removeFirst(frameLength)

            let sliceFlag = frame[3]
            let isSliced = (1...3).contains(sliceFlag)
            let headerExtra = isSliced ? 2 : 1
            guard expected >= headerExtra else {
                results.append(.failure(.badLength(expected)))
                continue
            }

            let expectedCRC = UInt16(frame[3 + expected]) << 8 | UInt16(frame[4 + expected])
            let actualCRC = CRC16.compute(frame[0..<(3 + expected)])
            guard expectedCRC == actualCRC else {
                results.append(.failure(.badChecksum(expected: expectedCRC, actual: actualCRC)))
                slices.removeAll()
                continue
            }

            var payload = Array(frame[(3 + headerExtra)..<(3 + expected)])
            if isSliced {
                slices += payload
                guard sliceFlag == 3 else { continue }
                payload = slices
                slices.removeAll()
            }

            guard payload.count >= 2 else {
                results.append(.failure(.badLength(payload.count)))
                continue
            }
            results.append(.success(HuaweiPacket(serviceId: payload[0], commandId: payload[1], body: Array(payload.dropFirst(2)))))
        }
        return results
    }
}

// First step of every connection: unencrypted, no pairing needed (DeviceConfig.LinkParams)
enum LinkParams {
    static let serviceId: UInt8 = 0x01
    static let commandId: UInt8 = 0x01

    static func request() -> [UInt8] {
        let tlv = HuaweiTLV().with(0x01).with(0x02).with(0x03).with(0x04)
        return HuaweiPacket.serialize(serviceId: serviceId, commandId: commandId, body: tlv.serialize())
    }

    static func describe(_ tlv: HuaweiTLV) -> [String] {
        var lines: [String] = []
        if let v = tlv.int(0x01) { lines.append("Protocol version: \(v)") }
        if let v = tlv.int(0x02) { lines.append("Slice size: \(v)") }
        if let v = tlv.int(0x03) { lines.append("MTU: \(v)") }
        if let v = tlv.int(0x04) { lines.append("Interval: \(v)") }
        if let v = tlv.value(0x05), v.count >= 18 {
            lines.append("Auth version: \(v[1])")
            lines.append("Watch nonce: \(Array(v[2..<18]).hexCompact)")
        }
        if let v = tlv.int(0x07) { lines.append("Device support type: \(v)") }
        if let v = tlv.int(0x08) { lines.append("Auth algorithm: \(v)") }
        if let v = tlv.int(0x09) { lines.append("Bond status: \(v)") }
        if let v = tlv.int(0x0C) { lines.append("Encryption method: \(v)") }
        return lines
    }
}
