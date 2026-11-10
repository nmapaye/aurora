import AuroraCore
import Foundation
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads one drink photo with Apple's on-device frameworks only:
/// - Vision text recognition (label words and container size),
/// - Vision barcode detection (exact UPC/EAN database lookup),
/// - Vision image classification (drink kind),
/// - on iOS 27, the on-device Foundation Model with an image attachment, for
///   drink and brand words only.
/// No network request, no cloud or Private Cloud Compute model, no third-party
/// model. The image stays in memory and is dropped when the sheet closes.
/// Nothing here produces a caffeine amount: that comes from the bundled
/// database after the person confirms.
enum DrinkPhotoAnalyzer {
    static func analyze(_ image: UIImage) async -> DrinkPhotoObservation {
        guard let cgImage = upright(image) else { return .init() }
        var observation = await Task.detached(priority: .userInitiated) { vision(cgImage) }.value
        if let words = await modelWords(cgImage) {
            observation.modelDrink = words.drink
            observation.modelBrand = words.brand
        }
        return observation
    }

    /// Redraws in .up orientation so Vision and the model see what the
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

    /// The model only names words to search for. Its output is never shown
    /// as a fact and its numbers are discarded by AuroraCore.
    static func modelWords(_ image: CGImage) async -> (drink: String, brand: String)? {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            guard case .ready = AppleOnDeviceFeatures.readiness() else { return nil }
            do {
                let session = LanguageModelSession(model: SystemLanguageModel.default) {
                    """
                    You look at one photo of a drink. Name the drink type and any brand printed or clearly visible.
                    Use short words from the photo. Leave brand empty if you cannot read one. Never estimate caffeine, sizes or numbers.
                    """
                }
                let response = try await session.respond(generating: PhotoDrinkWords.self,
                                                         options: GenerationOptions(temperature: 0, maximumResponseTokens: 60)) {
                    "What drink is in this photo, and what brand is printed on it?"
                    Attachment(image)
                }
                try Task.checkCancellation()
                return (String(response.content.drink.prefix(60)), String(response.content.brand.prefix(40)))
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// Whether this device can add the on-device model to Vision's reading.
    static var modelAvailable: Bool {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *), case .ready = AppleOnDeviceFeatures.readiness() { return true }
        #endif
        return false
    }
}

#if canImport(FoundationModels) && compiler(>=6.4)
@available(iOS 27.0, *)
@Generable
private struct PhotoDrinkWords {
    @Guide(description: "Drink type in a few lowercase words, such as cold brew coffee, energy drink, green tea, cola")
    var drink: String
    @Guide(description: "Brand name exactly as printed, or empty string")
    var brand: String
}
#endif
