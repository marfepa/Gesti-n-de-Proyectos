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

    func testProjectPriorityTakesPrecedenceOverDeadline() {
        let service = WeeklySchedulerService()
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! // Lunes

        // Proyecto A: Deadline más cercano (3 días), pero prioridad Baja
        let lowPriorityProj = Project(name: "Low Priority Near Deadline", startDate: refDate, priority: .baja)
        let lowTask = ProjectTask(
            title: "Low Priority Task",
            startDate: refDate,
            endDate: calendar.date(byAdding: .day, value: 3, to: refDate)!,
            estimatedHours: 2.0,
            project: lowPriorityProj
        )
        lowPriorityProj.tasks = [lowTask]

        // Proyecto B: Deadline más lejano (10 días), pero prioridad Urgente
        let urgentProj = Project(name: "Urgent Priority Later Deadline", startDate: refDate, priority: .urgente)
        let urgentTask = ProjectTask(
            title: "Urgent Priority Task",
            startDate: refDate,
            endDate: calendar.date(byAdding: .day, value: 10, to: refDate)!,
            estimatedHours: 2.0,
            project: urgentProj
        )
        urgentProj.tasks = [urgentTask]

        // Solo 2 horas disponibles en total
        let slot = WorkSlot(weekday: 2, startMinute: 9 * 60, endMinute: 11 * 60)

        let result = service.schedule(
            projects: [lowPriorityProj, urgentProj],
            slots: [slot],
            startDate: refDate,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.0,
            calendar: calendar
        )

        // El proyecto Urgente debe ser asignado primero a pesar de que su deadline sea posterior
        XCTAssertEqual(result.scheduledItems.count, 1)
        XCTAssertEqual(result.scheduledItems.first?.taskTitle, "Urgent Priority Task")
        XCTAssertEqual(result.scheduledItems.first?.projectPriority, .urgente)
        XCTAssertEqual(result.unscheduledTasks.first?.taskTitle, "Low Priority Task")
    }

    func testProjectTargetEndDateTakesPrecedenceWhenEqualPriority() {
        let service = WeeklySchedulerService()
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! // Lunes

        // Proyecto A: Tiene targetEndDate explícito en 2 días
        let targetProj = Project(
            name: "Project Target 2 Days",
            startDate: refDate,
            targetEndDate: calendar.date(byAdding: .day, value: 2, to: refDate)!,
            priority: .media
        )
        let targetTask = ProjectTask(
            title: "Must Finish for Target",
            startDate: refDate,
            endDate: calendar.date(byAdding: .day, value: 10, to: refDate)!,
            estimatedHours: 2.0,
            project: targetProj
        )
        targetProj.tasks = [targetTask]

        // Proyecto B: Sin targetEndDate, termina en 6 días
        let regularProj = Project(
            name: "Project Regular 6 Days",
            startDate: refDate,
            priority: .media
        )
        let regularTask = ProjectTask(
            title: "Regular Task",
            startDate: refDate,
            endDate: calendar.date(byAdding: .day, value: 6, to: refDate)!,
            estimatedHours: 2.0,
            project: regularProj
        )
        regularProj.tasks = [regularTask]

        // Slot de 2 horas
        let slot = WorkSlot(weekday: 2, startMinute: 9 * 60, endMinute: 11 * 60)

        let result = service.schedule(
            projects: [regularProj, targetProj],
            slots: [slot],
            startDate: refDate,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.0,
            calendar: calendar
        )

        // El proyecto con targetEndDate más temprano (2 días) debe asignarse antes que el de 6 días
        XCTAssertEqual(result.scheduledItems.first?.taskTitle, "Must Finish for Target")
    }

    func testSubtaskHoursTakeEffectInProjectDemand() {
        let service = WeeklySchedulerService()
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!

        let project = Project(name: "Subtask Project", startDate: refDate)
        let parentTask = ProjectTask(
            title: "Parent Task",
            startDate: refDate,
            endDate: refDate,
            estimatedHours: 10.0, // Horas declaradas
            project: project
        )
        // Pero tiene 2 subtareas concretas de 1.5h cada una = 3.0h reales
        let sub1 = ProjectSubtask(title: "Sub 1", estimatedHours: 1.5, task: parentTask)
        let sub2 = ProjectSubtask(title: "Sub 2", estimatedHours: 1.5, task: parentTask)
        parentTask.subtasks = [sub1, sub2]
        project.tasks = [parentTask]

        let slot = WorkSlot(weekday: 2, startMinute: 9 * 60, endMinute: 15 * 60)

        let result = service.schedule(
            projects: [project],
            slots: [slot],
            startDate: refDate,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.0,
            calendar: calendar
        )

        // La demanda efectiva debe ser 3.0h (la suma de subtareas: 1.5 + 1.5), no 10.0h
        XCTAssertEqual(result.totalDemandHours, 3.0)
        XCTAssertEqual(result.scheduledItems.count, 2)
        XCTAssertEqual(result.scheduledItems[0].subtaskTitle, "Sub 1")
        XCTAssertEqual(result.scheduledItems[0].allocatedHours, 1.5)
        XCTAssertEqual(result.scheduledItems[1].subtaskTitle, "Sub 2")
        XCTAssertEqual(result.scheduledItems[1].allocatedHours, 1.5)
    }

    func testDynamicSlotReallocationWhenTaskCompletedEarly() {
        let service = WeeklySchedulerService()
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! // Lunes

        let projA = Project(name: "Proyecto A", startDate: refDate, priority: .alta)
        let taskA = ProjectTask(title: "Tarea Urgente A", startDate: refDate, endDate: refDate, estimatedHours: 2.0, project: projA)
        projA.tasks = [taskA]

        let projB = Project(name: "Proyecto B", startDate: refDate, priority: .media)
        let taskB = ProjectTask(title: "Tarea Pendiente B", startDate: refDate, endDate: refDate, estimatedHours: 2.0, project: projB)
        projB.tasks = [taskB]

        // Solo 2 horas disponibles en total: Lunes 9:00 - 11:00
        let slot = WorkSlot(weekday: 2, startMinute: 9 * 60, endMinute: 11 * 60)

        // Estado inicial: Tarea A ocupa todo el hueco de 9:00 a 11:00, Tarea B queda unscheduled
        let initialResult = service.schedule(
            projects: [projA, projB],
            slots: [slot],
            startDate: refDate,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.0,
            calendar: calendar
        )

        XCTAssertEqual(initialResult.scheduledItems.count, 1)
        XCTAssertEqual(initialResult.scheduledItems.first?.taskTitle, "Tarea Urgente A")
        XCTAssertEqual(initialResult.scheduledItems.first?.startMinute, 9 * 60)
        XCTAssertEqual(initialResult.scheduledItems.first?.endMinute, 11 * 60)
        XCTAssertEqual(initialResult.unscheduledTasks.count, 1)
        XCTAssertEqual(initialResult.unscheduledTasks.first?.taskTitle, "Tarea Pendiente B")

        // Simulamos que Tarea A se completa antes de tiempo
        taskA.isCompleted = true

        // Al recalcular, Tarea B debe ocupar inmediatamente el hueco liberado de 9:00 a 11:00
        let reallocatedResult = service.schedule(
            projects: [projA, projB],
            slots: [slot],
            startDate: refDate,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.0,
            calendar: calendar
        )

        XCTAssertEqual(reallocatedResult.scheduledItems.count, 1)
        XCTAssertEqual(reallocatedResult.scheduledItems.first?.taskTitle, "Tarea Pendiente B")
        XCTAssertEqual(reallocatedResult.scheduledItems.first?.projectName, "Proyecto B")
        XCTAssertEqual(reallocatedResult.scheduledItems.first?.startMinute, 9 * 60)
        XCTAssertEqual(reallocatedResult.scheduledItems.first?.endMinute, 11 * 60)
        XCTAssertTrue(reallocatedResult.unscheduledTasks.isEmpty)
    }

    func testMultiProjectContinuousPackingOptimizesAvailableSlots() {
        let service = WeeklySchedulerService()
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! // Lunes

        // Proyecto 1: 1.5 horas
        let p1 = Project(name: "P1", startDate: refDate, priority: .alta)
        let t1 = ProjectTask(title: "Task 1", startDate: refDate, endDate: refDate, estimatedHours: 1.5, project: p1)
        p1.tasks = [t1]

        // Proyecto 2: 2.0 horas
        let p2 = Project(name: "P2", startDate: refDate, priority: .media)
        let t2 = ProjectTask(title: "Task 2", startDate: refDate, endDate: refDate, estimatedHours: 2.0, project: p2)
        p2.tasks = [t2]

        // Proyecto 3: 0.5 horas
        let p3 = Project(name: "P3", startDate: refDate, priority: .baja)
        let t3 = ProjectTask(title: "Task 3", startDate: refDate, endDate: refDate, estimatedHours: 0.5, project: p3)
        p3.tasks = [t3]

        // Bloque de 4 horas exactas (9:00 - 13:00)
        let slot = WorkSlot(weekday: 2, startMinute: 9 * 60, endMinute: 13 * 60)

        let result = service.schedule(
            projects: [p3, p1, p2], // Desordenados
            slots: [slot],
            startDate: refDate,
            weeksToSchedule: 1,
            safetyBufferPercent: 0.0,
            calendar: calendar
        )

        // Comprobación de empaquetado continuo óptimo
        XCTAssertEqual(result.totalAllocatedHours, 4.0)
        XCTAssertEqual(result.slotUtilization, 1.0)
        XCTAssertTrue(result.unscheduledTasks.isEmpty)

        // Las tareas deben ordenarse por prioridad: P1 (alta), luego P2 (media), luego P3 (baja)
        XCTAssertEqual(result.scheduledItems.count, 3)
        XCTAssertEqual(result.scheduledItems[0].projectName, "P1")
        XCTAssertEqual(result.scheduledItems[0].startMinute, 9 * 60)
        XCTAssertEqual(result.scheduledItems[0].endMinute, 9 * 60 + 90) // 9:00 - 10:30

        XCTAssertEqual(result.scheduledItems[1].projectName, "P2")
        XCTAssertEqual(result.scheduledItems[1].startMinute, 9 * 60 + 90) // 10:30
        XCTAssertEqual(result.scheduledItems[1].endMinute, 9 * 60 + 210) // 10:30 - 12:30

        XCTAssertEqual(result.scheduledItems[2].projectName, "P3")
        XCTAssertEqual(result.scheduledItems[2].startMinute, 9 * 60 + 210) // 12:30
        XCTAssertEqual(result.scheduledItems[2].endMinute, 13 * 60) // 12:30 - 13:00
    }

    func testParallelColumnsLayoutAvoidsOverlaps() {
        let date = Date()
        let item1 = ScheduledItem(
            taskId: UUID(),
            taskTitle: "Tarea A",
            projectName: "Prj 1",
            date: date,
            startMinute: 9 * 60, // 09:00 - 11:00
            endMinute: 11 * 60,
            allocatedHours: 2.0,
            isCompleted: false
        )
        let item2 = ScheduledItem(
            taskId: UUID(),
            taskTitle: "Tarea B",
            projectName: "Prj 2",
            date: date,
            startMinute: 10 * 60, // 10:00 - 12:00 (solapa con A)
            endMinute: 12 * 60,
            allocatedHours: 2.0,
            isCompleted: false
        )
        let item3 = ScheduledItem(
            taskId: UUID(),
            taskTitle: "Tarea C",
            projectName: "Prj 3",
            date: date,
            startMinute: 13 * 60, // 13:00 - 14:00 (no solapa)
            endMinute: 14 * 60,
            allocatedHours: 1.0,
            isCompleted: false
        )

        let positioned = WeeklyScheduleGridView.computeParallelColumns(items: [item1, item2, item3])
        XCTAssertEqual(positioned.count, 3)

        // item1 e item2 deben estar en el mismo cluster de 2 columnas con índices distintos
        let pos1 = positioned.first { $0.item.taskTitle == "Tarea A" }!
        let pos2 = positioned.first { $0.item.taskTitle == "Tarea B" }!
        let pos3 = positioned.first { $0.item.taskTitle == "Tarea C" }!

        XCTAssertEqual(pos1.totalColumns, 2)
        XCTAssertEqual(pos2.totalColumns, 2)
        XCTAssertNotEqual(pos1.columnIndex, pos2.columnIndex)

        // item3 está solo en su cluster de 1 columna
        XCTAssertEqual(pos3.totalColumns, 1)
        XCTAssertEqual(pos3.columnIndex, 0)
    }
}
