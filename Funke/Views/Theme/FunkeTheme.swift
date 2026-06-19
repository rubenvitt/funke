import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Geteiltes „Glut"-Theme der Funke-App: warme Holzkohle/Papier-Palette mit
/// Akzent `#ef6c2f`, native System-Schrift, fette Headlines. Hell/Dunkel folgt
/// automatisch dem System-`colorScheme` (kein manueller Umschalter).
///
/// Werte stammen aus der Glut-Richtung des Claude-Design-Prototyps.
enum FunkeTheme {
    /// Markenakzent (Glut-Orange) — identisch in Hell & Dunkel.
    static let accent = Color(hex: 0xEF6C2F)

    // Flächen
    static let background = Color(light: 0xEFECE7, dark: 0x16110E)
    static let surface    = Color(light: 0xFFFFFF, dark: 0x211A15)
    static let surface2   = Color(light: 0xF6F1EC, dark: 0x2B221B)

    // Text
    static let text = Color(light: 0x1C1714, dark: 0xF4EDE5)
    static let dim  = Color(light: 0x867D73, dark: 0xA89E93)

    // Linien
    static let line  = Color(light: .black, lightAlpha: 0.09, dark: .white, darkAlpha: 0.10)
    static let line2 = Color(light: .black, lightAlpha: 0.05, dark: .white, darkAlpha: 0.055)

    // Akzent-Ableitungen (Hell schwächer als Dunkel)
    static let accentSoft = Color(light: 0xEF6C2F, lightAlpha: 0.08, dark: 0xEF6C2F, darkAlpha: 0.13)
    static let accentLine = Color(light: 0xEF6C2F, lightAlpha: 0.18, dark: 0xEF6C2F, darkAlpha: 0.28)

    // Überfällig-Rot
    static let red     = Color(light: 0xD2563F, dark: 0xFF7A6B)
    static let redBg   = Color(light: 0xD2563F, lightAlpha: 0.07, dark: 0xFF7A6B, darkAlpha: 0.12)
    static let redLine = Color(light: 0xD2563F, lightAlpha: 0.18, dark: 0xFF7A6B, darkAlpha: 0.28)

    // Tab-/Toast-Hintergründe
    static let barBackground = Color(light: 0xFFFFFF, lightAlpha: 0.82, dark: 0x211A15, darkAlpha: 0.82)
    static let toastBackground = Color(light: 0x26201B, dark: 0x2B221B)
    static let toastText = Color(hex: 0xF4EDE5)

    static let positive = Color(hex: 0x34C759)

    /// Eckenradius der Standard-Karten.
    static let cardRadius: CGFloat = 18
}

// MARK: - Farb-Hilfen

extension Color {
    /// Color aus 0xRRGGBB-Hexwert.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Dynamische Farbe, die je nach System-Erscheinungsbild zwischen zwei
    /// Werten umschaltet. Plattform-nativ (UIKit/AppKit), Fallback = hell.
    init(light: Color, dark: Color) {
        #if os(iOS)
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }

    /// Bequeme Variante mit Hexwerten.
    init(light: UInt32, dark: UInt32) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }

    /// Variante mit Hexwerten **und** getrennten Alphas für Hell/Dunkel.
    init(light: UInt32, lightAlpha: Double, dark: UInt32, darkAlpha: Double) {
        self.init(
            light: Color(hex: light, alpha: lightAlpha),
            dark: Color(hex: dark, alpha: darkAlpha)
        )
    }

    /// Variante mit Basis-`Color` + getrennten Alphas.
    init(light: Color, lightAlpha: Double, dark: Color, darkAlpha: Double) {
        self.init(
            light: light.opacity(lightAlpha),
            dark: dark.opacity(darkAlpha)
        )
    }
}

// MARK: - Typografie

extension View {
    /// Fette, leicht negativ gesperrte Headline im Glut-Stil (System-Font).
    func funkeTitle(_ size: CGFloat = 34) -> some View {
        self
            .font(.system(size: size, weight: .heavy))
            .tracking(-0.5)
            .foregroundStyle(FunkeTheme.text)
    }

    /// Versal-Section-Label (z. B. „CLICKUP", „ÜBERFÄLLIG").
    func funkeSectionLabel() -> some View {
        self
            .font(.system(size: 12, weight: .bold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(FunkeTheme.dim)
    }
}

// MARK: - Karte

/// Standard-Karte des Glut-Looks: abgerundete Fläche mit dezentem Schatten/Border.
struct FunkeCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(FunkeTheme.surface, in: RoundedRectangle(cornerRadius: FunkeTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FunkeTheme.cardRadius, style: .continuous)
                    .strokeBorder(FunkeTheme.line2, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Akzent-Kreis-Button (Senden)

/// Runder Akzent-Button mit Glow — der „Funke senden"-Knopf.
struct AccentCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(FunkeTheme.accent, in: Circle())
            .shadow(color: FunkeTheme.accent.opacity(0.6), radius: 12, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Fortschritts-Ring

/// Kreis-Fortschrittsanzeige (z. B. Execution-Ring auf „Heute").
struct ProgressRing: View {
    /// Fortschritt 0…1.
    var progress: Double
    var size: CGFloat = 52
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .stroke(FunkeTheme.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(FunkeTheme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: size * 0.32, weight: .heavy))
                .foregroundStyle(FunkeTheme.text)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

// MARK: - Toast

/// Kurzlebiger Bestätigungs-Toast am unteren Rand.
struct FunkeToast: View {
    let message: String
    var systemImage: String = "flame.fill"

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(FunkeTheme.accent)
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FunkeTheme.toastText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(FunkeTheme.toastBackground, in: Capsule())
        .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 10)
    }
}
