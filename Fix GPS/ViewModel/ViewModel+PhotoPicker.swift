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

            guard let assetIdentifier = item.itemIdentifier else {
                print("[E] failed to get asset identifier (index: \(index))")
                errorCount += 1
                continue
            }

            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                print("[E] failed to fetch asset (index: \(index))")
                errorCount += 1
                continue
            }

            let result = await processAsset(asset: asset, locationList: locationList, overwrite: overwrite)
            if result {
                successCount += 1
                print("[+] photo \(index + 1) processed successfully")
            } else {
                errorCount += 1
                print("[-] photo \(index + 1) processing failed")
            }
        }

        print("[*] completed: \(successCount) success, \(errorCount) errors")
        return PhotoPickerResult(successCount: successCount, errorCount: errorCount)
    }

    private func processAsset(asset: PHAsset, locationList: [LocationRecord], overwrite: Bool) async -> Bool {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { [self] input, _ in
                guard let input,
                      let url = input.fullSizeImageURL,
                      let data = try? Data(contentsOf: url)
                else {
                    print("[E] unable to get photo data")
                    continuation.resume(returning: false)
                    return
                }

                print("[*] photo data size: \(data.count) bytes")

                guard let timestamp = readingTimestamp(imageData: data) else {
                    print("[E] unable to read photo timestamp")
                    continuation.resume(returning: false)
                    return
                }

                print("[*] photo timestamp: \(timestamp)")

                guard let location = obtainNearestLocation(
                    forTimestamp: timestamp.timeIntervalSince1970,
                    in: locationList
                ) else {
                    print("[E] unable to find matching gps location (timestamp: \(timestamp.timeIntervalSince1970))")
                    continuation.resume(returning: false)
                    return
                }

                print("[*] matched location: lat=\(location.latitude), lon=\(location.longitude), alt=\(location.altitude)")

                guard let modifiedData = appendingGPSData(
                    imageData: data,
                    location: location,
                    overwrite: overwrite
                ) else {
                    print("[E] failed to write gps data to photo (overwrite=\(overwrite))")
                    continuation.resume(returning: false)
                    return
                }

                print("[*] gps data written to photo, saving to library...")
                print("[*] modified data size: \(modifiedData.count) bytes")

                let output = PHContentEditingOutput(contentEditingInput: input)
                output.adjustmentData = PHAdjustmentData(
                    formatIdentifier: "wiki.qaq.Fix-GPS",
                    formatVersion: "1.0",
                    data: "GPS".data(using: .utf8)!
                )

                do {
                    try modifiedData.write(to: output.renderedContentURL)
                } catch {
                    print("[E] failed to write modified data: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest(for: asset)
                    request.contentEditingOutput = output
                } completionHandler: { success, error in
                    if success {
                        self.print("[+] photo updated in library successfully")
                    } else {
                        self.print("[E] failed to update photo in library")
                        if let error {
                            self.print("[E] error details: \(error.localizedDescription)")
                        }
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
