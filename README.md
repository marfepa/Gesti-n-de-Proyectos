# PlanAI 🧭 — Gestión Inteligente de Proyectos para macOS

**PlanAI** es una aplicación nativa para macOS construida con SwiftUI, SwiftData, Swift Charts y el framework **FoundationModels** de Apple Intelligence.

Permite transformar descripciones de proyectos en lenguaje natural en un cronograma estructurado con diagrama de Gantt, ejecutando la inferencia completamente **on-device** en el Apple Neural Engine (ANE) con privacidad total y huella cero de servidores.

---

## Características Principales

1. **Descomposición con Apple Intelligence (On-Device LLM)**
   - Utiliza `LanguageModelSession` de `FoundationModels`.
   - **Guided Generation** mediante macros `@Generable` y `@Guide`: el modelo devuelve de forma determinista la estructura tipada `TaskPlan` / `SubtaskPlan` sin fragilidad de formato ni riesgo de fallo en el parseo JSON.

2. **Cálculo Determinista de Fechas**
   - El modelo de lenguaje estima las duraciones relativas y el orden secuencial lógico.
   - Swift y `Calendar.current` calculan las fechas exactas de inicio y fin de cada fase evitando solapamientos y gestionando días laborables.

3. **Visualización Interactiva tipo Gantt**
   - Implementado nativamente con **Swift Charts** usando `BarMark` horizontales.
   - Indicador dinámico de "Hoy" (`RuleMark`), desglose por duración en días y distinción cromática según el estado de la tarea (pendiente vs completada).

4. **Persistencia Robusta con SwiftData**
   - Modelos `@Model Project` y `@Model ProjectTask` con borrado en cascada y ordenación secuencial.
   - Datos guardados localmente en el Mac.

5. **Edición Manual Completa**
   - Creación, modificación de fechas/título/notas y eliminación manual de tareas sin necesidad de usar IA.
   - Opción para crear proyectos vacíos de forma directa.

6. **Soporte Bilingüe (Español / Inglés)**
   - Catálogos de localización integrados (`es.lproj` y `en.lproj`) adaptables al idioma del sistema.

7. **Resiliencia y Detección de Disponibilidad**
   - Monitorea `SystemLanguageModel.default.availability`.
   - Si Apple Intelligence no está activado o el dispositivo no es compatible, la app muestra un banner informativo claro y permite continuar mediante un fallback heurístico y gestión manual.

---

## Requisitos

- **macOS**: macOS 15.0 o superior (macOS 26+ para inferencia directa con Apple Intelligence on-device).
- **Hardware**: Mac con Apple Silicon (M1 o posterior) y Apple Intelligence activado en Ajustes del Sistema para las capacidades de IA local.
- **Xcode**: Xcode 16 o superior (Xcode 26 / beta para compilar contra los SDKs de FoundationModels).

---

## Estructura del Código

```
Gestion_Proyectos/
├── project.yml                       # Especificación declarativa para XcodeGen
├── Package.swift                     # Definición de Swift Package
├── PlanAI.xcodeproj                  # Proyecto nativo de Xcode
├── PlanAI/
│   ├── App/
│   │   └── PlanAIApp.swift           # Punto de entrada @main y contenedor SwiftData
│   ├── Models/
│   │   ├── Project.swift             # Modelo de persistencia SwiftData
│   │   ├── ProjectTask.swift         # Modelo de persistencia de tareas
│   │   └── GenerablePlan.swift       # DTOs @Generable (AITaskPlan, SubtaskPlan)
│   ├── Services/
│   │   ├── AIAvailabilityService.swift      # Monitor de estado de Apple Intelligence
│   │   └── TaskDecompositionService.swift   # Sesión LLM y cálculo de cronograma
│   ├── ViewModels/
│   │   └── ProjectViewModel.swift    # @Observable principal
│   ├── Views/
│   │   ├── ContentView.swift         # NavigationSplitView lateral y detalle
│   │   ├── ProjectDetailView.swift   # Selector de vistas (Gantt, Lista, Dividido)
│   │   ├── GanttChartView.swift      # Diagrama Gantt con Swift Charts
│   │   ├── TaskListView.swift        # Lista editable de tareas
│   │   ├── TaskEditSheet.swift       # Modal para añadir/editar tareas manualmente
│   │   ├── ProjectInputView.swift    # Formulario de entrada con IA y contador
│   │   └── AIStatusBanner.swift      # Banner de disponibilidad de IA
│   └── Localization/
│       └── Resources/
│           ├── es.lproj/Localizable.strings
│           └── en.lproj/Localizable.strings
└── Tests/
    └── PlanAITests/
        └── TaskDecompositionTests.swift     # Pruebas unitarias de cálculo de fechas
```

---

## Compilación y Ejecución

### Desde Xcode
Abre `PlanAI.xcodeproj` en Xcode y presiona `⌘ + R` para compilar y ejecutar en tu Mac.

### Regenerar el Proyecto Xcode
Si agregas archivos o modificas la configuración:
```bash
xcodegen generate
```

### Ejecutar Pruebas desde Terminal
```bash
swift test
```
