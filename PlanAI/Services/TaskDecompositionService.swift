import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Errores específicos del servicio de descomposición con IA.
public enum DecompositionError: LocalizedError, Sendable {
    case modelUnavailable(String)
    case contextWindowExceeded
    case guardrailViolation
    case emptyInput
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return String(localized: "El modelo de lenguaje on-device no está disponible: \(reason)")
        case .contextWindowExceeded:
            return String(localized: "La descripción del proyecto es demasiado larga para la ventana de contexto del modelo. Intenta resumirla a 1-3 párrafos.")
        case .guardrailViolation:
            return String(localized: "La solicitud activó las políticas de seguridad del sistema. Reformula la descripción del proyecto.")
        case .emptyInput:
            return String(localized: "Por favor proporciona una descripción válida para descomponer el proyecto.")
        case .generationFailed(let msg):
            return String(localized: "Fallo en la generación guiada: \(msg)")
        }
    }
}

/// Resultado de un comando rápido en lenguaje natural estilo "Structured AI".
public struct QuickScheduledTaskPayload: Sendable, Equatable {
    public var title: String
    public var startMinute: Int
    public var durationMinutes: Int
    public var iconName: String
    public var colorToken: String
    public var notes: String
    public var subtasks: [String]

    public init(
        title: String,
        startMinute: Int,
        durationMinutes: Int,
        iconName: String = "sparkles",
        colorToken: String = "coral",
        notes: String = "",
        subtasks: [String] = []
    ) {
        self.title = title
        self.startMinute = max(360, min(1380, startMinute))
        self.durationMinutes = max(15, min(240, durationMinutes))
        self.iconName = iconName
        self.colorToken = colorToken
        self.notes = notes
        self.subtasks = subtasks
    }
}

/// Servicio que orquesta la llamada a FoundationModels y el cálculo determinista de cronogramas.
public final class TaskDecompositionService: Sendable {

    public init() {}

