import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A book cover made small for the library: its longer side at most `maxPixels`, as JPEG. The
/// first version shows no other pictures, so the full-size image isn't kept.
enum CoverThumbnail {
    static func make(from data: Data, maxPixels: Int = 600) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}
