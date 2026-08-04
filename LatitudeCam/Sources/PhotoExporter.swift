//
//  PhotoExporter.swift
//  LatitudeCam
//
//  Export Photos: Save to Camera Roll with effects applied
//

import Foundation
import UIKit
import Photos
import UniformTypeIdentifiers

// MARK: - Photo Exporter

public class PhotoExporter {

    /// UTType.dng is iOS 18; the deployment target is 17, so the identifier is
    /// spelled out.
    private static let dngTypeIdentifier = "com.adobe.raw-image"

    /// Save one exposure to Apple Photos: the developed JPEG, and the DNG attached
    /// to the same asset as its raw alternate rather than as a second photo.
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

            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                if let jpeg {
                    request.addResource(with: .photo, data: jpeg, options: nil)
                    if let dng {
                        let options = PHAssetResourceCreationOptions()
                        options.uniformTypeIdentifier = dngTypeIdentifier
                        request.addResource(with: .alternatePhoto, data: dng, options: options)
                    }
                } else if let dng {
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = dngTypeIdentifier
                    request.addResource(with: .photo, data: dng, options: options)
                }
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success, success ? nil : (error?.localizedDescription ?? "Could not save to Photos"))
                }
            }
        }
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
