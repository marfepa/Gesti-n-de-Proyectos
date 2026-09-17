import XCTest
@testable import PlanAICore

final class TaskDecompositionTests: XCTestCase {

    func testSequentialDateCalculation() {
        let service = TaskDecompositionService()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())

        let subtasks = [
            SubtaskPlan(title: "Fase 1: Especificación", estimatedDays: 3, notes: "Notas 1"),
            SubtaskPlan(title: "Fase 2: Arquitectura", estimatedDays: 5, notes: "Notas 2"),
            SubtaskPlan(title: "Fase 3: Desarrollo", estimatedDays: 10, notes: "Notas 3")
        ]

        let payloads = service.buildTaskPayloads(from: subtasks, startingAt: start, calendar: calendar)

        XCTAssertEqual(payloads.count, 3)

        // Verificación de la primera tarea
        XCTAssertEqual(payloads[0].title, "Fase 1: Especificación")
        XCTAssertEqual(payloads[0].estimatedDays, 3)
        XCTAssertEqual(payloads[0].startDate, start)
        let expectedEnd1 = calendar.date(byAdding: .day, value: 3, to: start)!
        XCTAssertEqual(payloads[0].endDate, expectedEnd1)

        // Verificación de la segunda tarea (inicia donde termina la primera)
        XCTAssertEqual(payloads[1].startDate, expectedEnd1)
        let expectedEnd2 = calendar.date(byAdding: .day, value: 5, to: expectedEnd1)!
        XCTAssertEqual(payloads[1].endDate, expectedEnd2)

        // Verificación de la tercera tarea
        XCTAssertEqual(payloads[2].startDate, expectedEnd2)
        let expectedEnd3 = calendar.date(byAdding: .day, value: 10, to: expectedEnd2)!
        XCTAssertEqual(payloads[2].endDate, expectedEnd3)
    }

    func testHeuristicPlanFallback() {
        let service = TaskDecompositionService()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())

        let payloads = service.generateHeuristicPlan(from: "Proyecto de prueba simple", startDate: start, calendar: calendar)

        XCTAssertFalse(payloads.isEmpty)
        XCTAssertGreaterThanOrEqual(payloads.count, 3)
        XCTAssertEqual(payloads.first?.startDate, start)
    }

    func testProjectProgressCalculation() {
        let project = Project(name: "Test Project")
        let task1 = ProjectTask(title: "T1", startDate: Date(), endDate: Date(), isCompleted: true)
        let task2 = ProjectTask(title: "T2", startDate: Date(), endDate: Date(), isCompleted: false)

        project.tasks = [task1, task2]

        XCTAssertEqual(project.progress, 0.5)
    }

    func testTargetEndDateWindowCompression() {
        let service = TaskDecompositionService()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        // Ventana deseada de 10 días
        let targetEnd = calendar.date(byAdding: .day, value: 10, to: start)!

        // Las subtasks suman 20 días (3 + 7 + 10)
        let subtasks = [
            SubtaskPlan(title: "Fase 1", estimatedDays: 3, notes: ""),
            SubtaskPlan(title: "Fase 2", estimatedDays: 7, notes: ""),
            SubtaskPlan(title: "Fase 3", estimatedDays: 10, notes: "")
        ]

        let payloads = service.buildTaskPayloads(
            from: subtasks,
            startingAt: start,
            targetEndDate: targetEnd,
            calendar: calendar
        )

        let totalCompressedDays = payloads.reduce(0) { $0 + $1.estimatedDays }
        // La suma de días comprimidos debe ajustarse aproximadamente a la ventana de 10 días
        XCTAssertLessThanOrEqual(totalCompressedDays, 12)
        XCTAssertGreaterThanOrEqual(totalCompressedDays, 8)
    }

    func testLargeTaskSubtaskDecomposition() {
        let service = TaskDecompositionService()
        let subtasks = service.decomposeTaskIntoSubtasks(taskTitle: "Refactorización Arquitectura", estimatedHours: 8.0)

        XCTAssertEqual(subtasks.count, 3)
        let sumHours = subtasks.reduce(0.0) { $0 + $1.hours }
        XCTAssertEqual(sumHours, 8.0)
    }
}
