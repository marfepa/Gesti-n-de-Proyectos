import XCTest
@testable import PlanAICore

final class GanttTimeScaleTests: XCTestCase {

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "es_ES")
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return fixedCalendar.date(from: components)!
    }

    func testProjectStarting31Oct2026DomainAndTicks() {
        let calendar = fixedCalendar

        // Fechas con hora para verificar normalización
        let start = makeDate(year: 2026, month: 10, day: 31, hour: 14, minute: 30)
        let mid1 = makeDate(year: 2026, month: 11, day: 15, hour: 9, minute: 0)
        let mid2 = makeDate(year: 2026, month: 11, day: 25, hour: 18, minute: 0)
        let end = makeDate(year: 2026, month: 12, day: 5, hour: 20, minute: 0)

        let tasks = [
            ProjectTask(title: "Fase 1", startDate: start, endDate: mid1, estimatedDays: 15),
            ProjectTask(title: "Fase 2", startDate: mid1, endDate: mid2, estimatedDays: 10),
            ProjectTask(title: "Fase 3", startDate: mid2, endDate: end, estimatedDays: 10)
        ]

        let referenceToday = makeDate(year: 2026, month: 9, day: 17) // Fuera del proyecto
        let scale = GanttTimeScale(tasks: tasks, today: referenceToday, calendar: calendar)

        let expectedStart = makeDate(year: 2026, month: 10, day: 31)
        let expectedEnd = makeDate(year: 2026, month: 12, day: 5)

        // Verificación de dominio
        XCTAssertEqual(scale.startDate, expectedStart, "El inicio del dominio debe ser exactamente 31 oct 2026 00:00:00")
        XCTAssertEqual(scale.endDate, expectedEnd, "El fin del dominio debe ser 5 dic 2026 00:00:00")
        XCTAssertEqual(scale.domain.lowerBound, expectedStart)
        XCTAssertEqual(scale.domain.upperBound, expectedEnd)

        // Verificación de ticks semanales anclados al inicio
        let expectedTicks = [
            makeDate(year: 2026, month: 10, day: 31), // Día 0
            makeDate(year: 2026, month: 11, day: 7),  // Día 7
            makeDate(year: 2026, month: 11, day: 14), // Día 14
            makeDate(year: 2026, month: 11, day: 21), // Día 21
            makeDate(year: 2026, month: 11, day: 28), // Día 28
            makeDate(year: 2026, month: 12, day: 5)   // Día 35 (coincide con fin)
        ]

        XCTAssertEqual(scale.ticks, expectedTicks, "Los ticks deben nacer en 31 oct y progresar semanalmente (+7d)")

        // Hoy fuera de rango no debe ser visible
        XCTAssertFalse(scale.isTodayVisible, "Hoy (17 sep 2026) no debe ser visible en un proyecto que inicia el 31 oct 2026")
    }

    func testTodayVisibilityWithinAndOutsideRange() {
        let calendar = fixedCalendar
        let start = makeDate(year: 2026, month: 10, day: 31)
        let end = makeDate(year: 2026, month: 11, day: 20)

        let tasks = [
            ProjectTask(title: "Fase Única", startDate: start, endDate: end, estimatedDays: 20)
        ]

        // Antes del proyecto (p. ej. 8 oct 2026 mencionado en la incidencia)
        let todayOct8 = makeDate(year: 2026, month: 10, day: 8)
        let scaleOct8 = GanttTimeScale(tasks: tasks, today: todayOct8, calendar: calendar)
        XCTAssertFalse(scaleOct8.isTodayVisible)

        // Justo el primer día
        let todayOct31 = makeDate(year: 2026, month: 10, day: 31, hour: 11, minute: 0)
        let scaleOct31 = GanttTimeScale(tasks: tasks, today: todayOct31, calendar: calendar)
        XCTAssertTrue(scaleOct31.isTodayVisible)

        // En medio del proyecto
        let todayNov10 = makeDate(year: 2026, month: 11, day: 10)
        let scaleNov10 = GanttTimeScale(tasks: tasks, today: todayNov10, calendar: calendar)
        XCTAssertTrue(scaleNov10.isTodayVisible)

        // Justo el último día
        let todayNov20 = makeDate(year: 2026, month: 11, day: 20, hour: 23, minute: 59)
        let scaleNov20 = GanttTimeScale(tasks: tasks, today: todayNov20, calendar: calendar)
        XCTAssertTrue(scaleNov20.isTodayVisible)

        // Después del proyecto
        let todayNov21 = makeDate(year: 2026, month: 11, day: 21)
        let scaleNov21 = GanttTimeScale(tasks: tasks, today: todayNov21, calendar: calendar)
        XCTAssertFalse(scaleNov21.isTodayVisible)
    }

    func testEmptyTasksProvidesSafeFallbackDomain() {
        let calendar = fixedCalendar
        let today = makeDate(year: 2026, month: 9, day: 17)

        let scale = GanttTimeScale(tasks: [], today: today, calendar: calendar)

        XCTAssertEqual(scale.startDate, today)
        XCTAssertGreaterThan(scale.endDate, scale.startDate)
        XCTAssertFalse(scale.ticks.isEmpty)
        XCTAssertEqual(scale.ticks.first, today)
        XCTAssertTrue(scale.isTodayVisible)
    }

    func testSingleDayTaskProducesValidNonEmptyRange() {
        let calendar = fixedCalendar
        let date = makeDate(year: 2026, month: 10, day: 31)

        let task = ProjectTask(title: "Tarea 1 día", startDate: date, endDate: date, estimatedDays: 1)
        let scale = GanttTimeScale(tasks: [task], today: date, calendar: calendar)

        XCTAssertEqual(scale.startDate, date)
        XCTAssertGreaterThan(scale.endDate, scale.startDate)
        XCTAssertEqual(scale.totalDays, 1)
        XCTAssertTrue(scale.ticks.contains(date))
    }

    func testUnorderedTasksCalculatesCorrectDomain() {
        let calendar = fixedCalendar
        let d1 = makeDate(year: 2026, month: 11, day: 10)
        let d2 = makeDate(year: 2026, month: 11, day: 25)
        let dStart = makeDate(year: 2026, month: 10, day: 31)
        let dEnd = makeDate(year: 2026, month: 12, day: 1)

        let tasks = [
            ProjectTask(title: "Tarea intermedia", startDate: d1, endDate: d2, estimatedDays: 15),
            ProjectTask(title: "Tarea final", startDate: d2, endDate: dEnd, estimatedDays: 6),
            ProjectTask(title: "Tarea inicial", startDate: dStart, endDate: d1, estimatedDays: 10)
        ]

        let scale = GanttTimeScale(tasks: tasks, calendar: calendar)

        XCTAssertEqual(scale.startDate, dStart)
        XCTAssertEqual(scale.endDate, dEnd)
        XCTAssertEqual(scale.ticks.first, dStart)
    }

    func testWeeklyTickIntervalsAreExactly7DaysApart() {
        let calendar = fixedCalendar
        let start = makeDate(year: 2026, month: 10, day: 31)
        let end = makeDate(year: 2026, month: 12, day: 31)

        let ticks = GanttTimeScale.calculateTicks(from: start, to: end, calendar: calendar)

        XCTAssertGreaterThanOrEqual(ticks.count, 2)
        for i in 1..<ticks.count {
            let diff = calendar.dateComponents([.day], from: ticks[i - 1], to: ticks[i]).day
            XCTAssertEqual(diff, 7, "Cada tick consecutivo debe estar separado por exactamente 7 días")
        }
    }
}
