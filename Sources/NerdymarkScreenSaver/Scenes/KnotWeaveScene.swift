import Cocoa

/// Knot weave: N strands all centered on the same horizontal band, each
/// phase-offset by 2π/N. They cross at every quarter wavelength. Over/under
/// is decided per-segment by a pseudo-3D depth value (cos of phase) — a
/// strand whose depth is greater is in front. Two-pass rendering: first
/// dark outlines, then colored fills with "under" segments skipped so the
/// dark outline shows through, creating clear over/under crossings.
final class KnotWeaveScene: DemoScene {
    static let identifier = "knot_weave"
    static let displayName = "Celtic Braid"

    static let options: [SceneOption] = [
        .slider(key: "strands", label: "Strand Count", min: 2, max: 6, defaultValue: 3, format: "%.0f"),
        .slider(key: "thickness", label: "Strand Width", min: 8, max: 50, defaultValue: 24, format: "%.0f px"),
        .slider(key: "speed", label: "Animation Speed", min: 0.05, max: 1.5, defaultValue: 0.35, format: "%.2f"),
        .slider(key: "wavelength", label: "Wavelength", min: 80, max: 400, defaultValue: 220, format: "%.0f px"),
        .slider(key: "amplitude", label: "Amplitude", min: 0.1, max: 0.6, defaultValue: 0.3, format: "%.2f"),
        .choice(key: "palette", label: "Palette",
                choices: ["Celtic Gold", "Royal", "Forest", "Mono", "Sunset"],
                defaultValue: "Celtic Gold"),
    ]

    private struct Sample {
        let x: CGFloat
        let y: CGFloat
        let depth: Double   // cos(phase): higher = in front
    }

    private var size: CGSize = .zero
    private let strandCount: Int
    private let thickness: CGFloat
    private let speed: Double
    private let wavelength: CGFloat
    private let amplitudeFrac: Double
    private let paletteName: String
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.strandCount = max(2, Int(settings.double("strands", default: 3)))
        self.thickness = CGFloat(settings.double("thickness", default: 24))
        self.speed = settings.double("speed", default: 0.35)
        self.wavelength = CGFloat(settings.double("wavelength", default: 220))
        self.amplitudeFrac = settings.double("amplitude", default: 0.3)
        self.paletteName = settings.string("palette", default: "Celtic Gold")
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize

        let (bg, _) = colors()
        ctx.setFillColor(bg)
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Sample each strand at fixed x-stride.
        let stepX: CGFloat = 4
        let centerY = targetSize.height / 2
        let amp = Double(targetSize.height) * amplitudeFrac
        let scrollPhase = elapsed * speed
        let twoPi = 2 * Double.pi
        let wavelen = Double(wavelength)

        var strands: [[Sample]] = []
        strands.reserveCapacity(strandCount)
        for i in 0..<strandCount {
            let phaseOffset = twoPi * Double(i) / Double(strandCount)
            var samples: [Sample] = []
            var x: CGFloat = 0
            while x <= targetSize.width {
                let phase = (Double(x) / wavelen) * twoPi + phaseOffset + scrollPhase
                let y = centerY + CGFloat(sin(phase) * amp)
                samples.append(Sample(x: x, y: y, depth: cos(phase)))
                x += stepX
            }
            strands.append(samples)
        }

        // Pass A: dark outlines for every strand (the "halo" that shows
        // through where strands go under each other).
        ctx.setStrokeColor(bg)
        ctx.setLineWidth(thickness + 8)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for samples in strands {
            stroke(samples: samples, ctx: ctx)
        }

        // Pass B: colored fills, skipping segments where this strand is
        // behind another (sharing y region, lower depth).
        for (idx, samples) in strands.enumerated() {
            ctx.setStrokeColor(strandColor(strandIdx: idx))
            ctx.setLineWidth(thickness)
            var inPath = false
            for k in 0..<samples.count {
                let me = samples[k]
                var underAnother = false
                for (j, other) in strands.enumerated() where j != idx {
                    let o = other[k]
                    if abs(me.y - o.y) < thickness * 0.9 && o.depth > me.depth + 0.02 {
                        underAnother = true; break
                    }
                }
                if underAnother {
                    if inPath { ctx.strokePath(); inPath = false }
                } else {
                    if !inPath {
                        ctx.beginPath()
                        ctx.move(to: CGPoint(x: me.x, y: me.y))
                        inPath = true
                    } else {
                        ctx.addLine(to: CGPoint(x: me.x, y: me.y))
                    }
                }
            }
            if inPath { ctx.strokePath() }
        }
    }

    // MARK: - Helpers

    private func stroke(samples: [Sample], ctx: CGContext) {
        guard let first = samples.first else { return }
        ctx.beginPath()
        ctx.move(to: CGPoint(x: first.x, y: first.y))
        for i in 1..<samples.count {
            ctx.addLine(to: CGPoint(x: samples[i].x, y: samples[i].y))
        }
        ctx.strokePath()
    }

    private func colors() -> (CGColor, CGColor) {
        switch paletteName {
        case "Royal":   return (CGColor(red: 0.04, green: 0.02, blue: 0.10, alpha: 1),
                                 CGColor(red: 0.55, green: 0.30, blue: 0.95, alpha: 1))
        case "Forest":  return (CGColor(red: 0.04, green: 0.08, blue: 0.04, alpha: 1),
                                 CGColor(red: 0.40, green: 0.85, blue: 0.40, alpha: 1))
        case "Mono":    return (CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
                                 CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))
        case "Sunset":  return (CGColor(red: 0.10, green: 0.04, blue: 0.15, alpha: 1),
                                 CGColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1))
        default:        return (CGColor(red: 0.05, green: 0.04, blue: 0.02, alpha: 1),
                                 CGColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1))
        }
    }

    /// Each strand gets a slightly hue-shifted variant of the palette base color.
    private func strandColor(strandIdx: Int) -> CGColor {
        let base = colors().1
        guard let comps = base.components, comps.count >= 3 else { return base }
        let r = comps[0], g = comps[1], b = comps[2]
        let a: CGFloat = comps.count >= 4 ? comps[3] : 1
        let shimmer = CGFloat(0.85 + 0.15 * sin(elapsed * 0.5 + Double(strandIdx) * 0.7))
        // Per-strand hue tint via small RGB rotation.
        let tint = CGFloat(strandIdx) / CGFloat(max(1, strandCount))
        let nr = min(1, r * shimmer * (1 - tint * 0.2))
        let ng = min(1, g * shimmer * (1 + tint * 0.15))
        let nb = min(1, b * shimmer + tint * 0.2)
        return CGColor(red: nr, green: ng, blue: nb, alpha: a)
    }
}
