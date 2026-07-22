import Foundation
import SQLite3

enum TrackDatabaseError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case invalidDatabasePath
}

nonisolated final class TrackDatabase {
    static let shared: TrackDatabase = {
        do {
            return try TrackDatabase()
        } catch {
            assertionFailure(error.localizedDescription)
            return TrackDatabase(initializationError: error)
        }
    }()

    private static let schemaVersion = 3

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let initializationError: Error?

    init(databaseURL: URL? = nil) throws {
        initializationError = nil
        var handle: OpaquePointer?
        let url = try databaseURL ?? Self.defaultDatabaseURL()
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            sqlite3_close(handle)
            throw TrackDatabaseError.openFailed(message)
        }
        db = handle
        try migrate()
    }

    private init(initializationError: Error) {
        self.initializationError = initializationError
        db = nil
    }

    deinit {
        sqlite3_close(db)
    }

    private static func defaultDatabaseURL() throws -> URL {
        guard let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TrackDatabaseError.invalidDatabasePath
        }
        let directory = supportURL.appendingPathComponent("footprint", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("footprint.db")
    }

    private var errorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) }
            ?? initializationError.map { AppFormatters.errorMessage($0) }
            ?? "database is not open"
    }

    private func migrate() throws {
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA temp_store = MEMORY")
        try execute("""
            CREATE TABLE IF NOT EXISTS track_points (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              lng REAL NOT NULL,
              lat REAL NOT NULL,
              ts INTEGER NOT NULL,
              accuracy REAL,
              speed REAL,
              altitude REAL,
              heading REAL,
              session_id INTEGER,
              segment_id INTEGER,
              source TEXT,
              profile TEXT,
              local_day_key TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_track_points_ts ON track_points (ts);
            CREATE INDEX IF NOT EXISTS idx_track_points_segment_ts ON track_points (segment_id, ts);
            CREATE INDEX IF NOT EXISTS idx_track_points_session_ts ON track_points (session_id, ts);
            CREATE INDEX IF NOT EXISTS idx_track_points_local_day_ts ON track_points (local_day_key, ts);

            CREATE TABLE IF NOT EXISTS recording_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              profile TEXT,
              start_ts INTEGER,
              end_ts INTEGER,
              received_count INTEGER NOT NULL DEFAULT 0,
              accepted_count INTEGER NOT NULL DEFAULT 0,
              rejected_count INTEGER NOT NULL DEFAULT 0,
              source TEXT,
              kind TEXT NOT NULL DEFAULT 'manual',
              origin TEXT,
              status TEXT,
              local_day_key TEXT,
              timezone_offset_min INTEGER,
              distance_meters REAL,
              stop_reason TEXT,
              created_ts INTEGER
            );
            CREATE INDEX IF NOT EXISTS idx_recording_sessions_status
              ON recording_sessions (status, source, start_ts);
            CREATE INDEX IF NOT EXISTS idx_recording_sessions_local_day
              ON recording_sessions (local_day_key, start_ts);

            CREATE TABLE IF NOT EXISTS track_segments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id INTEGER,
              start_ts INTEGER,
              end_ts INTEGER,
              point_count INTEGER NOT NULL DEFAULT 0,
              distance_meters REAL,
              local_day_key TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_track_segments_session
              ON track_segments (session_id, start_ts);

            CREATE TABLE IF NOT EXISTS region_achievement_cells (
              cell_key TEXT PRIMARY KEY,
              lat REAL NOT NULL,
              lng REAL NOT NULL,
              first_point_id INTEGER NOT NULL,
              first_seen_ts INTEGER,
              last_seen_ts INTEGER,
              point_count INTEGER NOT NULL DEFAULT 0,
              country_code TEXT,
              country_name TEXT,
              admin_area TEXT,
              city_name TEXT,
              city_key TEXT,
              resolved_ts INTEGER
            );
            CREATE INDEX IF NOT EXISTS idx_region_achievement_cells_city
              ON region_achievement_cells (city_key);

            CREATE TABLE IF NOT EXISTS region_achievements (
              city_key TEXT PRIMARY KEY,
              country_code TEXT NOT NULL,
              country_name TEXT NOT NULL,
              admin_area TEXT,
              city_name TEXT NOT NULL,
              first_seen_ts INTEGER,
              last_seen_ts INTEGER,
              cell_count INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_region_achievements_country
              ON region_achievements (country_code, city_name);

            CREATE TABLE IF NOT EXISTS regions (
              region_id TEXT PRIMARY KEY,
              level TEXT NOT NULL,
              datum TEXT NOT NULL,
              name_zh TEXT NOT NULL,
              name_en TEXT NOT NULL,
              country_code TEXT NOT NULL,
              parent_id TEXT,
              min_lat REAL NOT NULL,
              max_lat REAL NOT NULL,
              min_lng REAL NOT NULL,
              max_lng REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_regions_country
              ON regions (country_code, level, region_id);

            CREATE TABLE IF NOT EXISTS region_geometries (
              region_id TEXT NOT NULL,
              polygon_index INTEGER NOT NULL,
              coordinates_blob BLOB NOT NULL,
              datum TEXT NOT NULL,
              PRIMARY KEY(region_id, polygon_index)
            );

            CREATE TABLE IF NOT EXISTS region_geometry_index (
              id INTEGER PRIMARY KEY,
              region_id TEXT NOT NULL,
              polygon_index INTEGER NOT NULL,
              UNIQUE(region_id, polygon_index)
            );
            CREATE INDEX IF NOT EXISTS idx_region_geometry_index_region
              ON region_geometry_index (region_id);

            CREATE VIRTUAL TABLE IF NOT EXISTS region_rtree
              USING rtree(id, minLat, maxLat, minLng, maxLng);

            CREATE TABLE IF NOT EXISTS region_catalog_metadata (
              catalog_key TEXT PRIMARY KEY,
              fingerprint TEXT NOT NULL,
              region_count INTEGER NOT NULL,
              updated_ts INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS region_hits (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              region_id TEXT NOT NULL,
              track_point_id INTEGER,
              session_id INTEGER,
              ts INTEGER,
              lat REAL NOT NULL,
              lng REAL NOT NULL,
              accuracy REAL,
              hit_method TEXT NOT NULL,
              created_ts INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_region_hits_region_ts
              ON region_hits (region_id, ts);
            """)

        if try !columnExists(table: "recording_sessions", column: "kind") {
            try execute("ALTER TABLE recording_sessions ADD COLUMN kind TEXT NOT NULL DEFAULT 'manual'")
        }
        if try !columnExists(table: "recording_sessions", column: "origin") {
            try execute("ALTER TABLE recording_sessions ADD COLUMN origin TEXT")
        }

        let currentVersion = try databaseUserVersion()
        if currentVersion < Self.schemaVersion {
            try setDatabaseUserVersion(Self.schemaVersion)
        }
    }

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw TrackDatabaseError.openFailed("database is not open") }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw TrackDatabaseError.stepFailed(errorMessage)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let db else { throw TrackDatabaseError.openFailed("database is not open") }
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw TrackDatabaseError.prepareFailed(errorMessage)
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, values: [Any?]) {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case nil:
                sqlite3_bind_null(statement, position)
            case let value as Int:
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Double:
                sqlite3_bind_double(statement, position, value)
            case let value as String:
                sqlite3_bind_text(statement, position, value, -1, sqliteTransient)
            case let value as Data:
                _ = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, position, bytes.baseAddress, Int32(value.count), sqliteTransient)
                }
            default:
                sqlite3_bind_null(statement, position)
            }
        }
    }

    @discardableResult
    private func run(_ sql: String, _ values: [Any?] = []) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, values: values)
        if sqlite3_step(statement) != SQLITE_DONE {
            throw TrackDatabaseError.stepFailed(errorMessage)
        }
        return sqlite3_last_insert_rowid(db)
    }

    private func query<T>(_ sql: String, _ values: [Any?] = [], map: (OpaquePointer?) throws -> T) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, values: values)
        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(try map(statement))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw TrackDatabaseError.stepFailed(errorMessage)
            }
        }
    }

    private func scalarInt(_ sql: String, _ values: [Any?] = []) throws -> Int {
        try query(sql, values) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    private func databaseUserVersion() throws -> Int {
        try scalarInt("PRAGMA user_version")
    }

    private func setDatabaseUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    private func columnExists(table: String, column: String) throws -> Bool {
        try query("PRAGMA table_info(\(table))") { statement in
            text(statement, 1)
        }
        .contains { $0 == column }
    }

    func databaseUserVersionForTesting() throws -> Int {
        try databaseUserVersion()
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: pointer)
    }

    private func int64(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private func double(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }

    private func data(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_blob(statement, index)
        else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func point(from statement: OpaquePointer?) -> TrackPoint {
        TrackPoint(
            id: int64(statement, 0),
            longitude: sqlite3_column_double(statement, 1),
            latitude: sqlite3_column_double(statement, 2),
            timestampMs: sqlite3_column_int64(statement, 3),
            accuracy: double(statement, 4),
            speed: double(statement, 5),
            altitude: double(statement, 6),
            heading: double(statement, 7),
            sessionID: int64(statement, 8),
            segmentID: int64(statement, 9),
            source: text(statement, 10),
            profile: text(statement, 11).flatMap(RecordingProfile.init(rawValue:)),
            localDayKey: text(statement, 12)
        )
    }

    func trackPointCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM track_points")
    }

    func loadTrackPoints(limit: Int = 20_000) throws -> [TrackPoint] {
        let safeLimit = max(0, min(50_000, limit))
        return try query("""
            SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
              session_id, segment_id, source, profile, local_day_key
            FROM track_points
            ORDER BY ts ASC
            LIMIT ?
            """, [safeLimit], map: point)
    }

    func loadRecentTrackPoints(limit: Int = 3_000) throws -> [TrackPoint] {
        let safeLimit = max(0, min(20_000, limit))
        return try query("""
            SELECT * FROM (
              SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
                session_id, segment_id, source, profile, local_day_key
              FROM track_points
              ORDER BY ts DESC
              LIMIT ?
            )
            ORDER BY ts ASC
            """, [safeLimit], map: point)
    }

    func loadLatestSessionTrackPoints(limit: Int = 3_000) throws -> [TrackPoint] {
        guard let sessionID = try latestTrackSessionID() else {
            return try loadRecentTrackPoints(limit: limit)
        }
        return try loadTrackPoints(forSessionID: sessionID, limit: limit)
    }

    private func latestTrackSessionID() throws -> Int64? {
        try query("""
            SELECT session_id
            FROM track_points
            WHERE session_id IS NOT NULL
            GROUP BY session_id
            ORDER BY MAX(ts) DESC
            LIMIT 1
            """) { sqlite3_column_int64($0, 0) }.first
    }

    func loadLastTrackPoint() throws -> TrackPoint? {
        try query("""
            SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
              session_id, segment_id, source, profile, local_day_key
            FROM track_points
            ORDER BY ts DESC
            LIMIT 1
            """, map: point).first
    }

#if DEBUG
    func seedRegionAchievementDemoTrackPoints() throws {
        lock.lock()
        defer { lock.unlock() }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try run("DELETE FROM track_points WHERE source = ?", [RegionAchievementDemoSeeds.source])
            for seed in RegionAchievementDemoSeeds.points {
                try run("""
                    INSERT INTO track_points (
                      lng, lat, ts, accuracy, speed, altitude, heading,
                      session_id, segment_id, source, profile, local_day_key
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                        seed.coordinate.longitude,
                        seed.coordinate.latitude,
                        seed.timestampMs,
                        10.0,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        RegionAchievementDemoSeeds.source,
                        RecordingProfile.high.rawValue,
                        "2026-07-09"
                    ])
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
#endif

    func loadRegionAchievementTrackSamples(limit: Int = 120_000) throws -> [RegionAchievementTrackCoordinate] {
        let safeLimit = max(0, min(250_000, limit))
        guard safeLimit > 0 else { return [] }

        return try query("""
            WITH samples AS (
              SELECT
                CAST(lat * 40 AS INTEGER) AS lat_cell,
                CAST(lng * 40 AS INTEGER) AS lng_cell,
                AVG(lat) AS lat,
                AVG(lng) AS lng,
                MAX(ts) AS last_seen_ts,
                MIN(accuracy) AS best_accuracy,
                COUNT(*) AS point_count
              FROM track_points
              WHERE lat BETWEEN -90 AND 90
                AND lng BETWEEN -180 AND 180
              GROUP BY lat_cell, lng_cell
              ORDER BY last_seen_ts DESC
              LIMIT ?
            )
            SELECT lat, lng, last_seen_ts, best_accuracy, point_count
            FROM samples
            """, [safeLimit]) { statement in
                RegionAchievementTrackCoordinate(
                    latitude: sqlite3_column_double(statement, 0),
                    longitude: sqlite3_column_double(statement, 1),
                    timestampMs: sqlite3_column_int64(statement, 2),
                    accuracy: double(statement, 3),
                    pointCount: Int(sqlite3_column_int64(statement, 4))
                )
            }
    }

    func replaceRegionCatalog(
        regions: [Region],
        geometryByRegionId: [String: [RegionPolygon]],
        catalogKey: String? = nil,
        fingerprint: String? = nil
    ) throws {
        let encoder = JSONEncoder()
        lock.lock()
        defer { lock.unlock() }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try run("DELETE FROM region_rtree")
            try run("DELETE FROM region_geometry_index")
            try run("DELETE FROM region_geometries")
            try run("DELETE FROM regions")

            for region in regions {
                try run("""
                    INSERT INTO regions (
                      region_id, level, datum, name_zh, name_en, country_code,
                      parent_id, min_lat, max_lat, min_lng, max_lng
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                        region.regionId,
                        region.level.rawValue,
                        region.datum.rawValue,
                        region.nameZh,
                        region.nameEn,
                        region.countryCode.uppercased(),
                        region.parentId,
                        region.bbox.minLatitude,
                        region.bbox.maxLatitude,
                        region.bbox.minLongitude,
                        region.bbox.maxLongitude
                    ])

                let polygons = geometryByRegionId[region.regionId] ?? []
                for (polygonIndex, polygon) in polygons.enumerated() {
                    let geometryData = try encoder.encode(polygon)
                    try run("""
                        INSERT INTO region_geometries (
                          region_id, polygon_index, coordinates_blob, datum
                        ) VALUES (?, ?, ?, ?)
                        """, [
                            region.regionId,
                            polygonIndex,
                            geometryData,
                            region.datum.rawValue
                        ])
                    let geometryIndexID = try run("""
                        INSERT INTO region_geometry_index (region_id, polygon_index)
                        VALUES (?, ?)
                        """, [
                            region.regionId,
                            polygonIndex
                        ])
                    let bbox = polygon.bbox
                    try run("""
                        INSERT INTO region_rtree (id, minLat, maxLat, minLng, maxLng)
                        VALUES (?, ?, ?, ?, ?)
                        """, [
                            geometryIndexID,
                            bbox.minLatitude,
                            bbox.maxLatitude,
                            bbox.minLongitude,
                            bbox.maxLongitude
                        ])
                }
            }

            if let catalogKey, let fingerprint {
                try run("""
                    INSERT INTO region_catalog_metadata (
                      catalog_key, fingerprint, region_count, updated_ts
                    ) VALUES (?, ?, ?, ?)
                    ON CONFLICT(catalog_key) DO UPDATE SET
                      fingerprint = excluded.fingerprint,
                      region_count = excluded.region_count,
                      updated_ts = excluded.updated_ts
                    """, [
                        catalogKey,
                        fingerprint,
                        regions.count,
                        AppFormatters.nowMs()
                    ])
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    func replaceRegionCatalogIfNeeded(
        catalogKey: String,
        fingerprint: String,
        regions: [Region],
        geometryByRegionId: [String: [RegionPolygon]]
    ) throws -> Bool {
        if try isRegionCatalogFresh(catalogKey: catalogKey, fingerprint: fingerprint) {
            return false
        }
        try replaceRegionCatalog(
            regions: regions,
            geometryByRegionId: geometryByRegionId,
            catalogKey: catalogKey,
            fingerprint: fingerprint
        )
        return true
    }

    private func isRegionCatalogFresh(catalogKey: String, fingerprint: String) throws -> Bool {
        let rows = try query("""
            SELECT region_count
            FROM region_catalog_metadata
            WHERE catalog_key = ? AND fingerprint = ?
            """, [catalogKey, fingerprint]) { statement in
                Int(sqlite3_column_int64(statement, 0))
            }
        guard let regionCount = rows.first, regionCount > 0 else {
            return false
        }
        let storedRegionCount = try scalarInt("SELECT COUNT(*) FROM regions")
        let indexedPolygonCount = try scalarInt("SELECT COUNT(*) FROM region_rtree")
        return storedRegionCount == regionCount && indexedPolygonCount > 0
    }

    func loadRegionCatalog() throws -> (regions: [Region], geometryByRegionId: [String: [RegionPolygon]]) {
        let regions = try query("""
            SELECT region_id, level, datum, name_zh, name_en, country_code,
              parent_id, min_lat, max_lat, min_lng, max_lng
            FROM regions
            ORDER BY region_id ASC
            """) { statement in
                Region(
                    regionId: text(statement, 0) ?? "",
                    level: text(statement, 1).flatMap(RegionLevel.init(rawValue:)) ?? .city,
                    datum: text(statement, 2).flatMap(Datum.init(rawValue:)) ?? .wgs84,
                    bbox: BBox(
                        minLatitude: sqlite3_column_double(statement, 7),
                        maxLatitude: sqlite3_column_double(statement, 8),
                        minLongitude: sqlite3_column_double(statement, 9),
                        maxLongitude: sqlite3_column_double(statement, 10)
                    ),
                    parentId: text(statement, 6),
                    nameZh: text(statement, 3) ?? "",
                    nameEn: text(statement, 4) ?? "",
                    countryCode: text(statement, 5) ?? ""
                )
            }

        let decoder = JSONDecoder()
        let geometryRows = try query("""
            SELECT region_id, coordinates_blob
            FROM region_geometries
            ORDER BY region_id ASC, polygon_index ASC
            """) { statement in
                (
                    regionId: text(statement, 0) ?? "",
                    polygon: try decoder.decode(RegionPolygon.self, from: data(statement, 1) ?? Data())
                )
            }
        var geometryByRegionId: [String: [RegionPolygon]] = [:]
        for row in geometryRows where !row.regionId.isEmpty {
            geometryByRegionId[row.regionId, default: []].append(row.polygon)
        }

        return (regions, geometryByRegionId)
    }

    func loadRegionSpatialCandidateIds(
        for coordinate: Coordinate,
        padding: Double = 0.0005
    ) throws -> Set<String> {
        let rows = try query("""
            SELECT DISTINCT idx.region_id
            FROM region_rtree rtree
            JOIN region_geometry_index idx
              ON idx.id = rtree.id
            WHERE rtree.minLat <= ?
              AND rtree.maxLat >= ?
              AND rtree.minLng <= ?
              AND rtree.maxLng >= ?
            """, [
                coordinate.latitude + padding,
                coordinate.latitude - padding,
                coordinate.longitude + padding,
                coordinate.longitude - padding
            ]) { statement in
                text(statement, 0) ?? ""
            }
        return Set(rows.filter { !$0.isEmpty })
    }

    func appendTrackPoint(_ point: TrackPoint) throws {
        try run("""
            INSERT INTO track_points (
              lng, lat, ts, accuracy, speed, altitude, heading,
              session_id, segment_id, source, profile, local_day_key
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                point.longitude,
                point.latitude,
                point.timestampMs,
                point.accuracy,
                point.speed,
                point.altitude,
                point.heading,
                point.sessionID,
                point.segmentID,
                point.source ?? "gps",
                point.profile?.rawValue,
                point.localDayKey ?? AppFormatters.localDayKey(for: point.timestampMs)
            ])
    }

    func loadTrackPoints(forSessionID sessionID: Int64, limit: Int = 20_000) throws -> [TrackPoint] {
        let safeLimit = max(0, min(50_000, limit))
        let totalCount = try trackPointCount(forSessionID: sessionID)
        guard totalCount > safeLimit, safeLimit > 0 else {
            return try query("""
                SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
                  session_id, segment_id, source, profile, local_day_key
                FROM track_points
                WHERE session_id = ?
                ORDER BY ts ASC
                LIMIT ?
                """, [sessionID, safeLimit], map: point)
        }

        let stride = max(1, (totalCount + safeLimit - 1) / safeLimit)
        return try query("""
            WITH filtered AS (
              SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
                session_id, segment_id, source, profile, local_day_key
              FROM track_points
              WHERE session_id = ?
            ),
            numbered AS (
              SELECT *,
                ROW_NUMBER() OVER (ORDER BY ts ASC) AS row_index,
                COUNT(*) OVER () AS total_count
              FROM filtered
            )
            SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
              session_id, segment_id, source, profile, local_day_key
            FROM numbered
            WHERE row_index = 1
              OR row_index = total_count
              OR ((row_index - 1) % ?) = 0
            ORDER BY ts ASC
            LIMIT ?
            """, [sessionID, stride, safeLimit], map: point)
    }

    func trackPointCount(forSessionID sessionID: Int64) throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM track_points WHERE session_id = ?", [sessionID])
    }

    func forEachTrackPoint(forSessionID sessionID: Int64, body: (TrackPoint) throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare("""
            SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
              session_id, segment_id, source, profile, local_day_key
            FROM track_points
            WHERE session_id = ?
            ORDER BY ts ASC
            """)
        defer { sqlite3_finalize(statement) }
        bind(statement, values: [sessionID])
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                try body(point(from: statement))
            } else if result == SQLITE_DONE {
                return
            } else {
                throw TrackDatabaseError.stepFailed(errorMessage)
            }
        }
    }

    func startRecordingSession(
        profile: RecordingProfile,
        startMs: Int64,
        kind: RecordingSessionKind = .manual,
        origin: AmbientSessionOrigin? = nil
    ) throws -> Int64 {
        let source = kind == .manual ? "foreground" : "ambient"
        return try run("""
            INSERT INTO recording_sessions (
              profile, start_ts, source, kind, origin, status, local_day_key,
              timezone_offset_min, created_ts
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                profile.rawValue,
                startMs,
                source,
                kind.rawValue,
                origin?.rawValue,
                "recording",
                AppFormatters.localDayKey(for: startMs),
                AppFormatters.timezoneOffsetMinutes(for: startMs),
                AppFormatters.nowMs()
            ])
    }

    func startTrackSegment(sessionID: Int64, startMs: Int64) throws -> Int64 {
        try run("""
            INSERT INTO track_segments (
              session_id, start_ts, local_day_key, point_count
            ) VALUES (?, ?, ?, 0)
            """, [
                sessionID,
                startMs,
                AppFormatters.localDayKey(for: startMs)
            ])
    }

    func startOrResumeAmbientDaySession(profile: RecordingProfile, timestampMs: Int64) throws -> ActiveRecordingSession {
        let dayKey = AppFormatters.localDayKey(for: timestampMs)
        if let existing = try loadOpenAmbientDaySession(dayKey: dayKey, fallbackProfile: profile) {
            return existing
        }

        let sessionID = try startRecordingSession(
            profile: profile,
            startMs: timestampMs,
            kind: .ambient,
            origin: .day
        )
        let segmentID = try startTrackSegment(sessionID: sessionID, startMs: timestampMs)
        return ActiveRecordingSession(
            sessionID: sessionID,
            segmentID: segmentID,
            profile: profile,
            kind: .ambient,
            origin: .day,
            startedAtMs: timestampMs,
            receivedCount: 0,
            acceptedCount: 0,
            rejectedCount: 0,
            distanceMeters: 0,
            lastAccepted: nil
        )
    }

    private func loadOpenAmbientDaySession(dayKey: String, fallbackProfile: RecordingProfile) throws -> ActiveRecordingSession? {
        let rows = try query("""
            SELECT id, profile, start_ts, received_count, rejected_count
            FROM recording_sessions
            WHERE kind = 'ambient'
              AND origin = 'day'
              AND local_day_key = ?
              AND status = 'recording'
              AND end_ts IS NULL
            ORDER BY start_ts ASC
            LIMIT 1
            """, [dayKey]) { statement in
                (
                    sessionID: sqlite3_column_int64(statement, 0),
                    profile: text(statement, 1).flatMap(RecordingProfile.init(rawValue:)),
                    startMs: sqlite3_column_int64(statement, 2),
                    receivedCount: Int(sqlite3_column_int64(statement, 3)),
                    rejectedCount: Int(sqlite3_column_int64(statement, 4))
                )
            }

        guard let row = rows.first else { return nil }
        let segmentID = try latestTrackSegmentID(forSessionID: row.sessionID)
            ?? startTrackSegment(sessionID: row.sessionID, startMs: row.startMs)
        let lastAccepted = try loadLastTrackPoint(forSessionID: row.sessionID)
        let acceptedCount = try trackPointCount(forSessionID: row.sessionID)
        let distanceMeters = try distanceMeters(forSessionID: row.sessionID)

        return ActiveRecordingSession(
            sessionID: row.sessionID,
            segmentID: segmentID,
            profile: row.profile ?? fallbackProfile,
            kind: .ambient,
            origin: .day,
            startedAtMs: row.startMs,
            receivedCount: max(row.receivedCount, acceptedCount),
            acceptedCount: acceptedCount,
            rejectedCount: row.rejectedCount,
            distanceMeters: distanceMeters,
            lastAccepted: lastAccepted
        )
    }

    private func latestTrackSegmentID(forSessionID sessionID: Int64) throws -> Int64? {
        try query("""
            SELECT id
            FROM track_segments
            WHERE session_id = ?
            ORDER BY start_ts DESC
            LIMIT 1
            """, [sessionID]) { sqlite3_column_int64($0, 0) }.first
    }

    private func loadLastTrackPoint(forSessionID sessionID: Int64) throws -> TrackPoint? {
        try query("""
            SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
              session_id, segment_id, source, profile, local_day_key
            FROM track_points
            WHERE session_id = ?
            ORDER BY ts DESC
            LIMIT 1
            """, [sessionID], map: point).first
    }

    private func distanceMeters(forSessionID sessionID: Int64) throws -> Double {
        var previous: TrackPoint?
        var total = 0.0
        try forEachTrackPoint(forSessionID: sessionID) { point in
            if let previous {
                total += LocationFilter.distanceMeters(from: previous, to: point)
            }
            previous = point
        }
        return total
    }

    func finishRecordingSession(
        sessionID: Int64,
        segmentID: Int64?,
        endMs: Int64,
        status: String,
        stopReason: String,
        receivedCount: Int,
        rejectedCount: Int,
        distanceMeters: Double
    ) throws {
        let pointCount = try scalarInt("SELECT COUNT(*) FROM track_points WHERE session_id = ?", [sessionID])
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            if let segmentID {
                try run("""
                    UPDATE track_segments
                    SET end_ts = ?,
                      point_count = (SELECT COUNT(*) FROM track_points WHERE segment_id = ?),
                      distance_meters = ?
                    WHERE id = ?
                    """, [endMs, segmentID, distanceMeters, segmentID])
            }
            try run("""
                UPDATE recording_sessions
                SET end_ts = ?,
                  status = ?,
                  stop_reason = ?,
                  received_count = ?,
                  accepted_count = ?,
                  rejected_count = ?,
                  distance_meters = ?
                WHERE id = ?
                """, [
                    endMs,
                    status,
                    stopReason,
                    max(receivedCount, pointCount),
                    pointCount,
                    rejectedCount,
                    distanceMeters,
                    sessionID
                ])
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func interruptOpenForegroundSessions(reason: String = "replaced") throws {
        let rows = try query("""
            SELECT id FROM recording_sessions
            WHERE source = 'foreground'
              AND kind = 'manual'
              AND status = 'recording'
            """) { sqlite3_column_int64($0, 0) }
        let now = AppFormatters.nowMs()
        for sessionID in rows {
            try finishRecordingSession(
                sessionID: sessionID,
                segmentID: nil,
                endMs: now,
                status: "interrupted",
                stopReason: reason,
                receivedCount: 0,
                rejectedCount: 0,
                distanceMeters: 0
            )
        }
    }

    func loadDaySummaries() throws -> [DaySummary] {
        try query("""
            SELECT
              local_day_key,
              COUNT(*) AS session_count,
              COALESCE(SUM(accepted_count), 0) AS point_count,
              COALESCE(SUM(distance_meters), 0) AS distance_meters,
              COALESCE(SUM(CASE WHEN end_ts IS NOT NULL AND start_ts IS NOT NULL
                THEN end_ts - start_ts ELSE 0 END), 0) AS duration_ms,
              MIN(start_ts) AS first_started_at,
              MAX(end_ts) AS last_ended_at
            FROM recording_sessions
            WHERE kind IN ('manual', 'ambient')
              AND local_day_key IS NOT NULL
              AND (status IS NULL OR status != 'start_failed')
            GROUP BY local_day_key
            ORDER BY local_day_key DESC
            """) { statement in
                DaySummary(
                    dayKey: text(statement, 0) ?? "",
                    sessionCount: Int(sqlite3_column_int64(statement, 1)),
                    pointCount: Int(sqlite3_column_int64(statement, 2)),
                    distanceMeters: sqlite3_column_double(statement, 3),
                    durationSeconds: TimeInterval(sqlite3_column_double(statement, 4) / 1000),
                    firstStartedAtMs: int64(statement, 5),
                    lastEndedAtMs: int64(statement, 6)
                )
            }
    }

    func loadSessions(for dayKey: String) throws -> [DaySession] {
        try query("""
            SELECT id, profile, start_ts, end_ts, accepted_count, distance_meters, kind, origin
            FROM recording_sessions
            WHERE local_day_key = ?
              AND kind IN ('manual', 'ambient')
              AND (status IS NULL OR status != 'start_failed')
            ORDER BY start_ts ASC
            """, [dayKey]) { statement in
                DaySession(
                    id: sqlite3_column_int64(statement, 0),
                    profile: text(statement, 1).flatMap(RecordingProfile.init(rawValue:)),
                    startMs: int64(statement, 2),
                    endMs: int64(statement, 3),
                    pointCount: Int(sqlite3_column_int64(statement, 4)),
                    distanceMeters: sqlite3_column_double(statement, 5),
                    kind: text(statement, 6).flatMap(RecordingSessionKind.init(rawValue:)) ?? .manual,
                    origin: text(statement, 7).flatMap(AmbientSessionOrigin.init(rawValue:))
                )
            }
    }

    func loadTrackPoints(for dayKey: String, limit: Int = 50_000) throws -> [TrackPoint] {
        let safeLimit = max(0, min(50_000, limit))
        let totalCount = try trackPointCount(for: dayKey)
        guard totalCount > safeLimit, safeLimit > 0 else {
            return try query("""
                SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
                  session_id, segment_id, source, profile, local_day_key
                FROM track_points
                WHERE session_id IN (
                  SELECT id FROM recording_sessions
                  WHERE local_day_key = ?
                    AND kind IN ('manual', 'ambient')
                    AND (status IS NULL OR status != 'start_failed')
                )
                ORDER BY ts ASC
                LIMIT ?
                """, [dayKey, safeLimit], map: point)
        }

        let stride = max(1, (totalCount + safeLimit - 1) / safeLimit)
        return try query("""
            WITH filtered AS (
              SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
                session_id, segment_id, source, profile, local_day_key
              FROM track_points
              WHERE session_id IN (
                SELECT id FROM recording_sessions
                WHERE local_day_key = ?
                  AND kind IN ('manual', 'ambient')
                  AND (status IS NULL OR status != 'start_failed')
              )
            ),
            numbered AS (
              SELECT *,
                ROW_NUMBER() OVER (ORDER BY ts ASC) AS row_index,
                COUNT(*) OVER () AS total_count
              FROM filtered
            )
            SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
              session_id, segment_id, source, profile, local_day_key
            FROM numbered
            WHERE row_index = 1
              OR row_index = total_count
              OR ((row_index - 1) % ?) = 0
            ORDER BY ts ASC
            LIMIT ?
            """, [dayKey, stride, safeLimit], map: point)
    }

    func trackPointCount(for dayKey: String) throws -> Int {
        try scalarInt("""
            SELECT COUNT(*)
            FROM track_points
            WHERE session_id IN (
              SELECT id FROM recording_sessions
              WHERE local_day_key = ?
                AND kind IN ('manual', 'ambient')
                AND (status IS NULL OR status != 'start_failed')
            )
            """, [dayKey])
    }

    func forEachTrackPoint(for dayKey: String, body: (TrackPoint) throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare("""
            SELECT id, lng, lat, ts, accuracy, speed, altitude, heading,
              session_id, segment_id, source, profile, local_day_key
            FROM track_points
            WHERE session_id IN (
              SELECT id FROM recording_sessions
              WHERE local_day_key = ?
                AND kind IN ('manual', 'ambient')
                AND (status IS NULL OR status != 'start_failed')
            )
            ORDER BY ts ASC
            """)
        defer { sqlite3_finalize(statement) }
        bind(statement, values: [dayKey])
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                try body(point(from: statement))
            } else if result == SQLITE_DONE {
                return
            } else {
                throw TrackDatabaseError.stepFailed(errorMessage)
            }
        }
    }

    func loadPendingRegionAchievementCells(limit: Int = 28) throws -> [RegionAchievementCandidateCell] {
        let safeLimit = max(1, min(100, limit))
        return try query("""
            WITH cells AS (
              SELECT
                CAST(lat * 40 AS INTEGER) || ':' || CAST(lng * 40 AS INTEGER) AS cell_key,
                CAST(lat * 40 AS INTEGER) AS lat_cell,
                CAST(lng * 40 AS INTEGER) AS lng_cell,
                AVG(lat) AS lat,
                AVG(lng) AS lng,
                MIN(id) AS first_point_id,
                MIN(ts) AS first_seen_ts,
                MAX(ts) AS last_seen_ts,
                COUNT(*) AS point_count
              FROM track_points
              GROUP BY lat_cell, lng_cell
            )
            SELECT
              cells.cell_key,
              cells.lat,
              cells.lng,
              cells.first_point_id,
              cells.first_seen_ts,
              cells.last_seen_ts,
              cells.point_count
            FROM cells
            LEFT JOIN region_achievement_cells done
              ON done.cell_key = cells.cell_key
            WHERE done.cell_key IS NULL
            ORDER BY cells.first_point_id ASC
            LIMIT ?
            """, [safeLimit]) { statement in
                RegionAchievementCandidateCell(
                    cellKey: text(statement, 0) ?? "",
                    latitude: sqlite3_column_double(statement, 1),
                    longitude: sqlite3_column_double(statement, 2),
                    firstPointID: sqlite3_column_int64(statement, 3),
                    firstSeenMs: sqlite3_column_int64(statement, 4),
                    lastSeenMs: sqlite3_column_int64(statement, 5),
                    pointCount: Int(sqlite3_column_int64(statement, 6))
                )
            }
    }

    func hasPendingRegionAchievementCells() throws -> Bool {
        try !loadPendingRegionAchievementCells(limit: 1).isEmpty
    }

    @discardableResult
    func saveRegionAchievementCell(
        _ cell: RegionAchievementCandidateCell,
        place: RegionAchievementResolvedPlace?
    ) throws -> Bool {
        let cityAlreadyExists: Bool
        if let place {
            cityAlreadyExists = try scalarInt("SELECT COUNT(*) FROM region_achievements WHERE city_key = ?", [place.cityKey]) > 0
        } else {
            cityAlreadyExists = true
        }

        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try run("""
                INSERT OR REPLACE INTO region_achievement_cells (
                  cell_key, lat, lng, first_point_id, first_seen_ts,
                  last_seen_ts, point_count, country_code, country_name,
                  admin_area, city_name, city_key, resolved_ts
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [
                    cell.cellKey,
                    cell.latitude,
                    cell.longitude,
                    cell.firstPointID,
                    cell.firstSeenMs,
                    cell.lastSeenMs,
                    cell.pointCount,
                    place?.countryCode,
                    place?.countryName,
                    place?.adminArea,
                    place?.cityName,
                    place?.cityKey,
                    AppFormatters.nowMs()
                ])

            if let place {
                try run("""
                    INSERT INTO region_achievements (
                      city_key, country_code, country_name, admin_area,
                      city_name, first_seen_ts, last_seen_ts, cell_count
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 1)
                    ON CONFLICT(city_key) DO UPDATE SET
                      country_name = excluded.country_name,
                      admin_area = excluded.admin_area,
                      city_name = excluded.city_name,
                      first_seen_ts = MIN(region_achievements.first_seen_ts, excluded.first_seen_ts),
                      last_seen_ts = MAX(region_achievements.last_seen_ts, excluded.last_seen_ts),
                      cell_count = region_achievements.cell_count + 1
                    """, [
                        place.cityKey,
                        place.countryCode,
                        place.countryName,
                        place.adminArea,
                        place.cityName,
                        cell.firstSeenMs,
                        cell.lastSeenMs
                    ])
            }

            try execute("COMMIT")
            return place != nil && !cityAlreadyExists
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func loadRegionAchievements() throws -> [RegionAchievementCountry] {
        let cities = try query("""
            SELECT
              city_key, country_code, country_name, admin_area, city_name,
              first_seen_ts, last_seen_ts, cell_count
            FROM region_achievements
            ORDER BY country_name COLLATE NOCASE ASC,
              city_name COLLATE NOCASE ASC
            """) { statement in
                RegionAchievementCity(
                    cityKey: text(statement, 0) ?? "",
                    countryCode: text(statement, 1) ?? "",
                    countryName: text(statement, 2) ?? "",
                    adminArea: text(statement, 3),
                    cityName: text(statement, 4) ?? "",
                    firstSeenMs: int64(statement, 5),
                    lastSeenMs: int64(statement, 6),
                    cellCount: Int(sqlite3_column_int64(statement, 7))
                )
            }

        var order: [String] = []
        var grouped: [String: (name: String, cities: [RegionAchievementCity])] = [:]
        for city in cities {
            if grouped[city.countryCode] == nil {
                order.append(city.countryCode)
                grouped[city.countryCode] = (city.countryName, [])
            }
            grouped[city.countryCode]?.cities.append(city)
        }

        return order.compactMap { countryCode in
            guard let group = grouped[countryCode] else { return nil }
            return RegionAchievementCountry(
                countryCode: countryCode,
                countryName: group.name,
                cities: group.cities
            )
        }
    }

    func loadRegionAchievementMapCities() throws -> [RegionAchievementMapCity] {
        let cellPaddingDegrees = 0.0125
        let rows = try query("""
            SELECT
              achievement.city_key,
              achievement.country_code,
              achievement.country_name,
              achievement.admin_area,
              achievement.city_name,
              MIN(cell.lat) AS min_lat,
              MAX(cell.lat) AS max_lat,
              MIN(cell.lng) AS min_lng,
              MAX(cell.lng) AS max_lng,
              COUNT(cell.cell_key) AS cell_count
            FROM region_achievements achievement
            JOIN region_achievement_cells cell
              ON cell.city_key = achievement.city_key
            GROUP BY
              achievement.city_key,
              achievement.country_code,
              achievement.country_name,
              achievement.admin_area,
              achievement.city_name
            ORDER BY achievement.country_name COLLATE NOCASE ASC,
              achievement.city_name COLLATE NOCASE ASC
            """) { statement in
                (
                    cityKey: text(statement, 0) ?? "",
                    countryCode: text(statement, 1) ?? "",
                    countryName: text(statement, 2) ?? "",
                    adminArea: text(statement, 3),
                    cityName: text(statement, 4) ?? "",
                    minLatitude: sqlite3_column_double(statement, 5) - cellPaddingDegrees,
                    maxLatitude: sqlite3_column_double(statement, 6) + cellPaddingDegrees,
                    minLongitude: sqlite3_column_double(statement, 7) - cellPaddingDegrees,
                    maxLongitude: sqlite3_column_double(statement, 8) + cellPaddingDegrees,
                    cellCount: Int(sqlite3_column_int64(statement, 9))
                )
            }

        return rows.enumerated().map { index, row in
            RegionAchievementMapCity(
                cityKey: row.cityKey,
                regionId: nil,
                countryCode: row.countryCode,
                countryName: row.countryName,
                adminArea: row.adminArea,
                cityName: row.cityName,
                minLatitude: row.minLatitude,
                maxLatitude: row.maxLatitude,
                minLongitude: row.minLongitude,
                maxLongitude: row.maxLongitude,
                cellCount: row.cellCount,
                colorIndex: index,
                isUnlocked: true,
                cityKeyAliases: [],
                boundaryPolygons: []
            )
        }
    }

    func clearRegionAchievements() throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try run("DELETE FROM region_achievement_cells")
            try run("DELETE FROM region_achievements")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteDay(_ dayKey: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let sessionFilter = """
                SELECT id FROM recording_sessions
                WHERE local_day_key = ?
                  AND kind IN ('manual', 'ambient')
                  AND (status IS NULL OR status != 'start_failed')
                """
            try run("DELETE FROM track_points WHERE session_id IN (\(sessionFilter))", [dayKey])
            try run("DELETE FROM track_segments WHERE session_id IN (\(sessionFilter))", [dayKey])
            try run("""
                DELETE FROM recording_sessions
                WHERE local_day_key = ?
                  AND kind IN ('manual', 'ambient')
                  AND (status IS NULL OR status != 'start_failed')
                """, [dayKey])
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
