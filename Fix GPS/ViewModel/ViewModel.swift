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
        let message = items.map { "\($0)" }.joined(separator: separator) + terminator
        Swift.print(message, terminator: "")
        if Thread.isMainThread {
            logs.append(message)
            if !logs.hasSuffix("\n") { logs.append("\n") }
        } else {
            DispatchQueue.main.asyncAndWait {
                self.logs.append(message)
                if !self.logs.hasSuffix("\n") { self.logs.append("\n") }
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
