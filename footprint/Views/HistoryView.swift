import SwiftUI

struct HistoryView: View {
    let onBack: () -> Void
    let onSelectDay: (String) -> Void

    @State private var summaries: [DaySummary] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading history")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if summaries.isEmpty {
                    ContentUnavailableView(
                        "No recordings yet",
                        systemImage: "figure.walk",
                        description: Text("Start a session or enable persistent recording and it will appear here by local day.")
                    )
                } else {
                    List(summaries) { summary in
                        Button {
                            onSelectDay(summary.dayKey)
                        } label: {
                            DayCard(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", action: onBack)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        load()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
            .task { load() }
        }
    }

    private func load() {
        loading = true
        errorMessage = nil
        do {
            summaries = try TrackDatabase.shared.loadDaySummaries()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        loading = false
    }
}

private struct DayCard: View {
    let summary: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppFormatters.formatDayKey(summary.dayKey))
                    .font(.headline.weight(.bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text("\(summary.sessionCount.formatted()) trips · \(summary.pointCount.formatted()) points")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(AppFormatters.formatDistance(summary.distanceMeters))
                Text(AppFormatters.formatDuration(summary.durationSeconds))
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.teal)
        }
        .padding(.vertical, 8)
    }
}
