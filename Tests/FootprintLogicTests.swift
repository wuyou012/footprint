import CoreLocation
import Foundation
import SQLite3

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure.failed(message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure.failed("\(message). expected=\(expected), actual=\(actual)")
    }
}

func expectApprox(_ actual: Double, _ expected: Double, _ message: String) throws {
    if abs(actual - expected) > 0.001 {
        throw TestFailure.failed("\(message). expected=\(expected), actual=\(actual)")
    }
}

@main
struct FootprintLogicTests {
    static func main() throws {
        try testRecordingProfileAmbientParameters()
        try testMotionGateClassifiesActivity()
        try testDailyPersistentCoordinatorUsesSystemManagedUpdates()
        try testEcoPersistentCoordinatorUsesLowPowerMonitoring()
        try testLocationUpdateRouterKeepsMapAnchorOutOfTrackStorage()
        try testPersistentRecordingMetricsAccumulateActiveAndPausedTime()
        try testSessionSegmenterPolicies()
        try testDatabaseAmbientSessionSchema()
        try testDatabaseAppendsTrackPointsInBatch()
        try testDatabaseResumesOpenAmbientDaySession()
        try testMigrationDoesNotDowngradeUserVersion()
        print("FootprintLogicTests passed")
    }

    private static func testRecordingProfileAmbientParameters() throws {
        try expectApprox(RecordingProfile.eco.distanceFilter, 200, "Eco distanceFilter should be coarse for ambient recording")
        try expectApprox(RecordingProfile.daily.distanceFilter, 15, "Daily fallback distanceFilter should preserve walking turns")
        try expectApprox(RecordingProfile.high.distanceFilter, 10, "High distanceFilter should stay precise")

        try expectApprox(RecordingProfile.eco.minDistanceMeters, 180, "Eco accepted points should stay sparse")
        try expectApprox(RecordingProfile.daily.minDistanceMeters, 12, "Daily accepted points should keep 10-15m walking detail")
        try expectApprox(RecordingProfile.high.minDistanceMeters, 8, "High accepted points should stay dense")

        try expectApprox(RecordingProfile.eco.minIntervalSeconds, 30, "Eco accepted points should stay infrequent")
        try expectApprox(RecordingProfile.daily.minIntervalSeconds, 5, "Daily should not drop short walking turns due to a long interval")
        try expectApprox(RecordingProfile.high.minIntervalSeconds, 1, "High should keep near-real-time points")

        try expectEqual(RecordingProfile.eco.ambientSessionPolicy, .daily, "Eco should group ambient points by day")
        try expectEqual(RecordingProfile.daily.ambientSessionPolicy, .trip, "Daily should group ambient points by trip")
        try expectEqual(RecordingProfile.high.ambientSessionPolicy, .trip, "High should group ambient points by trip")

        try expectEqual(RecordingProfile.eco.stationaryTimeoutSeconds, 0, "Eco legacy stationary timeout")
        try expectEqual(RecordingProfile.daily.stationaryTimeoutSeconds, 180, "Daily legacy stationary timeout")
        try expectEqual(RecordingProfile.high.stationaryTimeoutSeconds, 300, "High legacy stationary timeout")
    }

    private static func testMotionGateClassifiesActivity() throws {
        try expectEqual(
            MotionGate.decision(for: MotionActivitySnapshot(kind: .stationary, confidence: .high, timestampMs: 1_000)),
            .stationary,
            "High-confidence stationary should be stationary"
        )
        try expectEqual(
            MotionGate.decision(for: MotionActivitySnapshot(kind: .walking, confidence: .medium, timestampMs: 1_000)),
            .moving,
            "Medium-confidence walking should be moving"
        )
        try expectEqual(
            MotionGate.decision(for: MotionActivitySnapshot(kind: .automotive, confidence: .high, timestampMs: 1_000)),
            .moving,
            "Automotive should be moving"
        )
        try expectEqual(
            MotionGate.decision(for: MotionActivitySnapshot(kind: .walking, confidence: .low, timestampMs: 1_000)),
            .moving,
            "Low-confidence walking should still be treated as moving (avoid dropping walk segments)"
        )
        try expectEqual(
            MotionGate.decision(for: MotionActivitySnapshot(kind: .stationary, confidence: .low, timestampMs: 1_000)),
            .unknown,
            "Low-confidence stationary should not be treated as a reliable stop signal"
        )
    }

