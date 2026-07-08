import PhotosUI
import SwiftUI

struct RecordView: View {
    @ObservedObject var recorder: RecordingManager
    let onOpenHistory: () -> Void
    let onOpenAchievements: () -> Void

    @State private var selectedProfile: RecordingProfile = .daily
    @State private var lowPower = false
    @State private var exporting = false
    @State private var importingPhotos = false
    @State private var exportError: String?
    @State private var photoImportMessage: String?
    @State private var shareItem: ShareItem?
    @State private var photoPoints: [PhotoMapPoint] = []
    @State private var photoStorageRevision = 0
    @AppStorage("record.mapTint.red") private var mapTintRed = 84
    @AppStorage("record.mapTint.green") private var mapTintGreen = 132
    @AppStorage("record.mapTint.blue") private var mapTintBlue = 255
    @AppStorage("record.mapTint.strength") private var mapTintStrength = 0.0
    @AppStorage("record.track.red") private var trackRed = 0
    @AppStorage("record.track.green") private var trackGreen = 158
    @AppStorage("record.track.blue") private var trackBlue = 184
    @AppStorage("record.photoPoints") private var storedPhotoPoints = "[]"
    @AppStorage("record.photoMarker.red") private var photoMarkerRed = 255
    @AppStorage("record.photoMarker.green") private var photoMarkerGreen = 62
    @AppStorage("record.photoMarker.blue") private var photoMarkerBlue = 128
    @AppStorage("record.photoMarker.size") private var photoMarkerSize = 12.0
    @AppStorage("record.photoMarker.renderMode") private var photoMarkerRenderModeRaw = PhotoMarkerRenderMode.mapDot.rawValue
    @AppStorage("record.photoMarker.shape") private var photoMarkerShapeRaw = PhotoMarkerShape.circle.rawValue