    /// Descompone una descripción de proyecto en un conjunto estructurado de tareas secuenciales con fechas, iconos y colores calculados.
    public func decompose(
        projectDescription: String,
        startDate: Date,
        targetEndDate: Date? = nil,
        calendar: Calendar = .current
    ) async throws -> [GeneratedTaskPayload] {
        let trimmed = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DecompositionError.emptyInput
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available else {
                throw DecompositionError.modelUnavailable(String(describing: model.availability))
            }

            let instructions = """
                Eres un gestor de proyectos senior con 20 años de experiencia estimando software y proyectos creativos.

                LEY DE PARKINSON - PRINCIPIO FUNDAMENTAL:
                - "El trabajo se expande hasta llenar el tiempo disponible para su realización."
                - Por lo tanto, SIEMPRE estima el tiempo MÍNIMO realista necesario, no el cómodo.
                - Si una tarea "podría" hacerse en 4 horas pero "cómodamente" en 8, estima 4-5 horas.
                - Prefiere estimaciones ajustadas pero realistas. Mejor quedarse ligeramente corto que largo.
                - Las personas rinden mejor con plazos ajustados que con plazos holgados.
                - Aplica un factor de reducción del 30% sobre tu primera estimación instintiva.

                FILOSOFÍA ESTOICA - UNA TAREA PARA CADA MOMENTO (MONOTAREA ABSOLUTA):
                - En cada momento o franja horaria existe foco exclusivo en una única tarea.
                - No se dispersa la atención en multitarea ni se intercalan tareas en el mismo intervalo.
                - Las tareas y subtareas deben estructurarse de forma estrictamente secuencial y autocontenida: una cosa se empieza y se termina por completo antes de pasar a la siguiente fase o tema.
                - Delimita claramente el final de cada tarea para permitir un cierre completo e impecable antes de cualquier transición.

                REGLAS CRÍTICAS DE ESTIMACIÓN:
                - Estima en HORAS de trabajo efectivo, no en días completos.
                - Una reunión de kickoff típica dura 1-2 horas, no un día.
                - Configurar un entorno de desarrollo toma 1-2 horas, no días.
                - Escribir un documento de requisitos de 2-3 páginas toma 2-4 horas.
                - Un diseño de UI sencillo (5-10 pantallas) toma 6-10 horas.
                - Implementar un CRUD básico toma 3-6 horas.
                - Implementar autenticación con un framework existente toma 3-6 horas.
                - Escribir tests unitarios para un módulo pequeño toma 1-3 horas.
                - Una revisión de código detallada toma 1-2 horas.
                - NO infles estimaciones "por si acaso". Sé agresivo pero realista.
                - Si una fase entera dura menos de 4 horas, NO la dividas en más de 2 subtareas.
                - Tareas muy cortas (< 1 hora) pueden no necesitar subtareas.

                ICONOS Y COLORES:
                - Asigna a cada fase un iconName de SF Symbols apropiado (laptopcomputer, paintbrush.fill, doc.fill, terminal.fill, server.rack, checkmark.shield.fill, chart.bar.fill, person.2.fill, sparkles, checklist).
                - Asigna un colorToken entre: coral, ocean, teal, lavender, amber, mint.

                REGLAS PARA SUBTAREAS:
                - Cada fase principal DEBE tener subtareas específicas y accionables.
                - Los títulos de subtareas deben describir QUÉ se hace concretamente, nunca usar genéricos como "Preparación" o "Revisión general".
                - La descripción de cada subtarea debe explicar paso a paso qué hacer, qué herramientas usar y cuál es el entregable.

                Desglosa el proyecto en fases lógicas secuenciales, cada una con subtareas detalladas.
                """

            let session = LanguageModelSession(instructions: instructions)

            let prompt = """
                Desglosa este proyecto en fases de trabajo secuenciales con subtareas detalladas.
                Estima las horas de trabajo efectivo de manera ajustada y ambiciosa.
                Recuerda: aplica la Ley de Parkinson (mínimo tiempo viable) y el Principio Estoico de una tarea para cada momento (foco único y secuencial sin multitarea).

                Descripción del proyecto:
                \(trimmed)
                """

            do {
                let response = try await session.respond(to: prompt, generating: AITaskPlan.self)
                let subtasks = response.content.subtasks.map { phase in
                    SubtaskPlan(
                        title: phase.title,
                        estimatedHours: phase.estimatedHours,
                        notes: phase.notes,
                        iconName: Self.sanitizeIcon(phase.iconName, fallbackForTitle: phase.title),
                        colorToken: Self.sanitizeColorToken(phase.colorToken),
                        subtaskDetails: phase.subtasks.map {
                            SubtaskDetailPlan(title: $0.title, estimatedHours: $0.estimatedHours, notes: $0.notes)
                        }
                    )
                }
                return buildTaskPayloads(from: subtasks, startingAt: startDate, targetEndDate: targetEndDate, calendar: calendar)
            } catch {
                let errorString = String(describing: error)
                if errorString.contains("context") || errorString.contains("exceeded") {
                    throw DecompositionError.contextWindowExceeded
                } else if errorString.contains("guardrail") || errorString.contains("safety") {
                    throw DecompositionError.guardrailViolation
                } else {
                    throw DecompositionError.generationFailed(error.localizedDescription)
                }
            }
        } else {
            return generateHeuristicPlan(from: trimmed, startDate: startDate, targetEndDate: targetEndDate, calendar: calendar)
        }
        #else
        return generateHeuristicPlan(from: trimmed, startDate: startDate, targetEndDate: targetEndDate, calendar: calendar)
        #endif
    }

    /// Convierte el plan tipado devuelto por la IA o fallback en payloads con fechas deterministas calculadas mediante Calendar.
    public func buildTaskPayloads(
        from subtasks: [SubtaskPlan],
        startingAt startDate: Date,
        targetEndDate: Date? = nil,
        hoursPerDay: Double = 4.0,
        calendar: Calendar = .current
    ) -> [GeneratedTaskPayload] {
        var currentStart = calendar.startOfDay(for: startDate)
        var results: [GeneratedTaskPayload] = []

        let effectiveHoursPerDay = max(1.0, hoursPerDay)

        var compressionRatio: Double = 1.0
        let totalRawHours = subtasks.reduce(0.0) { sum, item in
            let itemHours = item.estimatedHours > 0 ? item.estimatedHours : Double(item.estimatedDays * 4)
            return sum + max(0.5, itemHours)
        }
        let totalRawDays = max(1, Int(ceil(totalRawHours / effectiveHoursPerDay)))

        if let target = targetEndDate {
            let normalizedTarget = calendar.startOfDay(for: target)
            let comps = calendar.dateComponents([.day], from: currentStart, to: normalizedTarget)
            let availableDays = max(1, comps.day ?? totalRawDays)
            if totalRawDays > availableDays {
                compressionRatio = Double(availableDays) / Double(totalRawDays)
            }
        }

        for (index, item) in subtasks.enumerated() {
            let baseHours = item.estimatedHours > 0 ? item.estimatedHours : Double(item.estimatedDays * 4)
            let compressedHours = max(0.5, baseHours * compressionRatio)
            let calculatedDays = max(1, Int(ceil(compressedHours / effectiveHoursPerDay)))
            let taskEnd = calendar.date(byAdding: .day, value: calculatedDays, to: currentStart) ?? currentStart

            var generatedSubtasks: [(title: String, hours: Double, notes: String)] = []
            if !item.subtaskDetails.isEmpty {
                generatedSubtasks = item.subtaskDetails.map {
                    (title: $0.title, hours: max(0.5, $0.estimatedHours * compressionRatio), notes: $0.notes)
                }
            } else if calculatedDays >= 2 || compressedHours >= 6.0 {
                let step1Hours = max(0.5, round((compressedHours * 0.25) * 2) / 2)
                let step2Hours = max(0.5, round((compressedHours * 0.50) * 2) / 2)
                let step3Hours = max(0.5, max(0.5, compressedHours - step1Hours - step2Hours))
                generatedSubtasks = [
                    (title: "Especificación técnica y preparación: \(item.title)", hours: step1Hours, notes: "Definir requisitos y dependencias iniciales"),
                    (title: "Implementación principal", hours: step2Hours, notes: "Desarrollo de las piezas clave"),
                    (title: "Verificación y pruebas", hours: step3Hours, notes: "Revisión de calidad y validación")
                ]
            }

            let resolvedIcon = Self.sanitizeIcon(item.iconName, fallbackForTitle: item.title)
            let resolvedColor = Self.sanitizeColorToken(item.colorToken)

            let payload = GeneratedTaskPayload(
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: item.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: currentStart,
                endDate: taskEnd,
                estimatedDays: calculatedDays,
                estimatedHours: compressedHours,
                sortOrder: index,
                iconName: resolvedIcon,
                colorToken: resolvedColor,
                subtasks: generatedSubtasks
            )
            results.append(payload)

            currentStart = taskEnd
        }

        return results
    }

    /// Generador heurístico de respaldo cuando FoundationModels no está disponible en la máquina.
    public func generateHeuristicPlan(
        from description: String,
        startDate: Date,
        targetEndDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [GeneratedTaskPayload] {
        let lines = description.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var subtasks: [SubtaskPlan] = []
        let palette = ["ocean", "lavender", "coral", "teal", "mint", "amber"]

        if lines.count >= 2 {
            for (idx, line) in lines.enumerated() {
                let cleanTitle = line.replacingOccurrences(of: "^[0-9]+[.)-]\\s*", with: "", options: .regularExpression)
                let hours = Double((idx + 1) * 4)
                let subDetails = [
                    SubtaskDetailPlan(title: "Kickoff y alcance de \(cleanTitle)", estimatedHours: max(0.5, hours * 0.3), notes: "Alineación de objetivos y entregables"),
                    SubtaskDetailPlan(title: "Ejecución técnica de \(cleanTitle)", estimatedHours: max(0.5, hours * 0.7), notes: "Desarrollo de la fase y entregables")
                ]
                subtasks.append(SubtaskPlan(
                    title: cleanTitle,
                    estimatedHours: hours,
                    notes: "Fase generada automáticamente a partir del plan manual.",
                    iconName: Self.inferIcon(for: cleanTitle),
                    colorToken: palette[idx % palette.count],
                    subtaskDetails: subDetails
                ))
            }
        } else {
            subtasks = [
                SubtaskPlan(
                    title: "Análisis de Requisitos y Alcance",
                    estimatedHours: 4.0,
                    notes: "Definición concisa de especificaciones técnicas y criterios de aceptación.",
                    iconName: "doc.fill",
                    colorToken: "ocean",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Entrevistas de requerimientos y casos de uso", estimatedHours: 2.0, notes: "Identificar requerimientos funcionales críticos y restricciones."),
                        SubtaskDetailPlan(title: "Documentación de especificación técnica", estimatedHours: 2.0, notes: "Redactar documento de 2-3 páginas con criterios de aceptación.")
                    ]
                ),
                SubtaskPlan(
                    title: "Diseño y Arquitectura",
                    estimatedHours: 5.0,
                    notes: "Estructuración de componentes, modelos de datos y wireframes.",
                    iconName: "paintbrush.fill",
                    colorToken: "lavender",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Diseño de wireframes en Figma", estimatedHours: 3.0, notes: "Crear flujos visuales principales con estados vacío, activo y error."),
                        SubtaskDetailPlan(title: "Definición del modelo de datos y contratos de API", estimatedHours: 2.0, notes: "Estructurar esquemas SwiftData / endpoints.")
                    ]
                ),
                SubtaskPlan(
                    title: "Implementación Core",
                    estimatedHours: 10.0,
                    notes: "Desarrollo de las funcionalidades críticas del proyecto.",
                    iconName: "laptopcomputer",
                    colorToken: "coral",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Configuración de servicios base e inyección", estimatedHours: 2.0, notes: "Estructurar infraestructura y modelos persistentes."),
                        SubtaskDetailPlan(title: "Desarrollo de pantallas principales y vistas SwiftUI", estimatedHours: 5.0, notes: "Construcción interactiva de los componentes de UI."),
                        SubtaskDetailPlan(title: "Integración de lógica de negocio y persistencia", estimatedHours: 3.0, notes: "Conectar viewmodels con modelos y validaciones.")
                    ]
                ),
                SubtaskPlan(
                    title: "Pruebas y Verificación",
                    estimatedHours: 4.0,
                    notes: "Validación de calidad, cobertura de pruebas unitarias y corrección de errores.",
                    iconName: "checkmark.shield.fill",
                    colorToken: "teal",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Creación de suite de tests unitarios", estimatedHours: 2.0, notes: "Cobertura de casos límite y regresiones críticas."),
                        SubtaskDetailPlan(title: "Pruebas de interfaz y pulido de casos extremos", estimatedHours: 2.0, notes: "Validar rendimiento, accesibilidad y estados de error.")
                    ]
                ),
                SubtaskPlan(
                    title: "Despliegue y Cierre",
                    estimatedHours: 3.0,
                    notes: "Generación de artefactos de entrega y documentación final.",
                    iconName: "sparkles",
                    colorToken: "mint",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Configuración de compilación y empaquetado", estimatedHours: 1.5, notes: "Verificar esquema de release y firmas."),
                        SubtaskDetailPlan(title: "Documentación de entrega y guía de usuario", estimatedHours: 1.5, notes: "Manual de usuario y changelog.")
                    ]
                )
            ]
        }

        return buildTaskPayloads(from: subtasks, startingAt: startDate, targetEndDate: targetEndDate, calendar: calendar)
    }

    /// Descompone una tarea individual usando Apple Intelligence si está disponible, o recurre a la heurística.
    public func decomposeTaskWithAI(
        taskTitle: String,
        taskNotes: String = "",
        estimatedHours: Double
    ) async -> [(title: String, hours: Double, notes: String)] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.availability == .available {
            let instructions = """
                Desglosa una tarea de proyecto en 2 a 4 subtareas atómicas, secuenciales y accionables.
                La suma de horas debe aproximarse a \(String(format: "%.1f", max(1.0, estimatedHours))) horas.
                """
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Tarea: \(taskTitle)\nNotas: \(taskNotes)\nHoras totales estimadas: \(estimatedHours)"
            if let response = try? await session.respond(to: prompt, generating: AISubtaskPlan.self),
               !response.content.subtasks.isEmpty {
                return response.content.subtasks.map {
                    (title: $0.title, hours: max(0.25, $0.estimatedHours), notes: $0.notes)
                }
            }
        }
        #endif
        return decomposeTaskIntoSubtasks(taskTitle: taskTitle, taskNotes: taskNotes, estimatedHours: estimatedHours)
    }

    /// Descompone una tarea grande en un conjunto de subtareas accionables y más pequeñas (heurística síncrona).
    public func decomposeTaskIntoSubtasks(
        taskTitle: String,
        taskNotes: String = "",
        estimatedHours: Double
    ) -> [(title: String, hours: Double, notes: String)] {
        let cleanTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalHours = max(1.0, estimatedHours)

        let step1Hours = max(0.5, round((totalHours * 0.25) * 2) / 2)
        let step2Hours = max(0.5, round((totalHours * 0.50) * 2) / 2)
        let step3Hours = max(0.5, max(0.5, totalHours - step1Hours - step2Hours))

        return [
            (title: "Definición y especificación técnica: \(cleanTitle)", hours: step1Hours, notes: "Revisar requerimientos y alcance detallado"),
            (title: "Desarrollo e implementación principal", hours: step2Hours, notes: "Construcción técnica de la solución"),
            (title: "Pruebas, verificación y ajustes", hours: step3Hours, notes: "Validar funcionamiento y pulir detalles")
        ]
    }

    /// Analiza una instrucción en lenguaje natural estilo "Structured AI" (ej. "Reunión de diseño a las 11:30 durante 45 min")
    /// usando FoundationModels on-device o un parser heurístico determinista.
    public func parseQuickSchedulePrompt(
        _ prompt: String,
        defaultStartMinute: Int = 600
    ) async -> QuickScheduledTaskPayload {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return QuickScheduledTaskPayload(title: "Nueva Tarea", startMinute: defaultStartMinute, durationMinutes: 30)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.availability == .available {
            let instructions = """
                Extrae los datos de una tarea a partir de lenguaje natural para el calendario diario Structured.
                Convierte horas mencionadas a minutos desde medianoche (ej. 9:00 = 540, 10:30 = 630, 16:00 = 960).
                Si no se menciona hora de inicio, usa \(defaultStartMinute).
                """
            let session = LanguageModelSession(instructions: instructions)
            if let response = try? await session.respond(to: trimmed, generating: AIQuickScheduledTask.self) {
                let data = response.content
                return QuickScheduledTaskPayload(
                    title: data.title.isEmpty ? trimmed : data.title,
                    startMinute: data.startMinute,
                    durationMinutes: data.durationMinutes,
                    iconName: Self.sanitizeIcon(data.iconName, fallbackForTitle: data.title),
                    colorToken: Self.sanitizeColorToken(data.colorToken),
                    notes: data.notes,
                    subtasks: data.subtasks
                )
            }
        }
        #endif

        return parseHeuristicQuickPrompt(trimmed, defaultStartMinute: defaultStartMinute)
    }

    /// Parser determinista para extraer hora, duración, icono y color de una frase en español o inglés.
    public func parseHeuristicQuickPrompt(_ text: String, defaultStartMinute: Int = 600) -> QuickScheduledTaskPayload {
        var detectedStart = defaultStartMinute
        var detectedDuration = 30

        // Detectar hora formato HH:MM o "a las HH"
        if let timeMatch = text.range(of: #"\b([01]?[0-9]|2[0-3]):([0-5][0-9])\b"#, options: .regularExpression) {
            let parts = String(text[timeMatch]).split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                let adjustedH = (h < 7 && text.localizedCaseInsensitiveContains("tarde")) ? h + 12 : h
                detectedStart = adjustedH * 60 + m
            }
        }

        // Detectar duración en minutos ("45 min", "15m") o horas ("2h", "1 hora")
        if let minMatch = text.range(of: #"\b(\d{1,3})\s*(min|minutos|m)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let digits = String(text[minMatch]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let mins = Int(digits), mins > 0 {
                detectedDuration = mins
            }
        } else if let hrMatch = text.range(of: #"\b(\d{1,2})\s*(h|hr|hora|horas)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let digits = String(text[hrMatch]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let hrs = Int(digits), hrs > 0 {
                detectedDuration = hrs * 60
            }
        }

        let icon = Self.inferIcon(for: text)
        let color = Self.inferColor(for: text)

        return QuickScheduledTaskPayload(
            title: text,
            startMinute: detectedStart,
            durationMinutes: detectedDuration,
            iconName: icon,
            colorToken: color,
            notes: "",
            subtasks: []
        )
    }

    public static func inferIcon(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("diseñ") || lower.contains("figma") || lower.contains("ui") || lower.contains("ux") {
            return "paintbrush.fill"
        } else if lower.contains("código") || lower.contains("code") || lower.contains("implement") || lower.contains("dev") || lower.contains("swift") {
            return "laptopcomputer"
        } else if lower.contains("reunión") || lower.contains("sync") || lower.contains("kickoff") || lower.contains("equipo") || lower.contains("team") {
            return "person.2.fill"
        } else if lower.contains("test") || lower.contains("prueba") || lower.contains("qa") || lower.contains("verific") {
            return "checkmark.shield.fill"
        } else if lower.contains("email") || lower.contains("correo") || lower.contains("mensaje") {
            return "at"
        } else if lower.contains("server") || lower.contains("api") || lower.contains("base de datos") || lower.contains("backend") {
            return "server.rack"
        } else if lower.contains("deporte") || lower.contains("gym") || lower.contains("correr") || lower.contains("run") {
            return "figure.run"
        } else if lower.contains("leer") || lower.contains("estudio") || lower.contains("doc") {
            return "book.fill"
        }
        return "doc.fill"
    }

    public static func inferColor(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("diseñ") || lower.contains("ui") { return "lavender" }
        if lower.contains("código") || lower.contains("code") || lower.contains("backend") { return "ocean" }
        if lower.contains("test") || lower.contains("qa") { return "teal" }
        if lower.contains("reunión") || lower.contains("sync") { return "amber" }
        return "coral"
    }

    private static func sanitizeIcon(_ raw: String, fallbackForTitle title: String) -> String {
        let allowed: Set<String> = [
            "doc.fill", "at", "laptopcomputer", "person.2.fill",
            "paintbrush.fill", "figure.run", "cart.fill", "book.fill",
            "phone.fill", "sparkles", "terminal.fill", "checklist",
            "server.rack", "chart.bar.fill", "checkmark.shield.fill", "cup.and.saucer.fill"
        ]
        if allowed.contains(raw) {
            return raw
        }
        return inferIcon(for: title)
    }

    private static func sanitizeColorToken(_ raw: String) -> String {
        let allowed: Set<String> = ["coral", "ocean", "teal", "lavender", "amber", "mint", "nightNavy"]
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowed.contains(clean) ? clean : "coral"
    }
}

/// DTO intermedio para transferir datos generados antes de persistir en SwiftData.
public struct GeneratedTaskPayload: Sendable {
    public var title: String
    public var notes: String
    public var startDate: Date
    public var endDate: Date
    public var estimatedDays: Int
    public var estimatedHours: Double
    public var sortOrder: Int
    public var iconName: String
    public var colorToken: String
    public var subtasks: [(title: String, hours: Double, notes: String)]

    public init(
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date,
        estimatedDays: Int,
        estimatedHours: Double? = nil,
        sortOrder: Int,
        iconName: String = "doc.fill",
        colorToken: String = "coral",
        subtasks: [(title: String, hours: Double, notes: String)] = []
    ) {
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.estimatedDays = max(1, estimatedDays)
        self.estimatedHours = estimatedHours ?? Double(max(1, estimatedDays) * 4)
        self.sortOrder = sortOrder
        self.iconName = iconName
        self.colorToken = colorToken
        self.subtasks = subtasks
    }
}
