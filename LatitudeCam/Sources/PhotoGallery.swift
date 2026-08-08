//
//  PhotoGallery.swift
//  LatitudeCam
//
//  On-disk store for captured frames, plus the shoot metadata for each one.
//

import Foundation
import UIKit
import ImageIO
import Photos

public final class PhotoGallery: NSObject, ObservableObject {

    public struct Photo: Identifiable, Equatable {
        public let id: String
        /// Full roll copy — what the editor works from.
        public let image: UIImage
        /// Grid copy. A three-column cell is about 360px on a Pro Max; handing it
        /// a 2048px image means downsampling a megapixel per cell on every scroll
        /// tick, for a picture the size of a postage stamp.
        public let thumb: UIImage
        /// The asset in Apple Photos this row stands for. Nil only for a frame
        /// taken this session that the library has not confirmed yet.
        public let assetID: String?
        public let filmID: String
        public let iso: Int
        public let shutterDenominator: Int
        public let timestamp: Date

        public static func == (a: Photo, b: Photo) -> Bool { a.id == b.id }
    }

    /// Newest first.
    @Published public private(set) var photos: [Photo] = []

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.latitude.gallery", qos: .utility)

    public override init() {
        super.init()
        // Disk I/O never blocks launch — the grid fills in when it is ready.
        ioQueue.async { [weak self] in self?.loadPhotos() }
        // Two things this alone does not cover: PhotoGallery is built once at
        // launch, but Photos permission is normally granted later, on first
        // capture — a launch-time load found nothing and nothing ever asked
        // again, so the roll stayed empty for the rest of the session. And a
        // photo taken by any other app, or one still arriving from iCloud, would
        // never appear either. This observer reloads on every library change,
        // which covers all three.
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    /// Re-reads the album. Safe to call as often as needed — it always merges
    /// against whatever is already showing rather than flashing the grid empty.
    public func reload() {
        ioQueue.async { [weak self] in self?.loadPhotos() }
    }

    // MARK: - Mutation

    /// Returns the new entry's id. The insert itself hops to the main queue, so a
    /// caller that read `photos.first` instead would get the *previous* photo.
    @discardableResult
    public func addPhoto(
        _ image: UIImage, filmID: String, iso: Int, shutterDenominator: Int
    ) -> String {
        let timestamp = Date()
        let id = Self.makeID(timestamp: timestamp, filmID: filmID, iso: iso, shutter: shutterDenominator)
        let photo = Photo(
            id: id,
            image: image,
            thumb: Self.downscaled(image, maxEdge: Self.gridEdge),
            assetID: nil,
            filmID: filmID,
            iso: iso,
            shutterDenominator: shutterDenominator,
            timestamp: timestamp
        )

        // Shown immediately, so the roll never lags the shutter. Nothing is written
        // to app storage: Apple Photos is the only copy, and the next load reads it
        // back from there.
        DispatchQueue.main.async { [weak self] in
            self?.photos.insert(photo, at: 0)
        }
        return id
    }

    /// The name the frame is filed under in Photos. The shoot settings ride in it,
    /// which is how the roll reads them back without a second store of its own.
    public static func filename(for id: String) -> String { "\(id).jpg" }

    public func deletePhoto(_ id: String) {
        deletePhotos([id])
    }

    /// Deletes the corresponding Photos assets in one transaction. The roll is
    /// updated only after Photos confirms success; optimistic removal made a
    /// failed delete look successful until the next app launch reloaded the album.
    public func deletePhotos(
        _ ids: Set<String>, completion: @escaping (Bool, String?) -> Void = { _, _ in }
    ) {
        guard !ids.isEmpty else { return }
        let assetIDs = Set(photos.compactMap { ids.contains($0.id) ? $0.assetID : nil })

        guard !assetIDs.isEmpty else {
            completion(false, "The selected frames are still being added to Apple Photos. Please wait a moment and try again.")
            return
        }

        ioQueue.async {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(assetIDs), options: nil)
            guard assets.count > 0 else {
                DispatchQueue.main.async {
                    completion(false, "Photos could not find the selected frames.")
                }
                return
            }

            // This is the same one-way PhotoKit transaction used by the earlier
            // working single-frame delete. On this beta, the completion callback
            // can stall even after the system applies a change, so verify the
            // underlying assets instead of treating that callback as the truth.
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            self.verifyDeletion(assetIDs: assetIDs, frameIDs: ids, attempt: 0, completion: completion)
        }
    }

