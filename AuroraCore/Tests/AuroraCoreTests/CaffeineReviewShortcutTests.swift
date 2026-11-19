import Foundation
import Testing
@testable import AuroraCore

@Suite struct CaffeineReviewShortcutTests {
    @Test func noRequestDoesNotOpenReview() {
        var handoff = CaffeineReviewShortcut()
        let opened = handoff.consume(ready: true, hasOpenReview: false)
        #expect(!opened)
    }
    @Test func readinessDefersWithoutConsuming() {
        var handoff = CaffeineReviewShortcut()
        handoff.request()
        let early = handoff.consume(ready: false, hasOpenReview: false)
        #expect(!early && handoff.requested)
        let ready = handoff.consume(ready: true, hasOpenReview: false)
        #expect(ready && !handoff.requested)
    }
    @Test func repeatedRequestsCoalesceAndOpenOnlyOnce() {
        var handoff = CaffeineReviewShortcut()
        handoff.request(); handoff.request()
        let first = handoff.consume(ready: true, hasOpenReview: false)
        let repeated = handoff.consume(ready: true, hasOpenReview: false)
        #expect(first && !repeated && !handoff.requested)
    }
    @Test func existingWorkConsumesRequestWithoutOpeningOrDeferringAReplacement() {
        var handoff = CaffeineReviewShortcut()
        handoff.request()
        let blocked = handoff.consume(ready: true, hasOpenReview: true)
        let afterWorkFinishes = handoff.consume(ready: true, hasOpenReview: false)
        #expect(!blocked && !afterWorkFinishes && !handoff.requested)
    }
    @Test func cancelledRequestCannotReappear() {
        var handoff = CaffeineReviewShortcut()
        handoff.request(); handoff.cancel()
        let opened = handoff.consume(ready: true, hasOpenReview: false)
        #expect(!opened && !handoff.requested)
    }
    @Test func coveringWorkConsumesEvenBeforeForegroundStorageReadiness() {
        var handoff = CaffeineReviewShortcut()
        handoff.request()
        let covered = handoff.consume(ready: false, hasOpenReview: true)
        #expect(!covered && !handoff.requested)
        let afterDismissal = handoff.consume(ready: true, hasOpenReview: false)
        #expect(!afterDismissal && !handoff.requested)
    }
}
