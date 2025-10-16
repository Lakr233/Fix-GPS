import XCTest
@testable import Fix_GPS

final class Fix_GPSTests: XCTestCase {
    func testReadingTimestampFromHEIC() throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "B0000007", withExtension: "heic") else {
            XCTFail("Missing test resource B0000007.heic in test bundle")
            return
        }
        print("Testing with file at URL: \(url)")
        let worker = Worker()
        let date = worker.readingTimestamp(imageFile: url)
        print("Extracted date: \(String(describing: date))")
        XCTAssertNotNil(date, "Expected non-nil timestamp from HEIC metadata or file attributes")
    }
}

