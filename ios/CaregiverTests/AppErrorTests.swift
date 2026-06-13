import XCTest
@testable import Caregiver

final class AppErrorTests: XCTestCase {
    func testForbiddenMessage() {
        XCTAssertEqual(AppError.forStatus(403, serverMessage: nil).message,
                       "You don't have permission to do that.")
    }

    func testBadRequestSurfacesServerMessage() {
        XCTAssertEqual(AppError.forStatus(400, serverMessage: "systolic is required").message,
                       "systolic is required")
    }

    func testNotFoundMessage() {
        XCTAssertEqual(AppError.forStatus(404, serverMessage: nil).message, "Not found.")
    }

    func testTransportMessage() {
        XCTAssertEqual(AppError.transport.message, "No connection — please try again.")
    }
}
