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
        let locationList = loadLocationRecords(from: URL(fileURLWithPath: gpsFilePath))
        guard !locationList.isEmpty else {
            return PhotoPickerResult(successCount: 0, errorCount: items.count)
        }

        var successCount = 0
        var errorCount = 0

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorCount += 1
                    continue
                }

                if processPhotoData(data: data, locationList: locationList, overwrite: overwrite) {
                    successCount += 1
                } else {
                    errorCount += 1
                }
            } catch {
                errorCount += 1
            }
        }

        return PhotoPickerResult(successCount: successCount, errorCount: errorCount)
    }

    private func processPhotoData(data: Data, locationList: [LocationRecord], overwrite: Bool) -> Bool {
        guard let timestamp = readingTimestamp(imageData: data) else { return false }

        guard let location = obtainNearestLocation(
            forTimestamp: timestamp.timeIntervalSince1970,
            in: locationList,
        ) else {
            return false
        }

        guard let modifiedData = appendingGPSData(
            imageData: data,
            location: location,
            overwrite: overwrite,
        ) else {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: modifiedData, options: nil)
        } completionHandler: { result, _ in
            success = result
            semaphore.signal()
        }

        semaphore.wait()
        return success
    }
}
