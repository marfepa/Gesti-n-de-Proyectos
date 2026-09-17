import SwiftUI

/// Vista de cuadrícula mensual (estilo calendario de pared) para visualizar la distribución y densidad de trabajo.
public struct MonthlyScheduleGridView: View {
    public let result: ScheduleResult
    public let selectedDate: Date

    @State private var currentMonth: Date

    private let calendar = Calendar.current
    private let dayHeaders = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]

    public init(result: ScheduleResult, selectedDate: Date = Date()) {
        self.result = result
        self.selectedDate = selectedDate
        _currentMonth = State(initialValue: selectedDate)
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Controles de navegación mensual
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(monthYearString(from: currentMonth))
                    .font(.headline)
                    .fontWeight(.bold)
                    .frame(minWidth: 150)

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Spacer()

                Button(String(localized: "Mes Actual")) {
                    currentMonth = Date()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Cabecera de días de la semana
            HStack(spacing: 6) {
                ForEach(dayHeaders, id: \.self) { header in
                    Text(header)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)

            // Matriz de días del mes
            let days = daysInMonth(for: currentMonth)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(days, id: \.self) { day in
                        if let date = day {
                            DayCell(
                                date: date,
                                isToday: calendar.isDateInToday(date),
                                items: itemsForDate(date)
                            )
                        } else {
                            // Espacio en blanco para cuadrar con el día de la semana
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                                .frame(height: 90)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
    }

    private func itemsForDate(_ date: Date) -> [ScheduledItem] {
        result.scheduledItems.filter {
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    private func previousMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = prev
        }
    }

    private func nextMonth() {
        if let next = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = next
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    private func daysInMonth(for date: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstDay = monthInterval.start
        
        // Determinar desfase para que empiece en Lunes (Lunes = 2, Domingo = 1)
        let weekday = calendar.component(.weekday, from: firstDay)
        let offset = (weekday == 1 ? 6 : weekday - 2) // 0 para Lunes, 6 para Domingo

        var resultDays: [Date?] = Array(repeating: nil, count: offset)

        guard let range = calendar.range(of: .day, in: .month, for: date) else { return resultDays }
        for day in 1...range.count {
            if let dayDate = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                resultDays.append(dayDate)
            }
        }

        // Rellenar hasta múltiplo de 7 si es necesario
        let remainder = resultDays.count % 7
        if remainder != 0 {
            resultDays.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }

        return resultDays
    }
}

/// Celda de un día individual en el calendario mensual
struct DayCell: View {
    let date: Date
    let isToday: Bool
    let items: [ScheduledItem]

    private let calendar = Calendar.current

    private var totalHours: Double {
        items.reduce(0) { $0 + $1.allocatedHours }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(calendar.component(.day, from: date))")
                    .font(.caption)
                    .fontWeight(isToday ? .bold : .medium)
                    .padding(4)
                    .background(isToday ? Circle().fill(Color.blue) : Circle().fill(Color.clear))
                    .foregroundStyle(isToday ? .white : .primary)

                Spacer()

                if totalHours > 0 {
                    Text(String(format: "%.1fh", totalHours))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.blue)
                }
            }

            if items.isEmpty {
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items.prefix(2)) { item in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(priorityColor(item.projectPriority))
                                .frame(width: 5, height: 5)

                            Text(item.taskTitle)
                                .font(.system(size: 8))
                                .lineLimit(1)
                        }
                    }

                    if items.count > 2 {
                        Text("+\(items.count - 2) más")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(6)
        .frame(height: 90)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? Color.blue.opacity(0.8) : Color.gray.opacity(0.15), lineWidth: isToday ? 1.5 : 1)
        )
    }

    private func priorityColor(_ priority: ProjectPriority) -> Color {
        switch priority {
        case .baja: return .gray
        case .media: return .blue
        case .alta: return .orange
        case .urgente: return .red
        }
    }
}
