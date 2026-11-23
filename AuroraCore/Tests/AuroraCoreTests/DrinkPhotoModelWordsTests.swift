import Testing
@testable import AuroraCore

/// The owner's matcha photo (Nov 19): stickers behind the mug and a generic
/// "coffee" classifier label. The on-device model's words decide the drink.
@Suite struct DrinkPhotoModelWordsTests {
    var db: CaffeineDatabase { CaffeineDatabase.bundled! }
    let stickerNoise = ["OF TOKENS", "Researching", "KEEP HONKING"]

    @Test func visionAloneGuessesCoffee() {
        let observation = DrinkPhotoObservation(recognizedText: stickerNoise, labels: ["coffee": 0.5, "cup": 0.8])
        guard case .candidates(let list, _) = DrinkPhotoMatcher.match(observation, in: db) else { Issue.record("expected candidates"); return }
        #expect(list.first?.entry.name.lowercased().contains("coffee") == true)
    }

    @Test func modelSeeingMatchaNeverOffersACoffeeRecord() {
        let observation = DrinkPhotoObservation(recognizedText: stickerNoise, labels: ["coffee": 0.5, "cup": 0.8],
                                                modelDrink: "matcha latte", modelBrand: "")
        #expect(DrinkPhotoMatcher.match(observation, in: db) == .noMatch(DrinkPhotoMatcher.unrecordedBrandMessage))
    }
}