    private static func testDailyPersistentCoordinatorUsesSystemManagedUpdates() throws {
        var coordinator = PersistentLocationCoordinator(profile: .daily)
        try expectEqual(coordinator.state, .stopped, "Coordinator should start stopped")

        var commands = coordinator.handle(.enabled(timestampMs: 1_000))
        try expectEqual(
            commands,
            [.startSystemManagedLocation(profile: .daily)],
            "Daily should start one system-managed live-update subscription when enabled"
        )
        try expectEqual(coordinator.state, .sampling, "Daily should enter sampling after live updates start")

        commands = coordinator.handle(.motion(.stationary, timestampMs: 60_000))
        try expect(commands.isEmpty, "CMMotion should no longer stop Daily location updates")
        try expectEqual(coordinator.state, .sampling, "Daily should remain sampling until Core Location reports stationary")

        commands = coordinator.handle(.systemStationary(timestampMs: 241_000))
        try expectEqual(
            commands,
            [.flushPendingTrackPoints, .finishCurrentSegment(reason: "system_paused")],
            "Core Location stationary should flush and end the active trip without cancelling the subscription"
        )
        try expectEqual(coordinator.state, .systemPaused, "Daily should expose the system-paused state")

        commands = coordinator.handle(.liveLocation(timestampMs: 242_000))
        try expect(commands.isEmpty, "A resumed live location should keep the existing subscription instead of starting a new one")
        try expectEqual(coordinator.state, .sampling, "A live location after stationary should resume sampling")

        commands = coordinator.handle(.disabled(timestampMs: 300_000))
        try expectEqual(
            commands,
            [.flushPendingTrackPoints, .stopSystemManagedLocation],
            "Disabling Daily should stop the live-update subscription after flushing"
        )
        try expectEqual(coordinator.state, .stopped, "Disabled Daily should return stopped")
    }

    private static func testEcoPersistentCoordinatorUsesLowPowerMonitoring() throws {
        var coordinator = PersistentLocationCoordinator(profile: .eco)
        var commands = coordinator.handle(.enabled(timestampMs: 1_000))
        try expectEqual(
            commands,
            [.startLowPowerMonitoring(profile: .eco)],
            "Eco should use only low-power SLC/Visit monitoring when enabled"
        )
        try expectEqual(coordinator.state, .monitoring, "Eco should remain in low-power monitoring")

        commands = coordinator.handle(.motion(.moving, timestampMs: 2_000))
        try expect(commands.isEmpty, "CMMotion should not start standard GPS in Eco")
        try expectEqual(coordinator.state, .monitoring, "Eco motion diagnostics should not leave low-power monitoring")

        commands = coordinator.handle(.disabled(timestampMs: 3_000))
        try expectEqual(commands, [.stopLowPowerMonitoring], "Disabling Eco should stop SLC/Visit monitoring")
        try expectEqual(coordinator.state, .stopped, "Disabled Eco should return stopped")
    }

    private static func testLocationUpdateRouterKeepsMapAnchorOutOfTrackStorage() throws {
        try expectEqual(
            LocationUpdateRouter.destination(
                pendingMapAnchor: true,
                persistentRecordingEnabled: true,
                activeSessionKind: nil
            ),
            .mapAnchor,
            "One-shot startup location must anchor the map, not create an ambient track point"
        )
        try expectEqual(
            LocationUpdateRouter.destination(
                pendingMapAnchor: false,
                persistentRecordingEnabled: true,
                activeSessionKind: nil
            ),
            .persistentTrack,
            "SLC/Visit-delivered persistent locations should still be eligible for ambient track storage"
        )
        try expectEqual(
            LocationUpdateRouter.destination(
                pendingMapAnchor: false,
                persistentRecordingEnabled: false,
                activeSessionKind: .manual
            ),
            .manualTrack,
            "Manual recording locations should continue to write manual track points"
        )
    }

