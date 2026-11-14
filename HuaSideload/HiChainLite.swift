// Experimental Swift port of Gadgetbridge's Auth-1 HiChain Lite path.
// Derived from HuaweiCrypto.java, DeviceConfig.java and GetAuthRequest.java.
// Gadgetbridge copyright (C) 2024 Damien Gaignon, Martin.JM; AGPL-3.0-or-later.
// Upstream: https://github.com/Freeyourgadget/Gadgetbridge
import CommonCrypto
import Foundation

enum HiChainLite {
    static let pinCommand: UInt8 = 0x2C
    static let authCommand: UInt8 = 0x13
    static let bondParamsCommand: UInt8 = 0x0F
    static let bondCommand: UInt8 = 0x0E

    struct Authentication {
        let request: HuaweiTLV
        let expectedResponse: [UInt8]
        let wrappingKey: [UInt8]
    }

    // Deliberately limited to the observed GT 2 Pro protocol. Do not treat an
    // arbitrary unrecognised security-negotiation result as HiChain Lite.
    static func supports(_ link: LinkInfo, authType: Int) -> Bool {
        link.authVersion == 1 && link.deviceSupportType == 2 && !link.usesGCM
            && [0, 1].contains(link.authAlgo) && [1, 2].contains(authType)
    }

    static func authentication(pin: [UInt8], serverNonce: [UInt8], clientNonce: [UInt8],
                               authAlgo: Int) throws -> Authentication {
        guard !pin.isEmpty, serverNonce.count == 16, clientNonce.count == 16,
              [0, 1].contains(authAlgo) else {
            throw HuaweiAuthError.unexpected("Invalid HiChain Lite PIN/nonce/algorithm")
        }
        let nonce = serverNonce + clientNonce
        let challenge = try digest(message: [0x01, 0x00], pin: pin, nonce: nonce, authAlgo: authAlgo)
        let response = try digest(message: [0x01, 0x10], pin: pin, nonce: nonce, authAlgo: authAlgo)
        return Authentication(
            request: HuaweiTLV().with(0x01, Array(challenge.prefix(32)))
                .with(0x02, [0x00, 0x01] + clientNonce).with(0x03, [UInt8(authAlgo)]),
            expectedResponse: Array(response.prefix(32)),
            wrappingKey: Array(challenge[32..<48]))
    }

    private static func digest(message: [UInt8], pin: [UInt8], nonce: [UInt8],
                               authAlgo: Int) throws -> [UInt8] {
        // GB.hexdump is uppercase compact hex, NOT the raw PIN or spaced hex.
        let pinHash = HCrypto.sha256(Array(pin.hexCompact.utf8))
        let digestSecret = PinCode.digestSecret(authVersion: 1)
        let key = zip(digestSecret, pinHash).map { $0.0 ^ $0.1 } + message
        let first: [UInt8]
        if authAlgo == 1 {
            // Gadgetbridge uses the UTF-8 hex strings for both password and salt.
            let password = key.hexCompact
            let salt = Array(nonce.hexCompact.utf8)
            var output = [UInt8](repeating: 0, count: 32)
            let status = password.withCString { passwordBytes in
                salt.withUnsafeBufferPointer { saltBytes in
                    output.withUnsafeMutableBufferPointer { outputBytes in
                        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes,
                            password.utf8.count, saltBytes.baseAddress, salt.count,
                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 1_000,
                            outputBytes.baseAddress, 32)
                    }
                }
            }
            guard status == kCCSuccess else { throw HuaweiAuthError.crypto("HiChain Lite PBKDF2 failed") }
            first = output
        } else {
            first = HCrypto.hmac(key: key, nonce)
        }
        return HCrypto.hmac(key: first, nonce) + first
    }

    static func validates(_ actual: [UInt8], expected: [UInt8]) -> Bool {
        guard actual.count == expected.count, actual.count == 32 else { return false }
        return zip(actual, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    // iOS does not expose the phone's Bluetooth MAC. Use an app-owned, stable,
    // locally administered protocol identity, never the watch's UUID as a MAC.
    static func identity(seed: [UInt8]) -> (serial: [UInt8], mac: [UInt8]) {
        var bytes = Array(HCrypto.sha256(seed).prefix(6))
        bytes[0] = (bytes[0] | 0x02) & 0xFE
        return (Array(Array(bytes.suffix(3)).hexCompact.utf8),
                Array(bytes.map { String(format: "%02X", $0) }.joined(separator: ":").utf8))
    }

    static func bondParameters(serial: [UInt8], mac: [UInt8]) -> HuaweiTLV {
        HuaweiTLV().with(0x01).with(0x03, serial).with(0x04, [0x02])
            .with(0x05).with(0x07, mac).with(0x09)
    }

    static func nextIV(counter: inout UInt32) -> [UInt8] {
        counter = counter == UInt32.max ? 1 : counter + 1
        return [UInt8](repeating: 0, count: 12) + [UInt8].bigEndian(counter)
    }

    static func bond(serial: [UInt8], secret: [UInt8], wrappingKey: [UInt8], iv: [UInt8]) throws -> HuaweiTLV {
        guard secret.count == 16, wrappingKey.count == 16, iv.count == 16 else {
            throw HuaweiAuthError.unexpected("Invalid HiChain Lite bonding key/IV")
        }
        return HuaweiTLV().with(0x01).with(0x03, [0x00]).with(0x05, serial)
            .with(0x06, try HCrypto.cbcEncrypt(secret, key: wrappingKey, iv: iv)).with(0x07, iv)
    }
}
