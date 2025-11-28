//
//  WorkerView.swift
//  Fix GPS
//
//  Created by qaq on 28/11/2025.
//

import SwiftUI

struct WorkerView: View {
    @State var worker = ViewModel()
    @Binding var gpsLocation: String
    @Binding var pictureDirectory: String
    @Binding var overwrite: Bool
    @Environment(\.dismiss) var dismiss

    private var lines: [String] {
        worker.logs
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(worker.completed ? "Completed" : "Processing...").bold()
                Spacer()
                if !worker.completed {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            Divider()

            ScrollView {
                ScrollViewReader { value in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .foregroundStyle(line.hasPrefix("[E]") ? .red : .primary)
                                .id(index)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("EOF")
                    }
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: lines.count) { _, _ in
                        value.scrollTo("EOF", anchor: .bottom)
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                if worker.completed {
                    let errorCount = lines.count(where: { $0.hasPrefix("[E]") })
                    let successCount = lines.count(where: { $0.contains("image meta data updated") })
                    Text("\(successCount) updated, \(errorCount) error(s)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .disabled(!worker.completed)
            }
            .padding()
        }
        .frame(width: 500, height: 350)
        .task {
            worker.executeCommandLine(
                locationRecord: gpsLocation,
                photoDirectory: pictureDirectory,
                overwrite: overwrite,
            )
        }
    }
}
