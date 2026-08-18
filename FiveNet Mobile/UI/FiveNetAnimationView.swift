import SwiftUI

/// Ladescreen-Animation im Stil des FiveNet-Social-Cards: ein dunkler
/// Hintergrund, über den viele X-Kreuze in den FiveNet-Markenfarben
/// (Cyan/Teal, Blau/Violett, Rot/Pink sowie fast unsichtbare dunkle Varianten)
/// schweben. Jedes Kreuz wird einzeln animiert (ein-/ausblenden + leichtes
/// Skalieren), mit eigener Dauer/Verzögerung/Phase — nie synchron.
///
/// Das zentrale FiveNet-Logo (`FiveNetLogo`-Asset) liegt statisch darüber.
struct FiveNetAnimationView: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    Canvas { context, size in
                        let palette = FiveNetSplashPalette()
                        // Tiefe: Hintergrund → normal → Vordergrund.
                        for layer in [FiveNetSplashLayer.background, .normal, .foreground] {
                            for particle in FiveNetSplashParticles.all where particle.layer == layer {
                                drawCross(particle, in: &context, size: size, t: t, palette: palette)
                            }
                        }
                    }
                    .ignoresSafeArea()

                    Image("FiveNetLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoWidth(in: proxy.size))
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                }
                .background(FiveNetSplashPalette.background.ignoresSafeArea())
            }
        }
    }

    /// Logo proportional zur View-Breite, aber gedeckelt, damit es auf
    /// kleinen wie großen Screens gleich gut aussieht.
    private func logoWidth(in size: CGSize) -> CGFloat {
        min(size.width * 0.22, 300)
    }

    /// Zeichnet ein einzelnes X-Kreuz: zwei schmale, abgerundete Balken um
    /// ±45° gedreht. Beide Balken werden in EINEN Pfad gelegt und gemeinsam
    /// gefüllt — dadurch wird die Überlappung in der Mitte nicht doppelt
    /// (kein kräftigeres Alpha am Kreuzungspunkt). Fade/Scale folgen einer
    /// Sinuswelle je Partikel (eigene Dauer + Verzögerung + Phase).
    private func drawCross(
        _ particle: FiveNetSplashParticle,
        in context: inout GraphicsContext,
        size: CGSize,
        t: TimeInterval,
        palette: FiveNetSplashPalette
    ) {
        let local = t + particle.delay
        let wave = sin(2 * .pi * (local / particle.duration) + particle.phase)
        // Sinus in 0...1: langsames Ein- und Ausblenden.
        let fade = 0.5 + 0.5 * wave
        // Leichtes Atmen in der Größe (eigenes Wave, leicht versetzt).
        let scaleWave = sin(2 * .pi * (local / particle.duration) + particle.phase + 1.3)
        let scale = 1.0 + 0.10 * scaleWave

        let opacity = particle.maxOpacity * fade
        guard opacity > 0.01 else { return }

        let center = CGPoint(
            x: particle.x * size.width,
            y: particle.y * size.height
        )
        // Kreuzlänge relativ zur kleineren Bildschirm-Dimension.
        let base = min(size.width, size.height)
        let length = particle.size * base * scale
        let thickness = particle.size * base * 0.30

        let color = particle.particleColor(in: palette).opacity(opacity)

        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)

        let barRect = CGRect(
            x: -length / 2,
            y: -thickness / 2,
            width: length,
            height: thickness
        )

        let cornerSize = CGSize(width: 1, height: 1)

        var cross = Path()
        for angle in [Double.pi / 4, -Double.pi / 4] {
            cross.addRoundedRect(
                in: barRect,
                cornerSize: cornerSize,
                transform: CGAffineTransform(rotationAngle: angle)
            )
        }
        ctx.fill(cross, with: .color(color))
    }
}

/// Tiefen-Ebenen der Kreuze (Hintergrund / normal / Vordergrund).
enum FiveNetSplashLayer {
    case background
    case normal
    case foreground
}

/// Farbfamilien der Kreuze — passend zur FiveNet-Marke (Logo + Social-Card).
enum FiveNetSplashColorFamily {
    case teal
    case blue
    case violet
    case red
    case dark
}

