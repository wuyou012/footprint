import Combine
import CoreLocation
import Foundation
import UIKit

@MainActor
final class RecordingManager: NSObject, ObservableObject {
    @Published private(set) var points: [TrackPoint] = []
    @Published private(set) var recording = false
    @Published private(set) var busy = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var status = "Idle"
    @Published private(set) var stats = RecordingStats.idle
    @Published private(set) var totalPointCount = 0
    @Published private(set) var exportableSessionID: Int64?
    @Published private(set) var backgroundRecordingEnabled = false

    private let locationManager = CLLocationManager()
    private let store = TrackDatabase.shared
    private var activeSession: ActiveRecordingSession?
    private var timer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var userInterfaceActive = true
    private let maxVisiblePoints = 3_000

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false
        configureLifecycleObservers()
        Task { await bootstrap() }
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        timer?.invalidate()
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func reload() async {
        do {
            points = try store.loadLatestSessionTrackPoints(limit: maxVisiblePoints)
            totalPointCount = try store.trackPointCount()
            exportableSessionID = nil
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
    }

    private func bootstrap() async {
        busy = true
        defer { busy = false }
        do {
            try store.interruptOpenForegroundSessions(reason: "replaced")
            points = try store.loadLatestSessionTrackPoints(limit: maxVisiblePoints)
            totalPointCount = try store.trackPointCount()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
    }

    func start(profile: RecordingProfile) {
        guard !busy, !recording, activeSession == nil else { return }
        errorMessage = nil
        busy = true
        status = "Checking \(profile.label) GPS..."

        switch locationManager.authorizationStatus {
        case .notDetermined:
            pendingProfile = profile
            status = "Allow Always Location for background recording"
            locationManager.requestAlwaysAuthorization()
            busy = false
            return
        case .authorizedAlways:
            startAuthorized(profile: profile)
        case .authorizedWhenInUse:
            pendingProfile = profile
            status = "Requesting Always Location..."
            locationManager.requestAlwaysAuthorization()
            busy = false
        case .denied, .restricted:
            errorMessage = "Location permission denied"
            status = "GPS unavailable"
            busy = false
        @unknown default:
            errorMessage = "Unknown location permission state"
            status = "GPS unavailable"
            busy = false
        }
    }

    private var pendingProfile: RecordingProfile?

    private func startAuthorized(profile: RecordingProfile) {
        do {
            let startedAt = AppFormatters.nowMs()
            let sessionID = try store.startRecordingSession(profile: profile, startMs: startedAt)
            let segmentID = try store.startTrackSegment(sessionID: sessionID, startMs: startedAt)
            points = []
            exportableSessionID = sessionID
            activeSession = ActiveRecordingSession(
                sessionID: sessionID,
                segmentID: segmentID,
                profile: profile,
                startedAtMs: startedAt,
                receivedCount: 0,
                acceptedCount: 0,
                rejectedCount: 0,
                distanceMeters: 0,
                lastAccepted: nil
            )

            locationManager.desiredAccuracy = profile.desiredAccuracy
            locationManager.distanceFilter = profile.distanceFilter
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = false
            locationManager.startUpdatingLocation()
            UIApplication.shared.isIdleTimerDisabled = true
            backgroundRecordingEnabled = true
            recording = true
            busy = false
            status = "\(profile.label) recording"
            refreshStats()
            startTimer(interval: profile.statsRefreshInterval)
        } catch {
            activeSession = nil
            recording = false
            busy = false
            status = "GPS unavailable"
            errorMessage = AppFormatters.errorMessage(error)
        }
    }

    func stop() {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        UIApplication.shared.isIdleTimerDisabled = false

        do {
            if let activeSession {
                try store.finishRecordingSession(
                    sessionID: activeSession.sessionID,
                    segmentID: activeSession.segmentID,
                    endMs: AppFormatters.nowMs(),
                    status: "completed",
                    stopReason: "stopped",
                    receivedCount: activeSession.receivedCount,
                    rejectedCount: activeSession.rejectedCount,
                    distanceMeters: activeSession.distanceMeters
                )
            }
            activeSession = nil
            totalPointCount = try store.trackPointCount()
            backgroundRecordingEnabled = false
            recording = false
            stats = .idle
            status = "Stopped"
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
            status = "Stop failed"
        }
        busy = false
    }

    private func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        let refreshInterval = max(1, interval)
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStats()
            }
        }
        timer?.tolerance = min(2, refreshInterval * 0.2)
    }

    private func configureLifecycleObservers() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appDidEnterBackground()
            }
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appDidBecomeActive()
            }
        })
    }

    private func appDidEnterBackground() {
        userInterfaceActive = false
        timer?.invalidate()
        timer = nil
        if recording {
            points.removeAll(keepingCapacity: false)
            status = "Recording in background"
        }
    }

    private func appDidBecomeActive() {
        userInterfaceActive = true
        guard let activeSession else { return }
        do {
            points = try store.loadTrackPoints(forSessionID: activeSession.sessionID, limit: maxVisiblePoints)
            totalPointCount = try store.trackPointCount()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        status = "\(activeSession.profile.label) recording"
        refreshStats()
        startTimer(interval: activeSession.profile.statsRefreshInterval)
    }

    private func refreshStats() {
        guard let session = activeSession else {
            stats = .idle
            return
        }
        stats = RecordingStats(
            startedAtMs: session.startedAtMs,
            durationSeconds: TimeInterval(AppFormatters.nowMs() - session.startedAtMs) / 1000,
            distanceMeters: session.distanceMeters,
            acceptedCount: session.acceptedCount,
            receivedCount: session.receivedCount,
            lastFixMs: session.lastAccepted?.timestampMs,
            lastAccuracy: session.lastAccepted?.accuracy
        )
    }

    private func handle(_ location: CLLocation) {
        guard var session = activeSession else { return }
        let timestampMs = Int64(location.timestamp.timeIntervalSince1970 * 1000)
        let candidate = TrackPoint(
            id: nil,
            longitude: location.coordinate.longitude,
            latitude: location.coordinate.latitude,
            timestampMs: timestampMs,
            accuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            speed: location.speed >= 0 ? location.speed : nil,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            heading: location.course >= 0 ? location.course : nil,
            sessionID: session.sessionID,
            segmentID: session.segmentID,
            source: "gps",
            profile: session.profile,
            localDayKey: AppFormatters.localDayKey(for: timestampMs)
        )

        session.receivedCount += 1
        switch LocationFilter.shouldAccept(previous: session.lastAccepted, candidate: candidate, profile: session.profile) {
        case .accept(let distanceMeters, _):
            do {
                try store.appendTrackPoint(candidate)
                session.acceptedCount += 1
                session.distanceMeters += distanceMeters ?? 0
                session.lastAccepted = candidate
                activeSession = session
                if userInterfaceActive {
                    appendVisiblePoint(candidate)
                    totalPointCount += 1
                    refreshStats()
                }
            } catch {
                errorMessage = AppFormatters.errorMessage(error)
                status = "GPS write failed"
                activeSession = session
            }
        case .reject:
            session.rejectedCount += 1
            activeSession = session
            if userInterfaceActive {
                refreshStats()
            }
        }
    }

    private func appendVisiblePoint(_ point: TrackPoint) {
        points.append(point)
        let overflow = points.count - maxVisiblePoints
        if overflow > 0 {
            points.removeFirst(overflow)
        }
    }
}

extension RecordingManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard let pendingProfile else { return }
            if manager.authorizationStatus == .notDetermined {
                return
            }
            if manager.authorizationStatus == .authorizedAlways {
                self.pendingProfile = nil
                startAuthorized(profile: pendingProfile)
            } else if manager.authorizationStatus == .authorizedWhenInUse {
                self.pendingProfile = nil
                errorMessage = "Always Location is required for background recording"
                status = "Background permission needed"
                busy = false
            } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self.pendingProfile = nil
                errorMessage = "Location permission denied"
                status = "GPS unavailable"
                busy = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                handle(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let locationError = error as? CLError,
               locationError.code == .locationUnknown {
                return
            }
            errorMessage = AppFormatters.errorMessage(error)
            status = "GPS error"
        }
    }
}
