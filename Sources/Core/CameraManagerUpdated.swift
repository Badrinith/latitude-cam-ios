//
//  CameraManager Extension
//  Add PreviewEngine integration
//

import Foundation

extension CameraManager {
    
    private static var previewEngine: PreviewEngine = PreviewEngine()
    
    /// Get preview engine for frame processing
    static func getPreviewEngine() -> PreviewEngine {
        return previewEngine
    }
    
    /// Process frame through preview engine
    func processPreviewFrame(_ frame: CGImage) {
        let engine = CameraManager.getPreviewEngine()
        
        // Convert to pixels
        let pixels = engine.convertToPixels(frame)
        
        // Apply current settings
        let processed = engine.processPixels(pixels, film: currentFilmProfile, iso: currentISO, shutter: currentShutterTime)
        
        // Convert back to image for preview
        let previewImage = engine.convertToImage(processed, width: frame.width, height: frame.height)
        
        // Update preview
        DispatchQueue.main.async {
            self.onPreviewUpdate?()
        }
    }
}
