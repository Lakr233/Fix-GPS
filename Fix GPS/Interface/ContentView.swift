//
//  ContentView.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import Photos
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
    @State var showPhotosPicker = false
    @State var showPermissionAlert = false

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
                Button {
                    checkPhotoLibraryPermission()
                } label: {
                    Text("Or select photos from System Library")
                        .font(.footnote)
                        .underline()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(gpsLocation.isEmpty)
                .photosPicker(
                    isPresented: $showPhotosPicker,
                    selection: $photoPickerItems,
                    matching: .images,
                    photoLibrary: .shared()
                )
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
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Full photo library access is required to modify photos. Please grant access in System Settings.")
        }
    }

    private func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            showPhotosPicker = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        showPhotosPicker = true
                    } else {
                        showPermissionAlert = true
                    }
                }
            }
        default:
            showPermissionAlert = true
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
