//
//  ViewModel+PhotoPicker.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import CoreLocation
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
        if asset.location != nil, !overwrite {
            print("[i] photo already has location, skipping (overwrite=false)")
            return false
        }

        guard let timestamp = await getAssetTimestamp(asset: asset) else {
            print("[E] unable to read photo timestamp")
            return false
        }

        print("[*] photo timestamp: \(timestamp)")

        guard let location = obtainNearestLocation(
            forTimestamp: timestamp.timeIntervalSince1970,
            in: locationList
        ) else {
            print("[E] unable to find matching gps location (timestamp: \(timestamp.timeIntervalSince1970))")
            return false
        }

        print("[*] matched location: lat=\(location.latitude), lon=\(location.longitude), alt=\(location.altitude)")

        let clLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            altitude: location.altitude,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            timestamp: timestamp
        )

        do {
            try await writeGPSLocation(to: asset, location: clLocation)
            print("[+] photo location updated in library")
            return true
        } catch {
            print("[E] failed to update photo location: \(error.localizedDescription)")
            return false
        }
    }

    private func getAssetTimestamp(asset: PHAsset) async -> Date? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.version = .current
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { [self] data, _, _, _ in
                guard let data else {
                    continuation.resume(returning: asset.creationDate)
                    return
                }
                let timestamp = readingTimestamp(imageData: data)
                continuation.resume(returning: timestamp ?? asset.creationDate)
            }
        }
    }

    private func writeGPSLocation(to asset: PHAsset, location: CLLocation) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.location = location
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: NSError(domain: "PhotoLibrary", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
