import Foundation

/// Resumen ligero de subtarea para mostrar checklists interactivos dentro del Timeline.
public struct ScheduledSubtaskSummary: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool

    public init(id: UUID, title: String, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

/// Representa una asignación concreta de una tarea a un día y bloque horario.
public struct ScheduledItem: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var taskId: UUID
    public var projectId: UUID?
    public var subtaskId: UUID?
    public var taskTitle: String
    public var subtaskTitle: String?
    public var taskNotes: String
    public var subtaskNotes: String?
    public var projectName: String
    public var projectPriority: ProjectPriority
    public var date: Date
    public var startMinute: Int
    public var endMinute: Int
    public var allocatedHours: Double
    public var isCompleted: Bool
    public var iconName: String
    public var colorToken: String
    public var subtaskItems: [ScheduledSubtaskSummary]
    public var isExternalCalendarEvent: Bool

    public init(
        id: UUID = UUID(),
        taskId: UUID,
        projectId: UUID? = nil,
        subtaskId: UUID? = nil,
        taskTitle: String,
        subtaskTitle: String? = nil,
        taskNotes: String = "",
        subtaskNotes: String? = nil,
        projectName: String,
        projectPriority: ProjectPriority = .media,
        date: Date,
        startMinute: Int,
        endMinute: Int,
        allocatedHours: Double,
        isCompleted: Bool,
        iconName: String = "doc.fill",
        colorToken: String = "coral",
        subtaskItems: [ScheduledSubtaskSummary] = [],
        isExternalCalendarEvent: Bool = false
    ) {
        self.id = id
        self.taskId = taskId
        self.projectId = projectId
        self.subtaskId = subtaskId
        self.taskTitle = taskTitle
        self.subtaskTitle = subtaskTitle
        self.taskNotes = taskNotes
        self.subtaskNotes = subtaskNotes
        self.projectName = projectName
        self.projectPriority = projectPriority
        self.date = date
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.allocatedHours = allocatedHours
        self.isCompleted = isCompleted
        self.iconName = iconName
        self.colorToken = colorToken
        self.subtaskItems = subtaskItems
        self.isExternalCalendarEvent = isExternalCalendarEvent
    }

    public var displayTitle: String {
        if let sub = subtaskTitle, !sub.isEmpty {
            return "\(taskTitle) · \(sub)"
        }
        return taskTitle
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

    public var slotUtilization: Double {
        guard totalAvailableHours > 0 else { return 0.0 }
        return min(1.0, totalAllocatedHours / totalAvailableHours)
    }
}

/// Motor determinista de asignación de tareas a bloques semanales + soporte de eventos con hora fija y carving de huecos.
public final class WeeklySchedulerService: Sendable {

    public init() {}

    /// Encuentra el primer hueco libre en un día dado que pueda alojar `durationMinutes` sin solaparse con `existingItems`.
    public func findNextAvailableGap(
        on date: Date,
        durationMinutes: Int,
        existingItems: [ScheduledItem],
        wakeUpMinute: Int = 375,
        windDownMinute: Int = 1305,
        preferredStartMinute: Int = 540,
        calendar: Calendar = .current
    ) -> Int {
        let dayItems = existingItems
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.startMinute < $1.startMinute }

        let needed = max(15, durationMinutes)
        var candidateStart = max(wakeUpMinute, preferredStartMinute)

        for item in dayItems {
            let candidateEnd = candidateStart + needed
            if candidateEnd <= item.startMinute {
                return candidateStart
            }
            if candidateStart < item.endMinute {
                // Redondear al siguiente múltiplo de 5 minutos tras el fin de la tarea existente
                let rawNext = item.endMinute
                let rem = rawNext % 5
                candidateStart = rem == 0 ? rawNext : rawNext + (5 - rem)
            }
        }

        if candidateStart + needed <= windDownMinute {
            return candidateStart
        }

        // Segunda pasada desde wakeUpMinute por si había hueco temprano antes de preferredStartMinute
        var earlyCandidate = wakeUpMinute
        for item in dayItems {
            if earlyCandidate + needed <= item.startMinute {
                return earlyCandidate
            }
            if earlyCandidate < item.endMinute {
                earlyCandidate = item.endMinute
            }
        }

        return min(max(wakeUpMinute, candidateStart), max(wakeUpMinute, 1410 - needed))
    }

    public func schedule(
        projects: [Project],
        slots: [WorkSlot],
        externalEvents: [ScheduledItem] = [],
        startDate: Date = Date(),
        weeksToSchedule: Int = 2,
        safetyBufferPercent: Double = 0.15,
        calendar: Calendar = .current
    ) -> ScheduleResult {
        let enabledSlots = slots.filter { $0.isEnabled && $0.durationMinutes > 0 }

        struct TaskCandidate {
            let task: ProjectTask
            let subtask: ProjectSubtask?
            let projectId: UUID
            let projectName: String
            let projectPriority: ProjectPriority
            let projectDeadline: Date
            let taskSortOrder: Int
            let subtaskSortOrder: Int
            var remainingHours: Double
        }

        var candidates: [TaskCandidate] = []
        var fixedScheduledItems: [ScheduledItem] = externalEvents
        var totalDemand: Double = 0.0
        var totalAllocatedHours: Double = 0.0

        for project in projects {
            let activeTasks = project.sortedTasks.filter { !$0.isInbox }
            let deadline = project.effectiveDeadline
            let priority = project.priority

            for task in activeTasks {
                let subtaskSummaries = task.sortedSubtasks.map {
                    ScheduledSubtaskSummary(id: $0.id, title: $0.title, isCompleted: $0.isCompleted)
                }

                // 1. Tareas con hora fija agendadas directamente en el Timeline (estilo Structured)
                if task.hasFixedTime, let fStart = task.fixedStartMinute, let fEnd = task.fixedEndMinute {
                    let durationMin = max(1, fEnd - fStart)
                    let hours = Double(durationMin) / 60.0
                    let targetDate = calendar.startOfDay(for: task.scheduledDate ?? task.startDate)
                    fixedScheduledItems.append(
                        ScheduledItem(
                            taskId: task.id,
                            projectId: project.id,
                            subtaskId: nil,
                            taskTitle: task.title,
                            subtaskTitle: task.subtasks.isEmpty ? nil : "\(task.subtasks.filter(\.isCompleted).count)/\(task.subtasks.count) subtasks",
                            taskNotes: task.notes,
                            subtaskNotes: nil,
                            projectName: project.name,
                            projectPriority: priority,
                            date: targetDate,
                            startMinute: fStart,
                            endMinute: fEnd,
                            allocatedHours: hours,
                            isCompleted: task.isCompleted,
                            iconName: task.iconName,
                            colorToken: task.effectiveColorToken,
                            subtaskItems: subtaskSummaries
                        )
                    )
                    if !task.isCompleted {
                        totalDemand += hours
                        totalAllocatedHours += hours
                    }
                    continue
                }

                // 2. Tareas automáticas de proyecto (solo pendientes)
                guard !task.isCompleted else { continue }
                let pendingSubtasks = task.sortedSubtasks.filter { !$0.isCompleted }

                if !pendingSubtasks.isEmpty {
                    for sub in pendingSubtasks {
                        let hours = max(0.25, sub.estimatedHours)
                        totalDemand += hours
                        candidates.append(
                            TaskCandidate(
                                task: task,
                                subtask: sub,
                                projectId: project.id,
                                projectName: project.name,
                                projectPriority: priority,
                                projectDeadline: deadline,
                                taskSortOrder: task.sortOrder,
                                subtaskSortOrder: sub.sortOrder,
                                remainingHours: hours
                            )
                        )
                    }
                } else {
                    let hours = max(0.5, task.effectiveEstimatedHours)
                    totalDemand += hours
                    candidates.append(
                        TaskCandidate(
                            task: task,
                            subtask: nil,
                            projectId: project.id,
                            projectName: project.name,
                            projectPriority: priority,
                            projectDeadline: deadline,
                            taskSortOrder: task.sortOrder,
                            subtaskSortOrder: 0,
                            remainingHours: hours
                        )
                    )
                }
            }
        }

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
            if a.taskSortOrder != b.taskSortOrder {
                return a.taskSortOrder < b.taskSortOrder
            }
            return a.subtaskSortOrder < b.subtaskSortOrder
        }

        guard !enabledSlots.isEmpty else {
            return ScheduleResult(
                scheduledItems: fixedScheduledItems,
                unscheduledTasks: candidates.map {
                    UnscheduledTaskInfo(
                        id: $0.subtask?.id ?? $0.task.id,
                        taskTitle: $0.subtask != nil ? "\($0.task.title) · \($0.subtask!.title)" : $0.task.title,
                        projectName: $0.projectName,
                        projectPriority: $0.projectPriority,
                        remainingHours: $0.remainingHours,
                        reason: "No hay momentos disponibles configurados o habilitados."
                    )
                },
                totalAvailableHours: 0,
                totalDemandHours: totalDemand,
                totalAllocatedHours: totalAllocatedHours,
                bufferPercentApplied: safetyBufferPercent
            )
        }

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

            // Eventos y tareas de hora fija en este día concreto (no completados) que bloquean capacidad
            let dayFixedIntervals: [(start: Int, end: Int)] = fixedScheduledItems
                .filter { !$0.isCompleted && calendar.isDate($0.date, inSameDayAs: slotDate) }
                .map { (start: $0.startMinute, end: $0.endMinute) }
                .sorted { $0.start < $1.start }

            for s in matchingSlots {
                let grossMinutes = s.durationMinutes
                let bufferMinutes = Int(Double(grossMinutes) * safetyBufferPercent)
                let netMinutes = max(15, grossMinutes - bufferMinutes)
                let slotStart = s.startMinute
                let slotEnd = s.startMinute + netMinutes

                // Recortar (carve out) cualquier intervalo fijo que solape con este WorkSlot
                var freeSegments: [(start: Int, end: Int)] = [(start: slotStart, end: slotEnd)]
                for fixed in dayFixedIntervals {
                    var nextSegments: [(start: Int, end: Int)] = []
                    for seg in freeSegments {
                        // Sin solapamiento
                        if fixed.end <= seg.start || fixed.start >= seg.end {
                            nextSegments.append(seg)
                        } else {
                            // Tramo anterior libre
                            if fixed.start > seg.start {
                                nextSegments.append((start: seg.start, end: fixed.start))
                            }
                            // Tramo posterior libre
                            if fixed.end < seg.end {
                                nextSegments.append((start: fixed.end, end: seg.end))
                            }
                        }
                    }
                    freeSegments = nextSegments
                }

                for seg in freeSegments {
                    let segDuration = seg.end - seg.start
                    guard segDuration >= 15 else { continue }
                    totalAvailableHours += Double(segDuration) / 60.0
                    concreteSlots.append(
                        ConcreteSlot(
                            date: slotDate,
                            startMinute: seg.start,
                            endMinute: seg.end,
                            usableMinutes: segDuration,
                            remainingMinutes: segDuration,
                            currentCursorMinute: seg.start
                        )
                    )
                }
            }
        }

        var scheduledItems: [ScheduledItem] = fixedScheduledItems
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

                let candidateTask = candidates[candidateIndex].task
                let candidateSub = candidates[candidateIndex].subtask
                let summaries = candidateTask.sortedSubtasks.map {
                    ScheduledSubtaskSummary(id: $0.id, title: $0.title, isCompleted: $0.isCompleted)
                }

                scheduledItems.append(
                    ScheduledItem(
                        taskId: candidateTask.id,
                        projectId: candidates[candidateIndex].projectId,
                        subtaskId: candidateSub?.id,
                        taskTitle: candidateTask.title,
                        subtaskTitle: candidateSub?.title,
                        taskNotes: candidateTask.notes,
                        subtaskNotes: candidateSub?.notes,
                        projectName: candidates[candidateIndex].projectName,
                        projectPriority: candidates[candidateIndex].projectPriority,
                        date: currentSlot.date,
                        startMinute: startMin,
                        endMinute: endMin,
                        allocatedHours: assignedHours,
                        isCompleted: candidateSub?.isCompleted ?? candidateTask.isCompleted,
                        iconName: candidateTask.iconName,
                        colorToken: candidateTask.effectiveColorToken,
                        subtaskItems: summaries
                    )
                )

                candidates[candidateIndex].remainingHours -= assignedHours
                currentSlot.remainingMinutes -= minutesToAssign
                currentSlot.currentCursorMinute = endMin
                concreteSlots[slotIndex] = currentSlot
                totalAllocatedHours += assignedHours

                slotIndex += 1
            }
        }

        var unscheduled: [UnscheduledTaskInfo] = []
        for candidate in candidates where candidate.remainingHours > 0.05 {
            let label = candidate.subtask != nil ? "\(candidate.task.title) · \(candidate.subtask!.title)" : candidate.task.title
            unscheduled.append(
                UnscheduledTaskInfo(
                    id: candidate.subtask?.id ?? candidate.task.id,
                    taskTitle: label,
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
