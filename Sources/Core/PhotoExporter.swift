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
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                completion(false, "Photo library access denied")
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                completion(success, error?.localizedDescription)
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
