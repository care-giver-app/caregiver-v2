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

    func testNotFoundIsTheStatusNotTheWording() {
        XCTAssertTrue(AppError.forStatus(404, serverMessage: nil).isNotFound)
        XCTAssertEqual(AppError.forStatus(404, serverMessage: nil).status, 404)
        XCTAssertFalse(AppError(message: "Not found.").isNotFound,
                       "a message that happens to read \"Not found.\" is not a 404")
        XCTAssertFalse(AppError.forStatus(403, serverMessage: nil).isNotFound)
        XCTAssertFalse(AppError.transport.isNotFound)
    }

    func testAnUndocumentedStatusKeepsItsStatus() {
        let error = AppError.forStatus(500, serverMessage: nil)
        XCTAssertEqual(error.message, AppError.unknown.message)
        XCTAssertEqual(error.status, 500)
    }
}
