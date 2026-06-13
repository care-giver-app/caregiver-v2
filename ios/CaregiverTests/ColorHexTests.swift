import XCTest
import SwiftUI
@testable import Caregiver

final class ColorHexTests: XCTestCase {
    func testParsesSixDigitHexWithHash() {
        let c = Color(hex: "#1F6FEB")
        XCTAssertNotNil(c.rgbaComponents)
        let rgba = c.rgbaComponents!
        XCTAssertEqual(rgba.r, 0x1F / 255.0, accuracy: 0.01)
        XCTAssertEqual(rgba.g, 0x6F / 255.0, accuracy: 0.01)
        XCTAssertEqual(rgba.b, 0xEB / 255.0, accuracy: 0.01)
    }

    func testParsesWithoutHash() {
        XCTAssertNotNil(Color(hex: "30A46C").rgbaComponents)
    }

    func testBadInputFallsBackToGray() {
        let c = Color(hex: "not-a-color")
        XCTAssertNotNil(c.rgbaComponents) // fallback, not a crash
    }
}
