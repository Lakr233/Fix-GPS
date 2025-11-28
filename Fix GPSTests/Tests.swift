@testable import Fix_GPS
import ImageIO
import XCTest

final class WriteGPSTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FixGPSTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir, FileManager.default.fileExists(atPath: tmpDir.path) {
            try FileManager.default.removeItem(at: tmpDir)
        }
    }

    // MARK: - GPS Writing Tests

    /// Test writing GPS data with positive coordinates (Northern & Eastern hemisphere)
    func testWriteGPSNorthEast() throws {
        let (lat, lon, alt) = (35.681236, 139.767125, 40.0) // Tokyo
        let result = try writeAndReadGPS(latitude: lat, longitude: lon, altitude: alt)

        XCTAssertEqual(result.lat ?? 0, lat, accuracy: 1e-4)
        XCTAssertEqual(result.lon ?? 0, lon, accuracy: 1e-4)
        XCTAssertEqual(result.latRef, "N")
        XCTAssertEqual(result.lonRef, "E")
        XCTAssertEqual(result.alt ?? 0, alt, accuracy: 1e-2)
    }

    /// Test writing GPS data with negative latitude (Southern hemisphere)
    func testWriteGPSSouthEast() throws {
        let (lat, lon, alt) = (-36.810933, 174.736279, 51.0) // Auckland, New Zealand
        let result = try writeAndReadGPS(latitude: lat, longitude: lon, altitude: alt)

        XCTAssertEqual(result.lat ?? 0, abs(lat), accuracy: 1e-4)
        XCTAssertEqual(result.lon ?? 0, lon, accuracy: 1e-4)
        XCTAssertEqual(result.latRef, "S")
        XCTAssertEqual(result.lonRef, "E")
        XCTAssertEqual(result.alt ?? 0, alt, accuracy: 1e-2)
    }

    /// Test writing GPS data with negative longitude (Western hemisphere)
    func testWriteGPSNorthWest() throws {
        let (lat, lon, alt) = (40.712776, -74.005974, 10.0) // New York
        let result = try writeAndReadGPS(latitude: lat, longitude: lon, altitude: alt)

        XCTAssertEqual(result.lat ?? 0, lat, accuracy: 1e-4)
        XCTAssertEqual(result.lon ?? 0, abs(lon), accuracy: 1e-4)
        XCTAssertEqual(result.latRef, "N")
        XCTAssertEqual(result.lonRef, "W")
        XCTAssertEqual(result.alt ?? 0, alt, accuracy: 1e-2)
    }

    /// Test writing GPS data with both negative coordinates (Southern & Western hemisphere)
    func testWriteGPSSouthWest() throws {
        let (lat, lon, alt) = (-33.448890, -70.669265, 520.0) // Santiago, Chile
        let result = try writeAndReadGPS(latitude: lat, longitude: lon, altitude: alt)

        XCTAssertEqual(result.lat ?? 0, abs(lat), accuracy: 1e-4)
        XCTAssertEqual(result.lon ?? 0, abs(lon), accuracy: 1e-4)
        XCTAssertEqual(result.latRef, "S")
        XCTAssertEqual(result.lonRef, "W")
        XCTAssertEqual(result.alt ?? 0, alt, accuracy: 1e-2)
    }

    /// Test writing GPS data with high altitude
    func testWriteGPSHighAltitude() throws {
        let (lat, lon, alt) = (-31.906653, 162.058187, 12533.87) // High altitude flight
        let result = try writeAndReadGPS(latitude: lat, longitude: lon, altitude: alt)

        XCTAssertEqual(result.lat ?? 0, abs(lat), accuracy: 1e-4)
        XCTAssertEqual(result.lon ?? 0, lon, accuracy: 1e-4)
        XCTAssertEqual(result.latRef, "S")
        XCTAssertEqual(result.lonRef, "E")
        XCTAssertEqual(result.alt ?? 0, alt, accuracy: 1.0) // EXIF altitude may lose decimal precision
    }

    // MARK: - CSV Header Matching Tests

    /// Test flexible header matching with standard headers
    func testCSVHeaderMatchingStandard() throws {
        let csv = """
        dataTime,longitude,latitude,altitude,heading,speed
        1729010680,139.767125,35.681236,40.0,0,0
        """
        let result = try processCSVAndReadGPS(csvContent: csv)
        XCTAssertNotNil(result.lat)
        XCTAssertNotNil(result.lon)
    }

    /// Test flexible header matching with underscores
    func testCSVHeaderMatchingUnderscore() throws {
        let csv = """
        data_time,lon,lat,alt,heading,speed
        1729010680,139.767125,35.681236,40.0,0,0
        """
        let result = try processCSVAndReadGPS(csvContent: csv)
        XCTAssertNotNil(result.lat)
        XCTAssertNotNil(result.lon)
    }

    /// Test flexible header matching with dashes
    func testCSVHeaderMatchingDash() throws {
        let csv = """
        date-time,lng,latitude,elevation,dir,velocity
        1729010680,139.767125,35.681236,40.0,0,0
        """
        let result = try processCSVAndReadGPS(csvContent: csv)
        XCTAssertNotNil(result.lat)
        XCTAssertNotNil(result.lon)
    }

    /// Test flexible header matching with mixed case
    func testCSVHeaderMatchingMixedCase() throws {
        let csv = """
        DateTime,Longitude,Latitude,Altitude,Heading,Speed
        1729010680,139.767125,35.681236,40.0,0,0
        """
        let result = try processCSVAndReadGPS(csvContent: csv)
        XCTAssertNotNil(result.lat)
        XCTAssertNotNil(result.lon)
    }

    /// Test flexible header matching with prefix-only headers
    func testCSVHeaderMatchingPrefixOnly() throws {
        let csv = """
        tim,lon,lat,alt,hea,spe
        1729010680,139.767125,35.681236,40.0,0,0
        """
        let result = try processCSVAndReadGPS(csvContent: csv)
        XCTAssertNotNil(result.lat)
        XCTAssertNotNil(result.lon)
    }

    // MARK: - Overwrite Tests

    /// Test that existing GPS data is not overwritten when overwrite is false
    func testNoOverwriteExistingGPS() throws {
        // First write
        let firstResult = try writeAndReadGPS(latitude: 35.0, longitude: 139.0, altitude: 10.0)
        XCTAssertEqual(firstResult.lat ?? 0, 35.0, accuracy: 1e-4)

        // Second write without overwrite - should keep original
        let imageURL = tmpDir.appendingPathComponent("test_no_overwrite.heic")
        try copyTestImage(to: imageURL)

        // Write first GPS
        let worker = ViewModel()
        let ts = try getImageTimestamp(from: imageURL)
        let csv1 = createCSV(timestamp: ts, lon: 139.0, lat: 35.0, alt: 10.0)
        let csvURL = tmpDir.appendingPathComponent("record1.csv")
        try csv1.write(to: csvURL, atomically: true, encoding: .utf8)
        worker.executeCommandLineEx(locationRecord: csvURL.path, photoDirectory: tmpDir.path, overwrite: true)

        // Try to write second GPS without overwrite
        let csv2 = createCSV(timestamp: ts, lon: 100.0, lat: 10.0, alt: 5.0)
        let csvURL2 = tmpDir.appendingPathComponent("record2.csv")
        try csv2.write(to: csvURL2, atomically: true, encoding: .utf8)
        worker.executeCommandLineEx(locationRecord: csvURL2.path, photoDirectory: tmpDir.path, overwrite: false)

        // Should still have original GPS
        let result = try readGPS(from: imageURL)
        XCTAssertEqual(result.lat ?? 0, 35.0, accuracy: 1e-4)
        XCTAssertEqual(result.lon ?? 0, 139.0, accuracy: 1e-4)
    }

    /// Test that existing GPS data is overwritten when overwrite is true
    func testOverwriteExistingGPS() throws {
        let imageURL = tmpDir.appendingPathComponent("test_overwrite.heic")
        try copyTestImage(to: imageURL)

        let worker = ViewModel()
        let ts = try getImageTimestamp(from: imageURL)

        // Write first GPS
        let csv1 = createCSV(timestamp: ts, lon: 139.0, lat: 35.0, alt: 10.0)
        let csvURL = tmpDir.appendingPathComponent("record1.csv")
        try csv1.write(to: csvURL, atomically: true, encoding: .utf8)
        worker.executeCommandLineEx(locationRecord: csvURL.path, photoDirectory: tmpDir.path, overwrite: true)

        // Write second GPS with overwrite
        let csv2 = createCSV(timestamp: ts, lon: 100.0, lat: 10.0, alt: 5.0)
        let csvURL2 = tmpDir.appendingPathComponent("record2.csv")
        try csv2.write(to: csvURL2, atomically: true, encoding: .utf8)
        worker.executeCommandLineEx(locationRecord: csvURL2.path, photoDirectory: tmpDir.path, overwrite: true)

        // Should have new GPS
        let result = try readGPS(from: imageURL)
        XCTAssertEqual(result.lat ?? 0, 10.0, accuracy: 1e-4)
        XCTAssertEqual(result.lon ?? 0, 100.0, accuracy: 1e-4)
    }

    // MARK: - Timestamp Reading Tests

    /// Test reading timestamp from image
    func testReadTimestamp() throws {
        let imageURL = tmpDir.appendingPathComponent("test_timestamp.heic")
        try copyTestImage(to: imageURL)

        let worker = ViewModel()
        let timestamp = worker.readingTimestamp(imageFile: imageURL)

        XCTAssertNotNil(timestamp)
    }

    // MARK: - Helpers

    private func copyTestImage(to destination: URL) throws {
        let bundle = Bundle(for: type(of: self))
        guard let srcURL = bundle.url(forResource: "B0000007", withExtension: "HEIC") ??
            bundle.url(forResource: "B0000007", withExtension: "heic")
        else {
            throw NSError(domain: "FixGPSTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing test resource"])
        }
        try FileManager.default.copyItem(at: srcURL, to: destination)
    }

    private func getImageTimestamp(from url: URL) throws -> Double {
        let worker = ViewModel()
        guard let date = worker.readingTimestamp(imageFile: url) else {
            throw NSError(domain: "FixGPSTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to read timestamp"])
        }
        return date.timeIntervalSince1970
    }

    private func createCSV(timestamp: Double, lon: Double, lat: Double, alt: Double) -> String {
        let header = "dataTime,longitude,latitude,altitude,heading,speed\n"
        let payload = String(format: "%.3f,%.6f,%.6f,%.2f,0,0\n", timestamp, lon, lat, alt)
        return header + payload
    }

    private func writeAndReadGPS(latitude: Double, longitude: Double, altitude: Double) throws -> GPSResult {
        let imageURL = tmpDir.appendingPathComponent("test_\(UUID().uuidString).heic")
        try copyTestImage(to: imageURL)

        let worker = ViewModel()
        let ts = try getImageTimestamp(from: imageURL)
        let csv = createCSV(timestamp: ts, lon: longitude, lat: latitude, alt: altitude)
        let csvURL = tmpDir.appendingPathComponent("record_\(UUID().uuidString).csv")
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)

        worker.executeCommandLineEx(locationRecord: csvURL.path, photoDirectory: tmpDir.path, overwrite: true)

        return try readGPS(from: imageURL)
    }

    private func processCSVAndReadGPS(csvContent: String) throws -> GPSResult {
        let imageURL = tmpDir.appendingPathComponent("test_\(UUID().uuidString).heic")
        try copyTestImage(to: imageURL)

        let worker = ViewModel()
        let ts = try getImageTimestamp(from: imageURL)

        // Replace timestamp in CSV content
        let lines = csvContent.components(separatedBy: "\n")
        let header = lines[0]
        let data = lines[1].components(separatedBy: ",")
        var newData = data
        newData[0] = String(format: "%.3f", ts)
        let newCSV = header + "\n" + newData.joined(separator: ",") + "\n"

        let csvURL = tmpDir.appendingPathComponent("record_\(UUID().uuidString).csv")
        try newCSV.write(to: csvURL, atomically: true, encoding: .utf8)

        worker.executeCommandLineEx(locationRecord: csvURL.path, photoDirectory: tmpDir.path, overwrite: true)

        return try readGPS(from: imageURL)
    }

    private struct GPSResult {
        let lat: Double?
        let latRef: String?
        let lon: Double?
        let lonRef: String?
        let alt: Double?
    }

    private func readGPS(from url: URL) throws -> GPSResult {
        guard let dataProvider = CGDataProvider(filename: url.path),
              let data = dataProvider.data,
              let imageSource = CGImageSourceCreateWithData(data, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else {
            throw NSError(domain: "FixGPSTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read image properties"])
        }
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        return GPSResult(
            lat: gps?[kCGImagePropertyGPSLatitude] as? Double,
            latRef: gps?[kCGImagePropertyGPSLatitudeRef] as? String,
            lon: gps?[kCGImagePropertyGPSLongitude] as? Double,
            lonRef: gps?[kCGImagePropertyGPSLongitudeRef] as? String,
            alt: gps?[kCGImagePropertyGPSAltitude] as? Double,
        )
    }
}
