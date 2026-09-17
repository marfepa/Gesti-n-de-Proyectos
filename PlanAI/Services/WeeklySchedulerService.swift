import Foundation

/// Representa una asignación concreta de una tarea a un día y bloque horario.
public struct ScheduledItem: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var taskId: UUID
    public var taskTitle: String
    public var projectName: String
    public var projectPriority: ProjectPriority
    public var date: Date
    public var startMinute: Int
    public var endMinute: Int
    public var allocatedHours: Double
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        taskId: UUID,
        taskTitle: String,
        projectName: String,
        projectPriority: ProjectPriority = .media,
        date: Date,
        startMinute: Int,
        endMinute: Int,
        allocatedHours: Double,
        isCompleted: Bool
    ) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.projectName = projectName
        self.projectPriority = projectPriority
        self.date = date
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.allocatedHours = allocatedHours
        self.isCompleted = isCompleted
    }

    public var timeRangeFormatted: String {
        let start = WorkSlot.formatTime(minute: startMinute)
        let end = WorkSlot.formatTime(minute: endMinute)
        return "\(start) - \(end)"
    }
}

/// Tarea que no ha podido ser asignada en la ventana de planificación por falta de huecos.
public struct UnscheduledTaskInfo: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var taskTitle: String
    public var projectName: String
    public var projectPriority: ProjectPriority
    public var remainingHours: Double
    public var reason: String

    public init(
        id: UUID,
        taskTitle: String,
        projectName: String,
        projectPriority: ProjectPriority = .media,
        remainingHours: Double,
        reason: String
    ) {
        self.id = id
        self.taskTitle = taskTitle
        self.projectName = projectName
        self.projectPriority = projectPriority
        self.remainingHours = remainingHours
        self.reason = reason
    }
}

/// Diagnóstico y resultado global del cálculo de despacho semanal.
public struct ScheduleResult: Sendable, Equatable {
    public var scheduledItems: [ScheduledItem]
    public var unscheduledTasks: [UnscheduledTaskInfo]
    public var totalAvailableHours: Double
    public var totalDemandHours: Double
    public var totalAllocatedHours: Double
    public var bufferPercentApplied: Double

    public var hasOverload: Bool {
        !unscheduledTasks.isEmpty
    }

    public var deficitHours: Double {
        max(0, totalDemandHours - totalAllocatedHours)
    }
}

/// Motor determinista de asignación de tareas a bloques semanales.
public final class WeeklySchedulerService: Sendable {
    public init() {}

