//
//  Worker.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import AppKit
import Cocoa
import CoreLocation
import Foundation

class Worker: ObservableObject {
    @Published var logs: String = ""
    @Published var completed: Bool = false

    func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        if Thread.isMainThread {
            logs.append(items.map { "\($0)" }.joined(separator: separator) + terminator)
            if !logs.hasSuffix("\n") { logs.append("\n") }
        } else {
            DispatchQueue.main.asyncAndWait {
                self.print(items, separator: separator, terminator: terminator)
            }
        }
    }

    func executeCommandLine(locationRecord: String, photoDirectory: String, overwrite: Bool = false) {
        completed = false
        defer { completed = true }
        DispatchQueue.global().async {
            self.executeCommandLineEx(locationRecord: locationRecord, photoDirectory: photoDirectory, overwrite: overwrite)
        }
    }

    func executeCommandLineEx(locationRecord: String, photoDirectory: String, overwrite: Bool = false) {
        let gpsFile = URL(fileURLWithPath: locationRecord)
        let searchDir = URL(fileURLWithPath: photoDirectory)

        struct LocationRecord: Codable {
            let timestamp: Double
            let longitude: Double
            let latitude: Double
            let altitude: Double
            let heading: Double
            let speed: Double
        }

        var locationList: [LocationRecord] = []

        print("[i] reading from \(gpsFile.path)")
        do {
            let csv = try CSV<Named>(url: gpsFile)
            for row in csv.rows {
                // read LocationRecord from row as? [String : String] and convert to double all keys
                guard let strTimestamp = row["dataTime"],
                      let strLongitude = row["longitude"],
                      let strLatitude = row["latitude"],
                      let strAltitude = row["altitude"],
                      let strHeading = row["heading"],
                      let strSpeed = row["speed"]
                else {
                    continue
                }
                guard let timestamp = Double(strTimestamp),
                      let longitude = Double(strLongitude),
                      let latitude = Double(strLatitude),
                      let altitude = Double(strAltitude),
                      let heading = Double(strHeading),
                      let speed = Double(strSpeed)
                else {
                    continue
                }
                let record = LocationRecord(
                    timestamp: timestamp,
                    longitude: longitude,
                    latitude: latitude,
                    altitude: altitude,
                    heading: heading,
                    speed: speed
                )
                locationList.append(record)
            }
        } catch {
            print("[E] unable to read from csv \(error.localizedDescription)")
            return
        }

        print("[*] preparing \(locationList.count) gps record")
        locationList.sort { $0.timestamp < $1.timestamp }

        print("[*] loaded \(locationList.count) locations")

        func obtainNearestLocation(forTimestamp: Double) -> LocationRecord? {
            var left = 0
            var right = locationList.count - 1
            while left < right {
                let mid = (left + right) / 2
                let loc = locationList[mid]
                if loc.timestamp == forTimestamp {
                    left = mid
                    right = mid
                    break
                } else if loc.timestamp < forTimestamp {
                    left = mid + 1
                } else {
                    right = mid - 1
                }
            }
            let mid = (left + right) / 2
            var candidate: LocationRecord?
            var minDelta: Double?
            for idx in mid - 2 ... mid + 2 {
                if idx >= 0, idx < locationList.count {
                    let loc = locationList[idx]
                    let delta = abs(loc.timestamp - forTimestamp)
                    if minDelta == nil || minDelta! > delta {
                        minDelta = delta
                        candidate = loc
                    }
                }
            }
            return candidate
        }

        func readingTimestamp(imageFile: URL) -> Date? {
            guard let dataProvider = CGDataProvider(filename: imageFile.path),
                  let data = dataProvider.data,
                  let imageSource = CGImageSourceCreateWithData(data, nil),
                  let imageProperties = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil)
            else {
                print("[E] unable to load image")
                return nil
            }
            guard let dateTag = CGImageMetadataCopyTagMatchingImageProperty(
                imageProperties,
                kCGImagePropertyExifDictionary,
                kCGImagePropertyExifDateTimeDigitized
            ), let offsetTag = CGImageMetadataCopyTagMatchingImageProperty(
                imageProperties,
                kCGImagePropertyExifDictionary,
                kCGImagePropertyExifOffsetTimeDigitized
            ) else {
                print("[E] unable to read image tags")
                return nil
            }
            let date = CGImageMetadataTagCopyValue(dateTag) as? String
            let offset = CGImageMetadataTagCopyValue(offsetTag) as? String
            guard let date, let offset else {
                print("[E] unable to read image date")
                return nil
            }
            let str = date + " " + offset
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS Z"
            return fmt.date(from: str)
        }

        func appendingGPSData(imageFile: URL, lat: Double, lon: Double, alt: Double, overwrite: Bool = false) {
            guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: imageFile.path) else {
                print("[E] unable to read file attributes")
                return
            }

            guard let dataProvider = CGDataProvider(filename: imageFile.path),
                  let data = dataProvider.data,
                  let cgImage = NSImage(data: data as Data)?
                  .cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                print("[E] unable to prepare data")
                return
            }

            let mutableData = NSMutableData(data: data as Data)

            guard let imageSource = CGImageSourceCreateWithData(data, nil),
                  let type = CGImageSourceGetType(imageSource),
                  let imageDestination = CGImageDestinationCreateWithData(mutableData, type, 1, nil),
                  let imageProperties = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil),
                  let mutableMetadata = CGImageMetadataCreateMutableCopy(imageProperties)
            else {
                print("[E] unable to load image")
                return
            }

            if CGImageMetadataCopyTagMatchingImageProperty(
                imageProperties,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLatitude
            ) != nil || CGImageMetadataCopyTagMatchingImageProperty(
                imageProperties,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLongitude
            ) != nil {
                print("[i] GPS data already exists")
                if !overwrite { return }
            }

            let coornidate2D = CLLocationCoordinate2D(latitude: .init(lat), longitude: .init(lon))

            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLatitudeRef,
                (lat < 0 ? "S" : "N") as CFTypeRef
            )
            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLatitude,
                coornidate2D.latitude as CFTypeRef
            )
            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLongitudeRef,
                (lon < 0 ? "W" : "E") as CFTypeRef
            )
            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLongitude,
                coornidate2D.longitude as CFTypeRef
            )
            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSAltitude,
                alt as CFTypeRef
            )

            let finalMetadata = mutableMetadata as CGImageMetadata
            CGImageDestinationAddImageAndMetadata(imageDestination, cgImage, finalMetadata, nil)
            guard CGImageDestinationFinalize(imageDestination) else {
                print("[E] failed to finalize image data")
                return
            }

            do {
                try FileManager.default.removeItem(at: imageFile)
                try mutableData.write(toFile: imageFile.path)
                try FileManager.default.setAttributes(fileAttributes, ofItemAtPath: imageFile.path)
            } catch {
                print("[E] failed to write")
                print(error.localizedDescription)
                return
            }

            print("[*] image meta data updated")
        }

        print("[*] starting file walk inside \(searchDir.path)")

        let enumerator = FileManager.default.enumerator(atPath: searchDir.path)
        var candidates = [URL]()
        while let subPath = enumerator?.nextObject() as? String {
            guard subPath.lowercased().hasSuffix("jpg") || subPath.lowercased().hasSuffix("jpeg") else { continue }
            let file = searchDir.appendingPathComponent(subPath)
            candidates.append(file)
        }

        print("[*] found \(candidates.count) candidates")

        guard candidates.count > 0 else {
            print("no candidates found!")
            return
        }

        let paddingLength = String(candidates.count).count
        for (idx, url) in candidates.enumerated() {
            print("[*] processing \(idx.paddedString(totalLength: paddingLength))/\(candidates.count) <\(url.lastPathComponent)>")
            autoreleasepool {
                guard let date = readingTimestamp(imageFile: url) else {
                    return
                }
                guard let location = obtainNearestLocation(forTimestamp: date.timeIntervalSince1970) else {
                    print("[E] unable to determine location")
                    return
                }
                appendingGPSData(
                    imageFile: url,
                    lat: location.latitude,
                    lon: location.longitude,
                    alt: location.altitude,
                    overwrite: overwrite
                )
            }
        }

        print("[*] completed update")
    }
}

