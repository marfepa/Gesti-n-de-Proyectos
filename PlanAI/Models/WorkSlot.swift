import Foundation
import SwiftData

/// Representa una franja horaria recurrente de disponibilidad en la semana.
@Model
public final class WorkSlot: Identifiable {
    public var id: UUID = UUID()
    /// Día de la semana en formato estándar de Calendar (1 = Domingo, 2 = Lunes, ..., 7 = Sábado).
    public var weekday: Int = 2
    /// Minuto del día de inicio (ej. 17:30 = 17 * 60 + 30 = 1050).
    public var startMinute: Int = 540 // 09:00 por defecto
    /// Minuto del día de fin (ej. 19:30 = 19 * 60 + 30 = 1170).
    public var endMinute: Int = 660   // 11:00 por defecto
    /// Título o etiqueta del bloque (ej. "Tarde de foco", "Mañana desarrollo").
    public var label: String = ""
    /// Permite activar o desactivar el hueco sin borrarlo.
    public var isEnabled: Bool = true
    /// Orden visual.
    public var sortOrder: Int = 0

    public init(
        id: UUID = UUID(),
        weekday: Int,
        startMinute: Int,
        endMinute: Int,
        label: String = "",
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = max(startMinute + 15, endMinute)
        self.label = label
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    /// Duración total del bloque en minutos.
    public var durationMinutes: Int {
        max(0, endMinute - startMinute)
    }

    /// Duración formateada (ej. "2h 30m").
    public var durationFormatted: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    /// Nombre localizado del día de la semana.
    public var weekdayName: String {
        let calendar = Calendar.current
        let symbols = calendar.standaloneWeekdaySymbols
        let index = weekday - 1
        if index >= 0 && index < symbols.count {
            return symbols[index].capitalized
        }
        return String(localized: "Día \(weekday)")
    }

    /// Hora de inicio formateada (HH:mm).
    public var startTimeFormatted: String {
        WorkSlot.formatTime(minute: startMinute)
    }

    /// Hora de fin formateada (HH:mm).
    public var endTimeFormatted: String {
        WorkSlot.formatTime(minute: endMinute)
    }

    public static func formatTime(minute: Int) -> String {
        let h = (minute / 60) % 24
        let m = minute % 60
        return String(format: "%02d:%02d", h, m)
    }

    /// Plantilla de slots por defecto para inicialización rápida.
    public static func defaultSlots() -> [WorkSlot] {
        [
            WorkSlot(weekday: 2, startMinute: 9 * 60, endMinute: 13 * 60, label: "Mañana de foco", sortOrder: 0),
            WorkSlot(weekday: 3, startMinute: 9 * 60, endMinute: 13 * 60, label: "Mañana de foco", sortOrder: 1),
            WorkSlot(weekday: 4, startMinute: 9 * 60, endMinute: 13 * 60, label: "Mañana de foco", sortOrder: 2),
            WorkSlot(weekday: 5, startMinute: 9 * 60, endMinute: 13 * 60, label: "Mañana de foco", sortOrder: 3),
            WorkSlot(weekday: 6, startMinute: 9 * 60, endMinute: 13 * 60, label: "Mañana de foco", sortOrder: 4)
        ]
    }
}
