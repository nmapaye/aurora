import AuroraCore
import Foundation
import UIKit
import Vision

/// Reads one drink photo with Apple's on-device frameworks only:
/// - Vision text recognition (label words and container size),
/// - Vision barcode detection (exact UPC/EAN database lookup),
/// - Vision image classification (drink kind).
/// No language model reads the photo: an image-attachment path for a future
/// SDK was removed because CI's SDK could never type-check it (see
/// docs/drink-photo-logging.md). No network request, no cloud or Private
/// Cloud Compute model, no third-party model. The image stays in memory and is dropped when the sheet closes.
/// Nothing here produces a caffeine amount: that comes from the bundled
/// database after the person confirms.
enum DrinkPhotoAnalyzer {
    static func analyze(_ image: UIImage) async -> DrinkPhotoObservation {
        guard let cgImage = upright(image) else { return .init() }
        return await Task.detached(priority: .userInitiated) { vision(cgImage) }.value
    }

    /// Redraws in .up orientation so Vision sees what the
    /// person saw, and caps the size so analysis stays quick.
    static func upright(_ image: UIImage, maxSide: CGFloat = 2048) -> CGImage? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    nonisolated static func vision(_ image: CGImage) -> DrinkPhotoObservation {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.recognitionLanguages = ["en-US"]
        let barcodes = VNDetectBarcodesRequest()
        barcodes.symbologies = [.ean13, .ean8, .upce, .itf14]
        let classify = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try? handler.perform([text, barcodes, classify])
        let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let codes = (barcodes.results ?? []).compactMap(\.payloadStringValue)
        var labels: [String: Double] = [:]
        for result in (classify.results ?? []) where result.confidence >= 0.3 {
            labels[result.identifier] = Double(result.confidence)
        }
        return DrinkPhotoObservation(recognizedText: lines, barcodes: codes, labels: labels)
    }
}
