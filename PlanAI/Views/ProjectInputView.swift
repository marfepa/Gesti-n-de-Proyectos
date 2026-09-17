import SwiftUI
import SwiftData

public struct ProjectInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    public let viewModel: ProjectViewModel

    @State private var projectName: String = ""
    @State private var projectDescription: String = ""
    @State private var startDate: Date = Date()

    // Servicio nativo de audio y transcripción
    @State private var transcriptionService = AudioTranscriptionService()
    @State private var baseDescriptionBeforeRecording: String = ""

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

                    // Cabecera de Descripción con Controles de Dictado
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "Descripción en Lenguaje Natural"))
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Spacer()

                            Text("\(projectDescription.count) / 2000")
                                .font(.caption2)
                                .foregroundStyle(projectDescription.count > 1500 ? .orange : .secondary)
                        }

                        // Barra de herramientas de grabación y transcripción
                        HStack(spacing: 12) {
                            // Selector de idioma nativo de Apple
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Picker("", selection: $transcriptionService.selectedLocaleOption) {
                                    ForEach(transcriptionService.availableLocales) { opt in
                                        Text(opt.displayName).tag(opt)
                                    }
                                }
                                .pickerStyle(.menu)
                                .disabled(transcriptionService.isRecording)
                                .frame(maxWidth: 220)
                            }

                            Spacer()

                            // Botón de grabación / micrófono
                            Button(action: toggleRecording) {
                                HStack(spacing: 6) {
                                    Image(systemName: transcriptionService.isRecording ? "stop.circle.fill" : "mic.fill")
                                        .foregroundStyle(transcriptionService.isRecording ? .red : .primary)
                                        .symbolEffect(.pulse, isActive: transcriptionService.isRecording)

                                    if transcriptionService.isRecording {
                                        Text(transcriptionService.formattedDuration)
                                            .font(.caption.monospacedDigit())
                                            .fontWeight(.bold)
                                            .foregroundStyle(.red)

                                        Text(String(localized: "Detener"))
                                            .font(.caption)
                                    } else {
                                        Text(String(localized: "Dictar con Voz"))
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(transcriptionService.isRecording ? .red : .blue)
                            .help(String(localized: "voice_input_tooltip"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Banner de estado de grabación
                        if transcriptionService.isRecording {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .opacity(0.8)

                                Text(String(localized: "listening"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                        }

                        // Error de transcripción o micrófono
                        if let error = transcriptionService.errorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                        }

                        // Editor de texto
                        TextEditor(text: $projectDescription)
                            .frame(minHeight: 120)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )

                        Text(String(localized: "Describe objetivos, requerimientos o fases clave. Puedes escribir o dictar por voz."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Botones de acción
                    VStack(spacing: 10) {
                        Button(action: {
                            // Detener grabación si está en curso antes de analizar
                            if transcriptionService.isRecording {
                                transcriptionService.stopRecording()
                            }

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
                            if transcriptionService.isRecording {
                                transcriptionService.stopRecording()
                            }

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
                        if transcriptionService.isRecording {
                            transcriptionService.stopRecording()
                        }
                        dismiss()
                    }
                    .disabled(viewModel.isDecomposing)
                }
            }
            .frame(minWidth: 520, minHeight: 520)
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
            .onDisappear {
                if transcriptionService.isRecording {
                    transcriptionService.stopRecording()
                }
            }
        }
    }

    private func toggleRecording() {
        if transcriptionService.isRecording {
            transcriptionService.stopRecording()
        } else {
            baseDescriptionBeforeRecording = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                await transcriptionService.startRecording { recognizedText in
                    if baseDescriptionBeforeRecording.isEmpty {
                        self.projectDescription = recognizedText
                    } else {
                        self.projectDescription = "\(baseDescriptionBeforeRecording)\n\(recognizedText)"
                    }
                }
            }
        }
    }
}
