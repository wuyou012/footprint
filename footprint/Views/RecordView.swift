import SwiftUI

struct RecordView: View {
    @ObservedObject var recorder: RecordingManager
    let onOpenHistory: () -> Void

    @State private var selectedProfile: RecordingProfile = .daily
    @State private var lowPower = false
    @State private var exporting = false
    @State private var exportError: String?
    @State private var shareItem: ShareItem?
    @AppStorage("record.mapTint.red") private var mapTintRed = 84
    @AppStorage("record.mapTint.green") private var mapTintGreen = 132
    @AppStorage("record.mapTint.blue") private var mapTintBlue = 255
    @AppStorage("record.mapTint.strength") private var mapTintStrength = 0.0
    @AppStorage("record.track.red") private var trackRed = 0
    @AppStorage("record.track.green") private var trackGreen = 158
    @AppStorage("record.track.blue") private var trackBlue = 184

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
                    recording: recorder.recording,
                    backgroundRecordingEnabled: recorder.backgroundRecordingEnabled,
                    canExport: canExportCurrentTrack,
                    exporting: exporting,
                    exportError: exportError,
                    onBack: { showingSettings = false },
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
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
    }

    private var mapScene: some View {
        ZStack {
            TrackMapView(
                points: recorder.points,
                followLatest: recorder.recording,
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
