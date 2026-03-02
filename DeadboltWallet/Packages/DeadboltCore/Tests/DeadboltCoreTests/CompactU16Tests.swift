import XCTest
@testable import DeadboltCore

final class CompactU16Tests: XCTestCase {

    func testEncodeZero() {
        XCTAssertEqual(CompactU16.encode(0), [0x00])
    }

    func testEncodeSingleByte() {
        // Values 0-127 are 1 byte
        XCTAssertEqual(CompactU16.encode(1), [0x01])
        XCTAssertEqual(CompactU16.encode(127), [0x7F])
    }

    func testEncodeTwoBytes() {
        // 128 = 0x80 -> low 7 bits = 0x00 with continuation, then 0x01
        XCTAssertEqual(CompactU16.encode(128), [0x80, 0x01])
        // 255 = 0xFF -> low 7 bits = 0x7F with continuation, then 0x01
        XCTAssertEqual(CompactU16.encode(255), [0xFF, 0x01])
        // 16383 = 0x3FFF -> [0xFF, 0x7F]
        XCTAssertEqual(CompactU16.encode(16383), [0xFF, 0x7F])
    }

    func testEncodeThreeBytes() {
        // 16384 = 0x4000 -> [0x80, 0x80, 0x01]
        XCTAssertEqual(CompactU16.encode(16384), [0x80, 0x80, 0x01])
        // 65535 = 0xFFFF -> [0xFF, 0xFF, 0x03]
        XCTAssertEqual(CompactU16.encode(65535), [0xFF, 0xFF, 0x03])
    }

    func testRoundTrip() throws {
        let testValues: [UInt16] = [0, 1, 127, 128, 255, 256, 16383, 16384, 32767, 65535]
        for value in testValues {
            let encoded = CompactU16.encode(value)
            let (decoded, bytesRead) = try CompactU16.decode(Data(encoded), offset: 0)
            XCTAssertEqual(decoded, value, "Round-trip failed for \(value)")
            XCTAssertEqual(bytesRead, encoded.count, "Bytes read mismatch for \(value)")
        }
    }

    func testDecodeAtOffset() throws {
        // Prefix some bytes, then encode 300 at offset 3
        var data = Data([0xAA, 0xBB, 0xCC])
        data.append(contentsOf: CompactU16.encode(300))
        let (decoded, bytesRead) = try CompactU16.decode(data, offset: 3)
        XCTAssertEqual(decoded, 300)
        XCTAssertEqual(bytesRead, 2)
    }

    func testDecodeUnexpectedEnd() {
        // Byte with continuation bit set but no next byte
        let data = Data([0x80])
        XCTAssertThrowsError(try CompactU16.decode(data, offset: 0))
    }
}
