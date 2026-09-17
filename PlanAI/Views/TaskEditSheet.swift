import SwiftUI

public struct TaskEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let task: ProjectTask?
    public let onSave: (String, String, Date, Date, Double) -> Void

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var estimatedHours: Double = 4.0

    public init(task: ProjectTask?, onSave: @escaping (String, String, Date, Date, Double) -> Void) {
        self.task = task
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "Información Básica"))) {
                    TextField(String(localized: "Título de la tarea"), text: $title)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Notas y Justificación"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $notes)
                            .frame(minHeight: 60)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                    }
                }

                Section(header: Text(String(localized: "Cronograma"))) {
                    DatePicker(
                        String(localized: "Fecha de Inicio"),
                        selection: $startDate,
                        displayedComponents: [.date]
                    )

                    DatePicker(
                        String(localized: "Fecha de Fin"),
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: [.date]
                    )

                    HStack {
                        Text(String(localized: "Duración en días:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(calculatedDays) " + String(localized: "días laborables"))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    Stepper(value: $estimatedHours, in: 0.5...40.0, step: 0.5) {
                        HStack {
                            Text(String(localized: "Horas de trabajo estimadas:"))
                            Spacer()
                            Text(String(format: "%.1f h", estimatedHours))
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(task == nil ? String(localized: "Nueva Tarea") : String(localized: "Editar Tarea"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancelar")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Guardar")) {
                        onSave(title, notes, startDate, endDate, estimatedHours)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let task = task {
                    self.title = task.title
                    self.notes = task.notes
                    self.startDate = task.startDate
                    self.endDate = task.endDate
                    self.estimatedHours = task.estimatedHours
                }
            }
            .frame(minWidth: 420, minHeight: 340)
        }
    }

    private var calculatedDays: Int {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.day], from: startDate, to: endDate)
        return max(1, comps.day ?? 1)
    }
}
