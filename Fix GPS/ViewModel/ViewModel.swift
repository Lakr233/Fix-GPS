//
//  ViewModel.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import Foundation

@Observable
class ViewModel {
    var logs: String = ""
    var completed: Bool = false

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
        DispatchQueue.global().async {
            defer { self.completed = true }
            self.executeCommandLineEx(
                locationRecord: locationRecord,
                photoDirectory: photoDirectory,
                overwrite: overwrite,
            )
        }
    }
}

extension Int {
    func paddedString(totalLength: Int) -> String {
        var str = String(self)
        while str.count < totalLength {
            str = "0" + str
        }
        return str
    }
}
