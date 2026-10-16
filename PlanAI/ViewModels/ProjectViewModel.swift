import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
public final class ProjectViewModel {
    public var isDecomposing: Bool = false
    public var errorMessage: String?
    public var showErrorAlert: Bool = false
    
    public enum SidebarTab: String, CaseIterable, Hashable, Identifiable {
        case todayTimeline
        case weeklySchedule
        case inbox
        case projects

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .todayTimeline: return String(localized: "Hoy")
            case .weeklySchedule: return String(localized: "Semana")
            case .inbox: return String(localized: "Bandeja")
            case .projects: return String(localized: "Proyectos")
            }
        }

        public var iconName: String {
            switch self {
            case .todayTimeline: return "sun.max.fill"
            case .weeklySchedule: return "calendar"
            case .inbox: return "tray.fill"
            case .projects: return "chart.bar.xaxis"
            }
        }
    }

    public var activeTab: SidebarTab = .todayTimeline
    public var selectedProject: Project?
    public var showingNewProjectSheet: Bool = false
    public var showingTaskSheet: Bool = false
    public var editingTask: ProjectTask?
    public var showingEditProjectSheet: Bool = false
    public var projectToEdit: Project?

    private let decompositionService = TaskDecompositionService()
    public let aiAvailability = AIAvailabilityService()

    public init() {}

    /// Descompone el texto del proyecto con IA y guarda las tareas y subtareas en SwiftData asociadas al proyecto.
    public func createProjectWithAI(
        name: String,
        description: String,
        startDate: Date,
        targetEndDate: Date? = nil,
        priority: ProjectPriority = .media,
        colorToken: String = "coral",
        iconName: String = "folder.fill",
        context: ModelContext
    ) async {
        isDecomposing = true
        errorMessage = nil
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = trimmedName.isEmpty ? String(localized: "Proyecto sin título") : trimmedName
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedTarget = targetEndDate.map { calendar.startOfDay(for: $0) }
        
        do {
            let payloads = try await decompositionService.decompose(
                projectDescription: description,
                startDate: normalizedStart,
                targetEndDate: normalizedTarget,
                calendar: calendar
            )

            let project = Project(
                name: projectName,
                projectDescription: description,
                startDate: normalizedStart,
                targetEndDate: normalizedTarget,
                priority: priority,
                colorToken: colorToken,
                iconName: iconName
            )
            context.insert(project)

            for payload in payloads {
                let task = ProjectTask(
                    title: payload.title,
                    notes: payload.notes,
                    startDate: payload.startDate,
                    endDate: payload.endDate,
                    estimatedDays: payload.estimatedDays,
                    estimatedHours: payload.estimatedHours,
                    isCompleted: false,
                    sortOrder: payload.sortOrder,
                    iconName: payload.iconName,
                    colorToken: payload.colorToken,
                    project: project
                )
                context.insert(task)
                project.tasks.append(task)

                for (subIdx, sub) in payload.subtasks.enumerated() {
                    let subtask = ProjectSubtask(
                        title: sub.title,
                        notes: sub.notes,
                        estimatedHours: sub.hours,
                        sortOrder: subIdx,
                        task: task
                    )
                    context.insert(subtask)
                    task.subtasks.append(subtask)
                }
            }

            try context.save()
            self.selectedProject = project
            self.showingNewProjectSheet = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }

        isDecomposing = false
    }

    /// Crea un proyecto vacío para edición 100% manual.
    public func createManualProject(
        name: String,
        description: String,
        startDate: Date,
        targetEndDate: Date? = nil,
        priority: ProjectPriority = .media,
        colorToken: String = "coral",
        iconName: String = "folder.fill",
        context: ModelContext
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = trimmedName.isEmpty ? String(localized: "Proyecto Manual") : trimmedName
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedTarget = targetEndDate.map { calendar.startOfDay(for: $0) }

        let project = Project(
            name: projectName,
            projectDescription: description,
            startDate: normalizedStart,
            targetEndDate: normalizedTarget,
            priority: priority,
            colorToken: colorToken,
            iconName: iconName
        )
        context.insert(project)
        try? context.save()
        self.selectedProject = project
        self.showingNewProjectSheet = false
    }

    /// Actualiza la información integral de un proyecto existente.
    public func updateProject(
        _ project: Project,
        name: String,
        description: String,
        startDate: Date,
        targetEndDate: Date?,
        priority: ProjectPriority,
        colorToken: String? = nil,
        iconName: String? = nil,
        context: ModelContext
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.name = trimmedName.isEmpty ? project.name : trimmedName
        project.projectDescription = description
        project.startDate = Calendar.current.startOfDay(for: startDate)
        project.targetEndDate = targetEndDate.map { Calendar.current.startOfDay(for: $0) }
        project.priority = priority
        if let colorToken {
            project.colorToken = colorToken
        }
        if let iconName {
            project.iconName = iconName
        }

        try? context.save()
        self.showingEditProjectSheet = false
        self.projectToEdit = nil
    }

    /// Guarda o actualiza una tarea de forma manual.
    public func saveTask(
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date,
        estimatedHours: Double = 4.0,
        iconName: String? = nil,
        colorToken: String? = nil,
        in project: Project,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        var normalizedEnd = calendar.startOfDay(for: endDate)
        if normalizedEnd < normalizedStart {
            normalizedEnd = normalizedStart
        }
        let comps = calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd)
        let days = max(1, comps.day ?? 1)

        if let existing = editingTask {
            existing.title = title
            existing.notes = notes
            existing.startDate = normalizedStart
            existing.endDate = max(normalizedStart, normalizedEnd)
            existing.estimatedDays = days
            existing.estimatedHours = estimatedHours
            if let iconName { existing.iconName = iconName }
            if let colorToken { existing.colorToken = colorToken }
        } else {
            let nextOrder = (project.tasks.map(\.sortOrder).max() ?? -1) + 1
            let newTask = ProjectTask(
                title: title,
                notes: notes,
                startDate: normalizedStart,
                endDate: max(normalizedStart, normalizedEnd),
                estimatedDays: days,
                estimatedHours: estimatedHours,
                isCompleted: false,
                sortOrder: nextOrder,
                iconName: iconName ?? TaskDecompositionService.inferIcon(for: title),
                colorToken: colorToken ?? project.colorToken,
                project: project
            )
            context.insert(newTask)
            project.tasks.append(newTask)
        }

        try? context.save()
        self.editingTask = nil
        self.showingTaskSheet = false
    }

    /// Actualiza directamente las fechas de una tarea (por resize o drag en Gantt), recalculando días y horas.
    public func updateTaskDates(
        task: ProjectTask,
        newStart: Date,
        newEnd: Date,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: newStart)
        var normalizedEnd = calendar.startOfDay(for: newEnd)
        if normalizedEnd < normalizedStart {
            normalizedEnd = normalizedStart
        }

        let comps = calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd)
        let days = max(1, comps.day ?? 1)

        task.startDate = normalizedStart
        task.endDate = normalizedEnd
        task.estimatedDays = days
        task.estimatedHours = Double(days * 4)

        try? context.save()
    }

    /// Alterna el estado de completado de una tarea.
    public func toggleTaskCompletion(_ task: ProjectTask, context: ModelContext) {
        task.isCompleted.toggle()
        if task.isCompleted {
            for s in task.subtasks {
                s.isCompleted = true
            }
            NotificationService.shared.cancelNotification(for: task.id)
        }
        try? context.save()
    }

    /// Alterna el estado de completado de una subtarea.
    public func toggleSubtaskCompletion(_ subtask: ProjectSubtask, context: ModelContext) {
        subtask.isCompleted.toggle()
        
        if let parent = subtask.task {
            let allCompleted = parent.subtasks.allSatisfy { $0.isCompleted }
            if allCompleted && !parent.subtasks.isEmpty {
                parent.isCompleted = true
            } else if !subtask.isCompleted {
                parent.isCompleted = false
            }
        }
        
        try? context.save()
    }

    /// Desglosa una tarea existente en subtareas accionables usando IA on-device (con fallback heurístico).
    public func decomposeTask(_ task: ProjectTask, context: ModelContext) {
        let taskTitle = task.title
        let taskNotes = task.notes
        let estHours = task.estimatedHours

        Task {
            let generated = await decompositionService.decomposeTaskWithAI(
                taskTitle: taskTitle,
                taskNotes: taskNotes,
                estimatedHours: estHours
            )

            for (idx, item) in generated.enumerated() {
                let subtask = ProjectSubtask(
                    title: item.title,
                    notes: item.notes,
                    estimatedHours: item.hours,
                    sortOrder: (task.subtasks.map(\.sortOrder).max() ?? -1) + 1 + idx,
                    task: task
                )
                context.insert(subtask)
                task.subtasks.append(subtask)
            }

            try? context.save()
        }
    }

    /// Añade una subtarea manual a una tarea.
    public func addSubtask(title: String, hours: Double, to task: ProjectTask, context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let nextOrder = (task.subtasks.map(\.sortOrder).max() ?? -1) + 1
        let subtask = ProjectSubtask(
            title: trimmed,
            estimatedHours: hours,
            sortOrder: nextOrder,
            task: task
        )
        context.insert(subtask)
        task.subtasks.append(subtask)
        try? context.save()
    }

    /// Elimina una subtarea individual.
    public func deleteSubtask(_ subtask: ProjectSubtask, context: ModelContext) {
        context.delete(subtask)
        try? context.save()
    }

    /// Elimina una tarea individual.
    public func deleteTask(_ task: ProjectTask, context: ModelContext) {
        NotificationService.shared.cancelNotification(for: task.id)
        context.delete(task)
        try? context.save()
    }

    /// Elimina un proyecto completo (cascada en tareas).
    public func deleteProject(_ project: Project, context: ModelContext) {
        if selectedProject?.id == project.id {
            selectedProject = nil
        }
        for task in project.tasks {
            NotificationService.shared.cancelNotification(for: task.id)
        }
        context.delete(project)
        try? context.save()
    }
}
