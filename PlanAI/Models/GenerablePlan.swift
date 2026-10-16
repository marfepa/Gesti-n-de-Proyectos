import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Representa una subtarea accionable y detallada generada por FoundationModels.
@available(macOS 26.0, *)
@Generable(description: "Subtarea accionable dentro de una fase, con título descriptivo, horas estimadas y descripción detallada de qué hacer")
public struct AISubtaskDetail: Sendable {
    @Guide(description: "Título específico y accionable de la subtarea. No uses títulos genéricos como 'Preparación'. Describe qué se hace concretamente, por ejemplo: 'Crear esquema de base de datos con tablas de usuarios y permisos'")
    public var title: String

    @Guide(description: "Horas estimadas de trabajo efectivo para completar esta subtarea (mínimo 0.5 horas)", .range(0.5...160.0))
    public var estimatedHours: Double

    @Guide(description: "Descripción detallada paso a paso de qué hacer en esta subtarea: herramientas, técnicas, entregables específicos y criterios de finalización")
    public var notes: String

    public init(title: String, estimatedHours: Double, notes: String) {
        self.title = title
        self.estimatedHours = max(0.5, estimatedHours)
        self.notes = notes
    }
}

/// Representa el plan tipado para Guided Generation de Apple Intelligence en macOS 26+.
@available(macOS 26.0, *)
@Generable(description: "Plan estructurado de descomposición de un proyecto en etapas de trabajo lógicas y secuenciales")
public struct AITaskPlan: Sendable {
    @Guide(description: "Lista ordenada y cronológica de fases de trabajo necesarias para completar el proyecto")
    public var subtasks: [AISubtaskPlan]

    public init(subtasks: [AISubtaskPlan] = []) {
        self.subtasks = subtasks
    }
}

/// Representa la fase/tarea principal generada por FoundationModels.
@available(macOS 26.0, *)
@Generable(description: "Fase de trabajo con título, horas estimadas de trabajo efectivo, icono SF Symbol, color de categoría, notas y desglose de subtareas específicas")
public struct AISubtaskPlan: Sendable {
    @Guide(description: "Título conciso, profesional y accionable de la fase")
    public var title: String

    @Guide(description: "Horas estimadas de trabajo efectivo para completar esta fase (mínimo 0.5 horas)", .range(0.5...720.0))
    public var estimatedHours: Double

    @Guide(description: "Breve justificación de por qué es necesaria esta fase y cuál es su entregable")
    public var notes: String

    @Guide(description: "Nombre de icono SF Symbol adecuado para la tarea entre: laptopcomputer, paintbrush.fill, doc.fill, terminal.fill, server.rack, checkmark.shield.fill, chart.bar.fill, person.2.fill, sparkles, checklist")
    public var iconName: String

    @Guide(description: "Token de color para la fase entre: coral, ocean, teal, lavender, amber, mint")
    public var colorToken: String

    @Guide(description: "Lista de subtareas concretas y accionables que componen esta fase")
    public var subtasks: [AISubtaskDetail]

    public init(
        title: String,
        estimatedHours: Double,
        notes: String,
        iconName: String = "doc.fill",
        colorToken: String = "coral",
        subtasks: [AISubtaskDetail] = []
    ) {
        self.title = title
        self.estimatedHours = max(0.5, estimatedHours)
        self.notes = notes
        self.iconName = iconName
        self.colorToken = colorToken
        self.subtasks = subtasks
    }
}

/// Estructura generable para el asistente rápido "Structured AI" (lenguaje natural a tarea agendada).
@available(macOS 26.0, *)
@Generable(description: "Tarea extraída de una instrucción en lenguaje natural para agendar en el día")
public struct AIQuickScheduledTask: Sendable {
    @Guide(description: "Título claro y accionable de la tarea")
    public var title: String

    @Guide(description: "Minuto del día de inicio (ej. 9:00 AM = 540, 10:00 AM = 600, 4:00 PM = 960)", .range(360...1380))
    public var startMinute: Int

    @Guide(description: "Duración en minutos (15, 30, 45, 60, 90 o 120)", .range(15...240))
    public var durationMinutes: Int

    @Guide(description: "Icono SF Symbol entre: laptopcomputer, paintbrush.fill, doc.fill, at, person.2.fill, figure.run, book.fill, phone.fill, sparkles, checklist")
    public var iconName: String

    @Guide(description: "Token de color entre: coral, ocean, teal, lavender, amber, mint")
    public var colorToken: String

    @Guide(description: "Notas o contexto adicional")
    public var notes: String

    @Guide(description: "Lista breve de pasos o subtareas (máximo 4)")
    public var subtasks: [String]
}
#endif

/// Detalle de subtarea desacoplado de FoundationModels para modelos y tests.
public struct SubtaskDetailPlan: Sendable, Codable, Equatable {
    public var title: String
    public var estimatedHours: Double
    public var notes: String

    public init(title: String, estimatedHours: Double, notes: String = "") {
        self.title = title
        self.estimatedHours = max(0.25, estimatedHours)
        self.notes = notes
    }
}

/// Estructura de fase/tarea desacoplada, compatible con todas las versiones de macOS y persistencia.
public struct SubtaskPlan: Sendable, Codable, Equatable {
    public var title: String
    public var estimatedDays: Int
    public var estimatedHours: Double
    public var notes: String
    public var iconName: String
    public var colorToken: String
    public var subtaskDetails: [SubtaskDetailPlan]

    public init(
        title: String,
        estimatedDays: Int? = nil,
        estimatedHours: Double? = nil,
        notes: String = "",
        iconName: String = "doc.fill",
        colorToken: String = "coral",
        subtaskDetails: [SubtaskDetailPlan] = []
    ) {
        self.title = title
        let resolvedHours = estimatedHours ?? Double(max(1, estimatedDays ?? 1) * 4)
        let resolvedDays = estimatedDays ?? max(1, Int(ceil(resolvedHours / 4.0)))
        self.estimatedDays = max(1, resolvedDays)
        self.estimatedHours = max(0.5, resolvedHours)
        self.notes = notes
        self.iconName = iconName
        self.colorToken = colorToken
        self.subtaskDetails = subtaskDetails
    }
}

public struct TaskPlan: Sendable, Codable, Equatable {
    public var subtasks: [SubtaskPlan]

    public init(subtasks: [SubtaskPlan] = []) {
        self.subtasks = subtasks
    }
}
