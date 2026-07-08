import CoreLocation
import Foundation
import ImageIO
import Photos

enum PhotoLocationExtractor {
    struct AlbumFetchResult: Sendable {
        let albums: [PhotoAlbumSummary]
        let limitedAccess: Bool
        let denied: Bool
    }

    struct LibraryImportResult: Sendable {
        let points: [PhotoMapPoint]
        let scannedCount: Int
        let skippedCount: Int
        let limitedAccess: Bool
        let denied: Bool
    }

    static func coordinateFromPhotoAsset(identifier: String) async -> CLLocationCoordinate2D? {
        let status = await photoLibraryStatus()
        guard status == .authorized || status == .limited else {
            return nil
        }
        return await Task.detached(priority: .userInitiated) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            return assets.firstObject?.location?.coordinate
        }.value
    }

    static func photoPoints(from _: PhotoLibraryImportScope) async -> LibraryImportResult {
        let status = await photoLibraryStatus()
        guard status == .authorized || status == .limited else {
            return deniedImportResult
        }

        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            options.predicate = imagePredicate
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            return importResult(from: assets, limitedAccess: status == .limited)
        }.value
    }

    static func photoAlbums() async -> AlbumFetchResult {
        let status = await photoLibraryStatus()
        guard status == .authorized || status == .limited else {
            return AlbumFetchResult(albums: [], limitedAccess: false, denied: true)
        }

        return await Task.detached(priority: .userInitiated) {
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            let assetOptions = PHFetchOptions()
            assetOptions.predicate = imagePredicate

            var albums: [PhotoAlbumSummary] = []
            var seenIDs = Set<String>()
            collections.enumerateObjects { collection, _, _ in
                guard seenIDs.insert(collection.localIdentifier).inserted else { return }
                let count = PHAsset.fetchAssets(in: collection, options: assetOptions).count
                guard count > 0 else { return }
                albums.append(
                    PhotoAlbumSummary(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Untitled Album",
                        assetCount: count
                    )
                )
            }

            albums.sort { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return AlbumFetchResult(albums: albums, limitedAccess: status == .limited, denied: false)
        }.value
    }

    static func photoPoints(fromAlbumID albumID: String) async -> LibraryImportResult {
        let status = await photoLibraryStatus()
        guard status == .authorized || status == .limited else {
            return deniedImportResult
        }

        return await Task.detached(priority: .userInitiated) {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
            guard let collection = collections.firstObject else {
                return LibraryImportResult(
                    points: [],
                    scannedCount: 0,
                    skippedCount: 0,
                    limitedAccess: status == .limited,
                    denied: false
                )
            }

            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            options.predicate = imagePredicate
            let assets = PHAsset.fetchAssets(in: collection, options: options)
            return importResult(from: assets, limitedAccess: status == .limited)
        }.value
    }

    private static func photoLibraryStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated static func coordinateFromImageData(_ data: Data) -> CLLocationCoordinate2D? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = coordinateValue(gps[kCGImagePropertyGPSLatitude]),
              let longitude = coordinateValue(gps[kCGImagePropertyGPSLongitude])
        else { return nil }

        let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
        let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()
        return CLLocationCoordinate2D(
            latitude: latitudeRef == "S" ? -latitude : latitude,
            longitude: longitudeRef == "W" ? -longitude : longitude
        )
    }

    nonisolated private static var imagePredicate: NSPredicate {
        NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    }

    nonisolated private static var deniedImportResult: LibraryImportResult {
        LibraryImportResult(
            points: [],
            scannedCount: 0,
            skippedCount: 0,
            limitedAccess: false,
            denied: true
        )
    }

    nonisolated private static func importResult(
        from assets: PHFetchResult<PHAsset>,
        limitedAccess: Bool
    ) -> LibraryImportResult {
        var points: [PhotoMapPoint] = []
        var skippedCount = 0

        assets.enumerateObjects { asset, _, _ in
            guard let coordinate = asset.location?.coordinate else {
                skippedCount += 1
                return
            }
            points.append(
                PhotoMapPoint(
                    id: asset.localIdentifier,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            )
        }

        return LibraryImportResult(
            points: points,
            scannedCount: assets.count,
            skippedCount: skippedCount,
            limitedAccess: limitedAccess,
            denied: false
        )
    }

    nonisolated private static func coordinateValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        if let values = value as? [Any], values.count >= 3,
           let degrees = coordinateValue(values[0]),
           let minutes = coordinateValue(values[1]),
           let seconds = coordinateValue(values[2]) {
            return degrees + minutes / 60 + seconds / 3_600
        }
        return nil
    }
}
