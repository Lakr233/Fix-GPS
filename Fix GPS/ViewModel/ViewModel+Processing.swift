//
//  ViewModel+Processing.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import Foundation

extension ViewModel {
    func executeCommandLineEx(locationRecord: String, photoDirectory: String, overwrite: Bool = false) {
        let gpsFile = URL(fileURLWithPath: locationRecord)
        let searchDir = URL(fileURLWithPath: photoDirectory)

        let locationList = loadLocationRecords(from: gpsFile)
        guard !locationList.isEmpty else { return }

        let candidates = findImageCandidates(in: searchDir)
        guard !candidates.isEmpty else {
            print("no candidates found!")
            return
        }

        processImages(
            candidates: candidates,
            locationList: locationList,
            overwrite: overwrite,
        )

        print("[*] completed update")
    }

    private func findImageCandidates(in searchDir: URL) -> [URL] {
        print("[*] starting file walk inside \(searchDir.path)")

        let enumerator = FileManager.default.enumerator(atPath: searchDir.path)
        var candidates = [URL]()
        let supportedExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif"]

        while let subPath = enumerator?.nextObject() as? String {
            let lower = subPath.lowercased()
            guard let ext = lower.split(separator: ".").last.map(String.init),
                  supportedExtensions.contains(ext)
            else {
                continue
            }
            let file = searchDir.appendingPathComponent(subPath)
            candidates.append(file)
        }

        print("[*] found \(candidates.count) candidates")
        return candidates
    }

    private func processImages(candidates: [URL], locationList: [LocationRecord], overwrite: Bool) {
        let paddingLength = String(candidates.count).count

        for (idx, url) in candidates.enumerated() {
            print("[*] processing \(idx.paddedString(totalLength: paddingLength))/\(candidates.count) <\(url.lastPathComponent)>")
            autoreleasepool {
                guard let date = readingTimestamp(imageFile: url) else { return }
                guard let location = obtainNearestLocation(forTimestamp: date.timeIntervalSince1970, in: locationList) else {
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
    }
}
