import SwiftUI
import SwiftData

/// Modal para editar la información completa del proyecto: Nombre, Descripción, Fechas y Prioridad.
public struct ProjectEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    public let project: Project
    public let viewModel: ProjectViewModel

    @State private var name: String
    @State private var description: String
    @State private var startDate: Date
    @State private var hasTargetEndDate: Bool
    @State private var targetEndDate: Date
    @State private var priority: ProjectPriority

    public init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        _name = State(initialValue: project.name)
        _description = State(initialValue: project.projectDescription)
        _startDate = State(initialValue: project.startDate)
        _hasTargetEndDate = State(initialValue: project.targetEndDate != nil)
        _targetEndDate = State(initialValue: project.targetEndDate ?? project.estimatedEndDate)
        _priority = State(initialValue: project.priority)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "Datos Generales"))) {
                    TextField(String(localized: "Nombre del Proyecto"), text: $name)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Descripción:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $description)
                            .frame(minHeight: 80)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                Section(header: Text(String(localized: "Prioridad y Fechas"))) {
                    Picker(String(localized: "Prioridad"), selection: $priority) {
                        ForEach(ProjectPriority.allCases) { p in
                            Label(p.title, systemImage: p.iconName).tag(p)
                        }
                    }

                    DatePicker(
                        String(localized: "Fecha de Inicio"),
                        selection: $startDate,
                        displayedComponents: [.date]
                    )

                    Toggle(String(localized: "Definir fecha fin objetivo"), isOn: $hasTargetEndDate)

                    if hasTargetEndDate {
                        DatePicker(
                            String(localized: "Fecha Fin Objetivo"),
                            selection: $targetEndDate,
                            in: startDate...,
                            displayedComponents: [.date]
                        )

                        if targetEndDate < project.estimatedEndDate {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(String(localized: "Aviso: El cronograma actual de tareas termina después de esta fecha objetivo."))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Editar Proyecto"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancelar")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Guardar")) {
                        viewModel.updateProject(
                            project,
                            name: name,
                            description: description,
                            startDate: startDate,
                            targetEndDate: hasTargetEndDate ? targetEndDate : nil,
                            priority: priority,
                            context: modelContext
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 420, minHeight: 380)
        }
    }
}
