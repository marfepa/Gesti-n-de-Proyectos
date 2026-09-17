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
    
    public var project: Project?

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
        self.project = project
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
}
