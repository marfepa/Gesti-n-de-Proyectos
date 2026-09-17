import Foundation
import SwiftData

public enum ProjectPriority: Int, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case baja = 1
    case media = 2
    case alta = 3
    case urgente = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .baja: return String(localized: "Baja")
        case .media: return String(localized: "Media")
        case .alta: return String(localized: "Alta")
        case .urgente: return String(localized: "Urgente")
        }
    }

    public var iconName: String {
        switch self {
        case .baja: return "arrow.down.circle"
        case .media: return "minus.circle"
        case .alta: return "arrow.up.circle.fill"
        case .urgente: return "exclamationmark.triangle.fill"
        }
    }

    public static func < (lhs: ProjectPriority, rhs: ProjectPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@Model
public final class Project: Identifiable {
    public var id: UUID = UUID()
    public var name: String = ""
    public var projectDescription: String = ""
    public var startDate: Date = Date()
    public var targetEndDate: Date?
    public var createdAt: Date = Date()
    public var priorityRawValue: Int = ProjectPriority.media.rawValue

    public var priority: ProjectPriority {
        get { ProjectPriority(rawValue: priorityRawValue) ?? .media }
        set { priorityRawValue = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project)
    public var tasks: [ProjectTask] = []

    public init(
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        startDate: Date = Date(),
        targetEndDate: Date? = nil,
        createdAt: Date = Date(),
        priority: ProjectPriority = .media
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.startDate = startDate
        self.targetEndDate = targetEndDate
        self.createdAt = createdAt
        self.priorityRawValue = priority.rawValue
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

    /// Fecha límite efectiva: la fecha objetivo definida por el usuario o, si no existe, la fecha estimada de tareas.
    public var effectiveDeadline: Date {
        targetEndDate ?? estimatedEndDate
    }

    /// Indica si el plan de tareas actual desborda la fecha límite objetivo.
    public var isOverdueOrExceedsTarget: Bool {
        guard let target = targetEndDate else { return false }
        return estimatedEndDate > target
    }

    /// Días de desfase respecto a la fecha objetivo (positivo = retraso/exceso, negativo = holgura).
    public var targetVarianceInDays: Int {
        guard let target = targetEndDate else { return 0 }
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.day], from: target, to: estimatedEndDate)
        return comps.day ?? 0
    }

    /// Duración total estimada en días.
    public var totalDurationInDays: Int {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.day], from: startDate, to: estimatedEndDate)
        return max(0, comps.day ?? 0)
    }
}
