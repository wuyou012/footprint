import PhotosUI
import SwiftUI

struct RecordSettingsView: View {
    @Binding var selectedProfile: RecordingProfile
    @Binding var mapStyle: FootprintMapStyle
    @Binding var mapDimension: FootprintMapDimension
    @Binding var poiVisibility: FootprintPOIVisibility
    @Binding var mapTintColor: RGBColor
    @Binding var mapTintStrength: Double
    @Binding var trackColor: RGBColor
    @Binding var photoMarkerRenderMode: PhotoMarkerRenderMode
    @Binding var photoMarkerShape: PhotoMarkerShape
    @Binding var photoMarkerColor: RGBColor
    @Binding var photoMarkerSize: Double

    let photoPointCount: Int
    let importingPhotos: Bool
    let photoImportMessage: String?
    let recording: Bool
    let backgroundRecordingEnabled: Bool
    let canExport: Bool
    let exporting: Bool
    let exportError: String?
    let onBack: () -> Void
    let onImportPhotoLibrary: (PhotoLibraryImportScope) -> Void
    let onImportPhotoAlbum: (PhotoAlbumSummary) -> Void
    let onImportPhotos: ([PhotosPickerItem]) -> Void
    let onClearPhotoPoints: () -> Void
    let onExport: () -> Void

    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Recording") {
                    Picker("Mode", selection: $selectedProfile) {
                        ForEach(RecordingProfile.allCases) { profile in
                            Text(profile.label)
                                .tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(recording)

                    Text(selectedProfile.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if recording {
                        LabeledContent("Status", value: backgroundRecordingEnabled ? "Background enabled" : "Recording")
                    } else {
                        LabeledContent("Background", value: backgroundRecordingEnabled ? "Ready" : "Needs Always Location")
                    }
                }

                Section("Map") {
                    Picker("Perspective", selection: $mapDimension) {
                        ForEach(FootprintMapDimension.allCases) { dimension in
                            Text(dimension.label)
                                .tag(dimension)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Place names", selection: $poiVisibility) {
                        ForEach(FootprintPOIVisibility.allCases) { visibility in
                            Text(visibility.label)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Color", selection: $mapStyle) {
                        ForEach(FootprintMapStyle.allCases) { style in
                            Label(style.label, systemImage: style.symbolName)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.inline)

                    RGBColorEditor(title: "Map tint", rgb: $mapTintColor)

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Tint strength", value: "\(Int((mapTintStrength * 100).rounded()))%")
                            .font(.subheadline)
                        Slider(value: $mapTintStrength, in: 0...0.60, step: 0.05)
                    }
                }

                Section("Track") {
                    RGBColorEditor(title: "Track color", rgb: $trackColor)
                }

                Section("Photos") {
                    Button {
                        onImportPhotoLibrary(.all)
                    } label: {
                        Label("Import all photos", systemImage: PhotoLibraryImportScope.all.symbolName)
                    }
                    .disabled(importingPhotos)

                    NavigationLink {
                        PhotoAlbumPickerView(
                            importingPhotos: importingPhotos,
                            onImportAlbum: onImportPhotoAlbum
                        )
                    } label: {
                        Label("Choose album", systemImage: "rectangle.stack")
                    }
                    .disabled(importingPhotos)

                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 30,
                        matching: .images,
                        preferredItemEncoding: .current
                    ) {
                        Label(importingPhotos ? "Importing..." : "Choose specific photos", systemImage: "photo.on.rectangle")
                    }
                    .disabled(importingPhotos)
                    .onChange(of: selectedPhotoItems) { _, items in
                        guard !items.isEmpty else { return }
                        onImportPhotos(items)
                        selectedPhotoItems = []
                    }

                    LabeledContent("Imported", value: "\(photoPointCount)")

                    Picker("Point type", selection: $photoMarkerRenderMode) {
                        ForEach(PhotoMarkerRenderMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbolName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    if photoMarkerRenderMode == .fixedMarker {
                        Picker("Point shape", selection: $photoMarkerShape) {
                            ForEach(PhotoMarkerShape.allCases) { shape in
                                Label(shape.label, systemImage: shape.symbolName)
                                    .tag(shape)
                            }
                        }
                        .pickerStyle(.inline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Point size", value: "\(Int(photoMarkerSize.rounded()))")
                            .font(.subheadline)
                        Slider(value: $photoMarkerSize, in: 6...32, step: 1)
                    }

                    RGBColorEditor(title: "Point color", rgb: $photoMarkerColor)

                    Button(role: .destructive) {
                        onClearPhotoPoints()
                    } label: {
                        Label("Clear photo points", systemImage: "trash")
                    }
                    .disabled(photoPointCount == 0 || importingPhotos)

                    if importingPhotos {
                        ProgressView("Reading photo locations")
                    }

                    if let photoImportMessage {
                        Text(photoImportMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Export") {
                    Button {
                        onExport()
                    } label: {
                        Label(exporting ? "Exporting..." : "Export GPX", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!canExport || exporting)

                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
    }
}

private struct PhotoAlbumPickerView: View {
    let importingPhotos: Bool
    let onImportAlbum: (PhotoAlbumSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PhotoAlbumSummary] = []
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        List {
            if loading {
                ProgressView("Loading albums")
            } else if albums.isEmpty {
                Text(message ?? "No albums found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(albums) { album in
                    Button {
                        onImportAlbum(album)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Label(album.title, systemImage: "rectangle.stack")
                                .lineLimit(2)
                            Spacer(minLength: 12)
                            Text(album.assetCount.formatted())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(importingPhotos)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Choose album")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAlbums()
        }
        .refreshable {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        loading = true
        message = nil
        let result = await PhotoLocationExtractor.photoAlbums()
        albums = result.albums
        loading = false

        if result.denied {
            message = "Photo library access is required."
        } else if result.limitedAccess {
            message = "Limited photo access is active."
        }
    }
}
