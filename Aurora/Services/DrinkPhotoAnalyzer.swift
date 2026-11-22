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
/// - on iOS 27, Apple's on-device Foundation Model looking at the image
///   (drink and brand words only; `SystemLanguageModel.default`).
/// The model path compiles only with the iOS 27 SDK (Swift 6.4); older
/// toolchains build Vision-only. No network request, no cloud or Private
/// Cloud Compute model, no third-party model. The image stays in memory and is dropped when the sheet closes.
/// Nothing here produces a caffeine amount: that comes from the bundled
/// database after the person confirms.
enum DrinkPhotoAnalyzer {
    static func analyze(_ image: UIImage) async -> DrinkPhotoObservation {
        guard let cgImage = upright(image) else { return .init() }
        async let read = Task.detached(priority: .userInitiated) { vision(cgImage) }.value
        async let words = modelWords(cgImage)
        var observation = await read
        if let (drink, brand) = await words {
            observation.modelDrink = drink
            observation.modelBrand = brand
        }
        return observation
    }

    /// Drink and brand words from Apple's on-device model, or nil when the
    /// model isn't ready, the SDK predates image input, or the read fails.
    /// Words are search evidence only; numbers are never asked for or used.
    static func modelWords(_ image: CGImage) async -> (String, String)? {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            guard case .ready = AppleOnDeviceFeatures.readiness() else { return nil }
            do {
                // No `model:` argument: on iOS 27 that also matches the generic
                // `some LanguageModel` overloads. The default is
                // `SystemLanguageModel.default`, Apple's on-device model.
                let session = LanguageModelSession {
                    """
                    You look at one photo of a drink. Name the drink in the cup, glass, can or bottle by what it looks like \
                    (color, foam, ice, container) and any brand printed on its own label. Ignore stickers, books, screens \
                    and other text that is not on the drink. Leave brand empty if none is printed on the drink. \
                    Never estimate caffeine, sizes or numbers.
                    """
                }
                let response = try await session.respond(generating: PhotoDrinkWords.self,
                                                         options: GenerationOptions(temperature: 0, maximumResponseTokens: 60)) {
                    "What drink is in this photo, and what brand is printed on it?"
                    Attachment(image)
                }
                try Task.checkCancellation()
                let drink = String(response.content.drink.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
                let brand = String(response.content.brand.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
                return drink.isEmpty && brand.isEmpty ? nil : (drink, brand)
            } catch {
                return nil
            }
        }
        #endif
        return nil
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

#if canImport(FoundationModels) && compiler(>=6.4)
@available(iOS 27.0, *)
@Generable
private struct PhotoDrinkWords {
    @Guide(description: "Drink type in a few lowercase words, such as matcha latte, cold brew coffee, energy drink, green tea, cola")
    var drink: String
    @Guide(description: "Brand name exactly as printed on the drink's own label, or empty string")
    var brand: String
}
#endif
