import SwiftUI

struct RecordView: View {
    @ObservedObject var recorder: RecordingManager
    let onOpenHistory: () -> Void

    @AppStorage("record.selectedProfile") private var selectedProfileRaw = RecordingProfile.daily.rawValue
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
    @State private var recordingPulse = false

    var body: some View {
        Group {
            if showingSettings {
                RecordSettingsView(
                    selectedProfile: selectedProfileBinding,
                    persistentRecordingEnabled: persistentRecordingBinding,
                    mapStyle: $mapStyle,
                    mapDimension: $mapDimension,
                    poiVisibility: $poiVisibility,
                    mapTintColor: mapTintColorBinding,
                    mapTintStrength: $mapTintStrength,
                    trackColor: trackColorBinding,
                    recording: recorder.recording,
                    backgroundRecordingEnabled: recorder.backgroundRecordingEnabled,
                    persistentStatus: recorder.persistentStatus,
                    canExport: canExportCurrentTrack,
                    exporting: exporting,
                    exportError: exportError,
                    onBack: { showingSettings = false },
                    onPersistentRecordingChanged: setPersistentRecording,
                    onExport: exportCurrentTrack,
                    onExportDiagnostics: exportDiagnostics,
                    onClearDiagnostics: clearDiagnostics
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
                mapAnchorCoordinate: recorder.mapAnchorCoordinate,
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
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                recordingPulse = true
            }
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

            recordingIndicator

            Spacer()

            if !recorder.recording || recorder.persistentRecordingEnabled {
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

    private var persistentControlBar: some View {
        VStack(spacing: 8) {
            Text("常驻记录已开启 · \(selectedProfile.label) · 自动后台记录，无需手动 Start")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                setPersistentRecording(false)
            } label: {
                Label("关闭常驻记录", systemImage: "stop.circle.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color(.systemGray).opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 12) {
            if recorder.persistentRecordingEnabled {
                persistentControlBar
            } else if recorder.recording {
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
                    Label(
                        recorder.persistentRecordingEnabled ? "Persistent recording active" : "Start \(selectedProfile.label)",
                        systemImage: recorder.persistentRecordingEnabled ? "location.circle.fill" : "location.fill"
                    )
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(recorder.busy || recorder.persistentRecordingEnabled ? Color.teal.opacity(0.45) : Color.teal)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(recorder.busy || recorder.persistentRecordingEnabled)

            }
        }
    }

    private var recordingIndicator: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(indicatorDotColor)
                .frame(width: 10, height: 10)
                .opacity(recorder.isSampling && recordingPulse ? 0.3 : 1)
            Text(indicatorText)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(recorder.isSampling ? Color.red.opacity(0.9) : Color.black.opacity(0.72))
        .clipShape(Capsule())
    }

    private var indicatorDotColor: Color {
        if recorder.errorMessage != nil || exportError != nil { return .yellow }
        if recorder.isSampling { return .white }
        if recorder.persistentRecordingEnabled { return .orange }
        return .gray
    }

    private var indicatorText: String {
        if recorder.busy { return "Loading…" }
        if let message = recorder.errorMessage ?? exportError { return message }
        if recorder.isSampling {
            return "记录中 · \(recorder.stats.acceptedCount.formatted()) 点"
        }
        if recorder.persistentRecordingEnabled {
            return "常驻待命 · 移动即记录"
        }
        return "\(recorder.totalPointCount.formatted()) 已保存"
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
        if recorder.persistentRecordingEnabled {
            return recorder.persistentStatus
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

    private var selectedProfile: RecordingProfile {
        RecordingProfile(rawValue: selectedProfileRaw) ?? .daily
    }

    private var selectedProfileBinding: Binding<RecordingProfile> {
        Binding(
            get: { selectedProfile },
            set: { selectedProfileRaw = $0.rawValue }
        )
    }

    private var persistentRecordingBinding: Binding<Bool> {
        Binding(
            get: { recorder.persistentRecordingEnabled },
            set: { setPersistentRecording($0) }
        )
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

    private func setPersistentRecording(_ enabled: Bool) {
        exportError = nil
        recorder.setPersistentRecording(enabled, profile: selectedProfile)
    }

    private func exportDiagnostics() {
        shareItem = ShareItem(url: DiagnosticLogFile.shared.url)
    }

    private func clearDiagnostics() {
        DiagnosticLogFile.shared.clear()
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
