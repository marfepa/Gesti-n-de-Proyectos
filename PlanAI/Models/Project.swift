import Foundation
import SwiftData

@Model
public final class Project: Identifiable {
    public var id: UUID = UUID()
    public var name: String = ""
    public var projectDescription: String = ""
    public var startDate: Date = Date()
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project)
    public var tasks: [ProjectTask] = []

    public init(
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        startDate: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.startDate = startDate
        self.createdAt = createdAt
        self.tasks = []
    }

    /// Tareas ordenadas según su secuencia cronológica.
    public var sortedTasks: [ProjectTask] {
        tasks.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.startDate < $1.startDate
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    /// Progreso acumulado del proyecto de 0.0 a 1.0.
    public var progress: Double {
        guard !tasks.isEmpty else { return 0.0 }
        let completed = tasks.filter { $0.isCompleted }.count
        return Double(completed) / Double(tasks.count)
    }

    /// Fecha de finalización estimada del proyecto (fin de la última tarea).
    public var estimatedEndDate: Date {
        tasks.map(\.endDate).max() ?? startDate
    }

    /// Duración total estimada en días.
    public var totalDurationInDays: Int {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.day], from: startDate, to: estimatedEndDate)
        return max(0, comps.day ?? 0)
    }
}
