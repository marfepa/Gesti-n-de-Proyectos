import SwiftUI
import SwiftData

public struct ProjectInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    public let viewModel: ProjectViewModel

    @State private var projectName: String = ""
    @State private var projectDescription: String = ""
    @State private var startDate: Date = Date()

    public init(viewModel: ProjectViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Estado de Apple Intelligence
                    AIStatusBanner(service: viewModel.aiAvailability)

                    // Nombre del Proyecto
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Nombre del Proyecto"))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        TextField(
                            String(localized: "Ej. Rediseño App Móvil v2"),
                            text: $projectName
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    // Fecha de Inicio
                    VStack(alignment: .leading, spacing: 6) {
                        DatePicker(
                            String(localized: "Fecha de Inicio del Proyecto"),
                            selection: $startDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)
                    }

                    // Descripción del Proyecto en Lenguaje Natural
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(localized: "Descripción en Lenguaje Natural"))
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Spacer()

                            Text("\(projectDescription.count) / 2000")
                                .font(.caption2)
                                .foregroundStyle(projectDescription.count > 1500 ? .orange : .secondary)
                        }

                        TextEditor(text: $projectDescription)
                            .frame(minHeight: 120)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )

                        Text(String(localized: "Describe objetivos, requerimientos o fases clave. Apple Intelligence descompondrá esto en tareas estimadas."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Botones de acción
                    VStack(spacing: 10) {
                        Button(action: {
                            Task {
                                await viewModel.createProjectWithAI(
                                    name: projectName,
                                    description: projectDescription,
                                    startDate: startDate,
                                    context: modelContext
                                )
                            }
                        }) {
                            HStack {
                                if viewModel.isDecomposing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 4)
                                    Text(String(localized: "Analizando con Neural Engine..."))
                                } else {
                                    Image(systemName: "sparkles")
                                    Text(String(localized: "Descomponer con Apple Intelligence"))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(projectDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isDecomposing)

                        Button(action: {
                            viewModel.createManualProject(
                                name: projectName,
                                description: projectDescription,
                                startDate: startDate,
                                context: modelContext
                            )
                        }) {
                            Text(String(localized: "Crear Proyecto Manual (Sin IA)"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isDecomposing)
                    }
                }
                .padding(20)
            }
            .navigationTitle(String(localized: "Nuevo Proyecto"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancelar")) {
                        dismiss()
                    }
                    .disabled(viewModel.isDecomposing)
                }
            }
            .frame(minWidth: 500, minHeight: 460)
            .alert(
                String(localized: "Error al generar plan"),
                isPresented: Binding(
                    get: { viewModel.showErrorAlert },
                    set: { viewModel.showErrorAlert = $0 }
                )
            ) {
                Button(String(localized: "Aceptar"), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? String(localized: "Ocurrió un error inesperado."))
            }
        }
    }
}
