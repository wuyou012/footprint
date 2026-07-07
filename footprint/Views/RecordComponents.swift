import SwiftUI

struct MapOptionsMenu: View {
    @Binding var mapStyle: FootprintMapStyle
    @Binding var trackTint: TrackTint

    var body: some View {
        Menu {
            Picker("Base map", selection: $mapStyle) {
                ForEach(FootprintMapStyle.allCases) { style in
                    Label(style.label, systemImage: style.symbolName)
                        .tag(style)
                }
            }
            Picker("Track color", selection: $trackTint) {
                ForEach(TrackTint.allCases) { tint in
                    Text(tint.label)
                        .tag(tint)
                }
            }
        } label: {
            Label("Map", systemImage: "map")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.bold))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
        }
    }
}

struct ModeSelector: View {
    @Binding var selection: RecordingProfile
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(RecordingProfile.allCases) { profile in
                    Button {
                        selection = profile
                    } label: {
                        Text(profile.label)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == profile ? .white : Color.primary.opacity(0.72))
                    .background(selection == profile ? Color.teal : Color(.systemGray5).opacity(0.70))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(disabled && selection != profile ? 0.4 : 1)
                    .disabled(disabled)
                }
            }
            Text(selection.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct RecordStatusPanel: View {
    let stats: RecordingStats
    let modeLabel: String

    var body: some View {
        HStack(spacing: 0) {
            StatColumn(label: "Time", value: AppFormatters.formatDuration(stats.durationSeconds))
            StatColumn(label: "Distance", value: AppFormatters.formatDistance(stats.distanceMeters))
            StatColumn(label: "Points", value: "\(stats.acceptedCount)")
            StatColumn(label: "Mode", value: modeLabel)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LowPowerRecordingView: View {
    let stats: RecordingStats
    let modeLabel: String
    let onStop: () -> Void
    let onShowMap: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text("Recording · \(modeLabel)")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            Text(AppFormatters.formatDuration(stats.durationSeconds))
                .font(.system(size: 64, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            HStack(spacing: 48) {
                Metric(label: "Distance", value: AppFormatters.formatDistance(stats.distanceMeters))
                Metric(label: "Points", value: "\(stats.acceptedCount)")
            }
            .foregroundStyle(.white)

            Text("Last fix \(AppFormatters.formatRelativeTime(stats.lastFixMs)) · \(AppFormatters.formatAccuracy(stats.lastAccuracy))")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))

            HStack(spacing: 14) {
                Button(role: .destructive, action: onStop) {
                    Text("Stop")
                        .font(.headline.weight(.bold))
                        .frame(width: 112)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onShowMap) {
                    Text("View map")
                        .font(.headline.weight(.semibold))
                        .frame(width: 112)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            Text("Screen-on recording. Keep this screen open; locking may pause GPS.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(Color.black)
    }
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .textCase(.uppercase)
        }
    }
}
