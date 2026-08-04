//
//  PhotoExporter.swift
//  LatitudeCam
//
//  Export Photos: Save to Camera Roll with effects applied
//

import Foundation
import UIKit
import Photos

// MARK: - Photo Exporter

public class PhotoExporter {

    /// Save one exposure to Apple Photos: the developed JPEG, with the DNG attached
    /// to the same asset as its raw alternate rather than as a second photo.
    ///
    /// Falls back to two separate assets if the library will not accept the pair.
    /// Photos rejects a raw alternate whose frame does not match its primary, and
    /// the developed JPEG is cropped to the chosen aspect while the DNG keeps the
    /// full sensor frame — so on any aspect but the sensor's own, the pairing is
    /// expected to be refused. Losing the shot over a filing rule would be worse
    /// than two entries in the roll.
    public static func saveCapture(
        jpeg: Data?,
        dng: Data?,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard jpeg != nil || dng != nil else {
            completion(false, "Nothing to save")
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(false, permissionMessage(for: status))
                }
                return
            }

            // Photos wants raw on disk under a .dng extension. Added as a data
            // resource tagged with a UTI instead, it refused the whole change
            // request with changeNotSupported (PHPhotosErrorDomain 3300).
            let dngURL = dng.flatMap(writeTemporaryDNG)

            addPaired(jpeg: jpeg, dngURL: dngURL) { paired, pairError in
                if paired {
                    DispatchQueue.main.async { completion(true, nil) }
                    return
                }
                addSeparately(jpeg: jpeg, dngURL: dngURL) { ok, splitError in
                    if !ok, let dngURL { try? FileManager.default.removeItem(at: dngURL) }
                    DispatchQueue.main.async {
                        completion(ok, ok ? nil : describe(splitError ?? pairError))
                    }
                }
            }
        }
    }

    /// One asset carrying both resources — what Photos itself produces for ProRAW.
    private static func addPaired(
        jpeg: Data?,
        dngURL: URL?,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            if let jpeg {
                request.addResource(with: .photo, data: jpeg, options: nil)
            }
            if let dngURL {
                let options = PHAssetResourceCreationOptions()
                // Left in place: the fallback may still need the file.
                options.shouldMoveFile = false
                request.addResource(
                    with: jpeg == nil ? .photo : .alternatePhoto,
                    fileURL: dngURL,
                    options: options
                )
            }
        }, completionHandler: completion)
    }

    private static func addSeparately(
        jpeg: Data?,
        dngURL: URL?,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        PHPhotoLibrary.shared().performChanges({
            if let jpeg {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .photo, data: jpeg, options: nil)
            }
            if let dngURL {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .photo, fileURL: dngURL, options: options)
            }
        }, completionHandler: completion)
    }

    private static func writeTemporaryDNG(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("latitude-\(UUID().uuidString).dng")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Carries the domain and code through. "Could not save" alone gave nothing to
    /// work from when the library refused a change.
    private static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "Could not save to Photos" }
        return "Photos \(error.domain) \(error.code): \(error.localizedDescription)"
    }

    private static func permissionMessage(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .denied:     return "Photos permission denied. Settings › Latitude › Photos."
        case .restricted: return "Photos access is restricted on this device."
        default:          return "Unable to access Photos library."
        }
    }

    /// Export a processed image to Camera Roll
    public static func saveToPhotos(
        _ image: UIImage,
        completion: @escaping (Bool, String?) -> Void
    ) {
        // .addOnly is all this app needs, and it is the prompt users are far more
        // willing to accept than full library access.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }) { success, error in
                        DispatchQueue.main.async {
                            if success {
                                completion(true, nil)
                            } else {
                                completion(false, error?.localizedDescription ?? "Could not save to Photos")
                            }
                        }
                    }
                case .denied:
                    completion(false, "Photos permission denied. Enable in Settings › Latitude › Photos.")
                case .restricted:
                    completion(false, "Photos access is restricted on this device.")
                case .notDetermined:
                    completion(false, "Photos permission not determined.")
                @unknown default:
                    completion(false, "Unable to access Photos library.")
                }
            }
        }
    }
    
    /// Save image in both JPEG and HEIF RAW formats with maximum quality
    public static func exportToFile(
        _ image: UIImage,
        filmProfile: String,
        iso: Int,
        shutter: Double,
        completion: @escaping (URL?, String?) -> Void
    ) {
        let fileManager = FileManager.default

        guard let documentsDir = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            completion(nil, "Documents directory not found")
            return
        }

        let latitudeDir = documentsDir.appendingPathComponent("LatitudeCam", isDirectory: true)
        try? fileManager.createDirectory(at: latitudeDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        // Save maximum quality JPEG
        let jpegFilename = "Latitude_\(timestamp)_\(filmProfile)_ISO\(iso).jpg"
        let jpegURL = latitudeDir.appendingPathComponent(jpegFilename)

        guard let jpegData = image.jpegData(compressionQuality: 1.0) else {
            completion(nil, "Could not convert image to JPEG")
            return
        }

        do {
            try jpegData.write(to: jpegURL)

            // Also save as HEIF (Apple's RAW-capable format) for maximum quality archival
            let heifFilename = "Latitude_\(timestamp)_\(filmProfile)_ISO\(iso)_RAW.heif"
            let heifURL = latitudeDir.appendingPathComponent(heifFilename)

            if let heifData = image.heicData() {
                try heifData.write(to: heifURL)
            }

            completion(jpegURL, nil)
        } catch {
            completion(nil, error.localizedDescription)
        }
    }

    /// Save RAW/HEIF data from camera sensor (high-quality lossless)
    public static func saveRawDNG(
        _ rawData: Data,
        iso: Int,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let fileManager = FileManager.default

        guard let documentsDir = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            completion(false, "Documents directory not found")
            return
        }

        let latitudeDir = documentsDir.appendingPathComponent("LatitudeCam", isDirectory: true)
        try? fileManager.createDirectory(at: latitudeDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        // Use .heif extension since most modern iPhones use HEIF for RAW capture
        let filename = "Latitude_\(timestamp)_ISO\(iso)_RAW.heif"
        let fileURL = latitudeDir.appendingPathComponent(filename)

        do {
            try rawData.write(to: fileURL)
            completion(true, nil)
        } catch {
            completion(false, error.localizedDescription)
        }
    }

    /// Save image in HEIF format with maximum quality (RAW-capable format)
    public static func saveAsRAW(
        _ image: UIImage,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let fileManager = FileManager.default

        guard let documentsDir = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            completion(false, "Documents directory not found")
            return
        }

        let latitudeDir = documentsDir.appendingPathComponent("LatitudeCam", isDirectory: true)
        try? fileManager.createDirectory(at: latitudeDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let filename = "Latitude_\(timestamp)_RAW.heif"
        let fileURL = latitudeDir.appendingPathComponent(filename)

        if let heifData = image.heicData() {
            do {
                try heifData.write(to: fileURL)
                completion(true, nil)
            } catch {
                completion(false, error.localizedDescription)
            }
        } else {
            completion(false, "Could not convert image to HEIF format")
        }
    }
}