// helpers

extension Int {
    func paddedString(totalLength: Int) -> String {
        var str = String(self)
        while str.count < totalLength {
            str = "0" + str
        }
        return str
    }
}

// =====================================
// SwiftCSV
// =====================================

//
//  CSV+DelimiterGuessing.swift
//  SwiftCSV
//
//  Created by Christian Tietze on 21.12.21.
//  Copyright © 2021 SwiftCSV. All rights reserved.
//

import Foundation

public extension CSVDelimiter {
    static let recognized: [CSVDelimiter] = [.comma, .tab, .semicolon]

    /// - Returns: Delimiter between cells based on the first line in the CSV. Falls back to `.comma`.
    static func guessed(string: String) -> CSVDelimiter {
        let recognizedDelimiterCharacters = CSVDelimiter.recognized.map(\.rawValue)

        // Trim newline and spaces, but keep tabs (as delimiters)
        var trimmedCharacters = CharacterSet.whitespacesAndNewlines
        trimmedCharacters.remove("\t")
        let line = string.trimmingCharacters(in: trimmedCharacters).firstLine

        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            switch character {
            case "\"":
                // When encountering an open quote, skip to the closing counterpart.
                // If none is found, skip to end of line.

                // 1) Advance one character to skip the quote
                index = line.index(after: index)

                // 2) Look for the closing quote and move current position after it
                if index < line.endIndex,
                   let closingQuoteInddex = line[index...].firstIndex(of: character)
                {
                    index = line.index(after: closingQuoteInddex)
                } else {
                    index = line.endIndex
                }
            case _ where recognizedDelimiterCharacters.contains(character):
                return CSVDelimiter(rawValue: character)
            default:
                index = line.index(after: index)
            }
        }

