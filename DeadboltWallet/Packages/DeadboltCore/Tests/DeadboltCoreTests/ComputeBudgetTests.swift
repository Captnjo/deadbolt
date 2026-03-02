import XCTest
@testable import DeadboltCore

final class ComputeBudgetTests: XCTestCase {

    func testSetComputeUnitLimitData() {
        let ix = ComputeBudgetProgram.setComputeUnitLimit(200_000)

        XCTAssertEqual(ix.data.count, 5)
        XCTAssertEqual(ix.data[0], 2) // instruction type

        // 200_000 = 0x00030D40 LE -> [0x40, 0x0D, 0x03, 0x00]
        XCTAssertEqual(ix.data[1], 0x40)
        XCTAssertEqual(ix.data[2], 0x0D)
        XCTAssertEqual(ix.data[3], 0x03)
        XCTAssertEqual(ix.data[4], 0x00)
    }

    func testSetComputeUnitPriceData() {
        let ix = ComputeBudgetProgram.setComputeUnitPrice(50_000)

        XCTAssertEqual(ix.data.count, 9)
        XCTAssertEqual(ix.data[0], 3) // instruction type

        // 50_000 = 0xC350 LE -> [0x50, 0xC3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        XCTAssertEqual(ix.data[1], 0x50)
        XCTAssertEqual(ix.data[2], 0xC3)
        XCTAssertEqual(ix.data[3], 0x00)
        XCTAssertEqual(ix.data[4], 0x00)
    }

    func testComputeBudgetProgramId() {
        let ix = ComputeBudgetProgram.setComputeUnitLimit(100)
        XCTAssertEqual(ix.programId.base58, "ComputeBudget111111111111111111111111111111")
        XCTAssertTrue(ix.accounts.isEmpty)
    }
}
