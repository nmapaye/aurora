import Foundation
import Testing
@testable import AuroraCore

/// Owner report (Nov 19): "What's up?" answered with the full capability menu.
@Suite struct SmallTalkTests {
    @Test func greetingsAreSmallTalk() {
        for text in ["What’s up?", "whats up", "Hey", "hi aurora", "How's it going?", "good morning!", "sup"] {
            #expect(Welcome.isSmallTalk(text), "\(text)")
        }
    }

    @Test func requestsAreNotSmallTalk() {
        for text in ["what's up with my sleep", "hey log a coffee", "how am I doing on caffeine", "hi I had espresso now", "What can you do?"] {
            #expect(!Welcome.isSmallTalk(text), "\(text)")
        }
    }

    @Test func replyGreetsAndStatesOneRecordedFactOrTheNeutralLine() {
        let clock = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
        let now: Millis = 1_800_000_000_000
        let empty = Welcome.smallTalkReply(state: AppState(), now: now, clock: clock, text: fixtureText)
        #expect(empty.contains(Welcome.neutralLine) && empty.hasSuffix("snap a photo of your drink."))
        #expect(!empty.contains("0 mg"))
    }
}
