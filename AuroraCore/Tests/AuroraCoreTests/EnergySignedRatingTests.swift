import Testing
@testable import AuroraCore

@Suite struct EnergySignedRatingTests {
    @Test func negativeRatingsRemainUnspecified() {
        for input in ["-2/5", "I feel -2 out of 5", "energy -1/5"] {
            #expect(AssistantPlanner.explicitIntent(input) == .energyCheckIn)
            #expect(AssistantPlanner.statedSelfRating(input) == nil)
            #expect(AssistantPlanner.checkInRating(input) == nil)
        }
        // Out of 5 is the old energy scale: it opens a review, unfilled.
        #expect(AssistantPlanner.statedSelfRating("I feel 2 out of 5") == nil)
        #expect(AssistantPlanner.statedSelfRating("I feel 2 out of 9") == 2)
        #expect(AssistantPlanner.statedSelfRating("-2/9") == nil)
    }
}
