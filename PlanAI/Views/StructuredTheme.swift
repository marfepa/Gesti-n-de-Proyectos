import SwiftUI

/// Token de color personalizable estilo Structured para proyectos, tareas y tema de acento.
public enum StructuredColorToken: String, CaseIterable, Identifiable, Codable, Sendable {
    case coral = "coral"
    case ocean = "ocean"
    case teal = "teal"
    case lavender = "lavender"
    case amber = "amber"
    case mint = "mint"
    case nightNavy = "nightNavy"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .coral: return String(localized: "Coral")
        case .ocean: return String(localized: "Océano")
        case .teal: return String(localized: "Turquesa")
        case .lavender: return String(localized: "Lavanda")
        case .amber: return String(localized: "Ámbar")
        case .mint: return String(localized: "Menta")
        case .nightNavy: return String(localized: "Noche")
        }
    }

    public var primaryColor: Color {
        switch self {
        case .coral: return StructuredTheme.coral
        case .ocean: return StructuredTheme.ocean
        case .teal: return StructuredTheme.teal
        case .lavender: return StructuredTheme.lavender
        case .amber: return StructuredTheme.amber
        case .mint: return StructuredTheme.mint
        case .nightNavy: return StructuredTheme.nightNavy
        }
    }

    public var lightColor: Color {
        switch self {
        case .coral: return StructuredTheme.coralLight
        case .ocean: return StructuredTheme.ocean.opacity(0.16)
        case .teal: return StructuredTheme.teal.opacity(0.16)
        case .lavender: return StructuredTheme.lavender.opacity(0.16)
        case .amber: return StructuredTheme.amber.opacity(0.16)
        case .mint: return StructuredTheme.mint.opacity(0.16)
        case .nightNavy: return StructuredTheme.nightNavyLight
        }
    }

    public static func resolve(_ raw: String?) -> StructuredColorToken {
        guard let raw, let token = StructuredColorToken(rawValue: raw) else {
            return .coral
        }
        return token
    }
}

/// Sistema de diseño exacto de Structured.
/// Recrea fielmente la paleta coral/salmón, el azul marino nocturno,
/// el lienzo gris cálido, las tarjetas blancas flotantes con radio de 32pt
/// y la tipografía redondeada característica.
public enum StructuredTheme {
    // MARK: - Paleta Oficial de Structured
    /// Color salmón/coral icónico de Structured
    public static let coral = Color(red: 1.0, green: 0.44, blue: 0.42)          // #FF706B
    public static let coralHover = Color(red: 0.95, green: 0.38, blue: 0.36)
    public static let coralLight = Color(red: 1.0, green: 0.92, blue: 0.91)      // #FFEBE8
    public static let coralMuted = Color(red: 1.0, green: 0.44, blue: 0.42).opacity(0.18)

    /// Azul marino noche para rutinas como "Wind Down"
    public static let nightNavy = Color(red: 0.28, green: 0.38, blue: 0.48)       // #47617A
    public static let nightNavyLight = Color(red: 0.28, green: 0.38, blue: 0.48).opacity(0.15)

    /// Colores de apoyo para categorías
    public static let ocean = Color(red: 0.22, green: 0.58, blue: 0.98)
    public static let teal = Color(red: 0.22, green: 0.74, blue: 0.72)
    public static let lavender = Color(red: 0.68, green: 0.55, blue: 0.94)
    public static let amber = Color(red: 1.0, green: 0.65, blue: 0.25)
    public static let mint = Color(red: 0.30, green: 0.80, blue: 0.55)

    /// Catálogo de iconos SF Symbols recomendados para tareas y proyectos
    public static let curatedIcons: [String] = [
        "doc.fill", "at", "laptopcomputer", "person.2.fill",
        "paintbrush.fill", "figure.run", "cart.fill", "book.fill",
        "phone.fill", "sparkles", "terminal.fill", "checklist",
        "server.rack", "chart.bar.fill", "checkmark.shield.fill", "cup.and.saucer.fill"
    ]

    // MARK: - Fondos y Superficies de Structured
    /// Lienzo exterior (gris suave/cálido de Structured)
    public static func canvasBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.14)
            : Color(red: 0.95, green: 0.95, blue: 0.96) // #F2F2F5
    }

    /// Hoja blanca flotante del Timeline (radio 32pt)
    public static func sheetBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.21)
            : Color.white
    }

    /// Barra / tirador superior de la tarjeta (grab handle)
    public static let grabHandleColor = Color.gray.opacity(0.28)

    // MARK: - Radios de Esquinas de Structured
    public static let sheetCornerRadius: CGFloat = 32.0
    public static let cardCornerRadius: CGFloat = 18.0
    public static let pillCornerRadius: CGFloat = 24.0
    public static let circleIconSize: CGFloat = 46.0

    /// Mapeo de prioridad de proyecto a colores Structured
    public static func color(for priority: ProjectPriority) -> Color {
        switch priority {
        case .baja: return nightNavy
        case .media: return coral
        case .alta: return amber
        case .urgente: return Color(red: 0.95, green: 0.25, blue: 0.25)
        }
    }

    /// Devuelve el color primario asociado a un token de color
    public static func color(forToken token: String?) -> Color {
        StructuredColorToken.resolve(token).primaryColor
    }

    /// Devuelve el color claro de fondo asociado a un token de color
    public static func lightColor(forToken token: String?) -> Color {
        StructuredColorToken.resolve(token).lightColor
    }
}

// MARK: - Modificador de Hoja Flotante Structured
public struct StructuredSheetModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .background(StructuredTheme.sheetBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: StructuredTheme.sheetCornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 16, y: 4)
    }
}

public struct StructuredCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var isHighlighted: Bool = false
    public var highlightColor: Color = StructuredTheme.coral
    public var cornerRadius: CGFloat = StructuredTheme.cardCornerRadius

    public func body(content: Content) -> some View {
        content
            .background(StructuredTheme.sheetBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isHighlighted ? highlightColor : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06),
                        lineWidth: isHighlighted ? 2.0 : 1.0
                    )
            )
            .shadow(
                color: isHighlighted
                    ? highlightColor.opacity(0.18)
                    : Color.black.opacity(colorScheme == .dark ? 0.20 : 0.04),
                radius: isHighlighted ? 8 : 4,
                y: isHighlighted ? 3 : 1
            )
    }
}

public extension View {
    func structuredFloatingSheet() -> some View {
        self.modifier(StructuredSheetModifier())
    }

    func structuredCard(
        isHighlighted: Bool = false,
        highlightColor: Color = StructuredTheme.coral,
        cornerRadius: CGFloat = StructuredTheme.cardCornerRadius
    ) -> some View {
        self.modifier(
            StructuredCardModifier(
                isHighlighted: isHighlighted,
                highlightColor: highlightColor,
                cornerRadius: cornerRadius
            )
        )
    }
}
