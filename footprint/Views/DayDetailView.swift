import SwiftUI

struct DayDetailView: View {
    let dayKey: String
    let onBack: () -> Void
    let onDeleted: () -> Void

    @State private var sessions: [DaySession] = []
    @State private var points: [TrackPoint] = []
    @State private var loading = true
    @State private var exporting = false
    @State private var deleting = false
    @State private var errorMessage: String?
    @State private var shareItem: ShareItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading day")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            TrackMapView(points: points)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            HStack(spacing: 12) {
                                Button(action: exportDay) {
                                    Label(exporting ? "Exporting" : "Export GPX", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(actionDisabled || points.isEmpty)

                                Button(role: .destructive) {
                                    showDeleteConfirmation = true
                                } label: {
                                    Label(deleting ? "Deleting" : "Delete day", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(actionDisabled)
                            }

                            Text("Sessions")
                                .font(.title3.weight(.bold))
                                .padding(.top, 4)

                            if sessions.isEmpty {
                                Text("No sessions for this day.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(sessions) { session in
                                        SessionRow(session: session)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(AppFormatters.formatDayKey(dayKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", action: onBack)
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
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
            .confirmationDialog(
                "Delete this day?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteDay)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes this day from local history. Other days are not touched.")
            }
            .task { load() }
        }
    }

    private var totalDistance: Double {
        sessions.reduce(0) { $0 + $1.distanceMeters }
    }

    private var actionDisabled: Bool {
        loading || exporting || deleting
    }

    private func load() {
        loading = true
        errorMessage = nil
        do {
            sessions = try TrackDatabase.shared.loadSessions(for: dayKey)
            points = try TrackDatabase.shared.loadTrackPoints(for: dayKey)
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        loading = false
    }

    private func exportDay() {
        guard !actionDisabled, !points.isEmpty else { return }
        exporting = true
        errorMessage = nil
        do {
            shareItem = ShareItem(url: try GPXExporter.write(points: points))
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        exporting = false
    }

    private func deleteDay() {
        guard !actionDisabled else { return }
        deleting = true
        errorMessage = nil
        do {
            try TrackDatabase.shared.deleteDay(dayKey)
            onDeleted()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
            deleting = false
        }
    }
}

private struct SessionRow: View {
    let session: DaySession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppFormatters.formatClockRange(start: session.startMs, end: session.endMs))
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(session.profile?.rawValue.uppercased() ?? "UNKNOWN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
            }
            Text("\(session.pointCount.formatted()) points · \(AppFormatters.formatDistance(session.distanceMeters))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
