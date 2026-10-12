import Foundation
import Testing
@testable import AuroraCore

/// The calendar card's list, from events like a real day's.
struct CalendarAgendaTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Mon, Oct 12, 2026 at `hour:minute` in Los Angeles.
    func at(_ hour: Int, _ minute: Int = 0, day: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func event(_ title: String, _ start: Date, _ end: Date, provider: CalendarProviderID = .apple, allDay: Bool? = nil) -> Commitment {
        Commitment(id: title, calendarID: "home", provider: provider, title: title, start: start, end: end,
                   timeZone: "America/Los_Angeles", revision: "1", canMove: true, recurring: false, allDay: allDay)
    }

    @Test func showsWhatIsLeftOfTodayWithoutRoutines() {
        let now = at(14, 30)
        let events = [
            event("TIM 172A HW1 planning window", at(0, day: 8), at(0, day: 9), allDay: true),
            event("Joan's return flight", at(22, 45, day: 11), at(6, 23)),
            event("In Bed and Asleep", at(2), at(9, 30)),
            event("Morning Pills", at(9, 30), at(9, 40)),
            event("Lunch", at(13, 30), at(14, 15)),
            event("Zone 2 Cardio", at(14, 15), at(15)),
            event("Stop Caffeine", at(15), at(15, 15)),
            event("Stop Naps", at(15, 30), at(15, 45)),
            event("Dinner", at(18), at(19)),
            event("ECON 136: confirm meeting", at(18), at(18, 15)),
            event("Evening Routine", at(21, 45), at(22, 15)),
            event("In Bed and Asleep", at(22, 15), at(6, day: 13)),
            event("Tomorrow's lecture", at(10, day: 13), at(11, day: 13)),
        ]
        let shown = CalendarAgenda.restOfToday(events, now: now, calendar: calendar).map(\.title)
        // Ongoing cardio stays; earlier days, finished events, routines and tomorrow go.
        #expect(shown == ["Zone 2 Cardio", "Stop Caffeine", "ECON 136: confirm meeting", "Dinner"])
    }

    @Test func routineWordsMatchWordStartsOnly() {
        for title in ["In Bed and Asleep", "Stop Naps", "Morning Pills", "Morning Routine v5", "Bedtime", "Meds", "sleep window"] {
            #expect(CalendarAgenda.isRoutine(title), "\(title)")
        }
        for title in ["Snapshot review", "Stop Caffeine", "ECON 136 study", "Embedded systems lab"] {
            #expect(!CalendarAgenda.isRoutine(title), "\(title)")
        }
    }

    @Test func onlyOverlappingTimedEventsClash() {
        let dinner = event("Dinner", at(18), at(19))
        let meeting = event("ECON 136: confirm meeting", at(18), at(18, 15))
        let reading = event("ECON 136 reading", at(16, 35), at(16, 50))
        let adjacent = event("Call", at(19), at(19, 30))
        let allDay = event("Holiday", at(0), at(0, day: 13), allDay: true)
        let clashes = CalendarAgenda.clashing([reading, dinner, meeting, adjacent, allDay])
        #expect(clashes == [dinner.identity, meeting.identity])
    }

    @Test func sourceShowsOnlyWhenProvidersMix() {
        let apple = event("Dinner", at(18), at(19))
        let google = event("Standup", at(9), at(9, 15), provider: .google)
        #expect(!CalendarAgenda.showsSource([apple, apple]))
        #expect(CalendarAgenda.showsSource([apple, google]))
        #expect(!CalendarAgenda.showsSource([]))
    }

    @Test func overnightEventsEndTheNextDay() {
        #expect(CalendarAgenda.endsNextDay(event("Flight", at(22, 45), at(6, 23, day: 13)), calendar: calendar))
        #expect(!CalendarAgenda.endsNextDay(event("Dinner", at(18), at(19)), calendar: calendar))
        // Ending exactly at midnight is still the same evening.
        #expect(!CalendarAgenda.endsNextDay(event("Late", at(23), at(0, day: 13)), calendar: calendar))
        #expect(!CalendarAgenda.endsNextDay(event("Holiday", at(0), at(0, day: 13), allDay: true), calendar: calendar))
    }
}
