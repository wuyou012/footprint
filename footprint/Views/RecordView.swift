import SwiftUI

struct RecordView: View {
    @ObservedObject var recorder: RecordingManager
    let onOpenHistory: () -> Void

    @State private var selectedProfile: RecordingProfile = .daily
    @State private var lowPower = false
    @State private var exporting = false
    @State private var exportError: String?
    @State private var shareItem: ShareItem?

    var body: some View {
        if recorder.recording && lowPower {
            LowPowerRecordingView(
                stats: recorder.stats,
                modeLabel: selectedProfile.label,
                onStop: stop,
                onShowMap: { lowPower = false }
            )
        } else {
            ZStack {
                TrackMapView(points: recorder.points, followLatest: recorder.recording)
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
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
        }
    }

    private var topOverlay: some View {
        HStack(alignment: .top, spacing: 12) {
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
                ModeSelector(selection: $selectedProfile, disabled: recorder.busy)
                Button(action: start) {
                    Label("Start recording", systemImage: "location.fill")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(recorder.busy ? Color.teal.opacity(0.45) : Color.teal)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(recorder.busy)

                if !recorder.points.isEmpty {
                    Button(action: exportCurrentTrack) {
                        Label(exporting ? "Exporting..." : "Export GPX", systemImage: "square.and.arrow.up")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(Color(.systemGray6).opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(exporting)
                }

                Text("Screen-on recording: this is an active, screen-awake session. Locking the screen may pause GPS. All-day background recording comes later.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var badgeText: String {
        recorder.errorMessage ?? exportError ?? "\(recorder.points.count.formatted()) points"
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
        guard !exporting, !recorder.recording, !recorder.points.isEmpty else { return }
        exporting = true
        exportError = nil
        do {
            shareItem = ShareItem(url: try GPXExporter.write(points: recorder.points))
        } catch {
            exportError = AppFormatters.errorMessage(error)
        }
        exporting = false
    }
}
