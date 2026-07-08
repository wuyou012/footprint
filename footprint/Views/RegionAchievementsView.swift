import Combine
import SwiftUI

struct RegionAchievementsView: View {
    let onBack: () -> Void

    @StateObject private var model = RegionAchievementsViewModel()
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if model.loading && model.countries.isEmpty {
                    ProgressView("Loading achievements")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.countries.isEmpty {
                    ContentUnavailableView(
                        "No regions unlocked yet",
                        systemImage: "trophy",
                        description: Text("No unlocked cities from saved tracks.")
                    )
                } else {
                    achievementsList
                }
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", action: onBack)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.sync() }
                    } label: {
                        Label("Refresh", systemImage: model.syncing ? "hourglass" : "arrow.clockwise")
                    }
                    .disabled(model.syncing)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.syncing)
                }
            }
            .safeAreaInset(edge: .bottom) {
                statusBar
            }
            .confirmationDialog(
                "Rescan achievements?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear and rescan", role: .destructive) {
                    Task { await model.resetAndRescan() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears unlocked regions and rebuilds them from saved track points.")
            }
            .task {
                await model.loadAndSyncIfNeeded()
            }
        }
    }

    private var achievementsList: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    AchievementMetric(value: model.countryCount, label: "Countries")
                    AchievementMetric(value: model.cityCount, label: "Cities")
                }
                .padding(.vertical, 6)

                NavigationLink {
                    RegionAchievementMapView()
                } label: {
                    Label("City Map", systemImage: "map.fill")
                }
            }

            ForEach(model.countries) { country in
                Section {
                    ForEach(country.cities) { city in
                        CityAchievementRow(city: city)
                    }
                } header: {
                    HStack {
                        Label(country.countryName, systemImage: "flag.fill")
                        Spacer()
                        Text("\(country.cityCount.formatted())")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if model.syncing || model.statusMessage != nil || model.errorMessage != nil {
            VStack(spacing: 6) {
                if model.syncing {
                    ProgressView()
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else if let statusMessage = model.statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}

private struct AchievementMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted())
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CityAchievementRow: View {
    let city: RegionAchievementCity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text(city.cityName)
                    .font(.headline)
                Text(city.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(AppFormatters.formatRelativeTime(city.lastSeenMs))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private final class RegionAchievementsViewModel: ObservableObject {
    @Published var countries: [RegionAchievementCountry] = []
    @Published var loading = true
    @Published var syncing = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let service = RegionAchievementService()
    private var didInitialSync = false

    var countryCount: Int { countries.count }
    var cityCount: Int { countries.reduce(0) { $0 + $1.cityCount } }

    func loadAndSyncIfNeeded() async {
        await load()
        guard !didInitialSync else { return }
        didInitialSync = true
        await sync()
    }

    func load() async {
        loading = true
        errorMessage = nil
        do {
            countries = try await service.loadCountries()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        loading = false
    }

    func sync() async {
        guard !syncing else { return }
        syncing = true
        statusMessage = "Scanning track regions..."
        errorMessage = nil
        do {
            let result = try await service.syncNextBatch()
            countries = try await service.loadCountries()
            statusMessage = syncMessage(for: result)
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        syncing = false
        loading = false
    }

    func resetAndRescan() async {
        guard !syncing else { return }
        syncing = true
        errorMessage = nil
        statusMessage = "Clearing achievements..."
        do {
            try await service.clear()
            countries = []
            didInitialSync = true
            syncing = false
            await sync()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
            syncing = false
        }
    }

    private func syncMessage(for result: RegionAchievementSyncResult) -> String {
        if result.scannedCells == 0 {
            return "All saved track regions have been scanned."
        }
        var message = "Scanned \(result.scannedCells), unlocked \(result.newCities) new cities."
        if result.hasMore {
            message += " Refresh to continue."
        }
        return message
    }
}
