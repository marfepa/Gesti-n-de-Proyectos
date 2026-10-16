import Foundation
import SwiftData

@Model
public final class ProjectTask: Identifiable {
    public var id: UUID = UUID()
    public var title: String = ""
    public var notes: String = ""
    public var startDate: Date = Date()
    public var endDate: Date = Date()
    public var estimatedDays: Int = 1
    public var estimatedHours: Double = 4.0
    public var isCompleted: Bool = false
    public var sortOrder: Int = 0
    public var scheduledDate: Date?
    
    // Propiedades para soporte de UI/UX estilo Structured
    public var isInbox: Bool = false
    public var hasFixedTime: Bool = false
    public var fixedStartMinute: Int?
    public var fixedEndMinute: Int?
    public var iconName: String = "doc.fill"
    public var colorToken: String?
    public var alertOffsetMinutes: Int? = 5
    
    public var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \ProjectSubtask.task)
    public var subtasks: [ProjectSubtask] = []

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        startDate: Date,
        endDate: Date,
        estimatedDays: Int = 1,
        estimatedHours: Double? = nil,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        scheduledDate: Date? = nil,
        isInbox: Bool = false,
        hasFixedTime: Bool = false,
        fixedStartMinute: Int? = nil,
        fixedEndMinute: Int? = nil,
        iconName: String = "doc.fill",
        colorToken: String? = nil,
        alertOffsetMinutes: Int? = 5,
        project: Project? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.estimatedDays = max(1, estimatedDays)
        self.estimatedHours = estimatedHours ?? Double(max(1, estimatedDays) * 4)
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.scheduledDate = scheduledDate
        self.isInbox = isInbox
        self.hasFixedTime = hasFixedTime
        self.fixedStartMinute = fixedStartMinute
        self.fixedEndMinute = fixedEndMinute
        self.iconName = iconName
        self.colorToken = colorToken
        self.alertOffsetMinutes = alertOffsetMinutes
        self.project = project
        self.subtasks = []
    }

    /// Token de color efectivo: usa el de la tarea si está definido, o hereda del proyecto contenedor.
    public var effectiveColorToken: String {
        if let colorToken, !colorToken.isEmpty {
            return colorToken
        }
        return project?.colorToken ?? "coral"
    }

    /// Duración calculada en días entre la fecha de inicio y fin.
    public var durationInDays: Int {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.day], from: startDate, to: endDate)
        return max(1, comps.day ?? estimatedDays)
    }

    /// Rango de fechas formateado legible.
    public var dateRangeFormatted: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: startDate, to: endDate)
    }

    /// Subtareas ordenadas según su orden de visualización.
    public var sortedSubtasks: [ProjectSubtask] {
        subtasks.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Detecta si la tarea es de gran envergadura (más de 6 horas o más de 2 días de duración).
    public var isLargeTask: Bool {
        estimatedHours >= 6.0 || durationInDays >= 2
    }

    /// Progreso de las subtareas de 0.0 a 1.0 (si no tiene subtareas devuelve 1.0 si completada, 0.0 si no).
    public var subtasksProgress: Double {
        guard !subtasks.isEmpty else { return isCompleted ? 1.0 : 0.0 }
        let completed = subtasks.filter { $0.isCompleted }.count
        return Double(completed) / Double(subtasks.count)
    }

    /// Total de horas estimadas considerando subtareas si existen.
    public var effectiveEstimatedHours: Double {
        if subtasks.isEmpty {
            return estimatedHours
        }
        return subtasks.reduce(0.0) { $0 + $1.estimatedHours }
    }
}
