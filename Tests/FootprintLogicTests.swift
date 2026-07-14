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
        try testPersistentCoordinatorStateMachine()
        try testSessionSegmenterPolicies()
        try testDatabaseAmbientSessionSchema()
        try testDatabaseResumesOpenAmbientDaySession()
        try testMigrationDoesNotDowngradeUserVersion()
        print("FootprintLogicTests passed")
    }

    private static func testRecordingProfileAmbientParameters() throws {
        try expectApprox(RecordingProfile.eco.distanceFilter, 200, "Eco distanceFilter should be coarse for ambient recording")
        try expectApprox(RecordingProfile.daily.distanceFilter, 60, "Daily distanceFilter should be coarser for ambient recording")
        try expectApprox(RecordingProfile.high.distanceFilter, 10, "High distanceFilter should stay precise")

        try expectEqual(RecordingProfile.eco.ambientSessionPolicy, .daily, "Eco should group ambient points by day")
        try expectEqual(RecordingProfile.daily.ambientSessionPolicy, .trip, "Daily should group ambient points by trip")
        try expectEqual(RecordingProfile.high.ambientSessionPolicy, .trip, "High should group ambient points by trip")

        try expectEqual(RecordingProfile.eco.stationaryTimeoutSeconds, 0, "Eco should return dormant immediately when stationary")
        try expectEqual(RecordingProfile.daily.stationaryTimeoutSeconds, 180, "Daily stationary timeout")
        try expectEqual(RecordingProfile.high.stationaryTimeoutSeconds, 300, "High stationary timeout")
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
            "Low-confidence stationary should not force dormant"
        )
    }

    private static func testPersistentCoordinatorStateMachine() throws {
        var coordinator = PersistentLocationCoordinator(profile: .daily)
        try expectEqual(coordinator.state, .dormant, "Coordinator should start dormant")

        var commands = coordinator.handle(.motion(.moving, timestampMs: 1_000))
        try expectEqual(commands, [.startContinuousLocation(profile: .daily)], "Moving should start continuous location")
        try expectEqual(coordinator.state, .active, "Moving should enter active state")

        commands = coordinator.handle(.motion(.stationary, timestampMs: 60_000))
        try expect(commands.isEmpty, "Stationary before timeout should not stop continuous location")
        try expectEqual(coordinator.state, .active, "Coordinator should remain active before timeout")

        commands = coordinator.handle(.motion(.stationary, timestampMs: 241_000))
        try expectEqual(commands, [.stopContinuousLocation], "Stationary timeout should stop continuous location")
        try expectEqual(coordinator.state, .dormant, "Coordinator should return dormant after timeout")

        var ecoCoordinator = PersistentLocationCoordinator(profile: .eco)
        commands = ecoCoordinator.handle(.motion(.moving, timestampMs: 1_000))
        try expectEqual(commands, [.startDutyCycledLocation(profile: .eco)], "Eco moving should duty-cycle location")
        commands = ecoCoordinator.handle(.motion(.stationary, timestampMs: 2_000))
        try expectEqual(commands, [.stopContinuousLocation], "Eco should stop immediately when stationary")
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
            .startNew(origin: .visit, key: "trip-1"),
            "Daily first moving point starts first trip"
        )
        try expectEqual(daily.action(for: .location(timestampMs: sameDay)), .reuseCurrent, "Daily reuses active trip")
        try expectEqual(daily.action(for: .visitArrival(timestampMs: sameDay)), .finishCurrent, "Visit arrival ends trip")
        try expectEqual(
            daily.action(for: .location(timestampMs: sameDay + 60_000)),
            .startNew(origin: .visit, key: "trip-2"),
            "Daily next movement starts a new trip"
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