    private static func testPersistentRecordingMetricsAccumulateActiveAndPausedTime() throws {
        var metrics = PersistentRecordingMetrics()
        metrics.markStandardLocationStarted(atMs: 1_000)
        metrics.markLocationCallback()
        metrics.markAcceptedTrackPoint()
        metrics.markSystemPaused(atMs: 11_000)
        metrics.markDatabaseWriteBatch()

        try expectEqual(metrics.standardLocationActiveSeconds, 10, "Active seconds should accumulate before system pause")
        try expectEqual(metrics.systemPausedSeconds, 0, "Paused seconds should not accumulate until resume/stop")
        try expectEqual(metrics.locationCallbacks, 1, "Location callback count should increment")
        try expectEqual(metrics.acceptedTrackPoints, 1, "Accepted point count should increment")
        try expectEqual(metrics.databaseWriteBatches, 1, "Database batch count should increment")

        metrics.markStandardLocationStarted(atMs: 17_000)
        metrics.markStandardLocationStopped(atMs: 22_000)
        try expectEqual(metrics.standardLocationActiveSeconds, 15, "Active seconds should include resumed movement")
        try expectEqual(metrics.systemPausedSeconds, 6, "Paused seconds should accumulate between pause and resume")
    }

    private static func testSessionSegmenterPolicies() throws {
        var eco = SessionSegmenter(profile: .eco)
        let dayOne = Int64(1_704_067_200_000) // 2024-01-01T00:00:00Z
        let sameDay = dayOne + 60_000
        let dayTwo = dayOne + 86_400_000

        try expectEqual(
            eco.action(for: .location(timestampMs: dayOne)),
            .startNew(origin: .day, key: AppFormatters.localDayKey(for: dayOne)),
            "Eco first point starts a daily ambient session"
        )
        try expectEqual(
            eco.action(for: .location(timestampMs: sameDay)),
            .reuseCurrent,
            "Eco should reuse same-day ambient session"
        )
        try expectEqual(
            eco.action(for: .location(timestampMs: dayTwo)),
            .finishAndStartNew(origin: .day, key: AppFormatters.localDayKey(for: dayTwo)),
            "Eco should roll ambient session at day boundary"
        )

        var daily = SessionSegmenter(profile: .daily)
        try expectEqual(
            daily.action(for: .location(timestampMs: dayOne)),
            .startNew(origin: .trip, key: "trip-1"),
            "Daily first moving point starts first trip"
        )
        try expectEqual(daily.action(for: .location(timestampMs: sameDay)), .reuseCurrent, "Daily reuses active trip")
        // Visit 不再切段（避免 iOS 步行误报 visit 造成碎片段）。
        try expectEqual(daily.action(for: .visitArrival(timestampMs: sameDay)), .none, "Visit no longer ends trip")
        try expectEqual(daily.action(for: .location(timestampMs: sameDay + 60_000)), .reuseCurrent, "Same trip continues through visit")
        // Core Location system pause 结束当前 trip；下一次 live location 会开新段。
        daily.endCurrentSegment()
        try expectEqual(
            daily.action(for: .location(timestampMs: sameDay + 120_000)),
            .startNew(origin: .trip, key: "trip-2"),
            "After system pause (endCurrentSegment), next movement starts a new trip"
        )
    }

    private static func testDatabaseAmbientSessionSchema() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try TrackDatabase(databaseURL: url)
        let startMs = Int64(1_704_067_200_000)

        let manualID = try database.startRecordingSession(profile: .daily, startMs: startMs)
        let ambientID = try database.startRecordingSession(
            profile: .eco,
            startMs: startMs + 60_000,
            kind: .ambient,
            origin: .day
        )

        try database.finishRecordingSession(
            sessionID: manualID,
            segmentID: nil,
            endMs: startMs + 30_000,
            status: "completed",
            stopReason: "stopped",
            receivedCount: 0,
            rejectedCount: 0,
            distanceMeters: 0
        )
        try database.finishRecordingSession(
            sessionID: ambientID,
            segmentID: nil,
            endMs: startMs + 90_000,
            status: "completed",
            stopReason: "ambient",
            receivedCount: 0,
            rejectedCount: 0,
            distanceMeters: 0
        )

