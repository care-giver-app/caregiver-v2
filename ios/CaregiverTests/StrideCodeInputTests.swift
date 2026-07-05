import XCTest
@testable import Caregiver

final class StrideCodeInputTests: XCTestCase {
    func testPassesCleanDigitsThrough() {
        XCTAssertEqual(StrideCodeInput.sanitized("429", length: 6), "429")
        XCTAssertEqual(StrideCodeInput.sanitized("429315", length: 6), "429315")
    }

    func testStripsNonDigits() {
        XCTAssertEqual(StrideCodeInput.sanitized("4 2-9a", length: 6), "429")
        XCTAssertEqual(StrideCodeInput.sanitized("code", length: 6), "")
    }

    func testCapsAtLength() {
        XCTAssertEqual(StrideCodeInput.sanitized("4293157", length: 6), "429315")
        XCTAssertEqual(StrideCodeInput.sanitized("12345", length: 4), "1234")
    }

    func testPastedFormattedCode() {
        // Autofill / paste can arrive with separators in one shot.
        XCTAssertEqual(StrideCodeInput.sanitized("429 315", length: 6), "429315")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(StrideCodeInput.sanitized("", length: 6), "")
    }
}