        // Fallback value
        return .comma
    }
}

//
//  CSV.swift
//  SwiftCSV
//
//  Created by Naoto Kaneko on 2/18/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

import Foundation

public protocol CSVView {
    associatedtype Row
    associatedtype Columns

    var rows: [Row] { get }

    /// Is `nil` if `loadColumns` was set to `false`.
    var columns: Columns? { get }

    init(header: [String], text: String, delimiter: CSVDelimiter, loadColumns: Bool, rowLimit: Int?) throws

    func serialize(header: [String], delimiter: CSVDelimiter) -> String
}

/// CSV variant for which unique column names are assumed.
///
/// Example:
///
///     let csv = NamedCSV(...)
///     let allIDs = csv.columns["id"]
///     let firstEntry = csv.rows[0]
///     let fullName = firstEntry["firstName"] + " " + firstEntry["lastName"]
///
public typealias NamedCSV = CSV<Named>

/// CSV variant that exposes columns and rows as arrays.
/// Example:
///
///     let csv = EnumeratedCSV(...)
///     let allIds = csv.columns.filter { $0.header == "id" }.rows
///
public typealias EnumeratedCSV = CSV<Enumerated>

/// For convenience, there's `EnumeratedCSV` to access fields in rows by their column index,
/// and `NamedCSV` to access fields by their column names as defined in a header row.
open class CSV<DataView: CSVView> {
    public let header: [String]

    /// Unparsed contents.
    public let text: String

    /// Used delimiter to parse `text` and to serialize the data again.
    public let delimiter: CSVDelimiter

    /// Underlying data representation of the CSV contents.
    public let content: DataView

    public var rows: [DataView.Row] {
        content.rows
    }

    /// Is `nil` if `loadColumns` was set to `false` during initialization.
    public var columns: DataView.Columns? {
        content.columns
    }

    /// Load CSV data from a string.
    ///
    /// - Parameters:
    ///   - string: CSV contents to parse.
    ///   - delimiter: Character used to separate cells from one another in rows.
    ///   - loadColumns: Whether to populate the `columns` dictionary (default is `true`)
    ///   - rowLimit: Amount of rows to parse (default is `nil`).
    /// - Throws: `CSVParseError` when parsing `string` fails.
    public init(string: String, delimiter: CSVDelimiter, loadColumns: Bool = true, rowLimit: Int? = nil) throws {
        text = string
        self.delimiter = delimiter
        header = try Parser.array(text: string, delimiter: delimiter, rowLimit: 1).first ?? []
        content = try DataView(header: header, text: text, delimiter: delimiter, loadColumns: loadColumns, rowLimit: rowLimit)
    }

