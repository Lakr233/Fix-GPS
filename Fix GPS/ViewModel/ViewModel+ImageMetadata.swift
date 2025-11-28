//
//  ViewModel+ImageMetadata.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import AppKit
import Foundation

extension ViewModel {
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
            exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
            exif?[kCGImagePropertyExifDateTimeDigitized] as? String,
            tiff?[kCGImagePropertyTIFFDateTime] as? String,
        ]

        let offsetCandidates: [String?] = [
            exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String,
            exif?[kCGImagePropertyExifOffsetTimeDigitized] as? String,
            exif?[kCGImagePropertyExifOffsetTime] as? String,
        ]

        let subsecCandidates: [String?] = [
            exif?[kCGImagePropertyExifSubsecTimeOriginal] as? String,
            exif?[kCGImagePropertyExifSubsecTimeDigitized] as? String,
            exif?[kCGImagePropertyExifSubsecTime] as? String,
        ]

        guard let rawDate = dateCandidates.compactMap(\.self).first else {
            return readFileDateFallback(imageFile: imageFile)
        }

        let subsec = subsecCandidates.compactMap(\.self).first
        let offset = offsetCandidates.compactMap(\.self).first

        if let date = parseExifDate(rawDate: rawDate, subsec: subsec, offset: offset) {
            return date
        }

        return readFileDateFallback(imageFile: imageFile)
    }

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

        if hasExistingGPSData(imageProperties: imageProperties) {
            print("[i] GPS data already exists")
            if !overwrite { return }
        }

        writeGPSMetadata(to: mutableMetadata, lat: lat, lon: lon, alt: alt)

        let finalMetadata = mutableMetadata as CGImageMetadata
        CGImageDestinationAddImageAndMetadata(imageDestination, cgImage, finalMetadata, nil)

        guard CGImageDestinationFinalize(imageDestination) else {
            print("[E] failed to finalize image data")
            return
        }

        do {
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

    private func readFileDateFallback(imageFile: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: imageFile.path) else {
            return nil
        }
        if let c = attrs[.creationDate] as? Date { return c }
        if let m = attrs[.modificationDate] as? Date { return m }
        return nil
    }

    private func parseExifDate(rawDate: String, subsec: String?, offset: String?) -> Date? {
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

        return nil
    }

    private func hasExistingGPSData(imageProperties: CGImageMetadata) -> Bool {
        CGImageMetadataCopyTagMatchingImageProperty(
            imageProperties,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyGPSLatitude,
        ) != nil || CGImageMetadataCopyTagMatchingImageProperty(
            imageProperties,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyGPSLongitude,
        ) != nil
    }

    private func writeGPSMetadata(to metadata: CGMutableImageMetadata, lat: Double, lon: Double, alt: Double) {
        let absLatitude = abs(lat)
        let absLongitude = abs(lon)

        CGImageMetadataSetValueMatchingImageProperty(
            metadata,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyGPSLatitudeRef,
            (lat < 0 ? "S" : "N") as CFTypeRef,
        )
        CGImageMetadataSetValueMatchingImageProperty(
            metadata,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyGPSLatitude,
            absLatitude as CFTypeRef,
        )
        CGImageMetadataSetValueMatchingImageProperty(
            metadata,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyGPSLongitudeRef,
            (lon < 0 ? "W" : "E") as CFTypeRef,
        )
        CGImageMetadataSetValueMatchingImageProperty(
            metadata,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyGPSLongitude,
            absLongitude as CFTypeRef,
        )
        CGImageMetadataSetValueMatchingImageProperty(
            metadata,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyGPSAltitude,
            alt as CFTypeRef,
        )
    }
}
