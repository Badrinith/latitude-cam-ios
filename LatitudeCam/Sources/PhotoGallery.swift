//
//  PhotoGallery.swift
//  LatitudeCam
//
//  On-disk store for captured frames, plus the shoot metadata for each one.
//

import Foundation
import UIKit

public final class PhotoGallery: ObservableObject {

    public struct Photo: Identifiable, Equatable {
        public let id: String
        public let image: UIImage
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

    public init() {
        // Disk I/O never blocks launch — the grid fills in when it is ready.
        ioQueue.async { [weak self] in self?.loadPhotos() }
    }

    // MARK: - Mutation

    public func addPhoto(_ image: UIImage, filmID: String, iso: Int, shutterDenominator: Int) {
        let timestamp = Date()
        let id = Self.makeID(timestamp: timestamp, filmID: filmID, iso: iso, shutter: shutterDenominator)
        let photo = Photo(
            id: id,
            image: image,
            filmID: filmID,
            iso: iso,
            shutterDenominator: shutterDenominator,
            timestamp: timestamp
        )

        DispatchQueue.main.async { [weak self] in
            self?.photos.insert(photo, at: 0)
        }

        let quality = Pref.compressionQuality(
            Pref.string(Pref.jpegQuality, default: "High")
        )
        ioQueue.async { [weak self] in
            guard let self, let data = image.jpegData(compressionQuality: quality) else { return }
            try? data.write(to: self.galleryDirectory().appendingPathComponent("\(id).jpg"))
        }
    }

    public func deletePhoto(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            self?.photos.removeAll { $0.id == id }
        }
        ioQueue.async { [weak self] in
            guard let self else { return }
            // The file has to go too — dropping only the in-memory entry meant
            // loadPhotos() resurrected deleted photos on the next launch.
            try? self.fileManager.removeItem(
                at: self.galleryDirectory().appendingPathComponent("\(id).jpg")
            )
        }
    }

    // MARK: - Disk

    private func loadPhotos() {
        let urls = (try? fileManager.contentsOfDirectory(
            at: galleryDirectory(), includingPropertiesForKeys: nil
        )) ?? []

        let loaded: [Photo] = urls
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .compactMap { url in
                guard let image = UIImage(contentsOfFile: url.path) else { return nil }
                let id = url.deletingPathExtension().lastPathComponent
                let meta = Self.parseID(id)
                return Photo(
                    id: id,
                    image: image,
                    filmID: meta.filmID,
                    iso: meta.iso,
                    shutterDenominator: meta.shutter,
                    timestamp: meta.timestamp
                )
            }
            .sorted { $0.timestamp > $1.timestamp }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // A capture can land before this first disk read returns. Replacing
            // the array wholesale silently dropped that photo from the grid, so
            // merge on id and keep whatever is already in memory.
            let known = Set(self.photos.map(\.id))
            self.photos = (self.photos + loaded.filter { !known.contains($0.id) })
                .sorted { $0.timestamp > $1.timestamp }
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

    static func makeID(timestamp: Date, filmID: String, iso: Int, shutter: Int) -> String {
        let millis = Int(timestamp.timeIntervalSince1970 * 1000)
        return "photo_\(millis)_\(filmID)_\(iso)_\(shutter)"
    }

    static func parseID(_ id: String) -> (timestamp: Date, filmID: String, iso: Int, shutter: Int) {
        let parts = id.split(separator: "_").map(String.init)
        guard parts.count == 5, parts[0] == "photo", let millis = Int(parts[1]) else {
            return (Date(timeIntervalSince1970: 0), "amber", 100, 60)
        }
        return (
            Date(timeIntervalSince1970: Double(millis) / 1000),
            parts[2],
            Int(parts[3]) ?? 100,
            Int(parts[4]) ?? 60
        )
    }
}