    /// Load CSV data from a string and guess its delimiter from `CSV.recognizedDelimiters`, falling back to `.comma`.
    ///
    /// - parameter string: CSV contents to parse.
    /// - parameter loadColumns: Whether to populate the `columns` dictionary (default is `true`)
    /// - throws: `CSVParseError` when parsing `string` fails.
    public convenience init(string: String, loadColumns: Bool = true) throws {
        let delimiter = CSVDelimiter.guessed(string: string)
        try self.init(string: string, delimiter: delimiter, loadColumns: loadColumns)
    }

    /// Turn the CSV data into NSData using a given encoding
    open func dataUsingEncoding(_ encoding: String.Encoding) -> Data? {
        serialized.data(using: encoding)
    }

    /// Serialized form of the CSV data; depending on the View used, this may
    /// perform additional normalizations.
    open var serialized: String {
        content.serialize(header: header, delimiter: delimiter)
    }
}

extension CSV: CustomStringConvertible {
    public var description: String {
        serialized
    }
}

func enquoteContentsIfNeeded(cell: String) -> String {
    // Add quotes if value contains a comma
    if cell.contains(",") {
        return "\"\(cell)\""
    }
    return cell
}

public extension CSV {
    /// Load a CSV file from `url`.
    ///
    /// - Parameters:
    ///   - url: URL of the file (will be passed to `String(contentsOfURL:encoding:)` to load)
    ///   - delimiter: Character used to separate separate cells from one another in rows.
    ///   - encoding: Character encoding to read file (default is `.utf8`)
    ///   - loadColumns: Whether to populate the columns dictionary (default is `true`)
    /// - Throws: `CSVParseError` when parsing the contents of `url` fails, or file loading errors.
    convenience init(url: URL, delimiter: CSVDelimiter, encoding: String.Encoding = .utf8, loadColumns: Bool = true) throws {
        let contents = try String(contentsOf: url, encoding: encoding)

        try self.init(string: contents, delimiter: delimiter, loadColumns: loadColumns)
    }

    /// Load a CSV file from `url` and guess its delimiter from `CSV.recognizedDelimiters`, falling back to `.comma`.
    ///
    /// - Parameters:
    ///   - url: URL of the file (will be passed to `String(contentsOfURL:encoding:)` to load)
    ///   - encoding: Character encoding to read file (default is `.utf8`)
    ///   - loadColumns: Whether to populate the columns dictionary (default is `true`)
    /// - Throws: `CSVParseError` when parsing the contents of `url` fails, or file loading errors.
    convenience init(url: URL, encoding: String.Encoding = .utf8, loadColumns: Bool = true) throws {
        let contents = try String(contentsOf: url, encoding: encoding)

        try self.init(string: contents, loadColumns: loadColumns)
    }
}

public extension CSV {
    /// Load a CSV file as a named resource from `bundle`.
    ///
    /// - Parameters:
    ///   - name: Name of the file resource inside `bundle`.
    ///   - ext: File extension of the resource; use `nil` to load the first file matching the name (default is `nil`)
    ///   - bundle: `Bundle` to use for resource lookup (default is `.main`)
    ///   - delimiter: Character used to separate separate cells from one another in rows.
    ///   - encoding: encoding used to read file (default is `.utf8`)
    ///   - loadColumns: Whether to populate the columns dictionary (default is `true`)
    /// - Throws: `CSVParseError` when parsing the contents of the resource fails, or file loading errors.
    /// - Returns: `nil` if the resource could not be found
    convenience init?(name: String, extension ext: String? = nil, bundle: Bundle = .main, delimiter: CSVDelimiter, encoding: String.Encoding = .utf8, loadColumns: Bool = true) throws {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            return nil
        }
        try self.init(url: url, delimiter: delimiter, encoding: encoding, loadColumns: loadColumns)
    }

    /// Load a CSV file as a named resource from `bundle` and guess its delimiter from `CSV.recognizedDelimiters`, falling back to `.comma`.
    ///
    /// - Parameters:
    ///   - name: Name of the file resource inside `bundle`.
    ///   - ext: File extension of the resource; use `nil` to load the first file matching the name (default is `nil`)
    ///   - bundle: `Bundle` to use for resource lookup (default is `.main`)
    ///   - encoding: encoding used to read file (default is `.utf8`)
    ///   - loadColumns: Whether to populate the columns dictionary (default is `true`)
    /// - Throws: `CSVParseError` when parsing the contents of the resource fails, or file loading errors.
    /// - Returns: `nil` if the resource could not be found
    convenience init?(name: String, extension ext: String? = nil, bundle: Bundle = .main, encoding: String.Encoding = .utf8, loadColumns: Bool = true) throws {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            return nil
        }
        try self.init(url: url, encoding: encoding, loadColumns: loadColumns)
    }
}

