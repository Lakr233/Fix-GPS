//
//  ContentView.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("gpsLocation")
    var gpsLocation: String = "/Users/qaq/Download/backUpData.csv"
    @AppStorage("pictureDirectory")
    var pictureDirectory: String = "/Volumes/LUMIX/DCIM"
    @AppStorage("overwrite")
    var overwrite: Bool = false

    @State var gpsLocationPickerPresent = false
    @State var pictureDirectoryPickerPresent = false

    @State var run = false

    var body: some View {
        VStack {
            HStack {
                Text("GPS Record File")
                    .frame(width: 128, alignment: .trailing)
                TextField("", text: $gpsLocation)
                Button("...") {
                    gpsLocationPickerPresent = true
                }
                .fileImporter(isPresented: $gpsLocationPickerPresent, allowedContentTypes: [.data]) { result in
                    switch result {
                    case let .success(success):
                        gpsLocation = success.path
                    default: return
                    }
                }
            }

            HStack {
                Text("Picture Directory")
                    .frame(width: 128, alignment: .trailing)
                TextField("", text: $pictureDirectory)
                Button("...") {
                    pictureDirectoryPickerPresent = true
                }
                .fileImporter(isPresented: $pictureDirectoryPickerPresent, allowedContentTypes: [.directory]) { result in
                    switch result {
                    case let .success(success):
                        pictureDirectory = success.path
                    default: return
                    }
                }
            }
            HStack {
                Text("Overwrite")
                    .frame(width: 128, alignment: .trailing)
                Toggle("", isOn: $overwrite)
                Spacer()
            }

            Divider()

            Button("Run") {
                run = true
            }
            .sheet(isPresented: $run) {
                WorkerView(
                    gpsLocation: $gpsLocation,
                    pictureDirectory: $pictureDirectory,
                    overwrite: $overwrite
                )
            }
        }
        .frame(width: 500)
        .padding()
    }
}

struct WorkerView: View {
    @StateObject var worker = Worker()
    @Binding var gpsLocation: String
    @Binding var pictureDirectory: String
    @Binding var overwrite: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            ScrollView {
                Text(worker.logs)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack(alignment: .center, spacing: 0) {
                Text(worker.logs.components(separatedBy: "\n").filter { !$0.isEmpty }.last ?? "")
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .disabled(!worker.completed)
            }
            .padding()
        }
        .frame(width: 555, height: 333)
        .task {
            worker.executeCommandLine(
                locationRecord: gpsLocation,
                photoDirectory: pictureDirectory,
                overwrite: overwrite
            )
        }
    }
}

#Preview {
    ContentView()
}
