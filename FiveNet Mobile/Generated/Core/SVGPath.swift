import Foundation
import SwiftUI

/// Minimal SVG path parser for monochrome Material Design icons as served by
/// the FiveNet server (`IconMarker.icon` names like `mdi:fire`). The iconify
/// API returns simple `<path d="...">` SVGs with a `viewBox` of 24x24, which is
/// all we need to convert into a SwiftUI `Path`.
enum SVGPathParser {
    /// Parses an SVG path `d` string into a SwiftUI `Path`.
    static func path(from d: String) -> Path {
        var path = Path()
        let commands = tokenize(d)

        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCommand: Character?
        var lastControl: CGPoint?

        var index = 0
        while index < commands.count {
            let token = commands[index]
            let command: Character
            if let c = token.first, token.count == 1, "MmLlHhVvCcSsQqTtAaZz".contains(c) {
                command = token.first!
                index += 1
            } else if let c = lastCommand {
                command = c
            } else {
                break
            }
            lastCommand = command

            let relative = command.isLowercase
            let upper = Character(String(command).uppercased())

            func nextPoints(_ count: Int) -> [CGPoint] {
                var points: [CGPoint] = []
                var n = count
                while n > 0 && index < commands.count {
                    if let x = Double(commands[index]) {
                        if index + 1 < commands.count, let y = Double(commands[index + 1]) {
                            points.append(CGPoint(x: x, y: y))
                            index += 2
                        } else {
                            index += 1
                            break
                        }
                    } else {
                        index += 1
                        break
                    }
                    n -= 1
                }
                return points
            }

            func point(_ p: CGPoint) -> CGPoint {
                relative ? CGPoint(x: current.x + p.x, y: current.y + p.y) : p
            }

            switch upper {
            case "M":
                guard let p = nextPoints(1).first else { break }
                let target = point(p)
                path.move(to: target)
                current = target
                start = target
                lastControl = nil
                // Subsequent implicit coordinate pairs are lines (per SVG spec).
                lastCommand = relative ? "l" : "L"
            case "L":
                guard let p = nextPoints(1).first else { break }
                let target = point(p)
                path.addLine(to: target)
                current = target
                lastControl = nil
            case "H":
                if let x = index < commands.count ? Double(commands[index]) : nil {
                    index += 1
                    let xVal = relative ? current.x + x : x
                    let target = CGPoint(x: xVal, y: current.y)
                    path.addLine(to: target)
                    current = target
                }
                lastControl = nil
            case "V":
                if let y = index < commands.count ? Double(commands[index]) : nil {
                    index += 1
                    let yVal = relative ? current.y + y : y
                    let target = CGPoint(x: current.x, y: yVal)
                    path.addLine(to: target)
                    current = target
                }
                lastControl = nil
            case "C":
                let ps = nextPoints(3)
                guard ps.count == 3 else { break }
                let c1 = point(ps[0]), c2 = point(ps[1]), end = point(ps[2])
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastControl = c2
            case "S":
                let ps = nextPoints(2)
                guard ps.count == 2 else { break }
                let c1: CGPoint
                if let lc = lastControl, "CcSs".contains(lastCommand ?? " ") {
                    c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    c1 = current
                }
                let c2 = point(ps[0]), end = point(ps[1])
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastControl = c2
            case "Q":
                let ps = nextPoints(2)
                guard ps.count == 2 else { break }
                let control = point(ps[0]), end = point(ps[1])
                path.addQuadCurve(to: end, control: control)
                current = end
                lastControl = control
            case "T":
                guard let p = nextPoints(1).first else { break }
                let end = point(p)
                let control: CGPoint
                if let lc = lastControl, "QqTt".contains(lastCommand ?? " ") {
                    control = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    control = current
                }
                path.addQuadCurve(to: end, control: control)
                current = end
                lastControl = control
            case "A":
                // SVG arcs are converted to cubic beziers (approximation).
                guard index + 7 <= commands.count,
                      let rx = Double(commands[index]), let ry = Double(commands[index + 1]),
                      let rot = Double(commands[index + 2]), let largeArc = Double(commands[index + 3]),
                      let sweep = Double(commands[index + 4]), let ex = Double(commands[index + 5]),
                      let ey = Double(commands[index + 6]) else {
                    // Skip unrecognized arc parameters.
                    var skip = 0
                    while skip < 7 && index < commands.count {
                        if Double(commands[index]) != nil { skip += 1 }
                        index += 1
                    }
                    break
                }
                index += 7
                let end = relative
                    ? CGPoint(x: current.x + ex, y: current.y + ey)
                    : CGPoint(x: ex, y: ey)
                let arcs = arcToCubics(
                    from: current, to: end,
                    rx: abs(rx), ry: abs(ry),
                    rotationDegrees: rot,
                    largeArc: largeArc != 0,
                    sweep: sweep != 0
                )
                for arc in arcs {
                    path.addCurve(to: arc.end, control1: arc.c1, control2: arc.c2)
                }
                current = end
                lastControl = nil
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                break
            }
        }
        return path
    }