//
//  CSVDelimiter.swift
//  SwiftCSV
//
//  Created by Christian Tietze on 01.07.22.
//  Copyright © 2022 SwiftCSV. All rights reserved.
//

public enum CSVDelimiter: Equatable, ExpressibleByUnicodeScalarLiteral {
    public typealias UnicodeScalarLiteralType = Character

    case comma, semicolon, tab
    case character(Character)

    public init(unicodeScalarLiteral: Character) {
        self.init(rawValue: unicodeScalarLiteral)
    }

    init(rawValue: Character) {
        switch rawValue {
        case ",": self = .comma
        case ";": self = .semicolon
        case "\t": self = .tab
        default: self = .character(rawValue)
        }
    }

    public var rawValue: Character {
        switch self {
        case .comma: ","
        case .semicolon: ";"
        case .tab: "\t"
        case let .character(character): character
        }
    }
}

//
//  EnumeratedCSVView.swift
//  SwiftCSV
//
//  Created by Christian Tietze on 25/10/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

import Foundation

public struct Enumerated: CSVView {
    public struct Column: Equatable {
        public let header: String
        public let rows: [String]
    }

    public typealias Row = [String]
    public typealias Columns = [Column]

    public private(set) var rows: [Row]
    public private(set) var columns: Columns?

    public init(header: [String], text: String, delimiter: CSVDelimiter, loadColumns: Bool = false, rowLimit: Int? = nil) throws {
        rows = try {
            var rows: [Row] = []
            try Parser.enumerateAsArray(text: text, delimiter: delimiter, startAt: 1, rowLimit: rowLimit) { fields in
                rows.append(fields)
            }

            // Fill in gaps at the end of rows that are too short.
            return makingRectangular(rows: rows)
        }()

        columns = {
            guard loadColumns else { return nil }
            return header.enumerated().map { (index: Int, header: String) -> Column in
                Column(
                    header: header,
                    rows: rows.map { $0[safe: index] ?? "" }
                )
            }
        }()
    }

    public func serialize(header: [String], delimiter: CSVDelimiter) -> String {
        let separator = String(delimiter.rawValue)

        let head = header
            .map(enquoteContentsIfNeeded(cell:))
            .joined(separator: separator) + "\n"

        let content = rows.map { row in
            row.map(enquoteContentsIfNeeded(cell:))
                .joined(separator: separator)
        }.joined(separator: "\n")

        return head + content
    }
}

extension Collection {
    subscript(safe index: Self.Index) -> Self.Iterator.Element? {
        index < endIndex ? self[index] : nil
    }
}

private func makingRectangular(rows: [[String]]) -> [[String]] {
    let cellsPerRow = rows.map(\.count).max() ?? 0
    return rows.map { row -> [String] in
        let missingCellCount = cellsPerRow - row.count
        let appendix = Array(repeating: "", count: missingCellCount)
        return row + appendix
    }
}

//
//  NamedCSVView.swift
//  SwiftCSV
//
//  Created by Christian Tietze on 22/10/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

public struct Named: CSVView {
    public typealias Row = [String: String]
    public typealias Columns = [String: [String]]

    public var rows: [Row]
    public var columns: Columns?

    public init(header: [String], text: String, delimiter: CSVDelimiter, loadColumns: Bool = false, rowLimit: Int? = nil) throws {
        rows = try {
            var rows: [Row] = []
            try Parser.enumerateAsDict(header: header, content: text, delimiter: delimiter, rowLimit: rowLimit) { dict in
                rows.append(dict)
            }
            return rows
        }()

        columns = {
            guard loadColumns else { return nil }
            var columns: Columns = [:]
            for field in header {
                columns[field] = rows.map { $0[field] ?? "" }
            }
            return columns
        }()
    }