        let sessions = try database.loadSessions(for: AppFormatters.localDayKey(for: startMs))
        try expectEqual(sessions.count, 2, "History should include manual and ambient sessions")
        try expect(sessions.contains { $0.kind == .manual }, "Manual session kind should round-trip")
        try expect(sessions.contains { $0.kind == .ambient && $0.origin == .day }, "Ambient session kind and origin should round-trip")
        try expectEqual(try database.databaseUserVersionForTesting(), 2, "Fresh database should migrate to schema version 2")
    }

    private static func testDatabaseAppendsTrackPointsInBatch() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try TrackDatabase(databaseURL: url)
        let startMs = Int64(1_704_067_200_000)
        let sessionID = try database.startRecordingSession(
            profile: .daily,
            startMs: startMs,
            kind: .ambient,
            origin: .trip
        )
        let segmentID = try database.startTrackSegment(sessionID: sessionID, startMs: startMs)

        let points = [
            makePoint(latitude: 37.785, longitude: -122.406, timestampMs: startMs, sessionID: sessionID, segmentID: segmentID),
            makePoint(latitude: 37.786, longitude: -122.407, timestampMs: startMs + 30_000, sessionID: sessionID, segmentID: segmentID),
            makePoint(latitude: 37.787, longitude: -122.408, timestampMs: startMs + 60_000, sessionID: sessionID, segmentID: segmentID)
        ]
        try database.appendTrackPoints(points)

        let stored = try database.loadTrackPoints(forSessionID: sessionID)
        try expectEqual(stored.count, 3, "Batch append should persist all points")
        try expectApprox(stored[2].latitude, 37.787, "Batch append should preserve point order")
    }

    private static func testDatabaseResumesOpenAmbientDaySession() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try TrackDatabase(databaseURL: url)
        let startMs = Int64(1_704_067_200_000)

        let first = try database.startOrResumeAmbientDaySession(profile: .eco, timestampMs: startMs)
        try database.appendTrackPoint(TrackPoint(
            id: nil,
            longitude: -122.406,
            latitude: 37.785,
            timestampMs: startMs,
            accuracy: 30,
            speed: nil,
            altitude: nil,
            heading: nil,
            sessionID: first.sessionID,
            segmentID: first.segmentID,
            source: "ambient_gps",
            profile: .eco,
            localDayKey: AppFormatters.localDayKey(for: startMs)
        ))

        let resumed = try database.startOrResumeAmbientDaySession(profile: .eco, timestampMs: startMs + 60_000)
        try expectEqual(resumed.sessionID, first.sessionID, "Eco restart should reuse the open ambient day session")
        try expectEqual(resumed.segmentID, first.segmentID, "Eco restart should reuse the open ambient day segment")
        try expectEqual(resumed.acceptedCount, 1, "Resumed ambient session should restore accepted count")
        try expect(resumed.lastAccepted != nil, "Resumed ambient session should restore last accepted point")

        let sessions = try database.loadSessions(for: AppFormatters.localDayKey(for: startMs))
        try expectEqual(sessions.count, 1, "Eco restart should not create a second ambient day session")
    }

    private static func testMigrationDoesNotDowngradeUserVersion() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try execSQLite(at: url, sql: """
            CREATE TABLE recording_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              profile TEXT,
              start_ts INTEGER,
              end_ts INTEGER,
              received_count INTEGER NOT NULL DEFAULT 0,
              accepted_count INTEGER NOT NULL DEFAULT 0,
              rejected_count INTEGER NOT NULL DEFAULT 0,
              source TEXT,
              status TEXT,
              local_day_key TEXT,
              timezone_offset_min INTEGER,
              distance_meters REAL,
              stop_reason TEXT,
              created_ts INTEGER
            );
            PRAGMA user_version = 7;
            """)

        let database = try TrackDatabase(databaseURL: url)
        _ = try database.startRecordingSession(
            profile: .eco,
            startMs: 1_704_067_200_000,
            kind: .ambient,
            origin: .day
        )
        try expectEqual(try database.databaseUserVersionForTesting(), 7, "Migration must not downgrade higher user_version")
    }

    private static func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private static func makePoint(
        latitude: Double,
        longitude: Double,
        timestampMs: Int64,
        sessionID: Int64,
        segmentID: Int64,
        profile: RecordingProfile = .daily
    ) -> TrackPoint {
        TrackPoint(
            id: nil,
            longitude: longitude,
            latitude: latitude,
            timestampMs: timestampMs,
            accuracy: 20,
            speed: nil,
            altitude: nil,
            heading: nil,
            sessionID: sessionID,
            segmentID: segmentID,
            source: "ambient_gps",
            profile: profile,
            localDayKey: AppFormatters.localDayKey(for: timestampMs)
        )
    }

    private static func execSQLite(at url: URL, sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw TestFailure.failed("Failed to open sqlite database")
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
            throw TestFailure.failed(message)
        }
    }
}
