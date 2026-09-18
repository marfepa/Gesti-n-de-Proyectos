import Foundation

/// Helper puro y determinista para calcular el dominio temporal, marcas de eje y visibilidad de la línea «Hoy» en el diagrama de Gantt.
public struct GanttTimeScale: Sendable, Equatable {
    public let startDate: Date
    public let endDate: Date
    public let today: Date
    public let isTodayVisible: Bool
    public let ticks: [Date]
    public let totalDays: Int

    public var domain: ClosedRange<Date> {
        startDate...endDate
    }

    public init(
        tasks: [ProjectTask],
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        let taskDates = tasks.flatMap { [$0.startDate, $0.endDate] }
        self.init(dates: taskDates, today: today, calendar: calendar)
    }

    public init(
        dates: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        let normalizedToday = calendar.startOfDay(for: today)
        self.today = normalizedToday

        if dates.isEmpty {
            let start = normalizedToday
            let fallbackEnd = calendar.date(byAdding: .day, value: 14, to: start) ?? start
            let end = max(fallbackEnd, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
            self.startDate = start
            self.endDate = end
            self.isTodayVisible = true
            self.totalDays = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 14)
            self.ticks = Self.calculateTicks(from: start, to: end, calendar: calendar)
            return
        }

        let rawMin = dates.min() ?? today
        let rawMax = dates.max() ?? today

        let start = calendar.startOfDay(for: rawMin)
        var end = calendar.startOfDay(for: rawMax)

        // El dominio debe ser un ClosedRange válido (end > start)
        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }

        self.startDate = start
        self.endDate = end

        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 1
        self.totalDays = max(1, days)

        // Línea «Hoy» visible únicamente si se encuentra dentro del rango [startDate, endDate]
        self.isTodayVisible = (normalizedToday >= start && normalizedToday <= end)

        // Marcas semanales ancladas a startDate
        self.ticks = Self.calculateTicks(from: start, to: end, calendar: calendar)
    }

    /// Genera marcas semanales (cada 7 días) ancladas exactamente en startDate
    public static func calculateTicks(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        guard end >= start else { return [start] }
        var result: [Date] = [start]
        var current = calendar.date(byAdding: .day, value: 7, to: start) ?? start

        while current <= end {
            result.append(current)
            guard let next = calendar.date(byAdding: .day, value: 7, to: current), next > current else {
                break
            }
            current = next
        }

        return result
    }

    /// Calcula la posición horizontal en píxeles para una fecha determinada dentro del ancho total disponible.
    public func xPosition(for date: Date, totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else { return 0 }
        let totalDuration = endDate.timeIntervalSince(startDate)
        guard totalDuration > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        let ratio = max(0.0, min(1.0, elapsed / totalDuration))
        return CGFloat(ratio) * totalWidth
    }

    /// Convierte una coordenada X en píxeles a la fecha correspondiente en el dominio.
    public func date(forX x: CGFloat, totalWidth: CGFloat) -> Date {
        guard totalWidth > 0 else { return startDate }
        let totalDuration = endDate.timeIntervalSince(startDate)
        let ratio = max(0.0, min(1.0, Double(x / totalWidth)))
        return startDate.addingTimeInterval(ratio * totalDuration)
    }

    /// Redondea una fecha al inicio del día más cercano.
    public func snapToDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let midDay = startOfDay.addingTimeInterval(12 * 3600)
        return date >= midDay ? nextDay : startOfDay
    }
}
