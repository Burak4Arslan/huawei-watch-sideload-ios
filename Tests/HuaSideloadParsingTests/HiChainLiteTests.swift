import XCTest
@testable import HuaSideloadParsing

final class HiChainLiteTests: XCTestCase {
    private let pin = Array(UInt8(0)...UInt8(15))
    private let server = Array(UInt8(16)...UInt8(31))
    private let client = Array(UInt8(32)...UInt8(47))

    // Independent reference vectors: Python hashlib/hmac, matching the source
    // Gadgetbridge algorithm (uppercase ASCII hex, 1000-round PBKDF2 where selected).
    func testHMACInteroperabilityVector() throws {
        let auth = try HiChainLite.authentication(pin: pin, serverNonce: server, clientNonce: client, authAlgo: 0)
        XCTAssertEqual(auth.request.value(0x01)?.hexCompact, "E2A4D416D9534E59910A53D4D0179E3175EDF3C9D8B63A53DC557DFF95A7F937")
        XCTAssertEqual(auth.wrappingKey.hexCompact, "4AD1B01315107C2A4744446DA9F5E1AE")
        XCTAssertEqual(auth.expectedResponse.hexCompact, "8039871590527405CE2800CE48686B53CA405D38EA91F8D89697378E466B9FE3")
        XCTAssertEqual(auth.request.value(0x02), [0, 1] + client)
        XCTAssertEqual(auth.request.value(0x03), [0])
    }

    func testPBKDF2InteroperabilityVector() throws {
        let auth = try HiChainLite.authentication(pin: pin, serverNonce: server, clientNonce: client, authAlgo: 1)
        XCTAssertEqual(auth.request.value(0x01)?.hexCompact, "86C94EAAB1B88AA6C3910864D7020C3A856D72C2E4669445D524B8493640EB1B")
        XCTAssertEqual(auth.wrappingKey.hexCompact, "214E812571DE5DD5D375597214ADACC6")
        XCTAssertEqual(auth.expectedResponse.hexCompact, "BD43757BD303C5BD4C1DEEB2C540855EBE47ED4E3F28DA687E908B927C21671E")
    }

    func testRejectsWrongAuthenticationResponse() {
        let expected = [UInt8](repeating: 0xAB, count: 32)
        XCTAssertTrue(HiChainLite.validates(expected, expected: expected))
        XCTAssertFalse(HiChainLite.validates(Array(expected.dropLast()), expected: expected))
        XCTAssertFalse(HiChainLite.validates(expected + [0], expected: expected))
        var changed = expected
        changed[31] ^= 1
        XCTAssertFalse(HiChainLite.validates(changed, expected: expected))
        XCTAssertFalse(HiChainLite.validates([], expected: []))
    }

    func testRejectsMissingOrMalformedNonceAndUnknownAlgorithm() {
        XCTAssertThrowsError(try HiChainLite.authentication(pin: pin, serverNonce: [], clientNonce: client, authAlgo: 0))
        XCTAssertThrowsError(try HiChainLite.authentication(pin: [], serverNonce: server, clientNonce: client, authAlgo: 0))
        XCTAssertThrowsError(try HiChainLite.authentication(pin: pin, serverNonce: server, clientNonce: [0], authAlgo: 0))
        XCTAssertThrowsError(try HiChainLite.authentication(pin: pin, serverNonce: server, clientNonce: client, authAlgo: 2))
    }

    func testSupportGateFailsClosed() {
        var link = LinkInfo(HuaweiTLV().with(0x05, [0, 1] + server).with(0x07, [2]))
        XCTAssertEqual(link.serverNonce, server)
        XCTAssertTrue(HiChainLite.supports(link, authType: 1))
        XCTAssertTrue(HiChainLite.supports(link, authType: 2))
        XCTAssertFalse(HiChainLite.supports(link, authType: -1))
        link.authVersion = 2
        XCTAssertFalse(HiChainLite.supports(link, authType: 1))
        link.authVersion = 1
        link.encryptMethod = 1
        XCTAssertFalse(HiChainLite.supports(link, authType: 1))
    }

    func testCounterEndianAndWrap() {
        var counter: UInt32 = 0x01020303
        XCTAssertEqual(HiChainLite.nextIV(counter: &counter), [UInt8](repeating: 0, count: 12) + [1, 2, 3, 4])
        counter = UInt32.max
        XCTAssertEqual(HiChainLite.nextIV(counter: &counter), [UInt8](repeating: 0, count: 15) + [1])
    }

    func testIdentityIsStableAndLocallyAdministered() throws {
        let a = HiChainLite.identity(seed: pin)
        let b = HiChainLite.identity(seed: pin)
        XCTAssertEqual(a.serial, b.serial)
        XCTAssertEqual(a.mac, b.mac)
        XCTAssertEqual(a.serial.count, 6)
        let macText = String(decoding: a.mac, as: UTF8.self)
        let first = try XCTUnwrap(UInt8(String(macText.prefix(2)), radix: 16))
        XCTAssertEqual(first & 0x03, 0x02)
        XCTAssertEqual(macText.count, 17)
    }

    func testBondEncryptsSecretAndRejectsInvalidKeyLengths() throws {
        let iv = [UInt8](repeating: 0, count: 16)
        let secret = [UInt8](repeating: 0x55, count: 16)
        let key = [UInt8](repeating: 0xA5, count: 16)
        let bond = try HiChainLite.bond(serial: [1, 2], secret: secret, wrappingKey: key, iv: iv)
        let cipher = try XCTUnwrap(bond.value(0x06))
        XCTAssertEqual(cipher.count, 32)
        XCTAssertEqual(try HCrypto.cbcDecrypt(cipher, key: key, iv: iv), secret)
        XCTAssertThrowsError(try HiChainLite.bond(serial: [], secret: [], wrappingKey: key, iv: iv))
        XCTAssertThrowsError(try HiChainLite.bond(serial: [], secret: secret, wrappingKey: [1], iv: iv))
    }
}
