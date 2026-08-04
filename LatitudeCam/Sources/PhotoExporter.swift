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

    /// Export a processed image to Camera Roll
    public static func saveToPhotos(
        _ image: UIImage,
        completion: @escaping (Bool, String?) -> Void
    ) {
        // .addOnly is all this app needs, and it is the prompt users are far more
        // willing to accept than full library access.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    if success {
                        completion(true, nil)
                    } else {
                        completion(false, error?.localizedDescription ?? "Could not save to Photos")
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
    
    /// Export to file with metadata
    public static func exportToFile(
        _ image: UIImage,
        filmProfile: String,
        iso: Int,
        shutter: Double,
        completion: @escaping (URL?, String?) -> Void
    ) {
        let fileManager = FileManager.default
        
        // Create Latitude Cam documents directory
        guard let documentsDir = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            completion(nil, "Documents directory not found")
            return
        }
        
        let latitudeDir = documentsDir.appendingPathComponent("LatitudeCam", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: latitudeDir, withIntermediateDirectories: true)
        
        // Create filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        let filename = "Latitude_\(timestamp)_\(filmProfile)_ISO\(iso).jpg"
        let fileURL = latitudeDir.appendingPathComponent(filename)
        
        // Save image
        guard let jpegData = image.jpegData(compressionQuality: 0.95) else {
            completion(nil, "Could not convert image to JPEG")
            return
        }
        
        do {
            try jpegData.write(to: fileURL)
            completion(fileURL, nil)
        } catch {
            completion(nil, error.localizedDescription)
        }
    }
}