    public func serialize(header: [String], delimiter: CSVDelimiter) -> String {
        let separator = String(delimiter.rawValue)

        let head = header
            .map(enquoteContentsIfNeeded(cell:))
            .joined(separator: separator) + "\n"

        let content = rows.map { row in
            header
                .map { cellID in row[cellID]! }
                .map(enquoteContentsIfNeeded(cell:))
                .joined(separator: separator)
        }.joined(separator: "\n")

        return head + content
    }
}

//
//  Parser.swift
//  SwiftCSV
//
//  Created by Will Richardson on 13/04/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

public extension CSV {
    /// Parse the file and call a block on each row, passing it in as a list of fields.
    /// - Parameters limitTo: Maximum absolute line number in the content, *not* maximum amount of rows.
    @available(*, deprecated, message: "Use enumerateAsArray(startAt:rowLimit:_:) instead")
    func enumerateAsArray(limitTo maxRow: Int? = nil, startAt: Int = 0, _ rowCallback: @escaping ([String]) -> Void) throws {
        try Parser.enumerateAsArray(text: text, delimiter: delimiter, startAt: startAt, rowLimit: maxRow.map { $0 - startAt }, rowCallback: rowCallback)
    }

    /// Parse the CSV contents row by row from `start` for `rowLimit` amount of rows, or until the end of the input.
    /// - Parameters:
    ///   - startAt: Skip lines before this. Default value is `0` to start at the beginning.
    ///   - rowLimit: Amount of rows to consume, beginning to count at `startAt`. Default value is `nil` to consume
    ///     the whole input string.
    ///   - rowCallback: Array of each row's columnar values, in order.
    func enumerateAsArray(startAt: Int = 0, rowLimit: Int? = nil, _ rowCallback: @escaping ([String]) -> Void) throws {
        try Parser.enumerateAsArray(text: text, delimiter: delimiter, startAt: startAt, rowLimit: rowLimit, rowCallback: rowCallback)
    }

    func enumerateAsDict(_ block: @escaping ([String: String]) -> Void) throws {
        try Parser.enumerateAsDict(header: header, content: text, delimiter: delimiter, block: block)
    }
}

enum Parser {
    static func array(text: String, delimiter: CSVDelimiter, startAt offset: Int = 0, rowLimit: Int? = nil) throws -> [[String]] {
        var rows = [[String]]()

        try enumerateAsArray(text: text, delimiter: delimiter, startAt: offset, rowLimit: rowLimit) { row in
            rows.append(row)
        }

        return rows
    }

    /// Parse `text` and provide each row to `rowCallback` as an array of field values, one for each column per
    /// line of text, separated by `delimiter`.
    ///
    /// - Parameters:
    ///   - text: Text to parse.
    ///   - delimiter: Character to split row and header fields by (default is ',')
    ///   - offset: Skip lines before this. Default value is `0` to start at the beginning.
    ///   - rowLimit: Amount of rows to consume, beginning to count at `startAt`. Default value is `nil` to consume
    ///     the whole input string.
    ///   - rowCallback: Callback invoked for every parsed row between `startAt` and `limitTo` in `text`.
    /// - Throws: `CSVParseError`
    static func enumerateAsArray(text: String,
                                 delimiter: CSVDelimiter,
                                 startAt offset: Int = 0,
                                 rowLimit: Int? = nil,
                                 rowCallback: @escaping ([String]) -> Void) throws
    {
        let maxRowIndex = rowLimit.flatMap { $0 < 0 ? nil : offset + $0 }

        var currentIndex = text.startIndex
        let endIndex = text.endIndex

        var fields = [String]()
        let delimiter = delimiter.rawValue
        var field = ""

        var rowIndex = 0

        func finishRow() {
            defer {
                rowIndex += 1
                fields = []
                field = ""
            }

            guard rowIndex >= offset else { return }
            fields.append(String(field))
            rowCallback(fields)
        }

        var state = ParsingState(
            delimiter: delimiter,
            finishRow: finishRow,
            appendChar: {
                guard rowIndex >= offset else { return }
                field.append($0)
            },
            finishField: {
                guard rowIndex >= offset else { return }
                fields.append(field)
                field = ""
            }
        )

        func limitReached(_ rowNumber: Int) -> Bool {
            guard let maxRowIndex else { return false }
            return rowNumber >= maxRowIndex
        }

        while currentIndex < endIndex,
              !limitReached(rowIndex)
        {
            let char = text[currentIndex]

            try state.change(char)

            currentIndex = text.index(after: currentIndex)
        }

        // Append remainder of the cache, unless we're past the limit already.
        if !limitReached(rowIndex) {
            if !field.isEmpty {
                fields.append(field)
            }

            if !fields.isEmpty {
                rowCallback(fields)
            }
        }
    }

