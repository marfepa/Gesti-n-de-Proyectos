import Foundation

/// Representa una asignación concreta de una tarea a un día y bloque horario.
public struct ScheduledItem: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var taskId: UUID
    public var projectId: UUID?
    public var subtaskId: UUID?
    public var taskTitle: String
    public var subtaskTitle: String?
    public var projectName: String
    public var projectPriority: ProjectPriority
    public var date: Date
    public var startMinute: Int
    public var endMinute: Int
    public var allocatedHours: Double
    public var isCompleted: Bool
    public var iconName: String

    public init(
        id: UUID = UUID(),
        taskId: UUID,
        projectId: UUID? = nil,
        subtaskId: UUID? = nil,
        taskTitle: String,
        subtaskTitle: String? = nil,
        projectName: String,
        projectPriority: ProjectPriority = .media,
        date: Date,
        startMinute: Int,
        endMinute: Int,
        allocatedHours: Double,
        isCompleted: Bool,
        iconName: String = "doc.fill"
    ) {
        self.id = id
        self.taskId = taskId
        self.projectId = projectId
        self.subtaskId = subtaskId
        self.taskTitle = taskTitle
        self.subtaskTitle = subtaskTitle
        self.projectName = projectName
        self.projectPriority = projectPriority
        self.date = date
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.allocatedHours = allocatedHours
        self.isCompleted = isCompleted
        self.iconName = iconName
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

/// Motor determinista de asignación de tareas a bloques semanales + soporte de eventos con hora fija.
public final class WeeklySchedulerService: Sendable {

    public init() {}

    public func schedule(
        projects: [Project],
        slots: [WorkSlot],
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
        var fixedScheduledItems: [ScheduledItem] = []
        var totalDemand: Double = 0.0
        var totalAllocatedHours: Double = 0.0

        for project in projects {
            let activeTasks = project.sortedTasks.filter { !$0.isInbox }
            let deadline = project.effectiveDeadline
            let priority = project.priority

            for task in activeTasks {
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
                            projectName: project.name,
                            projectPriority: priority,
                            date: targetDate,
                            startMinute: fStart,
                            endMinute: fEnd,
                            allocatedHours: hours,
                            isCompleted: task.isCompleted,
                            iconName: task.iconName
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

            for s in matchingSlots {
                let grossMinutes = s.durationMinutes
                let bufferMinutes = Int(Double(grossMinutes) * safetyBufferPercent)
                let netMinutes = max(15, grossMinutes - bufferMinutes)

                totalAvailableHours += Double(netMinutes) / 60.0

                concreteSlots.append(
                    ConcreteSlot(
                        date: slotDate,
                        startMinute: s.startMinute,
                        endMinute: s.startMinute + netMinutes,
                        usableMinutes: netMinutes,
                        remainingMinutes: netMinutes,
                        currentCursorMinute: s.startMinute
                    )
                )
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

                scheduledItems.append(
                    ScheduledItem(
                        taskId: candidates[candidateIndex].task.id,
                        projectId: candidates[candidateIndex].projectId,
                        subtaskId: candidates[candidateIndex].subtask?.id,
                        taskTitle: candidates[candidateIndex].task.title,
                        subtaskTitle: candidates[candidateIndex].subtask?.title,
                        projectName: candidates[candidateIndex].projectName,
                        projectPriority: candidates[candidateIndex].projectPriority,
                        date: currentSlot.date,
                        startMinute: startMin,
                        endMinute: endMin,
                        allocatedHours: assignedHours,
                        isCompleted: candidates[candidateIndex].subtask?.isCompleted ?? candidates[candidateIndex].task.isCompleted,
                        iconName: candidates[candidateIndex].task.iconName
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

