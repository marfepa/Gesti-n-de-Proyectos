import XCTest
import SwiftData
@testable import PlanAICore

final class WeeklySchedulerTests: XCTestCase {

    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "es_ES")
        cal.timeZone = TimeZone(identifier: "UTC")!
        calendar = cal
    }

    func testEmptySlotsReturnsUnscheduledWithNoCrash() {
        let service = WeeklySchedulerService()
        let project = Project(name: "Test Project")
        let task = ProjectTask(
            title: "Task 1",
            startDate: Date(),
            endDate: Date(),
            estimatedHours: 4.0,
            project: project
        )
        project.tasks = [task]

        let result = service.schedule(
            projects: [project],
            slots: [],
            startDate: Date(),
            calendar: calendar
        )

        XCTAssertTrue(result.scheduledItems.isEmpty)
        XCTAssertEqual(result.unscheduledTasks.count, 1)
        XCTAssertEqual(result.totalDemandHours, 4.0)
        XCTAssertEqual(result.totalAvailableHours, 0.0)
        XCTAssertTrue(result.hasOverload)
    }

    func testAssignTasksWithinCapacityAndSafetyBuffer() {
        let service = WeeklySchedulerService()
        let startMonday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! // Lunes

        // Slot de 2 horas (120 min) el Lunes. Con 15% buffer = 102 min utilizables (1.7 horas)
        let slot = WorkSlot(weekday: 2, startMinute: 10 * 60, endMinute: 12 * 60, label: "Foco")
        
        let project = Project(name: "Proyecto Alpha", startDate: startMonday)
        let task1 = ProjectTask(
            title: "Tarea Corta",
            startDate: startMonday,
            endDate: startMonday,
            estimatedHours: 1.0,
            sortOrder: 0,
            project: project
        )
        project.tasks = [task1]

        let result = service.schedule(
            projects: [project],
            slots: [slot],
            startDate: startMonday,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.15,
            calendar: calendar
        )

        XCTAssertFalse(result.hasOverload)
        XCTAssertEqual(result.scheduledItems.count, 1)
        XCTAssertEqual(result.scheduledItems.first?.taskTitle, "Tarea Corta")
        XCTAssertEqual(result.scheduledItems.first?.allocatedHours, 1.0)
        XCTAssertEqual(result.scheduledItems.first?.startMinute, 600) // 10:00
        XCTAssertEqual(result.scheduledItems.first?.endMinute, 660)   // 11:00
    }

    func testEarliestDeadlineFirstPriorityOrdering() {
        let service = WeeklySchedulerService()
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! // Lunes

        // Proyecto Urgente: termina en 2 días
        let urgentProj = Project(name: "Urgente", startDate: refDate)
        let urgentTask = ProjectTask(
            title: "Crítica",
            startDate: refDate,
            endDate: calendar.date(byAdding: .day, value: 2, to: refDate)!,
            estimatedHours: 2.0,
            project: urgentProj
        )
        urgentProj.tasks = [urgentTask]

        // Proyecto Relajado: termina en 20 días
        let relaxedProj = Project(name: "Relajado", startDate: refDate)
        let relaxedTask = ProjectTask(
            title: "Postergable",
            startDate: refDate,
            endDate: calendar.date(byAdding: .day, value: 20, to: refDate)!,
            estimatedHours: 2.0,
            project: relaxedProj
        )
        relaxedProj.tasks = [relaxedTask]

        // Slot disponible el Lunes de 2 horas
        let slot = WorkSlot(weekday: 2, startMinute: 9 * 60, endMinute: 11 * 60)

        let result = service.schedule(
            projects: [relaxedProj, urgentProj], // Entran desordenados intencionalmente
            slots: [slot],
            startDate: refDate,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.0,
            calendar: calendar
        )

        // La primera tarea asignada debe ser la del proyecto urgente
        XCTAssertEqual(result.scheduledItems.first?.taskTitle, "Crítica")
    }

    func testOverloadDetectionWhenDemandExceedsAvailability() {
        let service = WeeklySchedulerService()
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! // Lunes

        let project = Project(name: "Gran Proyecto", startDate: refDate)
        let bigTask = ProjectTask(
            title: "Desarrollo Completo",
            startDate: refDate,
            endDate: refDate,
            estimatedHours: 10.0,
            project: project
        )
        project.tasks = [bigTask]

        // Solo 1 hora disponible en toda la semana
        let slot = WorkSlot(weekday: 2, startMinute: 9 * 60, endMinute: 10 * 60)

        let result = service.schedule(
            projects: [project],
            slots: [slot],
            startDate: refDate,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.0,
            calendar: calendar
        )

        XCTAssertTrue(result.hasOverload)
        XCTAssertEqual(result.unscheduledTasks.count, 1)
        XCTAssertEqual(result.unscheduledTasks.first?.taskTitle, "Desarrollo Completo")
        XCTAssertGreaterThan(result.deficitHours, 8.0)
    }
}
