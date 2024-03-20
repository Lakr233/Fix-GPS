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

    var lines: [String] {
        worker.logs
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text("Execution Log").bold()
                Spacer()
            }
            .padding()
            Divider()
            ScrollView {
                ScrollViewReader { value in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines, id: \.self) { line in
                            Text(line)
                        }
                        Text("").id("EOF")
                    }
                    .font(.system(.footnote))
                    .monospaced()
                    .onChange(of: lines) { _, _ in
                        value.scrollTo("EOF")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack(alignment: .center, spacing: 0) {
                Spacer()
                Button("Close") {
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
