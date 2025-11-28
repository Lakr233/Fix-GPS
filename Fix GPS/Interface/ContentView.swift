//
//  ContentView.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import PhotosUI
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

    @State var photoPickerItems: [PhotosPickerItem] = []
    @State var photoPickerProcessing = false
    @State var photoPickerResult: PhotoPickerResult?

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
                Text("Photos Folder").bold()
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
                PhotosPicker(
                    selection: $photoPickerItems,
                    matching: .images,
                    photoLibrary: .shared(),
                ) {
                    Text("Or select photos from System Library")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(gpsLocation.isEmpty)
                .onChange(of: photoPickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    processPhotoPicker(items: items)
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
        .sheet(isPresented: $photoPickerProcessing) {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Processing photos...")
                    .font(.headline)
            }
            .frame(width: 200, height: 120)
            .interactiveDismissDisabled()
        }
        .alert(
            "Processing Complete",
            isPresented: Binding(
                get: { photoPickerResult != nil },
                set: { if !$0 { photoPickerResult = nil } },
            ),
        ) {
            Button("OK") { photoPickerResult = nil }
        } message: {
            if let result = photoPickerResult {
                Text("\(result.successCount) updated, \(result.errorCount) error(s)")
            }
        }
    }

    private func processPhotoPicker(items: [PhotosPickerItem]) {
        photoPickerProcessing = true
        photoPickerItems = []

        Task.detached {
            let vm = ViewModel()
            let result = await vm.processPhotoPickerItems(
                items,
                gpsFilePath: gpsLocation,
                overwrite: overwrite,
            )
            await MainActor.run {
                photoPickerProcessing = false
                photoPickerResult = result
            }
        }
    }
}
