import Foundation
import Testing
@testable import AuroraCore

struct CalendarMergeTests {
    let start = Date(timeIntervalSince1970: 1_791_475_200)
    func event(_ provider: CalendarProviderID, _ title: String = "Team sync", id: String = UUID().uuidString, modified: Date? = nil, offset: TimeInterval = 0) -> Commitment {
        Commitment(id: id, calendarID: "c", provider: provider, title: title, start: start.addingTimeInterval(offset), end: start.addingTimeInterval(offset + 1800),
                   timeZone: "UTC", revision: "r", canMove: false, recurring: false, lastModified: modified)
    }

    @Test func keepsTheMostRecentlyUpdatedCopyAcrossProviders() {
        let apple = event(.apple, "Team  Sync", modified: start.addingTimeInterval(-100))
        let google = event(.google, "team sync", modified: start.addingTimeInterval(-10))
        #expect(CalendarMerge.newestCopies([apple, google]).map(\.provider) == [.google])
        let newerApple = event(.apple, modified: start)
        #expect(CalendarMerge.newestCopies([google, newerApple]).map(\.provider) == [.apple])
    }

    @Test func unknownChangeTimeLosesAndFirstWinsATie() {
        let google = event(.google, modified: nil)
        let apple = event(.apple, modified: start)
        #expect(CalendarMerge.newestCopies([google, apple]).map(\.provider) == [.apple])
        #expect(CalendarMerge.newestCopies([event(.google), event(.apple)]).map(\.provider) == [.google])
    }

    @Test func sameProviderLookalikesAndDifferentTimesStaySeparate() {
        #expect(CalendarMerge.newestCopies([event(.google, id: "1"), event(.google, id: "2")]).count == 2)
        #expect(CalendarMerge.newestCopies([event(.google), event(.apple, offset: 600)]).count == 2)
        #expect(CalendarMerge.newestCopies([event(.google, "Lunch"), event(.apple, "Gym")]).count == 2)
    }

    @Test func olderSnapshotsDecodeWithoutDisplayFields() throws {
        let json = #"{"id":"e","calendarID":"c","provider":"google","title":"T","start":0,"end":60,"timeZone":"UTC","revision":"r","canMove":false,"recurring":false}"#
        let decoded = try JSONDecoder().decode(Commitment.self, from: Data(json.utf8))
        #expect(decoded.location == nil && decoded.colorHex == nil && decoded.lastModified == nil && decoded.allDay == nil)
    }
}
