import Cocoa

/// Slime mold (Physarum polycephalum) simulation. Thousands of agents move
/// forward, sample three sensors (left/center/right), and steer toward the
/// strongest pheromone reading. Each step they deposit pheromone onto a
/// trail buffer that gradually evaporates and diffuses. Emergent organic
/// network patterns.
final class SlimeMoldScene: DemoScene {
    static let identifier = "slime_mold"
    static let displayName = "Slime Mold"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 6, defaultValue: 3, format: "%.0fx"),
        .slider(key: "agentCount", label: "Agents", min: 500, max: 8000, defaultValue: 3000, format: "%.0f"),
        .slider(key: "evaporate", label: "Trail Fade", min: 0.005, max: 0.1, defaultValue: 0.02, format: "%.3f"),
        .slider(key: "turnSpeed", label: "Turn Sharpness", min: 0.2, max: 2.0, defaultValue: 0.7, format: "%.2f"),
        .choice(key: "palette", label: "Palette",
                choices: ["Cyan", "Acid Green", "Ember", "Magenta"],
                defaultValue: "Cyan"),
    ]

    private struct Agent { var x: Float; var y: Float; var heading: Float }

    private var size: CGSize = .zero
    private let pixelScale: Int
    private let agentCount: Int
    private let evaporate: Float
    private let turnSpeed: Float
    private let paletteName: String

    private var w: Int = 0
    private var h: Int = 0
    private var trail: [Float] = []
    private var trailNext: [Float] = []
    private var agents: [Agent] = []
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var palette: [UInt32] = []
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.pixelScale = max(2, Int(settings.double("scale", default: 3)))
        self.agentCount = max(100, Int(settings.double("agentCount", default: 3000)))
        self.evaporate = Float(settings.double("evaporate", default: 0.02))
        self.turnSpeed = Float(settings.double("turnSpeed", default: 0.7))
        self.paletteName = settings.string("palette", default: "Cyan")
        palette = SlimeMoldScene.makePalette(named: paletteName)
        allocate(for: size)
    }

    deinit { pixels?.deallocate() }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        allocate(for: newSize)
    }

    func tick(dt: TimeInterval) {
        // Move + steer agents.
        let sensorDist: Float = 6
        let sensorAngle: Float = 0.5
        let moveStep: Float = 1.5
        for i in 0..<agents.count {
            var a = agents[i]
            let fwd = sense(x: a.x, y: a.y, heading: a.heading, dist: sensorDist)
            let lft = sense(x: a.x, y: a.y, heading: a.heading - sensorAngle, dist: sensorDist)
            let rgt = sense(x: a.x, y: a.y, heading: a.heading + sensorAngle, dist: sensorDist)
            if fwd > lft && fwd > rgt {
                // Continue.
            } else if fwd < lft && fwd < rgt {
                a.heading += (Bool.random() ? -1 : 1) * turnSpeed * 0.5
            } else if rgt > lft {
                a.heading += turnSpeed * 0.3
            } else if lft > rgt {
                a.heading -= turnSpeed * 0.3
            }
            a.x += cos(a.heading) * moveStep
            a.y += sin(a.heading) * moveStep
            // Bounce off walls by reflecting heading.
            if a.x < 0 { a.x = 0; a.heading = .pi - a.heading }
            else if a.x >= Float(w) { a.x = Float(w - 1); a.heading = .pi - a.heading }
            if a.y < 0 { a.y = 0; a.heading = -a.heading }
            else if a.y >= Float(h) { a.y = Float(h - 1); a.heading = -a.heading }
            // Deposit pheromone.
            let idx = Int(a.y) * w + Int(a.x)
            if idx >= 0 && idx < trail.count { trail[idx] = min(1, trail[idx] + 0.5) }
            agents[i] = a
        }
        // Diffuse + evaporate.
        diffuse()
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = pixels else { return }
        for i in 0..<(w * h) {
            let v = max(0, min(1, trail[i]))
            buf[i] = palette[Int(v * 255)]
        }
        let bytesPerRow = w * 4
        guard let provider = CGDataProvider(dataInfo: nil, data: buf, size: bytesPerRow * h, releaseData: { _, _, _ in }),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: bytesPerRow, space: colorSpace,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))
    }

    // MARK: - Sim helpers

    private func sense(x: Float, y: Float, heading: Float, dist: Float) -> Float {
        let sx = Int(x + cos(heading) * dist)
        let sy = Int(y + sin(heading) * dist)
        guard sx >= 0 && sx < w && sy >= 0 && sy < h else { return 0 }
        return trail[sy * w + sx]
    }

    private func diffuse() {
        let W = w, H = h
        let evap = 1 - evaporate
        for y in 1..<(H - 1) {
            for x in 1..<(W - 1) {
                let i = y * W + x
                let avg = (trail[i] + trail[i - 1] + trail[i + 1] + trail[i - W] + trail[i + W]) / 5
                trailNext[i] = avg * evap
            }
        }
        // Edges: just evaporate without blur.
        for x in 0..<W {
            trailNext[x] = trail[x] * evap
            trailNext[(H - 1) * W + x] = trail[(H - 1) * W + x] * evap
        }
        for y in 0..<H {
            trailNext[y * W] = trail[y * W] * evap
            trailNext[y * W + W - 1] = trail[y * W + W - 1] * evap
        }
        swap(&trail, &trailNext)
    }

    // MARK: - Setup

    private func allocate(for newSize: CGSize) {
        pixels?.deallocate()
        w = max(20, Int(newSize.width) / pixelScale)
        h = max(20, Int(newSize.height) / pixelScale)
        trail = [Float](repeating: 0, count: w * h)
        trailNext = trail
        pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
        // Seed agents in a ring around the center facing inward.
        let cx = Float(w) / 2
        let cy = Float(h) / 2
        let ringR = Float(min(w, h)) * 0.25
        agents = (0..<agentCount).map { _ in
            let angle = Float.random(in: 0..<(2 * .pi))
            return Agent(
                x: cx + cos(angle) * ringR,
                y: cy + sin(angle) * ringR,
                heading: angle + .pi   // pointing inward
            )
        }
    }

    // MARK: - Palette

    private static func makePalette(named name: String) -> [UInt32] {
        switch name {
        case "Acid Green":
            return gradient(stops: [(0,(0,0,0)),(60,(0,30,5)),(160,(50,200,40)),(255,(220,255,180))])
        case "Ember":
            return gradient(stops: [(0,(0,0,0)),(60,(40,0,0)),(160,(220,80,20)),(255,(255,230,140))])
        case "Magenta":
            return gradient(stops: [(0,(0,0,0)),(60,(40,0,40)),(160,(180,40,180)),(255,(255,200,255))])
        default: // Cyan
            return gradient(stops: [(0,(0,0,0)),(60,(0,20,50)),(160,(20,140,210)),(255,(220,255,255))])
        }
    }

    private static func gradient(stops: [(Int, (UInt8, UInt8, UInt8))]) -> [UInt32] {
        var pal = [UInt32](repeating: 0, count: 256)
        let sorted = stops.sorted { $0.0 < $1.0 }
        for i in 0..<256 {
            var lower = sorted.first!
            var upper = sorted.last!
            for s in sorted {
                if s.0 <= i { lower = s }
                if s.0 >= i { upper = s; break }
            }
            let span = max(1, upper.0 - lower.0)
            let frac = Double(i - lower.0) / Double(span)
            let r = UInt32(Double(lower.1.0) + (Double(upper.1.0) - Double(lower.1.0)) * frac)
            let g = UInt32(Double(lower.1.1) + (Double(upper.1.1) - Double(lower.1.1)) * frac)
            let b = UInt32(Double(lower.1.2) + (Double(upper.1.2) - Double(lower.1.2)) * frac)
            pal[i] = (0xFF << 24) | (r << 16) | (g << 8) | b
        }
        return pal
    }
}