    private func verifyDeletion(
        assetIDs: Set<String>, frameIDs: Set<String>, attempt: Int,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let remaining = PHAsset.fetchAssets(withLocalIdentifiers: Array(assetIDs), options: nil).count
        if remaining == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.photos.removeAll { frameIDs.contains($0.id) }
                completion(true, nil)
            }
            return
        }

        guard attempt < 16 else {
            DispatchQueue.main.async {
                completion(false, "Apple Photos did not apply the deletion. No frames were removed.")
            }
            return
        }

        ioQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.verifyDeletion(assetIDs: assetIDs, frameIDs: frameIDs, attempt: attempt + 1, completion: completion)
        }
    }

    // MARK: - Disk

    /// The longest edge kept in memory. The roll is a contact sheet — the masters
    /// live on disk and in Apple Photos. Holding full 48MP frames here cost about
    /// 190MB each, which is what emptied the grid: a few shots in, allocations
    /// started failing and later captures had nothing left to render into.
    static let inMemoryEdge: CGFloat = 1280
    /// Long edge of the grid copy.
    static let gridEdge: CGFloat = 420

    /// Decoded straight to the size we need. UIImage(contentsOfFile:) would
    /// materialise the whole frame first, which is the cost being avoided.
    static func thumbnail(at url: URL, maxEdge: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    /// Fits an image inside `maxEdge` without going through a file.
    static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let longest = CGFloat(max(cg.width, cg.height))
        guard longest > maxEdge else { return image }

        let scale = maxEdge / longest
        let size = CGSize(
            width: (CGFloat(cg.width) * scale).rounded(),
            height: (CGFloat(cg.height) * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Reads the roll back out of Apple Photos.
    ///
    /// The app used to keep its own JPEG of every frame in Documents, which meant
    /// every picture existed twice on the phone — once where the user expects it
    /// and once where they cannot see it. Photos is now the only copy, and this
    /// fetches our own album back.
    private func loadPhotos() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // .notDetermined is not a failure — permission is normally granted later,
        // on first capture, and the library-change observer re-runs this once it
        // is. Nothing to do yet, but nothing wrong either.
        guard status == .authorized || status == .limited else { return }
        guard let album = PhotoExporter.album() else { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAssets.fetch(in: album, options: options)

        // Grid-sized thumbnails only, and one request per asset rather than two.
        // The 1280pt "roll" copy used to be decoded synchronously for every
        // photo in the album before the grid could show a single one — on any
        // real-sized roll that read as the gallery having frozen. It is now
        // decoded on demand, the moment a specific photo is actually opened.
        let manager = PHImageManager.default()
        let request = PHImageRequestOptions()
        request.isSynchronous = false
        request.deliveryMode = .opportunistic
        // Grid thumbnails are small and these are our own recent captures —
        // almost always already local. Letting this wait on iCloud (as the
        // full-res fetch below correctly does) meant every thumbnail in the
        // roll queued behind a network round trip before it could appear.
        request.isNetworkAccessAllowed = false
        request.resizeMode = .fast

        // PHImageManager's completion handler can land on any thread and can
        // fire more than once per request (opportunistic delivery sends a fast
        // low-quality pass before the final one) — collect under a lock and
        // publish as a batch rather than racing the main-queue update.
        let resultLock = NSLock()
        var results: [String: Photo] = [:]
        let group = DispatchGroup()

        for asset in assets {
            // The filename carries the shoot settings; a frame taken by anything
            // else lands in the album without one and gets sensible defaults.
            let name = PHAssetResource.assetResources(for: asset)
                .first?.originalFilename ?? ""
            let rawID = (name as NSString).deletingPathExtension
            let id = rawID.isEmpty ? asset.localIdentifier : rawID
            let meta = Self.parseID(rawID)

            group.enter()
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: Self.gridEdge, height: Self.gridEdge),
                contentMode: .aspectFit, options: request
            ) { [weak self] image, info in
                guard let self else { return }
                defer {
                    // isDegraded marks the fast opportunistic pass; only leave the
                    // group once the final image has arrived, or a genuinely
                    // failed request would hang it open forever.
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if !degraded { group.leave() }
                }
                guard let image else { return }
                let photo = Photo(
                    id: id, image: image, thumb: image, assetID: asset.localIdentifier,
                    filmID: meta.filmID, iso: meta.iso, shutterDenominator: meta.shutter,
                    timestamp: asset.creationDate ?? meta.timestamp
                )
                resultLock.lock()
                results[id] = photo
                resultLock.unlock()

                // Published as each photo resolves rather than after the whole
                // album — the grid fills in progressively instead of staying
                // blank until the slowest asset (an iCloud original, typically)
                // finishes downloading.
                self.publish(Array(results.values))
            }
        }
    }

    /// Merges a batch of freshly loaded photos into what is already showing. A
    /// capture taken this session, or a photo from an earlier partial load, must
    /// survive being merged over rather than replaced.
    private func publish(_ batch: [Photo]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var byID = Dictionary(uniqueKeysWithValues: self.photos.map { ($0.id, $0) })
            for photo in batch { byID[photo.id] = photo }
            self.photos = byID.values.sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// The full-resolution roll copy, fetched only when a specific photo is
    /// opened — the viewer or the editor — rather than for the whole album up
    /// front.
    public func loadFullImage(for photo: Photo, completion: @escaping (UIImage?) -> Void) {
        guard let assetID = photo.assetID,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
        else {
            completion(photo.image)
            return
        }

        let request = PHImageRequestOptions()
        request.isSynchronous = false
        request.deliveryMode = .highQualityFormat
        request.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: Self.inMemoryEdge, height: Self.inMemoryEdge),
            contentMode: .aspectFit, options: request
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard !degraded else { return }
            DispatchQueue.main.async { completion(image ?? photo.image) }
        }
    }

    /// Reloads on any change to the library — a photo added from elsewhere, one
    /// finishing its iCloud download, or (the case that mattered most) Photos
    /// permission being granted after PhotoGallery already existed.
    private enum PHAssets {
        static func fetch(in album: PHAssetCollection, options: PHFetchOptions) -> [PHAsset] {
            let result = PHAsset.fetchAssets(in: album, options: options)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in assets.append(asset) }
            return assets
        }
    }

    private func galleryDirectory() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let gallery = documents.appendingPathComponent("Gallery", isDirectory: true)
        try? fileManager.createDirectory(at: gallery, withIntermediateDirectories: true)
        return gallery
    }

    // MARK: - Filename metadata
    //
    // The shoot settings ride in the filename. A sidecar file would be a second
    // thing to keep in sync, and the fields are all short and delimiter-free.

    private static let idLock = NSLock()
    private static var sequence = 0

    /// Ids must be unique: `deletePhoto` matches on id, so two frames sharing one
    /// are deleted together, and the second also overwrites the first on disk.
    /// Millisecond resolution alone is not enough — a capture and an edit-save
    /// land in the same millisecond easily — so a per-run sequence carries the
    /// uniqueness instead, leaving the timestamp exactly as supplied.
    static func makeID(timestamp: Date, filmID: String, iso: Int, shutter: Int) -> String {
        idLock.lock()
        sequence += 1
        let seq = sequence
        idLock.unlock()

        let millis = Int(timestamp.timeIntervalSince1970 * 1000)
        return "photo_\(millis)_\(seq)_\(filmID)_\(iso)_\(shutter)"
    }

    static func parseID(_ id: String) -> (timestamp: Date, filmID: String, iso: Int, shutter: Int) {
        let fallback = (Date(timeIntervalSince1970: 0), "amber", 100, 60)
        let parts = id.split(separator: "_").map(String.init)
        guard parts.first == "photo", parts.count > 1, let millis = Int(parts[1]) else {
            return fallback
        }
        let when = Date(timeIntervalSince1970: Double(millis) / 1000)

        switch parts.count {
        case 6:   // photo_<millis>_<seq>_<film>_<iso>_<shutter>
            return (when, parts[3], Int(parts[4]) ?? 100, Int(parts[5]) ?? 60)
        case 5:   // rolls written before ids carried a sequence
            return (when, parts[2], Int(parts[3]) ?? 100, Int(parts[4]) ?? 60)
        default:
            return fallback
        }
    }
}

// MARK: - Library change observation

extension PhotoGallery: PHPhotoLibraryChangeObserver {
    /// Fires on a background thread for any library change; loadPhotos() does
    /// its own hop to ioQueue and to main, so this only needs to kick it off.
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        reload()
    }
}
