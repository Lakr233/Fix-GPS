//
//  FileStatusView.swift
//  Fix GPS
//
//  Created by qaq on 28/11/2025.
//

import SwiftUI

struct FileStatusView: View {
    let path: String
    var isDirectory: Bool = false

    private var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private var itemCount: Int? {
        guard isDirectory, exists else { return nil }
        let url = URL(fileURLWithPath: path)
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
        )
        let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif"]
        return contents?.count(where: { imageExtensions.contains($0.pathExtension.lowercased()) })
    }

    var body: some View {
        if path.isEmpty {
            EmptyView()
        } else if exists {
            if let count = itemCount {
                Text("\(count) image(s) found")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Path not found")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}