    @State private var mapStyle: FootprintMapStyle = .standard
    @State private var mapDimension: FootprintMapDimension = .twoD
    @State private var poiVisibility: FootprintPOIVisibility = .shown
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                RecordSettingsView(
                    selectedProfile: $selectedProfile,
                    mapStyle: $mapStyle,
                    mapDimension: $mapDimension,
                    poiVisibility: $poiVisibility,
                    mapTintColor: mapTintColorBinding,
                    mapTintStrength: $mapTintStrength,
                    trackColor: trackColorBinding,
                    photoMarkerRenderMode: photoMarkerRenderModeBinding,
                    photoMarkerShape: photoMarkerShapeBinding,
                    photoMarkerColor: photoMarkerColorBinding,
                    photoMarkerSize: $photoMarkerSize,
                    photoPointCount: photoPoints.count,
                    importingPhotos: importingPhotos,
                    photoImportMessage: photoImportMessage,
                    recording: recorder.recording,
                    backgroundRecordingEnabled: recorder.backgroundRecordingEnabled,
                    canExport: canExportCurrentTrack,
                    exporting: exporting,
                    exportError: exportError,
                    onBack: { showingSettings = false },
                    onImportPhotoLibrary: importPhotoLibrary,
                    onImportPhotoAlbum: importPhotoAlbum,
                    onImportPhotos: importPhotoItems,
                    onClearPhotoPoints: clearPhotoPoints,
                    onExport: exportCurrentTrack
                )
            } else if recorder.recording && lowPower {
                LowPowerRecordingView(
                    stats: recorder.stats,
                    modeLabel: selectedProfile.label,
                    onStop: stop,
                    onShowMap: { lowPower = false }
                )
            } else {
                mapScene
            }
        }
        .onAppear(perform: loadPhotoPointsFromStorage)
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
    }

    private var mapScene: some View {
        ZStack {
            TrackMapView(
                points: recorder.points,
                followLatest: recorder.recording,
                photoPoints: photoPoints,
                photoMarkerRenderMode: photoMarkerRenderMode,
                photoMarkerShape: photoMarkerShape,
                photoMarkerColor: photoMarkerColor,
                photoMarkerSize: photoMarkerSize,
                mapStyle: mapStyle,
                mapDimension: mapDimension,
                poiVisibility: poiVisibility,
                mapTintColor: mapTintColor,
                mapTintStrength: mapTintStrength,
                appearance: mapAppearance
            )
                .ignoresSafeArea()

            VStack {
                topOverlay
                Spacer()
                bottomOverlay
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
            .padding(.bottom, 32)
        }
    }

    private var topOverlay: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel("Settings")

            Text(recorder.busy ? "Loading..." : badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer()

            if !recorder.recording {
                VStack(alignment: .trailing, spacing: 8) {
                    Button(action: onOpenAchievements) {
                        Label("Awards", systemImage: "trophy.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.bold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .disabled(recorder.busy)

                    Button(action: onOpenHistory) {
                        Label("History", systemImage: "clock.arrow.circlepath")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.bold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .disabled(recorder.busy)
                }
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 12) {
            if recorder.recording {
                RecordStatusPanel(stats: recorder.stats, modeLabel: selectedProfile.label)
                HStack(spacing: 12) {
                    Button(action: stop) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        lowPower = true
                    } label: {
                        Label("Low power", systemImage: "moon.fill")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(Color(.systemGray6).opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                Button(action: start) {
                    Label("Start \(selectedProfile.label)", systemImage: "location.fill")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(recorder.busy ? Color.teal.opacity(0.45) : Color.teal)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(recorder.busy)

            }
        }
    }

    private var badgeText: String {
        if let message = recorder.errorMessage ?? exportError {
            return message
        }
        if recorder.recording {
            return recorder.backgroundRecordingEnabled
                ? "\(recorder.stats.acceptedCount.formatted()) points · BG"
                : "\(recorder.stats.acceptedCount.formatted()) points"
        }
        return "\(recorder.totalPointCount.formatted()) saved"
    }

    private var mapAppearance: TrackMapAppearance {
        var appearance = TrackMapAppearance.custom(trackColor: trackColor)
        appearance.showsTrackPoints = recorder.recording
        appearance.lineWidth = recorder.recording ? 4.5 : 3.5
        return appearance
    }

    private var mapTintColor: RGBColor {
        RGBColor(red: mapTintRed, green: mapTintGreen, blue: mapTintBlue)
    }

    private var trackColor: RGBColor {
        RGBColor(red: trackRed, green: trackGreen, blue: trackBlue)
    }

    private var photoMarkerColor: RGBColor {
        RGBColor(red: photoMarkerRed, green: photoMarkerGreen, blue: photoMarkerBlue)
    }

    private var photoMarkerShape: PhotoMarkerShape {
        PhotoMarkerShape(rawValue: photoMarkerShapeRaw) ?? .circle
    }

    private var photoMarkerRenderMode: PhotoMarkerRenderMode {
        PhotoMarkerRenderMode(rawValue: photoMarkerRenderModeRaw) ?? .mapDot
    }

    private var mapTintColorBinding: Binding<RGBColor> {
        Binding(
            get: { mapTintColor },
            set: {
                mapTintRed = $0.red
                mapTintGreen = $0.green
                mapTintBlue = $0.blue
            }
        )
    }

    private var trackColorBinding: Binding<RGBColor> {
        Binding(
            get: { trackColor },
            set: {
                trackRed = $0.red
                trackGreen = $0.green
                trackBlue = $0.blue
            }
        )
    }

    private var photoMarkerColorBinding: Binding<RGBColor> {
        Binding(
            get: { photoMarkerColor },
            set: {
                photoMarkerRed = $0.red
                photoMarkerGreen = $0.green
                photoMarkerBlue = $0.blue
            }
        )
    }

    private var photoMarkerRenderModeBinding: Binding<PhotoMarkerRenderMode> {
        Binding(
            get: { photoMarkerRenderMode },
            set: { photoMarkerRenderModeRaw = $0.rawValue }
        )
    }

    private var photoMarkerShapeBinding: Binding<PhotoMarkerShape> {
        Binding(
            get: { photoMarkerShape },
            set: { photoMarkerShapeRaw = $0.rawValue }
        )
    }

    private var canExportCurrentTrack: Bool {
        recorder.exportableSessionID != nil && !recorder.points.isEmpty && !recorder.recording
    }

    private func start() {
        exportError = nil
        recorder.start(profile: selectedProfile)
    }

    private func stop() {
        lowPower = false
        recorder.stop()
    }

    private func importPhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, !importingPhotos else { return }
        importingPhotos = true
        photoImportMessage = nil

        Task {
            var candidates: [PhotoMapPoint] = []
            var skipped = 0

            for item in items {
                do {
                    if let point = try await photoPoint(for: item) {
                        candidates.append(point)
                    } else {
                        skipped += 1
                    }
                } catch {
                    skipped += 1
                }
            }

            await MainActor.run {
                let imported = mergePhotoPoints(candidates)
                importingPhotos = false
                photoImportMessage = photoImportSummary(
                    imported: imported,
                    skipped: skipped,
                    duplicate: candidates.count - imported
                )
            }
        }
    }

    private func importPhotoLibrary(_ scope: PhotoLibraryImportScope) {
        importPhotoMetadata(named: scope.label) {
            await PhotoLocationExtractor.photoPoints(from: scope)
        }
    }

    private func importPhotoAlbum(_ album: PhotoAlbumSummary) {
        importPhotoMetadata(named: album.title) {
            await PhotoLocationExtractor.photoPoints(fromAlbumID: album.id)
        }
    }

    private func importPhotoMetadata(
        named sourceName: String,
        load: @escaping () async -> PhotoLocationExtractor.LibraryImportResult
    ) {
        guard !importingPhotos else { return }
        importingPhotos = true
        photoImportMessage = nil

        Task {
            let result = await load()

            await MainActor.run {
                if result.denied {
                    importingPhotos = false
                    photoImportMessage = "Photo library access is required to import \(sourceName)."
                    return
                }

                let imported = mergePhotoPoints(result.points)
                importingPhotos = false
                photoImportMessage = "\(sourceName): " + photoImportSummary(
                    imported: imported,
                    skipped: result.skippedCount,
                    duplicate: result.points.count - imported,
                    scanned: result.scannedCount,
                    limitedAccess: result.limitedAccess
                )
            }
        }
    }

    private func photoPoint(for item: PhotosPickerItem) async throws -> PhotoMapPoint? {
        if let identifier = item.itemIdentifier,
           let coordinate = await PhotoLocationExtractor.coordinateFromPhotoAsset(identifier: identifier) {
            return PhotoMapPoint(
                id: identifier,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }

        guard let data = try await item.loadTransferable(type: Data.self) else {
            return nil
        }
        let coordinate = await Task.detached(priority: .userInitiated) {
            PhotoLocationExtractor.coordinateFromImageData(data)
        }.value
        guard let coordinate else {
            return nil
        }
        return PhotoMapPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    @discardableResult
    private func mergePhotoPoints(_ candidates: [PhotoMapPoint]) -> Int {
        guard !candidates.isEmpty else { return 0 }

        var merged = photoPoints
        var importedIDs = Set(merged.map(\.id))
        var importedCount = 0

        for point in candidates where importedIDs.insert(point.id).inserted {
            merged.append(point)
            importedCount += 1
        }

        if importedCount > 0 {
            savePhotoPoints(merged)
        }
        return importedCount
    }

    private func savePhotoPoints(_ points: [PhotoMapPoint]) {
        photoPoints = points
        photoStorageRevision += 1
        let revision = photoStorageRevision

        Task {
            let json = await Task.detached(priority: .utility) {
                Self.encodePhotoPoints(points)
            }.value
            guard revision == photoStorageRevision, let json else { return }
            storedPhotoPoints = json
        }
    }

    private func clearPhotoPoints() {
        savePhotoPoints([])
        photoImportMessage = nil
    }

    private func loadPhotoPointsFromStorage() {
        let json = storedPhotoPoints
        Task {
            let decoded = await Task.detached(priority: .utility) {
                Self.decodePhotoPoints(json)
            }.value
            photoPoints = decoded
        }
    }

    nonisolated private static func decodePhotoPoints(_ json: String) -> [PhotoMapPoint] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PhotoMapPoint].self, from: data)
        else { return [] }
        return decoded
    }

    nonisolated private static func encodePhotoPoints(_ points: [PhotoMapPoint]) -> String? {
        guard let data = try? JSONEncoder().encode(points) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func photoImportSummary(
        imported: Int,
        skipped: Int,
        duplicate: Int = 0,
        scanned: Int? = nil,
        limitedAccess: Bool = false
    ) -> String {
        var parts: [String] = []
        if let scanned {
            parts.append("Scanned \(scanned)")
        }
        if imported > 0 {
            parts.append("imported \(imported)")
        }
        if skipped > 0 {
            parts.append("skipped \(skipped) without location")
        }
        if duplicate > 0 {
            parts.append("ignored \(duplicate) already imported")
        }
        if imported == 0, skipped == 0, duplicate == 0 {
            parts.append("no GPS location found")
        }
        var message = parts.joined(separator: ", ") + "."
        if limitedAccess {
            message += " Limited photo access is active."
        }
        return message
    }

    private func exportCurrentTrack() {
        guard !exporting,
              !recorder.recording,
              let sessionID = recorder.exportableSessionID
        else { return }
        exporting = true
        exportError = nil
        do {
            shareItem = ShareItem(url: try GPXExporter.write(sessionID: sessionID))
        } catch {
            exportError = AppFormatters.errorMessage(error)
        }
        exporting = false
    }
}
