//
//  ContentView.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("gpsLocation")
    var gpsLocation: String = ""
    @AppStorage("pictureDirectory")
    var pictureDirectory: String = ""
    @AppStorage("overwrite")
    var overwrite: Bool = false

    @State var gpsLocationPickerPresent = false
    @State var pictureDirectoryPickerPresent = false
    @State var run = false

    private var canRun: Bool {
        !gpsLocation.isEmpty && !pictureDirectory.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GPS Record File").bold()
                HStack(spacing: 8) {
                    TextField("Select a CSV file...", text: $gpsLocation)
                        .textFieldStyle(.roundedBorder)
                    Button("...") {
                        gpsLocationPickerPresent = true
                    }
                    .fileImporter(
                        isPresented: $gpsLocationPickerPresent,
                        allowedContentTypes: [.commaSeparatedText, .data],
                    ) { result in
                        if case let .success(url) = result {
                            gpsLocation = url.path
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Picture Directory").bold()
                HStack(spacing: 8) {
                    TextField("Select a folder...", text: $pictureDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("...") {
                        pictureDirectoryPickerPresent = true
                    }
                    .fileImporter(
                        isPresented: $pictureDirectoryPickerPresent,
                        allowedContentTypes: [.folder],
                    ) { result in
                        if case let .success(url) = result {
                            pictureDirectory = url.path
                        }
                    }
                }
            }

            Divider().padding(.horizontal, -64)

            HStack {
                Toggle("Overwrite existing GPS data", isOn: $overwrite)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Start Processing") {
                    run = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRun)
                .sheet(isPresented: $run) {
                    WorkerView(
                        gpsLocation: $gpsLocation,
                        pictureDirectory: $pictureDirectory,
                        overwrite: $overwrite,
                    )
                }
            }
        }
        .frame(width: 444)
        .padding()
    }
}
