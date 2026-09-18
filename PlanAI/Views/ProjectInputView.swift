import SwiftUI
import SwiftData

public struct ProjectInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    public let viewModel: ProjectViewModel

    @State private var projectName: String = ""
    @State private var projectDescription: String = ""
    @State private var startDate: Date = Date()
    @State private var hasTargetEndDate: Bool = false
    @State private var targetEndDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var priority: ProjectPriority = .media

    // Servicio nativo de grabación y transcripción (AVAudioRecorder + SFSpeech)
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

                    // Fechas y Prioridad
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                DatePicker(
                                    String(localized: "Fecha de Inicio"),
                                    selection: $startDate,
                                    displayedComponents: [.date]
                                )
                                .datePickerStyle(.compact)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(String(localized: "Prioridad:"))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    Picker("", selection: $priority) {
                                        ForEach(ProjectPriority.allCases) { p in
                                            Label(p.title, systemImage: p.iconName).tag(p)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 130)
                                }
                            }
                        }

                        // Fecha Límite / Fin Objetivo opcional
                        HStack(spacing: 12) {
                            Toggle(String(localized: "Fijar fecha fin objetivo"), isOn: $hasTargetEndDate)
                                .font(.subheadline)

                            if hasTargetEndDate {
                                DatePicker(
                                    "",
                                    selection: $targetEndDate,
                                    in: startDate...,
                                    displayedComponents: [.date]
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                            }
                        }
                    }

                    // Cabecera de Descripción con Controles de Grabación y Transcripción
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

                        // Barra de herramientas de grabación — flujo: Grabar → Detener y Transcribir (automático)
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                // Selector de idioma
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
                                    .disabled(transcriptionService.isRecording || transcriptionService.isTranscribing)
                                    .frame(maxWidth: 200)
                                }

                                Spacer()

                                if transcriptionService.isRecording {
                                    // Grabando → botón para detener Y transcribir automáticamente
                                    Button(action: stopAndTranscribe) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "stop.circle.fill")
                                                .foregroundStyle(.red)
                                                .symbolEffect(.pulse, isActive: true)

                                            Text(transcriptionService.formattedDuration)
                                                .font(.caption.monospacedDigit())
                                                .fontWeight(.bold)
                                                .foregroundStyle(.red)

                                            Text(String(localized: "Detener y Transcribir"))
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)

                                } else if !transcriptionService.isTranscribing {
                                    // Idle → botón para iniciar grabación
                                    Button(action: startRecording) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "mic.fill")
                                                .foregroundStyle(.blue)
                                            Text(String(localized: "Grabar Descripción"))
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            // Progreso de transcripción
                            if transcriptionService.isTranscribing {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(String(localized: "Transcribiendo en el dispositivo..."))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        Text(String(format: "%.0f%%", transcriptionService.transcriptionProgress * 100))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)

                                        Button(action: { transcriptionService.cancel() }) {
                                            Text(String(localized: "Cancelar"))
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.borderless)
                                    }

                                    ProgressView(value: transcriptionService.transcriptionProgress)
                                        .progressViewStyle(.linear)
                                }
                                .padding(8)
                                .background(Color.blue.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Indicador REC animado
                        if transcriptionService.isRecording {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .opacity(0.85)

                                Text(String(localized: "Grabando… pulsa «Detener y Transcribir» cuando termines."))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                        }

                        // Mensaje de error
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

                        Text(String(localized: "Describe objetivos, requerimientos o fases clave. Puedes escribir o grabar audio."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Botones de acción
                    VStack(spacing: 10) {
                        Button(action: {
                            if transcriptionService.isRecording {
                                transcriptionService.cancel()
                            }

                            let effectiveTarget = hasTargetEndDate ? targetEndDate : nil
                            Task {
                                await viewModel.createProjectWithAI(
                                    name: projectName,
                                    description: projectDescription,
                                    startDate: startDate,
                                    targetEndDate: effectiveTarget,
                                    priority: priority,
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
                                transcriptionService.cancel()
                            }

                            let effectiveTarget = hasTargetEndDate ? targetEndDate : nil
                            viewModel.createManualProject(
                                name: projectName,
                                description: projectDescription,
                                startDate: startDate,
                                targetEndDate: effectiveTarget,
                                priority: priority,
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
                        transcriptionService.cancel()
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
                transcriptionService.cancel()
            }
            .onChange(of: transcriptionService.phase) { _, newPhase in
                // Cuando la transcripción completa, insertar el texto en la descripción
                if case .completed = newPhase {
                    let clean = transcriptionService.transcribedText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else {
                        transcriptionService.resetAfterCompletion()
                        return
                    }

                    if baseDescriptionBeforeRecording.isEmpty {
                        projectDescription = clean
                    } else {
                        projectDescription = baseDescriptionBeforeRecording + "\n\n" + clean
                    }
                    // Resetear para permitir nueva grabación
                    transcriptionService.resetAfterCompletion()
                }
            }
        }
    }

    // MARK: - Acciones de grabación

    private func startRecording() {
        baseDescriptionBeforeRecording = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await transcriptionService.startRecording()
        }
    }

    private func stopAndTranscribe() {
        transcriptionService.stopRecordingAndTranscribe()
    }
}