    /// Calcula la planificación segura para una ventana de semanas dada (por defecto 2 semanas a partir de startDate).
    /// - Parameters:
    ///   - projects: Proyectos activos con sus tareas.
    ///   - slots: Franjas semanales configuradas por el usuario.
    ///   - startDate: Fecha inicial (por defecto hoy a las 00:00).
    ///   - weeksToSchedule: Número de semanas hacia adelante a considerar (por defecto 2).
    ///   - safetyBufferPercent: Colchón de seguridad temporal reservado en cada hueco (ej. 0.15 = 15%).
    ///   - calendar: Calendario a utilizar.
    public func schedule(
        projects: [Project],
        slots: [WorkSlot],
        startDate: Date = Date(),
        weeksToSchedule: Int = 2,
        safetyBufferPercent: Double = 0.15,
        calendar: Calendar = .current
    ) -> ScheduleResult {
        let enabledSlots = slots.filter { $0.isEnabled && $0.durationMinutes > 0 }
        
        // 1. Recopilar tareas pendientes de proyectos activos ordenadas según criterio seguro (Prioridad + EDF + Fase)
        struct TaskCandidate {
            let task: ProjectTask
            let projectName: String
            let projectPriority: ProjectPriority
            let projectDeadline: Date
            let sortOrder: Int
            var remainingHours: Double
        }

        var candidates: [TaskCandidate] = []
        var totalDemand: Double = 0.0

        for project in projects {
            let pendingTasks = project.sortedTasks.filter { !$0.isCompleted }
            let deadline = project.effectiveDeadline
            let priority = project.priority
            for task in pendingTasks {
                let hours = max(0.5, task.effectiveEstimatedHours)
                totalDemand += hours
                candidates.append(
                    TaskCandidate(
                        task: task,
                        projectName: project.name,
                        projectPriority: priority,
                        projectDeadline: deadline,
                        sortOrder: task.sortOrder,
                        remainingHours: hours
                    )
                )
            }
        }

        // Orden de prioridad:
        // 1. Prioridad del proyecto (urgente > alta > media > baja)
        // 2. Earliest Deadline First (EDF) del proyecto
        // 3. Nombre del proyecto (determinismo)
        // 4. Orden secuencial de la tarea dentro del proyecto
        candidates.sort { a, b in
            if a.projectPriority != b.projectPriority {
                return a.projectPriority.rawValue > b.projectPriority.rawValue
            }
            if a.projectDeadline != b.projectDeadline {
                return a.projectDeadline < b.projectDeadline
            }
            if a.projectName != b.projectName {
                return a.projectName < b.projectName
            }
            return a.sortOrder < b.sortOrder
        }

        guard !enabledSlots.isEmpty else {
            return ScheduleResult(
                scheduledItems: [],
                unscheduledTasks: candidates.map {
                    UnscheduledTaskInfo(
                        id: $0.task.id,
                        taskTitle: $0.task.title,
                        projectName: $0.projectName,
                        projectPriority: $0.projectPriority,
                        remainingHours: $0.remainingHours,
                        reason: "No hay momentos disponibles configurados o habilitados."
                    )
                },
                totalAvailableHours: 0,
                totalDemandHours: totalDemand,
                totalAllocatedHours: 0,
                bufferPercentApplied: safetyBufferPercent
            )
        }

        // 2. Generar ocurrencias concretas de bloques en el rango [startDate, startDate + (weeks * 7 días)]
        let normalizedStart = calendar.startOfDay(for: startDate)
        let totalDays = max(7, weeksToSchedule * 7)

        struct ConcreteSlot {
            let date: Date
            let startMinute: Int
            let endMinute: Int
            let usableMinutes: Int
            var remainingMinutes: Int
            var currentCursorMinute: Int
        }

        var concreteSlots: [ConcreteSlot] = []
        var totalAvailableHours: Double = 0.0

        for dayOffset in 0..<totalDays {
            guard let slotDate = calendar.date(byAdding: .day, value: dayOffset, to: normalizedStart) else { continue }
            let weekday = calendar.component(.weekday, from: slotDate)

            let matchingSlots = enabledSlots
                .filter { $0.weekday == weekday }
                .sorted { $0.startMinute < $1.startMinute }

            for s in matchingSlots {
                let grossMinutes = s.durationMinutes
                let bufferMinutes = Int(Double(grossMinutes) * safetyBufferPercent)
                let netMinutes = max(15, grossMinutes - bufferMinutes)

                totalAvailableHours += Double(netMinutes) / 60.0
                concreteSlots.append(
                    ConcreteSlot(
                        date: slotDate,
                        startMinute: s.startMinute,
                        endMinute: s.startMinute + netMinutes, // El fin usable respeta el buffer
                        usableMinutes: netMinutes,
                        remainingMinutes: netMinutes,
                        currentCursorMinute: s.startMinute
                    )
                )
            }
        }

        // 3. Asignación determinista a los huecos
        var scheduledItems: [ScheduledItem] = []
        var totalAllocatedHours: Double = 0.0
        var slotIndex = 0

        for candidateIndex in 0..<candidates.count {
            while candidates[candidateIndex].remainingHours > 0.01 && slotIndex < concreteSlots.count {
                var currentSlot = concreteSlots[slotIndex]

                if currentSlot.remainingMinutes <= 0 {
                    slotIndex += 1
                    continue
                }

                let taskNeededMinutes = Int(round(candidates[candidateIndex].remainingHours * 60.0))
                let minutesToAssign = min(currentSlot.remainingMinutes, taskNeededMinutes)

                let startMin = currentSlot.currentCursorMinute
                let endMin = startMin + minutesToAssign
                let assignedHours = Double(minutesToAssign) / 60.0

                scheduledItems.append(
                    ScheduledItem(
                        taskId: candidates[candidateIndex].task.id,
                        taskTitle: candidates[candidateIndex].task.title,
                        projectName: candidates[candidateIndex].projectName,
                        projectPriority: candidates[candidateIndex].projectPriority,
                        date: currentSlot.date,
                        startMinute: startMin,
                        endMinute: endMin,
                        allocatedHours: assignedHours,
                        isCompleted: candidates[candidateIndex].task.isCompleted
                    )
                )

                candidates[candidateIndex].remainingHours -= assignedHours
                currentSlot.remainingMinutes -= minutesToAssign
                currentSlot.currentCursorMinute = endMin
                concreteSlots[slotIndex] = currentSlot
                totalAllocatedHours += assignedHours

                if currentSlot.remainingMinutes <= 0 {
                    slotIndex += 1
                }
            }
        }

        // 4. Identificar tareas desbordadas que no pudieron completarse en el horizonte
        var unscheduled: [UnscheduledTaskInfo] = []
        for candidate in candidates where candidate.remainingHours > 0.05 {
            unscheduled.append(
                UnscheduledTaskInfo(
                    id: candidate.task.id,
                    taskTitle: candidate.task.title,
                    projectName: candidate.projectName,
                    projectPriority: candidate.projectPriority,
                    remainingHours: candidate.remainingHours,
                    reason: "Capacidad semanal insuficiente en el horizonte de \(weeksToSchedule) semanas."
                )
            )
        }

        return ScheduleResult(
            scheduledItems: scheduledItems,
            unscheduledTasks: unscheduled,
            totalAvailableHours: totalAvailableHours,
            totalDemandHours: totalDemand,
            totalAllocatedHours: totalAllocatedHours,
            bufferPercentApplied: safetyBufferPercent
        )
    }
}