    static func enumerateAsDict(header: [String], content: String, delimiter: CSVDelimiter, rowLimit: Int? = nil, block: @escaping ([String: String]) -> Void) throws {
        let enumeratedHeader = header.enumerated()

        // Start after the header
        try enumerateAsArray(text: content, delimiter: delimiter, startAt: 1, rowLimit: rowLimit) { fields in
            var dict = [String: String]()
            for (index, head) in enumeratedHeader {
                dict[head] = index < fields.count ? fields[index] : ""
            }
            block(dict)
        }
    }
}

//
//  ParsingState.swift
//  SwiftCSV
//
//  Created by Christian Tietze on 25/10/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

public enum CSVParseError: Error {
    case generic(message: String)
    case quotation(message: String)
}

/// State machine of parsing CSV contents character by character.
struct ParsingState {
    private(set) var atStart = true
    private(set) var parsingField = false
    private(set) var parsingQuotes = false
    private(set) var innerQuotes = false

    let delimiter: Character
    let finishRow: () -> Void
    let appendChar: (Character) -> Void
    let finishField: () -> Void

    init(delimiter: Character,
         finishRow: @escaping () -> Void,
         appendChar: @escaping (Character) -> Void,
         finishField: @escaping () -> Void)
    {
        self.delimiter = delimiter
        self.finishRow = finishRow
        self.appendChar = appendChar
        self.finishField = finishField
    }

    /// - Throws: `CSVParseError`
    mutating func change(_ char: Character) throws {
        if atStart {
            if char == "\"" {
                atStart = false
                parsingQuotes = true
            } else if char == delimiter {
                finishField()
            } else if char.isNewline {
                finishRow()
            } else if char.isWhitespace {
                // ignore whitespaces between fields
            } else {
                parsingField = true
                atStart = false
                appendChar(char)
            }
        } else if parsingField {
            if innerQuotes {
                if char == "\"" {
                    appendChar(char)
                    innerQuotes = false
                } else {
                    throw CSVParseError.quotation(message: "Can't have non-quote here: \(char)")
                }
            } else {
                if char == "\"" {
                    innerQuotes = true
                } else if char == delimiter {
                    atStart = true
                    parsingField = false
                    innerQuotes = false
                    finishField()
                } else if char.isNewline {
                    atStart = true
                    parsingField = false
                    innerQuotes = false
                    finishRow()
                } else {
                    appendChar(char)
                }
            }
        } else if parsingQuotes {
            if innerQuotes {
                if char == "\"" {
                    appendChar(char)
                    innerQuotes = false
                } else if char == delimiter {
                    atStart = true
                    parsingField = false
                    innerQuotes = false
                    finishField()
                } else if char.isNewline {
                    atStart = true
                    parsingQuotes = false
                    innerQuotes = false
                    finishRow()
                } else if char.isWhitespace {
                    // ignore whitespaces between fields
                } else {
                    throw CSVParseError.quotation(message: "Can't have non-quote here: \(char)")
                }
            } else {
                if char == "\"" {
                    innerQuotes = true
                } else {
                    appendChar(char)
                }
            }
        } else {
            throw CSVParseError.generic(message: "me_irl")
        }
    }
}

//
//  String+Lines.swift
//  SwiftCSV
//
//  Created by Naoto Kaneko on 2/24/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

extension String {
    var firstLine: String {
        var current = startIndex
        while current < endIndex, self[current].isNewline == false {
            current = index(after: current)
        }
        return String(self[..<current])
    }
}

extension Character {
    var isNewline: Bool {
        self == "\n"
            || self == "\r\n"
            || self == "\r"
    }
}