/// Ein einzelnes X-Kreuz mit festen, relativen Positionen (0...1) — keine
/// Zufallswerte pro Render, damit das Layout stabil und reproduzierbar ist.
struct FiveNetSplashParticle: Identifiable {
    let id: Int
    /// Relative X-Position (0...1) im View.
    let x: CGFloat
    /// Relative Y-Position (0...1) im View.
    let y: CGFloat
    /// Kreuzgröße relativ zur kleineren View-Dimension.
    let size: CGFloat
    let family: FiveNetSplashColorFamily
    /// Maximale Deckkraft beim Animation-Scheitel.
    let maxOpacity: Double
    /// Dauer einer vollen Ein/Aus-Phase in Sekunden.
    let duration: TimeInterval
    /// Verzögerung, bis die Welle startet.
    let delay: TimeInterval
    /// Start-Phase der Sinuswelle (0...1), versetzt die Welle dauerhaft.
    let phase: Double
    /// Tiefen-Ebene des Kreuzes.
    let layer: FiveNetSplashLayer

    func particleColor(in palette: FiveNetSplashPalette) -> Color {
        switch family {
        case .teal: return palette.teal
        case .blue: return palette.blue
        case .violet: return palette.violet
        case .red: return palette.red
        case .dark: return palette.dark
        }
    }
}

/// FiveNet-Markenfarbpalette, extrahiert aus dem Social-Card-Referenzbild.
struct FiveNetSplashPalette {
    /// Fast schwarzer Hintergrund (#16171A).
    static let background = Color(red: 22 / 255, green: 23 / 255, blue: 26 / 255)

    let teal = Color(red: 36 / 255, green: 175 / 255, blue: 175 / 255)
    let blue = Color(red: 89 / 255, green: 171 / 255, blue: 255 / 255)
    let violet = Color(red: 144 / 255, green: 96 / 255, blue: 240 / 255)
    let red = Color(red: 237 / 255, green: 62 / 255, blue: 86 / 255)
    /// Fast unsichtbare, dunkle Kreuz-Variante.
    let dark = Color(red: 40 / 255, green: 60 / 255, blue: 66 / 255)
}

