import SwiftUI
import Charts

public struct GanttChartView: View {
    public let tasks: [ProjectTask]
    @Binding public var selectedTask: ProjectTask?
    public let onEditTask: (ProjectTask) -> Void

    @State private var showSubtasksInGantt: Bool = true

    public init(
        tasks: [ProjectTask],
        selectedTask: Binding<ProjectTask?>,
        onEditTask: @escaping (ProjectTask) -> Void
    ) {
        self.tasks = tasks
        self._selectedTask = selectedTask
        self.onEditTask = onEditTask
    }

    /// Estructura aplanada para graficar tanto tareas principales como sus subtareas asociadas en el eje Y.
    private struct GanttChartItem: Identifiable {
        let id: String
        let title: String
        let parentTitle: String?
        let startDate: Date
        let endDate: Date
        let isCompleted: Bool
        let isSubtask: Bool
        let taskRef: ProjectTask
    }

    private var chartItems: [GanttChartItem] {
        var items: [GanttChartItem] = []

        for task in tasks {
            // Tarea principal
            items.append(
                GanttChartItem(
                    id: task.id.uuidString,
                    title: task.title,
                    parentTitle: nil,
                    startDate: task.startDate,
                    endDate: task.endDate,
                    isCompleted: task.isCompleted,
                    isSubtask: false,
                    taskRef: task
                )
            )

            // Subtareas si está activado
            if showSubtasksInGantt && !task.subtasks.isEmpty {
                let subtasks = task.sortedSubtasks
                let totalSubtasks = max(1, subtasks.count)
                let taskSpan = max(1.0, task.endDate.timeIntervalSince(task.startDate))
                let slice = taskSpan / Double(totalSubtasks)

                for (idx, subtask) in subtasks.enumerated() {
                    let subStart = task.startDate.addingTimeInterval(Double(idx) * slice)
                    let subEnd = task.startDate.addingTimeInterval(Double(idx + 1) * slice)

                    items.append(
                        GanttChartItem(
                            id: subtask.id.uuidString,
                            title: "  ↳ \(subtask.title)",
                            parentTitle: task.title,
                            startDate: subStart,
                            endDate: subEnd,
                            isCompleted: subtask.isCompleted,
                            isSubtask: true,
                            taskRef: task
                        )
                    )
                }
            }
        }
        return items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cabecera y leyenda
            HStack {
                Text(String(localized: "Cronograma de Fases (Gantt)"))
                    .font(.headline)

                Spacer()

                HStack(spacing: 16) {
                    Toggle(String(localized: "Ver subtareas"), isOn: $showSubtasksInGantt)
                        .font(.caption)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "En progreso"))
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

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "Subtarea"))
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
                let scale = timeScale
                let items = chartItems
                ScrollView([.horizontal, .vertical]) {
                    Chart {
                        // Línea indicadora del día de hoy solo si cae dentro del cronograma
                        if scale.isTodayVisible {
                            RuleMark(
                                x: .value(String(localized: "Hoy"), scale.today)
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
                        }

                        // Barras horizontales por tarea y subtarea
                        ForEach(items) { item in
                            BarMark(
                                xStart: .value(String(localized: "Inicio"), item.startDate),
                                xEnd: .value(String(localized: "Fin"), item.endDate),
                                y: .value(String(localized: "Tarea"), item.title)
                            )
                            .foregroundStyle(barColor(for: item))
                            .cornerRadius(item.isSubtask ? 3 : 6)
                            .annotation(position: .trailing, alignment: .center) {
                                if !item.isSubtask {
                                    Text("\(item.taskRef.durationInDays)d")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 4)
                                }
                            }
                        }
                    }
                    .chartXScale(domain: scale.domain)
                    .chartXAxis {
                        AxisMarks(values: scale.ticks) { value in
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
                        minWidth: max(600, CGFloat(scale.totalDays * 25)),
                        minHeight: max(300, CGFloat(items.count * 38 + 80))
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

    private func barColor(for item: GanttChartItem) -> AnyShapeStyle {
        if item.isCompleted {
            return AnyShapeStyle(Color.green.gradient)
        } else if item.isSubtask {
            return AnyShapeStyle(Color.purple.opacity(0.85).gradient)
        } else {
            return AnyShapeStyle(Color.blue.gradient)
        }
    }

    private var timeScale: GanttTimeScale {
        GanttTimeScale(tasks: tasks)
    }
}
