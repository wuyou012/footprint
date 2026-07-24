import Combine
import CoreLocation
import Foundation
import os
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
    @Published private(set) var persistentRecordingEnabled: Bool
    @Published private(set) var persistentStatus = "Off"
    /// True while CLLocationManager is actively sampling GPS (manual or ambient). Drives the on-screen REC indicator.
    @Published private(set) var isSampling = false
    @Published private(set) var mapAnchorCoordinate: CLLocationCoordinate2D?

    private let locationManager = CLLocationManager()
    private let store = TrackDatabase.shared
    private var activeSession: ActiveRecordingSession?
    private var persistentProfile: RecordingProfile
    private var persistentCoordinator: PersistentLocationCoordinator
    private var ambientSegmenter: SessionSegmenter
    private var pendingPersistentProfile: RecordingProfile?
    private var liveLocationTask: Task<Void, Never>?
    private var pendingMapAnchorRequest = false
    private var pendingAmbientTrackPoints: [TrackPoint] = []
    private var pendingAmbientTrackPointsSinceMs: Int64?
    private var persistentMetrics = PersistentRecordingMetrics()
    private var timer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var userInterfaceActive = true
    private let maxVisiblePoints = 3_000
    private let ambientWriteBatchLimit = 15
    private let ambientWriteBatchMaxAgeMs: Int64 = 45_000
    private static let persistentEnabledKey = "record.persistent.enabled"
    private static let persistentProfileKey = "record.persistent.profile"

    #if canImport(CoreMotion)
    private lazy var motionProvider: CoreMotionActivityProvider = {
        let provider = CoreMotionActivityProvider()
        provider.onDecision = { [weak self] decision, timestampMs in
            self?.handleMotionDecision(decision, timestampMs: timestampMs)
        }
        return provider
    }()
    #endif

    override init() {
        let defaults = UserDefaults.standard
        let savedProfile = defaults.string(forKey: Self.persistentProfileKey)
            .flatMap(RecordingProfile.init(rawValue:)) ?? .daily
        persistentRecordingEnabled = defaults.bool(forKey: Self.persistentEnabledKey)
        persistentProfile = savedProfile
        persistentCoordinator = PersistentLocationCoordinator(profile: savedProfile)
        ambientSegmenter = SessionSegmenter(profile: savedProfile)
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
        liveLocationTask?.cancel()
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
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
            if persistentRecordingEnabled {
                startPersistentMonitoringIfAuthorized(profile: persistentProfile)
            }
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
    }

    func start(profile: RecordingProfile) {
        guard !busy, !recording, activeSession == nil else { return }
        guard !persistentRecordingEnabled else {
            errorMessage = "Turn off persistent recording before manual Start"
            status = "Persistent recording is active"
            return
        }
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
                kind: .manual,
                origin: nil,
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
            locationManager.pausesLocationUpdatesAutomatically = false
            locationManager.showsBackgroundLocationIndicator = false
            locationManager.startUpdatingLocation()
            isSampling = true
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
        if persistentRecordingEnabled, activeSession?.kind == .ambient {
            setPersistentRecording(false, profile: persistentProfile)
            return
        }
        busy = true
        errorMessage = nil
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        isSampling = false
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
        do {
            try flushPendingTrackPoints()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        timer?.invalidate()
        timer = nil
        if recording {
            points.removeAll(keepingCapacity: false)
            status = persistentRecordingEnabled ? "Persistent recording in background" : "Recording in background"
        } else if persistentRecordingEnabled {
            status = "Persistent \(persistentProfile.label) ready"
        }
    }

    private func appDidBecomeActive() {
        userInterfaceActive = true
        guard let activeSession else {
            if persistentRecordingEnabled {
                status = "Persistent \(persistentProfile.label) ready"
            }
            return
        }
        do {
            points = try store.loadTrackPoints(forSessionID: activeSession.sessionID, limit: maxVisiblePoints)
            totalPointCount = try store.trackPointCount()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        status = activeSession.kind == .ambient
            ? "Persistent \(activeSession.profile.label) recording"
            : "\(activeSession.profile.label) recording"
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

    func setPersistentRecording(_ enabled: Bool, profile: RecordingProfile) {
        if enabled {
            enablePersistentRecording(profile: profile)
        } else {
            disablePersistentRecording()
        }
    }

    private func enablePersistentRecording(profile: RecordingProfile) {
        guard !busy else { return }
        guard activeSession == nil || activeSession?.kind == .ambient else {
            errorMessage = "Stop the current manual recording before enabling persistent recording"
            status = "Manual recording active"
            return
        }

        errorMessage = nil
        persistentProfile = profile
        persistentCoordinator = PersistentLocationCoordinator(profile: profile)
        ambientSegmenter = SessionSegmenter(profile: profile)
        persistentMetrics = PersistentRecordingMetrics()
        persistentRecordingEnabled = true
        persistentStatus = "Checking permissions"
        UserDefaults.standard.set(true, forKey: Self.persistentEnabledKey)
        UserDefaults.standard.set(profile.rawValue, forKey: Self.persistentProfileKey)

        switch locationManager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            pendingPersistentProfile = profile
            status = "Allow Always Location for persistent recording"
            persistentStatus = "Needs Always Location"
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startPersistentMonitoringIfAuthorized(profile: profile)
        case .denied, .restricted:
            persistentRecordingEnabled = false
            persistentStatus = "Permission denied"
            UserDefaults.standard.set(false, forKey: Self.persistentEnabledKey)
            errorMessage = "Always Location is required for persistent recording"
            status = "Background permission needed"
        @unknown default:
            persistentRecordingEnabled = false
            persistentStatus = "Unavailable"
            UserDefaults.standard.set(false, forKey: Self.persistentEnabledKey)
            errorMessage = "Unknown location permission state"
            status = "GPS unavailable"
        }
    }

    private func startPersistentMonitoringIfAuthorized(profile: RecordingProfile) {
        guard locationManager.authorizationStatus == .authorizedAlways else {
            pendingPersistentProfile = profile
            persistentStatus = "Needs Always Location"
            return
        }

        persistentProfile = profile
        persistentCoordinator.updateProfile(profile)
        configurePersistentLocationManager(profile: profile)
        #if canImport(CoreMotion)
        motionProvider.start()
        #endif
        applyPersistentCommands(persistentCoordinator.handle(.enabled(timestampMs: AppFormatters.nowMs())))
        backgroundRecordingEnabled = true
        FootprintLog.diag("✔︎ persistent monitoring started \(profile.label) strategy=\(String(describing: profile.persistentLocationStrategy))")
        persistentStatus = "\(profile.label) ready"
        status = "Persistent \(profile.label) ready"
        requestMapAnchorLocation()
    }

    private func disablePersistentRecording() {
        pendingPersistentProfile = nil
        let commands = persistentCoordinator.handle(.disabled(timestampMs: AppFormatters.nowMs()))
        applyPersistentCommands(commands)
        #if canImport(CoreMotion)
        motionProvider.stop()
        #endif
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        pendingMapAnchorRequest = false
        isSampling = false
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = false
        finishAmbientSession(stopReason: "persistent_off")
        ambientSegmenter.reset()
        UserDefaults.standard.set(false, forKey: Self.persistentEnabledKey)
        persistentRecordingEnabled = false
        persistentStatus = "Off"
        backgroundRecordingEnabled = false
        status = "Persistent recording off"
    }

    private func handleMotionDecision(_ decision: MotionDecision, timestampMs: Int64) {
        guard persistentRecordingEnabled else { return }
        persistentMetrics.markMotionEvent()
        let signal: PersistentMotionSignal
        switch decision {
        case .stationary:
            signal = .stationary
        case .moving:
            signal = .moving
        case .unknown:
            signal = .unknown
        }
        applyPersistentCommands(persistentCoordinator.handle(.motion(signal, timestampMs: timestampMs)))
    }

    private func applyPersistentCommands(_ commands: [PersistentLocationCommand]) {
        for command in commands {
            switch command {
            case .startSystemManagedLocation(let profile):
                startSystemManagedLocation(profile: profile)
            case .stopSystemManagedLocation:
                stopSystemManagedLocation()
            case .startLowPowerMonitoring(let profile):
                startLowPowerMonitoring(profile: profile)
            case .stopLowPowerMonitoring:
                stopLowPowerMonitoring()
            case .flushPendingTrackPoints:
                do {
                    try flushPendingTrackPoints()
                } catch {
                    errorMessage = AppFormatters.errorMessage(error)
                    status = "Persistent write failed"
                }
            case .finishCurrentSegment(let reason):
                finishAmbientSession(stopReason: reason)
                if persistentProfile.ambientSessionPolicy == .trip {
                    ambientSegmenter.endCurrentSegment()
                }
            }
        }
    }

    private func startSystemManagedLocation(profile: RecordingProfile) {
        guard persistentRecordingEnabled, activeSession?.kind != .manual else { return }
        configurePersistentLocationManager(profile: profile)
        startLowPowerMonitoring(profile: profile)
        liveLocationTask?.cancel()
        liveLocationTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(Self.liveUpdateConfiguration(for: profile)) {
                    self?.handleLiveLocationUpdate(update)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.handleLiveLocationError(error)
            }
        }
        persistentMetrics.markStandardLocationStarted(atMs: AppFormatters.nowMs())
        isSampling = true
        FootprintLog.diag("▶︎ start system-managed live updates \(profile.label) config=\(Self.liveUpdateConfigurationLabel(for: profile)) \(persistentMetrics.diagnosticSummary)")
        persistentStatus = "\(profile.label) live"
        status = "Persistent \(profile.label) recording"
    }

    private func stopSystemManagedLocation() {
        persistentMetrics.markStandardLocationStopped(atMs: AppFormatters.nowMs())
        liveLocationTask?.cancel()
        liveLocationTask = nil
        stopLowPowerMonitoring()
        isSampling = false
        FootprintLog.diag("■ stop system-managed live updates \(persistentMetrics.diagnosticSummary)")
        persistentStatus = "\(persistentProfile.label) ready"
        if activeSession == nil {
            recording = false
            stats = .idle
            status = "Persistent \(persistentProfile.label) ready"
        }
    }

    private func startLowPowerMonitoring(profile: RecordingProfile) {
        configurePersistentLocationManager(profile: profile)
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        FootprintLog.diag("◌ low-power monitors active \(profile.label) (SLC+Visit)")
    }

    private func stopLowPowerMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        FootprintLog.diag("◌ low-power monitors stopped")
    }

    private func configurePersistentLocationManager(profile: RecordingProfile) {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.desiredAccuracy = profile.desiredAccuracy
        locationManager.distanceFilter = profile.distanceFilter
    }

    private func requestMapAnchorLocation() {
        pendingMapAnchorRequest = true
        locationManager.requestLocation()
        FootprintLog.diag("◎ request map anchor location")
    }

    private func handleMapAnchorLocation(_ location: CLLocation) {
        guard Self.isUsableMapAnchor(location) else {
            FootprintLog.diag("◎ rejected map anchor age=\(Int(abs(location.timestamp.timeIntervalSinceNow)))s acc=\(Int(location.horizontalAccuracy))m")
            return
        }
        mapAnchorCoordinate = location.coordinate
        FootprintLog.diag("◎ map anchor updated lat=\(location.coordinate.latitude) lng=\(location.coordinate.longitude) acc=\(Int(location.horizontalAccuracy))m")
    }

    private static func isUsableMapAnchor(_ location: CLLocation) -> Bool {
        let ageSeconds = abs(location.timestamp.timeIntervalSinceNow)
        return ageSeconds <= 30 * 60
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 2_000
    }

    private static func liveUpdateConfiguration(for profile: RecordingProfile) -> CLLocationUpdate.LiveConfiguration {
        switch profile {
        case .high:
            .fitness
        case .daily, .eco:
            .default
        }
    }

    private static func liveUpdateConfigurationLabel(for profile: RecordingProfile) -> String {
        switch liveUpdateConfiguration(for: profile) {
        case .default:
            "default"
        case .fitness:
            "fitness"
        case .automotiveNavigation:
            "automotiveNavigation"
        case .otherNavigation:
            "otherNavigation"
        case .airborne:
            "airborne"
        @unknown default:
            "unknown"
        }
    }

    private func handleLiveLocationUpdate(_ update: CLLocationUpdate) {
        guard persistentRecordingEnabled else { return }
        let receivedAtMs = AppFormatters.nowMs()
        persistentMetrics.markLocationCallback()

        if update.stationary {
            persistentMetrics.markSystemPaused(atMs: receivedAtMs)
            FootprintLog.diag("⏸ CoreLocation live update stationary=true; pausing writes but keeping subscription \(persistentMetrics.diagnosticSummary)")
            applyPersistentCommands(persistentCoordinator.handle(.systemStationary(timestampMs: receivedAtMs)))
            isSampling = false
            persistentStatus = "\(persistentProfile.label) system paused"
            status = "Persistent \(persistentProfile.label) paused"
            return
        }

        guard let location = update.location else { return }
        persistentMetrics.markStandardLocationStarted(atMs: receivedAtMs)
        applyPersistentCommands(persistentCoordinator.handle(.liveLocation(timestampMs: receivedAtMs)))
        isSampling = true
        persistentStatus = "\(persistentProfile.label) live"
        status = "Persistent \(persistentProfile.label) recording"
        handlePersistentLocation(location)
    }

    private func handleLiveLocationError(_ error: Error) {
        guard persistentRecordingEnabled else { return }
        errorMessage = AppFormatters.errorMessage(error)
        status = "Persistent location failed"
        persistentStatus = "\(persistentProfile.label) error"
        FootprintLog.diag("✖︎ live updates failed \(AppFormatters.errorMessage(error))")
    }

    private func handlePersistentLocation(_ location: CLLocation) {
        guard persistentRecordingEnabled, activeSession?.kind != .manual else { return }
        let timestampMs = Int64(location.timestamp.timeIntervalSince1970 * 1000)
        do {
            try ensureAmbientSession(for: timestampMs)
            handle(location, source: "ambient_gps")
            FootprintLog.diag("• recorded point lat=\(location.coordinate.latitude) lng=\(location.coordinate.longitude) acc=\(Int(location.horizontalAccuracy))m sampling=\(isSampling)")
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
            status = "Persistent write failed"
        }
    }

    private func ensureAmbientSession(for timestampMs: Int64) throws {
        let action = ambientSegmenter.action(for: .location(timestampMs: timestampMs))
        switch action {
        case .none, .reuseCurrent:
            if activeSession == nil {
                try startAmbientSession(
                    profile: persistentProfile,
                    startMs: timestampMs,
                    origin: persistentProfile.ambientSessionPolicy == .daily ? .day : .trip
                )
            }
        case .startNew(let origin, _):
            try startAmbientSession(profile: persistentProfile, startMs: timestampMs, origin: origin)
        case .finishAndStartNew(let origin, _):
            finishAmbientSession(stopReason: "segment_roll")
            try startAmbientSession(profile: persistentProfile, startMs: timestampMs, origin: origin)
        case .finishCurrent:
            finishAmbientSession(stopReason: "segment_end")
        }
    }

    private func startAmbientSession(profile: RecordingProfile, startMs: Int64, origin: AmbientSessionOrigin) throws {
        guard activeSession?.kind != .ambient else { return }
        if origin == .day {
            activeSession = try store.startOrResumeAmbientDaySession(profile: profile, timestampMs: startMs)
        } else {
            let sessionID = try store.startRecordingSession(
                profile: profile,
                startMs: startMs,
                kind: .ambient,
                origin: origin
            )
            let segmentID = try store.startTrackSegment(sessionID: sessionID, startMs: startMs)
            activeSession = ActiveRecordingSession(
                sessionID: sessionID,
                segmentID: segmentID,
                profile: profile,
                kind: .ambient,
                origin: origin,
                startedAtMs: startMs,
                receivedCount: 0,
                acceptedCount: 0,
                rejectedCount: 0,
                distanceMeters: 0,
                lastAccepted: nil
            )
        }
        exportableSessionID = nil
        recording = true
        status = "Persistent \(profile.label) recording"
        startTimer(interval: profile.statsRefreshInterval)
    }

    private func finishAmbientSession(stopReason: String) {
        guard let session = activeSession, session.kind == .ambient else { return }
        timer?.invalidate()
        timer = nil
        do {
            try flushPendingTrackPoints()
            try store.finishRecordingSession(
                sessionID: session.sessionID,
                segmentID: session.segmentID,
                endMs: AppFormatters.nowMs(),
                status: "completed",
                stopReason: stopReason,
                receivedCount: session.receivedCount,
                rejectedCount: session.rejectedCount,
                distanceMeters: session.distanceMeters
            )
            totalPointCount = try store.trackPointCount()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        activeSession = nil
        recording = false
        stats = .idle
    }

    private func handleVisit(_ visit: CLVisit) {
        guard persistentRecordingEnabled else { return }
        FootprintLog.diag("⚑ CLVisit observed lat=\(visit.coordinate.latitude) lng=\(visit.coordinate.longitude); live updates own Daily segmentation")
    }

    private func handle(_ location: CLLocation, source: String = "gps") {
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
            source: source,
            profile: session.profile,
            localDayKey: AppFormatters.localDayKey(for: timestampMs)
        )

        session.receivedCount += 1
        switch LocationFilter.shouldAccept(previous: session.lastAccepted, candidate: candidate, profile: session.profile) {
        case .accept(let distanceMeters, _):
            do {
                try persistAcceptedTrackPoint(candidate, sessionKind: session.kind)
                if session.kind == .ambient {
                    persistentMetrics.markAcceptedTrackPoint()
                }
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

    private func persistAcceptedTrackPoint(_ point: TrackPoint, sessionKind: RecordingSessionKind) throws {
        guard sessionKind == .ambient else {
            try store.appendTrackPoint(point)
            return
        }

        pendingAmbientTrackPoints.append(point)
        if pendingAmbientTrackPointsSinceMs == nil {
            pendingAmbientTrackPointsSinceMs = point.timestampMs
        }

        let oldestPendingMs = pendingAmbientTrackPointsSinceMs ?? point.timestampMs
        let pendingAgeMs = max(0, point.timestampMs - oldestPendingMs)
        if pendingAmbientTrackPoints.count >= ambientWriteBatchLimit || pendingAgeMs >= ambientWriteBatchMaxAgeMs {
            try flushPendingTrackPoints()
        }
    }

    private func flushPendingTrackPoints() throws {
        guard !pendingAmbientTrackPoints.isEmpty else { return }
        let batch = pendingAmbientTrackPoints
        pendingAmbientTrackPoints.removeAll(keepingCapacity: true)
        pendingAmbientTrackPointsSinceMs = nil
        do {
            try store.appendTrackPoints(batch)
            persistentMetrics.markDatabaseWriteBatch()
            FootprintLog.diag("▣ flushed ambient track batch count=\(batch.count) \(persistentMetrics.diagnosticSummary)")
        } catch {
            pendingAmbientTrackPoints = batch + pendingAmbientTrackPoints
            pendingAmbientTrackPointsSinceMs = batch.first?.timestampMs
            throw error
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
            if let pendingPersistentProfile {
                if manager.authorizationStatus == .authorizedAlways {
                    self.pendingPersistentProfile = nil
                    startPersistentMonitoringIfAuthorized(profile: pendingPersistentProfile)
                    return
                }
                if manager.authorizationStatus == .authorizedWhenInUse {
                    status = "Always Location required"
                    persistentStatus = "Needs Always Location"
                    return
                }
                if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                    self.pendingPersistentProfile = nil
                    persistentRecordingEnabled = false
                    UserDefaults.standard.set(false, forKey: Self.persistentEnabledKey)
                    errorMessage = "Always Location is required for persistent recording"
                    status = "Background permission needed"
                    persistentStatus = "Permission denied"
                    return
                }
            }

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
            if pendingMapAnchorRequest {
                pendingMapAnchorRequest = false
                if let location = locations.reversed().first(where: Self.isUsableMapAnchor) ?? locations.last {
                    handleMapAnchorLocation(location)
                }
                return
            }

            for location in locations {
                let destination = LocationUpdateRouter.destination(
                    pendingMapAnchor: false,
                    persistentRecordingEnabled: persistentRecordingEnabled,
                    activeSessionKind: activeSession?.kind
                )

                switch destination {
                case .mapAnchor:
                    handleMapAnchorLocation(location)
                case .persistentTrack:
                    handlePersistentLocation(location)
                case .manualTrack:
                    handle(location)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            handleVisit(visit)
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