/// Festes Partikel-Set: Positionen, Größen und Farben spiegeln die
/// X-Verteilung des Referenzbilds (1280×640) wider.
enum FiveNetSplashParticles {
    static let all: [FiveNetSplashParticle] = [
        // MARK: Hintergrund (dunkel, kaum sichtbar)
        FiveNetSplashParticle(id: 0, x: 0.245, y: 0.031, size: 0.077, family: .dark, maxOpacity: 0.22, duration: 5.0, delay: 0.0, phase: 0.00, layer: .background),
        FiveNetSplashParticle(id: 1, x: 0.402, y: 0.030, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 5.7, delay: 0.55, phase: 0.62, layer: .background),
        FiveNetSplashParticle(id: 2, x: 0.558, y: 0.030, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 6.4, delay: 1.1, phase: 0.24, layer: .background),
        FiveNetSplashParticle(id: 4, x: 0.050, y: 0.109, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 7.8, delay: 2.2, phase: 0.47, layer: .background),
        FiveNetSplashParticle(id: 7, x: 0.918, y: 0.093, size: 0.047, family: .dark, maxOpacity: 0.22, duration: 6.4, delay: 0.0, phase: 0.33, layer: .background),
        FiveNetSplashParticle(id: 8, x: 0.363, y: 0.109, size: 0.074, family: .dark, maxOpacity: 0.22, duration: 7.1, delay: 0.55, phase: 0.94, layer: .background),
        FiveNetSplashParticle(id: 9, x: 0.089, y: 0.187, size: 0.080, family: .dark, maxOpacity: 0.22, duration: 7.8, delay: 1.1, phase: 0.56, layer: .background),
        FiveNetSplashParticle(id: 11, x: 0.363, y: 0.187, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 5.7, delay: 2.2, phase: 0.80, layer: .background),
        FiveNetSplashParticle(id: 16, x: 0.987, y: 0.187, size: 0.077, family: .dark, maxOpacity: 0.22, duration: 5.7, delay: 1.1, phase: 0.89, layer: .background),
        FiveNetSplashParticle(id: 19, x: 0.246, y: 0.265, size: 0.075, family: .dark, maxOpacity: 0.22, duration: 7.8, delay: 2.75, phase: 0.74, layer: .background),
        FiveNetSplashParticle(id: 20, x: 0.324, y: 0.266, size: 0.077, family: .dark, maxOpacity: 0.22, duration: 5.0, delay: 3.3, phase: 0.36, layer: .background),
        FiveNetSplashParticle(id: 21, x: 0.987, y: 0.266, size: 0.070, family: .dark, maxOpacity: 0.22, duration: 5.7, delay: 0.0, phase: 0.98, layer: .background),
        FiveNetSplashParticle(id: 22, x: 0.058, y: 0.281, size: 0.046, family: .dark, maxOpacity: 0.22, duration: 6.4, delay: 0.55, phase: 0.60, layer: .background),
        FiveNetSplashParticle(id: 29, x: 0.089, y: 0.422, size: 0.078, family: .dark, maxOpacity: 0.22, duration: 7.8, delay: 0.55, phase: 0.92, layer: .background),
        FiveNetSplashParticle(id: 30, x: 0.246, y: 0.422, size: 0.077, family: .dark, maxOpacity: 0.22, duration: 5.0, delay: 1.1, phase: 0.54, layer: .background),
        FiveNetSplashParticle(id: 31, x: 0.714, y: 0.422, size: 0.077, family: .dark, maxOpacity: 0.22, duration: 5.7, delay: 1.65, phase: 0.16, layer: .background),
        FiveNetSplashParticle(id: 34, x: 0.363, y: 0.500, size: 0.080, family: .dark, maxOpacity: 0.22, duration: 7.8, delay: 3.3, phase: 0.01, layer: .background),
        FiveNetSplashParticle(id: 39, x: 0.324, y: 0.500, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 7.8, delay: 2.2, phase: 0.10, layer: .background),
        FiveNetSplashParticle(id: 40, x: 0.097, y: 0.516, size: 0.047, family: .dark, maxOpacity: 0.22, duration: 5.0, delay: 2.75, phase: 0.72, layer: .background),
        FiveNetSplashParticle(id: 43, x: 0.800, y: 0.580, size: 0.058, family: .dark, maxOpacity: 0.22, duration: 7.1, delay: 0.55, phase: 0.57, layer: .background),
        FiveNetSplashParticle(id: 44, x: 0.136, y: 0.562, size: 0.043, family: .dark, maxOpacity: 0.22, duration: 7.8, delay: 1.1, phase: 0.19, layer: .background),
        FiveNetSplashParticle(id: 47, x: 0.050, y: 0.657, size: 0.075, family: .dark, maxOpacity: 0.22, duration: 6.4, delay: 2.75, phase: 0.05, layer: .background),
        FiveNetSplashParticle(id: 48, x: 0.871, y: 0.656, size: 0.076, family: .dark, maxOpacity: 0.22, duration: 7.1, delay: 3.3, phase: 0.66, layer: .background),
        FiveNetSplashParticle(id: 55, x: 0.246, y: 0.813, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 5.0, delay: 3.3, phase: 0.99, layer: .background),
        FiveNetSplashParticle(id: 62, x: 0.285, y: 0.891, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 6.4, delay: 3.3, phase: 0.32, layer: .background),
        FiveNetSplashParticle(id: 63, x: 0.441, y: 0.891, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 7.1, delay: 0.0, phase: 0.93, layer: .background),
        FiveNetSplashParticle(id: 65, x: 0.871, y: 0.891, size: 0.079, family: .dark, maxOpacity: 0.22, duration: 5.0, delay: 1.1, phase: 0.17, layer: .background),
        FiveNetSplashParticle(id: 67, x: 0.207, y: 0.891, size: 0.073, family: .dark, maxOpacity: 0.22, duration: 6.4, delay: 2.2, phase: 0.41, layer: .background),
        FiveNetSplashParticle(id: 68, x: 0.761, y: 0.907, size: 0.047, family: .dark, maxOpacity: 0.22, duration: 7.1, delay: 2.75, phase: 0.02, layer: .background),

        // MARK: Normal (farbige Kreuze)
        FiveNetSplashParticle(id: 3, x: 0.605, y: 0.015, size: 0.047, family: .violet, maxOpacity: 0.75, duration: 6.7, delay: 1.95, phase: 0.85, layer: .normal),
        FiveNetSplashParticle(id: 6, x: 0.871, y: 0.109, size: 0.081, family: .teal, maxOpacity: 0.75, duration: 4.0, delay: 3.9, phase: 0.71, layer: .normal),
        FiveNetSplashParticle(id: 12, x: 0.597, y: 0.187, size: 0.082, family: .violet, maxOpacity: 0.75, duration: 4.0, delay: 1.95, phase: 0.42, layer: .normal),
        FiveNetSplashParticle(id: 13, x: 0.793, y: 0.187, size: 0.081, family: .teal, maxOpacity: 0.75, duration: 4.9, delay: 2.6, phase: 0.03, layer: .normal),
        FiveNetSplashParticle(id: 14, x: 0.902, y: 0.172, size: 0.048, family: .violet, maxOpacity: 0.75, duration: 5.8, delay: 3.25, phase: 0.65, layer: .normal),
        FiveNetSplashParticle(id: 17, x: 0.013, y: 0.250, size: 0.057, family: .red, maxOpacity: 0.75, duration: 8.5, delay: 5.2, phase: 0.51, layer: .normal),
        FiveNetSplashParticle(id: 18, x: 0.285, y: 0.266, size: 0.082, family: .teal, maxOpacity: 0.75, duration: 4.0, delay: 0.0, phase: 0.12, layer: .normal),
        FiveNetSplashParticle(id: 23, x: 0.292, y: 0.328, size: 0.047, family: .red, maxOpacity: 0.75, duration: 8.5, delay: 3.25, phase: 0.21, layer: .normal),
        FiveNetSplashParticle(id: 24, x: 0.324, y: 0.344, size: 0.082, family: .red, maxOpacity: 0.75, duration: 4.0, delay: 3.9, phase: 0.83, layer: .normal),
        FiveNetSplashParticle(id: 26, x: 0.793, y: 0.344, size: 0.082, family: .teal, maxOpacity: 0.75, duration: 5.8, delay: 5.2, phase: 0.07, layer: .normal),
        FiveNetSplashParticle(id: 27, x: 0.785, y: 0.406, size: 0.048, family: .red, maxOpacity: 0.75, duration: 6.7, delay: 0.0, phase: 0.69, layer: .normal),
        FiveNetSplashParticle(id: 28, x: 0.910, y: 0.422, size: 0.081, family: .red, maxOpacity: 0.75, duration: 7.6, delay: 0.65, phase: 0.30, layer: .normal),
        FiveNetSplashParticle(id: 32, x: 0.082, y: 0.484, size: 0.048, family: .teal, maxOpacity: 0.75, duration: 5.8, delay: 3.25, phase: 0.78, layer: .normal),
        FiveNetSplashParticle(id: 33, x: 0.285, y: 0.500, size: 0.082, family: .teal, maxOpacity: 0.75, duration: 6.7, delay: 3.9, phase: 0.39, layer: .normal),
        FiveNetSplashParticle(id: 36, x: 0.714, y: 0.500, size: 0.082, family: .red, maxOpacity: 0.75, duration: 4.0, delay: 0.0, phase: 0.25, layer: .normal),
        FiveNetSplashParticle(id: 37, x: 0.871, y: 0.500, size: 0.082, family: .teal, maxOpacity: 0.75, duration: 4.9, delay: 0.65, phase: 0.87, layer: .normal),
        FiveNetSplashParticle(id: 38, x: 0.910, y: 0.500, size: 0.082, family: .teal, maxOpacity: 0.75, duration: 5.8, delay: 1.3, phase: 0.48, layer: .normal),
        FiveNetSplashParticle(id: 41, x: 0.168, y: 0.578, size: 0.082, family: .teal, maxOpacity: 0.75, duration: 8.5, delay: 3.25, phase: 0.34, layer: .normal),
        FiveNetSplashParticle(id: 42, x: 0.675, y: 0.578, size: 0.082, family: .teal, maxOpacity: 0.75, duration: 4.0, delay: 3.9, phase: 0.96, layer: .normal),
        FiveNetSplashParticle(id: 46, x: 0.714, y: 0.656, size: 0.082, family: .violet, maxOpacity: 0.75, duration: 7.6, delay: 0.65, phase: 0.43, layer: .normal),
        FiveNetSplashParticle(id: 49, x: 0.285, y: 0.734, size: 0.082, family: .red, maxOpacity: 0.75, duration: 4.9, delay: 2.6, phase: 0.28, layer: .normal),
        FiveNetSplashParticle(id: 51, x: 0.910, y: 0.734, size: 0.082, family: .red, maxOpacity: 0.75, duration: 6.7, delay: 3.9, phase: 0.52, layer: .normal),
        FiveNetSplashParticle(id: 52, x: 0.058, y: 0.750, size: 0.048, family: .red, maxOpacity: 0.75, duration: 7.6, delay: 4.55, phase: 0.14, layer: .normal),
        FiveNetSplashParticle(id: 53, x: 0.207, y: 0.813, size: 0.081, family: .teal, maxOpacity: 0.75, duration: 8.5, delay: 5.2, phase: 0.75, layer: .normal),
        FiveNetSplashParticle(id: 54, x: 0.871, y: 0.813, size: 0.082, family: .red, maxOpacity: 0.75, duration: 4.0, delay: 0.0, phase: 0.37, layer: .normal),
        FiveNetSplashParticle(id: 56, x: 0.941, y: 0.797, size: 0.048, family: .red, maxOpacity: 0.75, duration: 5.8, delay: 1.3, phase: 0.61, layer: .normal),
        FiveNetSplashParticle(id: 57, x: 0.050, y: 0.891, size: 0.082, family: .violet, maxOpacity: 0.75, duration: 6.7, delay: 1.95, phase: 0.23, layer: .normal),
        FiveNetSplashParticle(id: 58, x: 0.167, y: 0.891, size: 0.082, family: .violet, maxOpacity: 0.75, duration: 7.6, delay: 2.6, phase: 0.84, layer: .normal),
        FiveNetSplashParticle(id: 59, x: 0.675, y: 0.891, size: 0.082, family: .violet, maxOpacity: 0.75, duration: 8.5, delay: 3.25, phase: 0.46, layer: .normal),
        FiveNetSplashParticle(id: 61, x: 0.253, y: 0.875, size: 0.047, family: .red, maxOpacity: 0.75, duration: 4.9, delay: 4.55, phase: 0.70, layer: .normal),
        FiveNetSplashParticle(id: 64, x: 0.746, y: 0.876, size: 0.047, family: .red, maxOpacity: 0.75, duration: 7.6, delay: 0.65, phase: 0.55, layer: .normal),
        FiveNetSplashParticle(id: 66, x: 0.949, y: 0.891, size: 0.080, family: .teal, maxOpacity: 0.75, duration: 4.0, delay: 1.95, phase: 0.79, layer: .normal),
        FiveNetSplashParticle(id: 69, x: 0.402, y: 0.969, size: 0.079, family: .teal, maxOpacity: 0.75, duration: 6.7, delay: 3.9, phase: 0.64, layer: .normal),
        FiveNetSplashParticle(id: 71, x: 0.675, y: 0.969, size: 0.079, family: .violet, maxOpacity: 0.75, duration: 8.5, delay: 5.2, phase: 0.88, layer: .normal),
        FiveNetSplashParticle(id: 72, x: 0.987, y: 0.969, size: 0.077, family: .teal, maxOpacity: 0.75, duration: 4.0, delay: 0.0, phase: 0.50, layer: .normal),

        // MARK: Vordergrund (größere, hellere Kreuze)
        FiveNetSplashParticle(id: 5, x: 0.089, y: 0.109, size: 0.093, family: .teal, maxOpacity: 1.0, duration: 8.5, delay: 3.25, phase: 0.09, layer: .foreground),
        FiveNetSplashParticle(id: 10, x: 0.175, y: 0.172, size: 0.055, family: .red, maxOpacity: 1.0, duration: 7.6, delay: 0.65, phase: 0.18, layer: .foreground),
        FiveNetSplashParticle(id: 15, x: 0.949, y: 0.187, size: 0.094, family: .violet, maxOpacity: 1.0, duration: 6.7, delay: 3.9, phase: 0.27, layer: .foreground),
        FiveNetSplashParticle(id: 25, x: 0.636, y: 0.344, size: 0.094, family: .teal, maxOpacity: 1.0, duration: 4.9, delay: 4.55, phase: 0.45, layer: .foreground),
        FiveNetSplashParticle(id: 35, x: 0.636, y: 0.500, size: 0.094, family: .teal, maxOpacity: 1.0, duration: 8.5, delay: 5.2, phase: 0.63, layer: .foreground),
        FiveNetSplashParticle(id: 45, x: 0.675, y: 0.656, size: 0.094, family: .violet, maxOpacity: 1.0, duration: 6.7, delay: 0.0, phase: 0.81, layer: .foreground),
        FiveNetSplashParticle(id: 50, x: 0.793, y: 0.734, size: 0.094, family: .teal, maxOpacity: 1.0, duration: 5.8, delay: 3.25, phase: 0.90, layer: .foreground),
        FiveNetSplashParticle(id: 60, x: 0.714, y: 0.891, size: 0.094, family: .teal, maxOpacity: 1.0, duration: 4.0, delay: 3.9, phase: 0.08, layer: .foreground),
        FiveNetSplashParticle(id: 70, x: 0.558, y: 0.969, size: 0.095, family: .red, maxOpacity: 1.0, duration: 7.6, delay: 4.55, phase: 0.26, layer: .foreground),
    ]
}

#Preview {
    FiveNetAnimationView()
}
