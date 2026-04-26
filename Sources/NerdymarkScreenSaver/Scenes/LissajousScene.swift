import Cocoa

/// Lissajous curves: parametric x(t), y(t) = sin(at + δ), sin(bt). The
/// frequency ratio (a/b) and phase shift δ slowly drift so the figure
/// continuously morphs through different shapes.
///
/// Rendering strategy: maintain a persistent offscreen bitmap that we fade
/// slightly each frame (alpha-darken with a black rect at low alpha), then
/// draw only the new segments since the last frame onto it. Per-frame work
/// is O(new segments), not O(trail length), which fixed a CPU watchdog kill
/// on hi-DPI displays.
final class LissajousScene: DemoScene {
    static let identifier = "lissajous"
    static let displayName = "Lissajous Curves"

    static let options: [SceneOption] = [
        .slider(key: "fadeRate", label: "Trail Fade", min: 0.005, max: 0.15, defaultValue: 0.04, format: "%.3f /frame"),
        .slider(key: "morphSpeed", label: "Morph Speed", min: 0.05, max: 0.5, defaultValue: 0.15, format: "%.2f"),
        .slider(key: "thickness", label: "Line Thickness", min: 0.5, max: 4, defaultValue: 1.5, format: "%.1f px"),
        .choice(key: "palette", label: "Palette",
                choices: ["Spectrum", "Cyan-Magenta", "Sunset", "Mono"],
                defaultValue: "Spectrum"),
    ]

    private var size: CGSize = .zero
    private let fadeRate: CGFloat
    private let morphSpeed: Double
    private let thickness: CGFloat
    private let palette: String

    private var t: Double = 0
    private var freqA: Double = 3
    private var freqB: Double = 2
    private var freqADrift: Double = 0
    private var freqBDrift: Double = 0
    private var phaseDelta: Double = 0
    private var lastFreqUpdate: Double = 0

    // Persistent fading bitmap that the trail accumulates onto.
    private var trailBitmap: CGContext?
    private var trailBitmapSize: CGSize = .zero
    private var lastPoint: CGPoint?

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.fadeRate = CGFloat(settings.double("fadeRate", default: 0.04))
        self.morphSpeed = settings.double("morphSpeed", default: 0.15)
        self.thickness = CGFloat(settings.double("thickness", default: 1.5))
        self.palette = settings.string("palette", default: "Spectrum")
        scrambleFrequencies()
    }

    func resize(_ newSize: CGSize) {
        if newSize != size {
            size = newSize
            trailBitmap = nil  // force rebuild
            lastPoint = nil
        }
    }

    func tick(dt: TimeInterval) {
        t += dt
        freqA += freqADrift * dt * morphSpeed
        freqB += freqBDrift * dt * morphSpeed
        phaseDelta += dt * 0.3 * morphSpeed
        if t - lastFreqUpdate > 6.0 {
            scrambleFrequencies()
            lastFreqUpdate = t
            // Frequencies just jumped, so the next computed (x,y) will be far
            // from the previous point — drop the trail anchor so we don't
            // draw a long straight line connecting the old/new positions.
            lastPoint = nil
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            size = targetSize
            trailBitmap = nil
            lastPoint = nil
        }
        ensureTrailBitmap()
        guard let trail = trailBitmap else { return }

        // Fade the existing trail by overlaying a translucent black rect.
        trail.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: fadeRate))
        trail.fill(CGRect(origin: .zero, size: targetSize))

        // Add new segments since last frame. We sample several points along the
        // curve since `tick` was called to keep the line continuous even as t
        // jumps in larger steps.
        let cx = Double(targetSize.width) / 2
        let cy = Double(targetSize.height) / 2
        let scale = min(cx, cy) * 0.78
        let segmentsPerFrame = 6
        let dtPerSeg = (1.0 / 30.0) / Double(segmentsPerFrame)

        trail.setLineWidth(thickness)
        trail.setLineCap(.butt)
        trail.setLineJoin(.bevel)

        for i in 0..<segmentsPerFrame {
            let tt = t - Double(segmentsPerFrame - 1 - i) * dtPerSeg
            let x = cx + sin(freqA * tt + phaseDelta) * scale
            let y = cy + sin(freqB * tt) * scale
            let pt = CGPoint(x: x, y: y)
            let hue = (tt * 0.05).truncatingRemainder(dividingBy: 1.0)
            if let last = lastPoint {
                trail.setStrokeColor(colorFor(hue: hue, alpha: 1.0))
                trail.beginPath()
                trail.move(to: last)
                trail.addLine(to: pt)
                trail.strokePath()
            }
            lastPoint = pt
        }

        // Composite trail bitmap to screen.
        if let img = trail.makeImage() {
            ctx.draw(img, in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func ensureTrailBitmap() {
        if trailBitmap != nil && trailBitmapSize == size { return }
        let w = Int(size.width.rounded(.up))
        let h = Int(size.height.rounded(.up))
        guard w > 0 && h > 0 else { return }
        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let bmp = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: cs, bitmapInfo: bi) else { return }
        bmp.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1))
        bmp.fill(CGRect(x: 0, y: 0, width: w, height: h))
        trailBitmap = bmp
        trailBitmapSize = size
    }

    private func scrambleFrequencies() {
        freqA = Double.random(in: 1...5)
        freqB = Double.random(in: 1...5)
        freqADrift = Double.random(in: -0.4...0.4)
        freqBDrift = Double.random(in: -0.4...0.4)
    }

    private func colorFor(hue: Double, alpha: CGFloat) -> CGColor {
        switch palette {
        case "Cyan-Magenta":
            // Slow oscillation between cyan and magenta over time.
            let osc = (sin(hue * 2 * .pi) + 1) / 2
            return CGColor(red: CGFloat(osc), green: CGFloat(1 - osc * 0.8), blue: 0.95, alpha: alpha)
        case "Sunset":
            let osc = (sin(hue * 2 * .pi) + 1) / 2
            return CGColor(red: 0.6 + CGFloat(osc) * 0.4, green: CGFloat(0.3 + osc * 0.5), blue: CGFloat(0.1 + osc * 0.3), alpha: alpha)
        case "Mono":
            return CGColor(red: 0.95, green: 0.95, blue: 1.0, alpha: alpha)
        default: // Spectrum
            return NSColor(hue: CGFloat(hue), saturation: 0.85, brightness: 1.0, alpha: alpha).cgColor
        }
    }
}
