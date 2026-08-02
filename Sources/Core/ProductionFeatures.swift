//
//  ProductionFeatures.swift
//  LatitudeCam - Phase 0.4.6-8
//
//  Error Handling, Permissions, Performance, Privacy
//

import Foundation
import Photos
import AVFoundation

// MARK: - Permission Manager

public class PermissionManager {
    public enum PermissionStatus { case notDetermined, authorized, denied, restricted }
    
    public static func getCameraPermission(completion: @escaping (PermissionStatus) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            completion(.authorized)
        case .denied:
            completion(.denied)
        case .restricted:
            completion(.restricted)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted ? .authorized : .denied)
            }
        @unknown default:
            completion(.notDetermined)
        }
    }
    
    public static func getPhotoLibraryPermission(completion: @escaping (PermissionStatus) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            completion(.authorized)
        case .denied:
            completion(.denied)
        case .restricted:
            completion(.restricted)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { _ in
                completion(.authorized)
            }
        @unknown default:
            completion(.notDetermined)
        }
    }
}

// MARK: - Error Handler

public class ErrorHandler {
    public enum AppError: LocalizedError {
        case cameraUnavailable
        case permissionDenied
        case processingFailed(String)
        case saveFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .cameraUnavailable: return "Camera is not available"
            case .permissionDenied: return "Camera permission denied"
            case .processingFailed(let msg): return "Processing failed: \(msg)"
            case .saveFailed(let msg): return "Save failed: \(msg)"
            }
        }
    }
}

// MARK: - Memory Optimizer

public class MemoryOptimizer {
    public static func optimizeImageSize(_ image: UIImage, maxWidth: CGFloat = 1920) -> UIImage? {
        let scale = min(1.0, maxWidth / image.size.width)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let optimized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return optimized
    }
    
    public static func clearCache() {
        URLCache.shared.removeAllCachedResponses()
    }
}

// MARK: - Privacy Manager

public class PrivacyManager {
    private static let defaults = UserDefaults.standard
    
    public static func logDataUsage(_ type: String) {
        let key = "privacy_\(type)"
        defaults.set(Date(), forKey: key)
    }
    
    public static func getPrivacyPolicy() -> String {
        return """
        Privacy Policy - Latitude Cam
        
        We collect:
        - Photos you capture (stored locally on your device)
        - Camera settings (ISO, shutter speed, film profile)
        - Usage analytics (anonymous, for improvement)
        
        We DO NOT:
        - Share photos with third parties
        - Store photos on our servers
        - Sell your data
        
        All processing happens on your device.
        """
    }
}
