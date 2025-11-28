//
//  Worker.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import AppKit
import Cocoa
import Combine
import Foundation
import SwiftCSV

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

    // Exposed for testing: read capture timestamp from image metadata (JPEG/HEIC/HEIF)
    func readingTimestamp(imageFile: URL) -> Date? {
        guard let dataProvider = CGDataProvider(filename: imageFile.path),
              let data = dataProvider.data,
              let imageSource = CGImageSourceCreateWithData(data, nil)
        else {
            print("[E] unable to load image")
            return nil
        }

        guard let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            print("[E] unable to read image properties")
            return nil
        }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let dateCandidates: [String?] = [
            (exif?[kCGImagePropertyExifDateTimeOriginal] as? String),
            exif?[kCGImagePropertyExifDateTimeDigitized] as? String,
            tiff?[kCGImagePropertyTIFFDateTime] as? String,
        ]

        let offsetCandidates: [String?] = [
            (exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String),
            exif?[kCGImagePropertyExifOffsetTimeDigitized] as? String,
            exif?[kCGImagePropertyExifOffsetTime] as? String,
        ]

        let subsecCandidates: [String?] = [
            (exif?[kCGImagePropertyExifSubsecTimeOriginal] as? String),
            exif?[kCGImagePropertyExifSubsecTimeDigitized] as? String,
            exif?[kCGImagePropertyExifSubsecTime] as? String,
        ]

        guard let rawDate = dateCandidates.compactMap(\.self).first else {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: imageFile.path) {
                if let c = attrs[.creationDate] as? Date { return c }
                if let m = attrs[.modificationDate] as? Date { return m }
            }
            return nil
        }

        let subsec = subsecCandidates.compactMap(\.self).first
        let offset = offsetCandidates.compactMap(\.self).first

        var candidateStrings: [String] = []
        if let sub = subsec, !sub.isEmpty {
            if let off = offset, !off.isEmpty {
                candidateStrings.append("\(rawDate).\(sub) \(off)")
            }
            candidateStrings.append("\(rawDate).\(sub)")
        } else {
            if let off = offset, !off.isEmpty {
                candidateStrings.append("\(rawDate) \(off)")
            }
            candidateStrings.append(rawDate)
        }

        let fmts = [
            "yyyy:MM:dd HH:mm:ss.SSS ZZZZZ",
            "yyyy:MM:dd HH:mm:ss.SSS",
            "yyyy:MM:dd HH:mm:ss ZZZZZ",
            "yyyy:MM:dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSS ZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss ZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for s in candidateStrings {
            for f in fmts {
                formatter.dateFormat = f
                if let d = formatter.date(from: s) { return d }
            }
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: imageFile.path) {
            if let c = attrs[.creationDate] as? Date { return c }
            if let m = attrs[.modificationDate] as? Date { return m }
        }
        return nil
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

        // Normalize header key: trim, lowercase, remove separators
        func normalizeKey(_ key: String) -> String {
            key.trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
        }

        // Match header by prefix (first 3 chars) or full normalized name
        func findValue(in row: [String: String], matching prefixes: [String]) -> String? {
            for (key, value) in row {
                let normalized = normalizeKey(key)
                for prefix in prefixes {
                    if normalized.hasPrefix(prefix) || normalized == prefix {
                        return value
                    }
                }
            }
            return nil
        }

        var locationList: [LocationRecord] = []

        print("[i] reading from \(gpsFile.path)")
        do {
            let csv = try CSV<Named>(url: gpsFile)
            for row in csv.rows {
                // Flexible header matching with prefix support
                guard let strTimestamp = findValue(in: row, matching: ["dat", "tim", "time"]),
                      let strLongitude = findValue(in: row, matching: ["lon", "lng"]),
                      let strLatitude = findValue(in: row, matching: ["lat"]),
                      let strAltitude = findValue(in: row, matching: ["alt", "ele", "elevation"]),
                      let strHeading = findValue(in: row, matching: ["hea", "dir", "bearing", "course"]),
                      let strSpeed = findValue(in: row, matching: ["spe", "vel"])
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
                    speed: speed,
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

        // readingTimestamp now available as instance method

        func appendingGPSData(imageFile: URL, lat: Double, lon: Double, alt: Double, overwrite: Bool = false) {
            guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: imageFile.path) else {
                print("[E] unable to read file attributes")
                return
            }

            guard let dataProvider = CGDataProvider(filename: imageFile.path),
                  let data = dataProvider.data,
                  let imageSource = CGImageSourceCreateWithData(data, nil),
                  let type = CGImageSourceGetType(imageSource),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
                  let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0),
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
                kCGImagePropertyGPSLatitude,
            ) != nil || CGImageMetadataCopyTagMatchingImageProperty(
                imageProperties,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLongitude,
            ) != nil {
                print("[i] GPS data already exists")
                if !overwrite { return }
            }

            // GPS EXIF standard requires absolute values for coordinates
            // The direction is indicated by LatitudeRef (N/S) and LongitudeRef (E/W)
            let absLatitude = abs(lat)
            let absLongitude = abs(lon)

            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLatitudeRef,
                (lat < 0 ? "S" : "N") as CFTypeRef,
            )
            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLatitude,
                absLatitude as CFTypeRef,
            )
            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLongitudeRef,
                (lon < 0 ? "W" : "E") as CFTypeRef,
            )
            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSLongitude,
                absLongitude as CFTypeRef,
            )
            CGImageMetadataSetValueMatchingImageProperty(
                mutableMetadata,
                kCGImagePropertyGPSDictionary,
                kCGImagePropertyGPSAltitude,
                alt as CFTypeRef,
            )

            let finalMetadata = mutableMetadata as CGImageMetadata
            CGImageDestinationAddImageAndMetadata(imageDestination, cgImage, finalMetadata, nil)
            guard CGImageDestinationFinalize(imageDestination) else {
                print("[E] failed to finalize image data")
                return
            }

            do {
                // Write atomically by replacing the original file
                let tmpURL = imageFile.deletingLastPathComponent().appendingPathComponent(".tmp_\(UUID().uuidString)")
                try (mutableData as NSData as Data).write(to: tmpURL)
                _ = try FileManager.default.replaceItemAt(imageFile, withItemAt: tmpURL)
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
        let supportedExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif"]
        while let subPath = enumerator?.nextObject() as? String {
            let lower = subPath.lowercased()
            guard let ext = lower.split(separator: ".").last.map(String.init), supportedExtensions.contains(ext) else { continue }
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
                guard let date = self.readingTimestamp(imageFile: url) else {
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
                    overwrite: overwrite,
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
