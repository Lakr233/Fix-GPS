//
//  ViewModel+PhotoPicker.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import Foundation
import Photos
import PhotosUI
import SwiftUI

struct PhotoPickerResult {
    let successCount: Int
    let errorCount: Int
}

extension ViewModel {
    func processPhotoPickerItems(
        _ items: [PhotosPickerItem],
        gpsFilePath: String,
        overwrite: Bool,
    ) async -> PhotoPickerResult {
        print("[*] processing \(items.count) photos")
        print("[*] gps record file: \(gpsFilePath)")

        let locationList = loadLocationRecords(from: URL(fileURLWithPath: gpsFilePath))
        guard !locationList.isEmpty else {
            print("[E] gps records empty, unable to process photos")
            return PhotoPickerResult(successCount: 0, errorCount: items.count)
        }

        print("[*] loaded \(locationList.count) gps records")

        var successCount = 0
        var errorCount = 0

        for (index, item) in items.enumerated() {
            print("[*] processing photo \(index + 1)/\(items.count)")

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    print("[E] failed to load photo data (index: \(index))")
                    errorCount += 1
                    continue
                }

                print("[*] photo data size: \(data.count) bytes")

                let result = processPhotoData(data: data, locationList: locationList, overwrite: overwrite)
                if result {
                    successCount += 1
                    print("[+] photo \(index + 1) processed successfully")
                } else {
                    errorCount += 1
                    print("[-] photo \(index + 1) processing failed")
                }
            } catch {
                print("[E] error loading photo data: \(error.localizedDescription)")
                errorCount += 1
            }
        }

        print("[*] completed: \(successCount) success, \(errorCount) errors")
        return PhotoPickerResult(successCount: successCount, errorCount: errorCount)
    }

    private func processPhotoData(data: Data, locationList: [LocationRecord], overwrite: Bool) -> Bool {
        guard let timestamp = readingTimestamp(imageData: data) else {
            print("[E] unable to read photo timestamp")
            return false
        }

        print("[*] photo timestamp: \(timestamp)")

        guard let location = obtainNearestLocation(
            forTimestamp: timestamp.timeIntervalSince1970,
            in: locationList,
        ) else {
            print("[E] unable to find matching gps location (timestamp: \(timestamp.timeIntervalSince1970))")
            return false
        }

        print("[*] matched location: lat=\(location.latitude), lon=\(location.longitude), alt=\(location.altitude)")

        guard let modifiedData = appendingGPSData(
            imageData: data,
            location: location,
            overwrite: overwrite,
        ) else {
            print("[E] failed to write gps data to photo (overwrite=\(overwrite))")
            return false
        }

        print("[*] gps data written to photo, saving to library...")
        print("[*] modified data size: \(modifiedData.count) bytes")

        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        var saveError: Error?

        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: modifiedData, options: nil)
        } completionHandler: { result, error in
            success = result
            saveError = error
            semaphore.signal()
        }

        semaphore.wait()

        if success {
            print("[+] photo saved to library successfully")
        } else {
            print("[E] failed to save to photo library")
            if let error = saveError {
                print("[E] error details: \(error.localizedDescription)")
                print("[E] error type: \(type(of: error))")
                if let nsError = error as NSError? {
                    print("[E] error domain: \(nsError.domain)")
                    print("[E] error code: \(nsError.code)")
                    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                        print("[E] underlying error: \(underlyingError.localizedDescription)")
                    }
                }
            } else {
                print("[E] unknown error (error is nil)")
            }
        }

        return success
    }
}
