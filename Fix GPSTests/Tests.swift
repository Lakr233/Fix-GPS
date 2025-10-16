import XCTest
import ImageIO
@testable import Fix_GPS

final class WriteGPSTests: XCTestCase {
    func testWritingGPSDataToTempCopyAndCleanup() throws {
        // Locate the bundled test HEIC; never modify original
        let bundle = Bundle(for: type(of: self))
        guard let srcURL = bundle.url(forResource: "B0000007", withExtension: "HEIC") ??
                bundle.url(forResource: "B0000007", withExtension: "heic") else {
            XCTFail("Missing test resource B0000007.HEIC in test bundle")
            return
        }

        // Create temp directory and copy the HEIC there
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FixGPSTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpImageURL = tmpDir.appendingPathComponent("B0000007_copy.HEIC")
        try FileManager.default.copyItem(at: srcURL, to: tmpImageURL)

        // Prepare a CSV with a single record aligned to the image timestamp
        let worker = Worker()
        guard let date = worker.readingTimestamp(imageFile: tmpImageURL) else {
            XCTFail("Failed to read timestamp from temp HEIC copy")
            try? FileManager.default.removeItem(at: tmpDir)
            return
        }
        let ts = date.timeIntervalSince1970
        let csvURL = tmpDir.appendingPathComponent("record.csv")
        let header = "dataTime,longitude,latitude,altitude,heading,speed\n"
        let payload = String(format: "%.3f,%.6f,%.6f,%.2f,0,0\n", ts, 120.123456, 30.654321, 15.0)
        try (header + payload).write(to: csvURL, atomically: true, encoding: .utf8)

        // Execute the write path targeting the temp directory
        worker.executeCommandLineEx(locationRecord: csvURL.path, photoDirectory: tmpDir.path, overwrite: true)

        // Verify GPS metadata exists and is approximately correct
        let (lat, latRef, lon, lonRef, alt) = try readGPS(from: tmpImageURL)
        XCTAssertNotNil(lat, "Latitude should be present after write")
        XCTAssertNotNil(lon, "Longitude should be present after write")
        XCTAssertNotNil(alt, "Altitude should be present after write")
        if let lat = lat { XCTAssertEqual(lat, 30.654321, accuracy: 1e-4) }
        if let lon = lon { XCTAssertEqual(lon, 120.123456, accuracy: 1e-4) }
        XCTAssertEqual(latRef, "N")
        XCTAssertEqual(lonRef, "E")

        // Cleanup: delete the temp directory; the temp image should no longer exist
        try FileManager.default.removeItem(at: tmpDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpImageURL.path))
    }

    // MARK: - Helpers
    private func readGPS(from url: URL) throws -> (lat: Double?, latRef: String?, lon: Double?, lonRef: String?, alt: Double?) {
        guard let dataProvider = CGDataProvider(filename: url.path),
              let data = dataProvider.data,
              let imageSource = CGImageSourceCreateWithData(data, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else {
            throw NSError(domain: "FixGPSTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read image properties"])
        }
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let lat = gps?[kCGImagePropertyGPSLatitude] as? Double
        let latRef = gps?[kCGImagePropertyGPSLatitudeRef] as? String
        let lon = gps?[kCGImagePropertyGPSLongitude] as? Double
        let lonRef = gps?[kCGImagePropertyGPSLongitudeRef] as? String
        let alt = gps?[kCGImagePropertyGPSAltitude] as? Double
        return (lat, latRef, lon, lonRef, alt)
    }
}

