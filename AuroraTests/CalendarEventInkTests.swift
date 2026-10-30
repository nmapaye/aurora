import Testing
@testable import Aurora

/// Text on a Google event's own color picks the higher-contrast ink.
@Suite struct CalendarEventInkTests {
    private func best(_ hex: String) -> Double {
        let background = EventInk.luminance(hex: hex)!
        let dark = EventInk.luminance(hex: "#1F1F1F")!
        return EventInk.darkReadsBetter(onHex: hex) ? EventInk.contrast(background, dark) : EventInk.contrast(background, 1)
    }

    @Test(arguments: ["#039BE5", "#E67C73", "#33B679"])
    func midToneGoogleColorsGetDarkText(hex: String) {
        #expect(EventInk.darkReadsBetter(onHex: hex))
        #expect(best(hex) >= 4.5)
    }

    @Test(arguments: ["#3F51B5", "#8E24AA", "#D50000", "#616161", "#0B8043"])
    func deepColorsKeepWhiteText(hex: String) {
        #expect(!EventInk.darkReadsBetter(onHex: hex))
    }

    @Test func notAColorFallsBackToWhite() {
        #expect(!EventInk.darkReadsBetter(onHex: nil))
        #expect(!EventInk.darkReadsBetter(onHex: "blue"))
    }
}
