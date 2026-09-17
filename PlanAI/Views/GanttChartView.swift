import SwiftUI
import Charts

public struct GanttChartView: View {
    public let tasks: [ProjectTask]
    @Binding public var selectedTask: ProjectTask?
    public let onEditTask: (ProjectTask) -> Void

    public init(
        tasks: [ProjectTask],
        selectedTask: Binding<ProjectTask?>,
        onEditTask: @escaping (ProjectTask) -> Void
    ) {
        self.tasks = tasks
        self._selectedTask = selectedTask
        self.onEditTask = onEditTask
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cabecera y leyenda
            HStack {
                Text(String(localized: "Cronograma de Fases (Gantt)"))
                    .font(.headline)

                Spacer()

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "En progreso / Pendiente"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "Completada"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            if tasks.isEmpty {
                ContentUnavailableView(
                    String(localized: "Sin tareas en el cronograma"),
                    systemImage: "calendar.badge.clock",
                    description: Text(String(localized: "Añade tareas manualmente o genera el plan con IA."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Chart {
                        // Línea indicadora del día de hoy
                        RuleMark(
                            x: .value(String(localized: "Hoy"), Date())
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.red.opacity(0.7))
                        .annotation(position: .top, alignment: .leading) {
                            Text(String(localized: "Hoy"))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        // Barras horizontales por tarea
                        ForEach(tasks) { task in
                            BarMark(
                                xStart: .value(String(localized: "Inicio"), task.startDate),
                                xEnd: .value(String(localized: "Fin"), task.endDate),
                                y: .value(String(localized: "Tarea"), task.title)
                            )
                            .foregroundStyle(task.isCompleted ? Color.green.gradient : Color.blue.gradient)
                            .cornerRadius(6)
                            .annotation(position: .trailing, alignment: .center) {
                                Text("\(task.durationInDays)d")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            AxisTick()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            AxisValueLabel()
                        }
                    }
                    .frame(
                        minWidth: max(600, CGFloat(chartWidthCalculated)),
                        minHeight: max(300, CGFloat(tasks.count * 45 + 80))
                    )
                    .padding()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private var chartWidthCalculated: Int {
        guard let minDate = tasks.map(\.startDate).min(),
              let maxDate = tasks.map(\.endDate).max() else {
            return 600
        }
        let days = Calendar.current.dateComponents([.day], from: minDate, to: maxDate).day ?? 14
        return max(600, days * 25)
    }
}