    /// Splits an SVG path string into command letters and numeric tokens.
    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var number = ""
        var isInNumber = false
        var lastWasExponent = false

        func flushNumber() {
            if isInNumber {
                tokens.append(number)
                number = ""
                isInNumber = false
            }
        }

        for scalar in d.unicodeScalars {
            let c = Character(scalar)
            if "MmHhLlVvCcSsQqTtAaZz".contains(c) {
                flushNumber()
                tokens.append(String(c))
            } else if scalar.value == 0x20 || scalar.value == 0x2C || scalar.value == 0x0A || scalar.value == 0x0D || scalar.value == 0x09 {
                // space, comma, newline, CR, tab
                flushNumber()
            } else if scalar.value == 0x2D {
                // minus sign: separator between numbers unless after exponent
                if isInNumber && !lastWasExponent {
                    flushNumber()
                }
                number.append(c)
                isInNumber = true
                lastWasExponent = false
            } else if scalar.value == 0x2E {
                // dot: a second dot starts a new number (e.g. iconify compresses
                // "4.17,.45" into "4.17.45"), so flush the current number first.
                if isInNumber && (number.contains(".") || number.contains("e") || number.contains("E")) {
                    flushNumber()
                }
                number.append(c)
                isInNumber = true
                lastWasExponent = false
            } else if c == "e" || c == "E" {
                number.append(c)
                isInNumber = true
                lastWasExponent = true
            } else if c.isNumber {
                number.append(c)
                isInNumber = true
                lastWasExponent = false
            } else {
                flushNumber()
            }
        }
        flushNumber()
        return tokens
    }

    // MARK: - Arc -> cubic conversion

    private struct CubicArc {
        let c1: CGPoint
        let c2: CGPoint
        let end: CGPoint
    }

    private static func arcToCubics(from start: CGPoint, to end: CGPoint, rx: Double, ry: Double, rotationDegrees: Double, largeArc: Bool, sweep: Bool) -> [CubicArc] {
        // Per SVG spec, approximate an elliptical arc with one or more cubic
        // bezier segments (endpoint -> center parameterization).
        if rx == 0 || ry == 0 || start == end {
            return [CubicArc(c1: start, c2: end, end: end)]
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        // Step 1: compute (x1', y1').
        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Correct out-of-range radii.
        var rx = rx, ry = ry
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }

        // Step 2: compute (cx', cy').
        let sign: Double = largeArc == sweep ? -1 : 1
        let rxSq = rx * rx, rySq = ry * ry
        let x1pSq = x1p * x1p, y1pSq = y1p * y1p
        let numerator = max(0, rxSq * rySq - rxSq * y1pSq - rySq * x1pSq)
        let denominator = rxSq * y1pSq + rySq * x1pSq
        let coef = sign * sqrt(numerator / denominator)
        let cxp = coef * ((rx * y1p) / ry)
        let cyp = coef * (-((ry * x1p) / rx))

        // Step 3: compute center (cx, cy) and angles.
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        let dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
            .truncatingRemainder(dividingBy: 2 * .pi)

        var deltaTheta = dTheta
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        // Step 4: split into segments of at most 90 degrees and convert each.
        let segments = Int(ceil(abs(deltaTheta) / (.pi / 2)))
        let segmentAngle = deltaTheta / Double(segments)
        var result: [CubicArc] = []
        var t1 = theta1

        for _ in 0..<segments {
            let t2 = t1 + segmentAngle
            let eta1 = t1, eta2 = t2
            let alpha = sin(eta2 - eta1) * (sqrt(4 + 3 * pow(tan((eta2 - eta1) / 2), 2)) - 1) / 3
            let cosEta1 = cos(eta1), sinEta1 = sin(eta1)
            let cosEta2 = cos(eta2), sinEta2 = sin(eta2)

            let p1x = cx + rx * cosEta1 * cosPhi - ry * sinEta1 * sinPhi
            let p1y = cy + rx * cosEta1 * sinPhi + ry * sinEta1 * cosPhi
            let p2x = cx + rx * cosEta2 * cosPhi - ry * sinEta2 * sinPhi
            let p2y = cy + rx * cosEta2 * sinPhi + ry * sinEta2 * cosPhi

            let dx1x = -rx * sinEta1 * cosPhi - ry * cosEta1 * sinPhi
            let dx1y = -rx * sinEta1 * sinPhi + ry * cosEta1 * cosPhi
            let dx2x = -rx * sinEta2 * cosPhi - ry * cosEta2 * sinPhi
            let dx2y = -rx * sinEta2 * sinPhi + ry * cosEta2 * cosPhi

            let q1 = CGPoint(x: p1x + alpha * dx1x, y: p1y + alpha * dx1y)
            let q2 = CGPoint(x: p2x - alpha * dx2x, y: p2y - alpha * dx2y)
            result.append(CubicArc(c1: q1, c2: q2, end: CGPoint(x: p2x, y: p2y)))
            t1 = t2
        }
        return result
    }
}
