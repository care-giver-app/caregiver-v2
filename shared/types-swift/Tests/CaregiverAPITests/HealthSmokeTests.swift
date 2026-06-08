import XCTest
import OpenAPIURLSession
@testable import CaregiverAPI

final class HealthSmokeTests: XCTestCase {
    func testHealthRoundTripsAgainstDevURL() async throws {
        guard let urlString = ProcessInfo.processInfo.environment["CAREGIVER_DEV_URL"],
              let url = URL(string: urlString) else {
            throw XCTSkip("CAREGIVER_DEV_URL not set; skipping live smoke.")
        }

        let client = Client(serverURL: url, transport: URLSessionTransport())
        let response = try await client.getHealth()

        switch response {
        case .ok(let ok):
            let payload = try ok.body.json
            XCTAssertEqual(payload.status, .ok)
            XCTAssertFalse(payload.version.isEmpty)
        default:
            XCTFail("Expected 200, got \(response)")
        }
    }
}
