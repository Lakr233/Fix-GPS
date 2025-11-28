//
//  ViewModel+LocationRecord.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import Foundation
import SwiftCSV

struct LocationRecord: Codable {
    let timestamp: Double
    let longitude: Double
    let latitude: Double
    let altitude: Double
    let heading: Double
    let speed: Double
}

extension ViewModel {
    func loadLocationRecords(from gpsFile: URL) -> [LocationRecord] {
        print("[i] reading from \(gpsFile.path)")

        var locationList: [LocationRecord] = []

        do {
            let csv = try CSV<Named>(url: gpsFile)
            for row in csv.rows {
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
            return []
        }

        print("[*] preparing \(locationList.count) gps record")
        locationList.sort { $0.timestamp < $1.timestamp }
        print("[*] loaded \(locationList.count) locations")

        return locationList
    }

    func obtainNearestLocation(forTimestamp timestamp: Double, in locationList: [LocationRecord]) -> LocationRecord? {
        guard !locationList.isEmpty else { return nil }

        var left = 0
        var right = locationList.count - 1

        while left < right {
            let mid = (left + right) / 2
            let loc = locationList[mid]
            if loc.timestamp == timestamp {
                left = mid
                right = mid
                break
            } else if loc.timestamp < timestamp {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }

        let mid = (left + right) / 2
        var candidate: LocationRecord?
        var minDelta: Double?

        for idx in mid - 2 ... mid + 2 {
            guard idx >= 0, idx < locationList.count else { continue }
            let loc = locationList[idx]
            let delta = abs(loc.timestamp - timestamp)
            if minDelta == nil || minDelta! > delta {
                minDelta = delta
                candidate = loc
            }
        }

        return candidate
    }

    private func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func findValue(in row: [String: String], matching prefixes: [String]) -> String? {
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
}
