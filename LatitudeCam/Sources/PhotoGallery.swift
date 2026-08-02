//
//  PhotoGallery.swift
//  LatitudeCam - Phase 0.4.2
//
//  Photo Gallery: Store and display captured photos with film info
//

import Foundation
import UIKit

public class PhotoGallery {
    public struct Photo {
        public let id: String
        public let image: UIImage
        public let filmProfile: String
        public let iso: Int
        public let shutter: Double
        public let timestamp: Date
    }
    
    private var photos: [Photo] = []
    private let fileManager = FileManager.default
    
    public init() {
        loadPhotos()
    }
    
    public func addPhoto(_ image: UIImage, filmProfile: String, iso: Int, shutter: Double) {
        let photo = Photo(
            id: UUID().uuidString,
            image: image,
            filmProfile: filmProfile,
            iso: iso,
            shutter: shutter,
            timestamp: Date()
        )
        photos.insert(photo, at: 0)
        savePhoto(photo)
    }
    
    public func getPhotos() -> [Photo] {
        return photos
    }
    
    public func deletePhoto(_ id: String) {
        photos.removeAll { $0.id == id }
    }
    
    private func savePhoto(_ photo: Photo) {
        let galleryDir = getGalleryDirectory()
        let photoFile = galleryDir.appendingPathComponent("\(photo.id).jpg")
        
        if let jpegData = photo.image.jpegData(compressionQuality: 0.95) {
            try? jpegData.write(to: photoFile)
        }
    }
    
    private func loadPhotos() {
        let galleryDir = getGalleryDirectory()
        let fileURLs = (try? fileManager.contentsOfDirectory(at: galleryDir, includingPropertiesForKeys: nil)) ?? []
        
        for url in fileURLs {
            if let image = UIImage(contentsOfFile: url.path) {
                let photo = Photo(
                    id: url.deletingPathExtension().lastPathComponent,
                    image: image,
                    filmProfile: "Unknown",
                    iso: 100,
                    shutter: 1.0,
                    timestamp: Date()
                )
                photos.append(photo)
            }
        }
    }
    
    private func getGalleryDirectory() -> URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDir = paths[0]
        let galleryDir = documentsDir.appendingPathComponent("Gallery", isDirectory: true)
        try? fileManager.createDirectory(at: galleryDir, withIntermediateDirectories: true)
        return galleryDir
    }
}

public class FilmPreviewGenerator {
    public static func generatePreview(for film: String, size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        // Create gradient based on film type
        let colors: [CGColor]
        switch film {
        case "Amber": colors = [CGColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 1.0), 
                               CGColor(red: 0.9, green: 0.7, blue: 0.3, alpha: 1.0)]
        case "Slate": colors = [CGColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 1.0),
                               CGColor(red: 0.4, green: 0.5, blue: 0.7, alpha: 1.0)]
        case "Rust": colors = [CGColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1.0),
                              CGColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1.0)]
        case "Mono": colors = [CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0),
                              CGColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0)]
        default: colors = [CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
                          CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)]
        }
        
        let colorspace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorspace, colors: colors as CFArray, locations: nil)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
