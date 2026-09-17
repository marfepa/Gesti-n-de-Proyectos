import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
public final class ProjectViewModel {
    public var isDecomposing: Bool = false
    public var errorMessage: String?
    public var showErrorAlert: Bool = false
    
    public var selectedProject: Project?
    public var showingNewProjectSheet: Bool = false
    public var showingTaskSheet: Bool = false
    public var editingTask: ProjectTask?
    
    private let decompositionService = TaskDecompositionService()
    public let aiAvailability = AIAvailabilityService()

    public init() {}

    /// Descompone el texto del proyecto con IA y guarda las tareas en SwiftData asociadas al proyecto.
    public func createProjectWithAI(
        name: String,
        description: String,
        startDate: Date,
        context: ModelContext
    ) async {
        isDecomposing = true
        errorMessage = nil
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = trimmedName.isEmpty ? String(localized: "Proyecto sin título") : trimmedName
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        
        do {
            let payloads = try await decompositionService.decompose(
                projectDescription: description,
                startDate: normalizedStart,
                calendar: calendar
            )

            let project = Project(
                name: projectName,
                projectDescription: description,
                startDate: normalizedStart
            )
            context.insert(project)

            for payload in payloads {
                let task = ProjectTask(
                    title: payload.title,
                    notes: payload.notes,
                    startDate: payload.startDate,
                    endDate: payload.endDate,
                    estimatedDays: payload.estimatedDays,
                    isCompleted: false,
                    sortOrder: payload.sortOrder,
                    project: project
                )
                context.insert(task)
                project.tasks.append(task)
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
        context: ModelContext
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = trimmedName.isEmpty ? String(localized: "Proyecto Manual") : trimmedName
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)

        let project = Project(
            name: projectName,
            projectDescription: description,
            startDate: normalizedStart
        )
        context.insert(project)
        try? context.save()
        self.selectedProject = project
        self.showingNewProjectSheet = false
    }

    /// Guarda o actualiza una tarea de forma manual.
    public func saveTask(
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date,
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
        } else {
            let nextOrder = (project.tasks.map(\.sortOrder).max() ?? -1) + 1
            let newTask = ProjectTask(
                title: title,
                notes: notes,
                startDate: normalizedStart,
                endDate: max(normalizedStart, normalizedEnd),
                estimatedDays: days,
                isCompleted: false,
                sortOrder: nextOrder,
                project: project
            )
            context.insert(newTask)
            project.tasks.append(newTask)
        }

        try? context.save()
        self.editingTask = nil
        self.showingTaskSheet = false
    }

    /// Alterna el estado de completado de una tarea.
    public func toggleTaskCompletion(_ task: ProjectTask, context: ModelContext) {
        task.isCompleted.toggle()
        try? context.save()
    }

    /// Elimina una tarea individual.
    public func deleteTask(_ task: ProjectTask, context: ModelContext) {
        context.delete(task)
        try? context.save()
    }

    /// Elimina un proyecto completo (cascada en tareas).
    public func deleteProject(_ project: Project, context: ModelContext) {
        if selectedProject?.id == project.id {
            selectedProject = nil
        }
        context.delete(project)
        try? context.save()
    }
}
