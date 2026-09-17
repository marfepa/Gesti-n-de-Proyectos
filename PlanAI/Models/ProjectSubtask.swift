import Foundation
import SwiftData

/// Representa una subtarea atómica dentro de una tarea más grande de un proyecto.
@Model
public final class ProjectSubtask: Identifiable {
    public var id: UUID = UUID()
    public var title: String = ""
    public var notes: String = ""
    public var estimatedHours: Double = 1.0
    public var isCompleted: Bool = false
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()

    public var task: ProjectTask?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        estimatedHours: Double = 1.0,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        task: ProjectTask? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.estimatedHours = max(0.25, estimatedHours)
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.task = task
    }
}
