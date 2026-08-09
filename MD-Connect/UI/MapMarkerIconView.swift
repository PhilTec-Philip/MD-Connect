import Foundation
import SwiftUI

/// Fetches marker marker icons by their iconify name (e.g. `mdi:fire`) from the
/// public iconify API and converts the returned SVG path into a SwiftUI `Path`.
@MainActor
final class MapIconLoader {
    static let shared = MapIconLoader()

    private var cache: [String: Path] = [:]

    private init() {}

    /// Returns the parsed icon path (in a 24x24 viewBox) or nil if unavailable.
    func path(for icon: String) async -> Path? {
        if let hit = cache[icon] {
            return hit
        }
        for url in Self.urlCandidates(for: icon) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let svg = String(data: data, encoding: .utf8),
                      let d = Self.extractPathData(from: svg) else { continue }
                let path = SVGPathParser.path(from: d)
                cache[icon] = path
                return path
            } catch {
                continue
            }
        }
        return nil
    }

    /// Builds the Iconify API URLs for an icon name. Handles the formats the
    /// server stores: PascalCase component names (`FireIcon`), dynamic Iconify
    /// names (`i-mdi-fire`) and `mdi:fire` — all normalized first.
    private static func urlCandidates(for icon: String) -> [URL] {
        let name = normalizedIconName(icon)
        let colon = URL(string: "https://api.iconify.design/\(name).svg")
        let slash = URL(string: "https://api.iconify.design/\(name.replacingOccurrences(of: ":", with: "/")).svg")
        return [colon, slash].compactMap { $0 }
    }

    /// Normalizes any stored icon name into Iconify `prefix:name` form.
    ///
    /// The web stores marker icons as mdi-vue3 component names (e.g.
    /// `MapMarkerQuestionIcon`) or dynamic Iconify names (`i-mdi-help`); the
    /// web converts them with `convertComponentIconNameToDynamic`. We replicate
    /// that here so URLs and SF-fallback matching see `mdi:map-marker-question`.
    static func normalizedIconName(_ icon: String) -> String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") { return trimmed }

        var name = trimmed
        if name.hasPrefix("i-mdi-") {
            name = String(name.dropFirst(6))
        } else if name.hasSuffix("Icon") {
            name = String(name.dropLast(4))
        }

        let kebab = name
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1-$2", options: .regularExpression)
            .lowercased()
        return kebab.isEmpty ? "mdi:map-marker-question" : "mdi:\(kebab)"
    }

    /// Extracts the first `d` attribute from a simple `<path d="..."/>` SVG.
    private static func extractPathData(from svg: String) -> String? {
        guard let range = svg.range(of: "<path") else { return nil }
        let pathTag = svg[range.lowerBound...]
        guard let dStart = pathTag.range(of: "d=\"") else { return nil }
        var rest = pathTag[dStart.upperBound...]
        if let end = rest.range(of: "\"") {
            rest = rest[..<end.lowerBound]
        }
        let value = String(rest)
        return value.isEmpty ? nil : value
    }
}

/// Renders an iconify marker icon (SVG path) tinted with a color, falling back
/// to an SF Symbol when the icon is unknown or cannot be fetched.
struct MapMarkerIconView: View {
    let icon: String
    let color: Color
    var size: CGFloat = 18

    @State private var path: Path?

    private var normalizedIcon: String {
        MapIconLoader.normalizedIconName(icon)
    }

    private var fallbackSymbol: String {
        switch normalizedIcon {
        case "mdi:fire", "mdi:fire-truck", "mdi:fire-truck-fast": return "flame"
        case "mdi:ambulance", "mdi:medical-bag", "mdi:hospital-box": return "cross.case"
        case "mdi:police-badge", "mdi:shield-star", "mdi:shield-half-full": return "shield.lefthalf.filled"
        case "mdi:car", "mdi:car-sports": return "car"
        case "mdi:alert", "mdi:alert-circle", "mdi:alert-circle-outline": return "exclamationmark.triangle"
        case "mdi:anchor": return "anchor"
        case "mdi:star", "mdi:star-outline": return "star"
        case "mdi:heart", "mdi:heart-outline": return "heart"
        case "mdi:crosshairs", "mdi:target", "mdi:crosshairs-gps": return "scope"
        case "mdi:map-marker", "mdi:map-marker-outline", "mdi:map-marker-question", "mdi:map-marker-question-outline": return "mappin"
        case "mdi:book-open-variant", "mdi:book", "mdi:book-open": return "book"
        case "mdi:clipboard-text", "mdi:clipboard": return "clipboard"
        case "mdi:wrench": return "wrench"
        case "mdi:account", "mdi:account-circle": return "person"
        case "mdi:phone": return "phone"
        case "mdi:email", "mdi:email-outline": return "envelope"
        case "mdi:bank", "mdi:store": return "building.columns"
        case "mdi:emoticon", "mdi:help", "mdi:help-circle-outline": return "questionmark.circle"
        default: return "mappin"
        }
    }

    var body: some View {
        ZStack {
            if let path {
                path
                    .fill(color)
                    .frame(width: 24, height: 24)
                    .scaleEffect(size / 24)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.9))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .task(id: normalizedIcon) {
            path = await MapIconLoader.shared.path(for: normalizedIcon)
        }
    }
}
