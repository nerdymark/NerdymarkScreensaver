import Cocoa

/// Lava lamp with believable physics:
///
///   - A heated reservoir of wax sits at the bottom.
///   - Bumps of wax detach with high "temperature"; buoyancy = f(temp).
///   - As a blob rises it cools (heat loss to surroundings); buoyancy drops.
///   - Cooled wax becomes denser-than-fluid, slows, then falls back.
///   - On reaching the reservoir, the blob merges away.
///
/// A glowing bulb at the bottom backlights the wax silhouette so the lava
/// pixels composite over the warm light. The metaball palette is built with
/// alpha so low-density areas are transparent and the bulb glow shows
/// through.
final class LavaLampScene: DemoScene {
    static let identifier = "lava_lamp"
    static let displayName = "Lava Lamp"

    static let options: [SceneOption] = [
        .slider(key: "blobCount", label: "Blobs in Flight", min: 1, max: 8, defaultValue: 4, format: "%.0f"),
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
        .slider(key: "buoyancy", label: "Buoyancy Strength", min: 0.3, max: 2.0, defaultValue: 0.9, format: "%.1f"),
        .slider(key: "cooling", label: "Cooling Rate", min: 0.05, max: 0.5, defaultValue: 0.18, format: "%.2f"),
        .slider(key: "puddleSize", label: "Reservoir Size", min: 14, max: 60, defaultValue: 30, format: "%.0f"),
        .slider(key: "lampGlow", label: "Lamp Brightness", min: 0.0, max: 2.0, defaultValue: 1.0, format: "%.2f"),
        .choice(key: "color", label: "Lava Color",
                choices: ["Classic Red", "Lime", "Purple", "Aqua", "Sunset"],
                defaultValue: "Classic Red"),
    ]

    private struct Blob {
        var x: Double
        var y: Double
        var vy: Double
        var radius: Double
        var temp: Double          // 0..1 (1 = freshly heated, 0 = cold)
        var phase: Double         // for horizontal wobble
    }

    private var size: CGSize = .zero
    private let blobCount: Int
    private let scale: Int
    private let buoyancyStrength: Double
    private let coolingRate: Double
    private let puddleRadius: Double
    private let lampGlow: Double
    private let palette: [UInt32]
    private let lampWarmColor: CGColor
    private let lampCoreColor: CGColor

    private var blobs: [Blob] = []
    private var bitmap: PaletteBitmap
    private var nextSpawnAt: Double = 0
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.blobCount = max(1, Int(settings.double("blobCount", default: 4)))
        self.scale = max(1, Int(settings.double("scale", default: 4)))
        self.buoyancyStrength = settings.double("buoyancy", default: 0.9)
        self.coolingRate = settings.double("cooling", default: 0.18)
        self.puddleRadius = settings.double("puddleSize", default: 30)
        self.lampGlow = settings.double("lampGlow", default: 1.0)
        let colorName = settings.string("color", default: "Classic Red")
        self.palette = LavaLampScene.makeAlphaPalette(named: colorName)
        let bulb = LavaLampScene.lampBulbColor(named: colorName)
        self.lampWarmColor = bulb.warm
        self.lampCoreColor = bulb.core
        self.bitmap = PaletteBitmap(width: max(1, Int(size.width) / scale),
                                     height: max(1, Int(size.height) / scale))
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        bitmap.resize(width: max(1, Int(newSize.width) / scale),
                       height: max(1, Int(newSize.height) / scale))
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        // Spawn new blobs from the reservoir at randomized intervals.
        if elapsed >= nextSpawnAt && blobs.count < blobCount {
            blobs.append(makeBlob())
            nextSpawnAt = elapsed + Double.random(in: 1.2...3.5)
        }
        let h = Double(bitmap.height)
        var i = 0
        while i < blobs.count {
            var b = blobs[i]
            // Cooling — faster when high in the column (more "ambient air").
            let altitudeFraction = max(0, min(1, 1 - b.y / h))   // 0 at top, 1 at bottom
            let coolMult = 1.0 + (1 - altitudeFraction) * 1.5    // higher up cools faster
            b.temp = max(0, b.temp - coolingRate * coolMult * dt)
            // Buoyancy from temperature; gravity pulls down.
            let buoy = (b.temp - 0.5) * 60 * buoyancyStrength    // sign: hot = up, cool = down
            let gravity = -9.0
            b.vy += (-buoy + gravity) * dt
            // Damping (wax viscosity).
            b.vy *= 0.94
            b.y += b.vy * dt * 4
            // Horizontal wobble.
            b.phase += dt * 0.7
            let centerX = Double(bitmap.width) / 2
            b.x = centerX + sin(b.phase + Double(i)) * Double(bitmap.width) * 0.13
            // Reabsorbed by reservoir.
            if b.y >= h - puddleRadius * 0.5 {
                blobs.remove(at: i)
                continue
            }
            // Soft top "ceiling" — reflect with strong damping.
            if b.y < puddleRadius * 0.4 {
                b.y = puddleRadius * 0.4
                b.vy = abs(b.vy) * 0.3
                b.temp = min(b.temp, 0.3)
            }
            blobs[i] = b
            i += 1
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        // 1. Dark glass background gradient (purple-black, like a lamp body).
        let glassTop = CGColor(red: 0.04, green: 0.02, blue: 0.06, alpha: 1)
        let glassBot = CGColor(red: 0.10, green: 0.05, blue: 0.04, alpha: 1)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [glassBot, glassTop] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0),
                                    end: CGPoint(x: 0, y: targetSize.height), options: [])
        }

        // 2. Lamp glow — large soft warm radial from bottom-center.
        let bulbCenter = CGPoint(x: targetSize.width / 2, y: 0)
        let bulbRadius = targetSize.height * 0.7
        if lampGlow > 0 {
            let warm = lampWarmColor.copy(alpha: CGFloat(0.55 * lampGlow)) ?? lampWarmColor
            let edge = lampWarmColor.copy(alpha: 0) ?? lampWarmColor
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [warm, edge] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: bulbCenter, startRadius: 0,
                                         endCenter: bulbCenter, endRadius: bulbRadius, options: [])
            }
        }

        // 3. Metaball field rendered with alpha-aware palette so the lamp
        //    glow shows through the cool/empty regions.
        renderMetaballs()
        bitmap.present(in: ctx, size: targetSize, smooth: true)

        // 4. Bright bulb spot at the very bottom — the visible incandescent
        //    element under the wax. Drawn LAST so it reads as the lit bulb.
        if lampGlow > 0 {
            let bulbR = min(targetSize.width, targetSize.height) * 0.10
            let core = lampCoreColor.copy(alpha: CGFloat(0.85 * lampGlow)) ?? lampCoreColor
            let warm = lampWarmColor.copy(alpha: CGFloat(0.4 * lampGlow)) ?? lampWarmColor
            let edge = lampWarmColor.copy(alpha: 0) ?? lampWarmColor
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [core, warm, edge] as CFArray, locations: [0, 0.4, 1]) {
                ctx.setBlendMode(.plusLighter)
                ctx.drawRadialGradient(g, startCenter: bulbCenter, startRadius: 0,
                                         endCenter: bulbCenter, endRadius: bulbR, options: [])
                ctx.setBlendMode(.normal)
            }
        }
    }

    // MARK: - Metaball field

    private func renderMetaballs() {
        guard let buf = bitmap.pixels else { return }
        let w = bitmap.width, h = bitmap.height
        let pal = palette
        let centerX = Double(w) / 2

        // Reservoir is a flat puddle at the bottom — represented as a row
        // of overlapping virtual blobs.
        let reservoirY = Double(h) - puddleRadius * 0.5
        let segments = max(3, Int(Double(w) * 0.5 / puddleRadius))

        for y in 0..<h {
            let row = y * w
            let yd = Double(y)
            let nearReservoir = abs(yd - reservoirY) < puddleRadius * 4
            for x in 0..<w {
                var sum = 0.0
                let xd = Double(x)
                if nearReservoir {
                    for k in 0..<segments {
                        let frac = (Double(k) - Double(segments - 1) / 2) / Double(segments - 1)
                        let px = centerX + frac * Double(w) * 0.32
                        let dx = xd - px
                        let dy = yd - reservoirY
                        let d2 = dx * dx + dy * dy + 1
                        sum += (puddleRadius * puddleRadius) / d2
                    }
                }
                for blob in blobs {
                    let dx = xd - blob.x
                    let dy = yd - blob.y
                    let d2 = dx * dx + dy * dy + 1
                    sum += (blob.radius * blob.radius) / d2
                }
                let v = min(1.0, sum * 0.5)
                let idx = Int(v * 255.0) & 0xFF
                buf[row + x] = pal[idx]
            }
        }
    }

    private func makeBlob() -> Blob {
        Blob(
            x: Double(bitmap.width) / 2,
            y: Double(bitmap.height) - puddleRadius * 0.4,
            vy: -Double.random(in: 4...8),
            radius: Double.random(in: 14...22),
            temp: Double.random(in: 0.85...1.0),
            phase: Double.random(in: 0..<(2 * .pi))
        )
    }

    // MARK: - Palettes

    /// Alpha-aware palette: low metaball values are fully transparent so
    /// background lamp glow shows through the cool spaces between wax. The
    /// stored colors are PREMULTIPLIED (CG byte order is BGRA little-endian
    /// with premultiplied-first alpha as set up by PaletteBitmap).
    private static func makeAlphaPalette(named name: String) -> [UInt32] {
        let stops: [(Int, (UInt8, UInt8, UInt8))]
        switch name {
        case "Lime":
            stops = [(80,(60,150,0)),(180,(180,255,80)),(255,(255,255,200))]
        case "Purple":
            stops = [(80,(80,20,140)),(180,(220,80,220)),(255,(255,200,255))]
        case "Aqua":
            stops = [(80,(0,90,150)),(180,(80,200,250)),(255,(220,255,255))]
        case "Sunset":
            stops = [(80,(150,30,80)),(180,(255,140,40)),(230,(255,220,80)),(255,(255,255,220))]
        default: // Classic Red
            stops = [(80,(150,30,0)),(180,(255,90,0)),(230,(255,210,80)),(255,(255,255,200))]
        }
        let sorted = stops.sorted { $0.0 < $1.0 }
        var pal = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            // Alpha curve: 0 below threshold, ramps quickly to opaque.
            let alphaF: Double
            if i < 60 { alphaF = 0 }
            else if i < 100 { alphaF = Double(i - 60) / 40 }
            else { alphaF = 1 }
            // Sample base color from stops (clamped at lowest stop below).
            var lower = sorted.first!
            var upper = sorted.last!
            for s in sorted {
                if s.0 <= i { lower = s }
                if s.0 >= i { upper = s; break }
            }
            let span = max(1, upper.0 - lower.0)
            let frac = Double(i - lower.0) / Double(span)
            let r = Double(lower.1.0) + (Double(upper.1.0) - Double(lower.1.0)) * frac
            let g = Double(lower.1.1) + (Double(upper.1.1) - Double(lower.1.1)) * frac
            let b = Double(lower.1.2) + (Double(upper.1.2) - Double(lower.1.2)) * frac
            // Premultiply RGB by alpha.
            let aByte = UInt32(alphaF * 255)
            let rByte = UInt32(r * alphaF)
            let gByte = UInt32(g * alphaF)
            let bByte = UInt32(b * alphaF)
            pal[i] = (aByte << 24) | (rByte << 16) | (gByte << 8) | bByte
        }
        return pal
    }

    private static func lampBulbColor(named name: String) -> (warm: CGColor, core: CGColor) {
        switch name {
        case "Lime":
            return (CGColor(red: 0.85, green: 1.0, blue: 0.50, alpha: 1),
                    CGColor(red: 1.0, green: 1.0, blue: 0.90, alpha: 1))
        case "Purple":
            return (CGColor(red: 0.95, green: 0.55, blue: 1.0, alpha: 1),
                    CGColor(red: 1.0, green: 0.95, blue: 1.0, alpha: 1))
        case "Aqua":
            return (CGColor(red: 0.50, green: 0.95, blue: 1.0, alpha: 1),
                    CGColor(red: 0.95, green: 1.0, blue: 1.0, alpha: 1))
        case "Sunset":
            return (CGColor(red: 1.0, green: 0.75, blue: 0.40, alpha: 1),
                    CGColor(red: 1.0, green: 1.0, blue: 0.85, alpha: 1))
        default: // Classic Red — warm yellow incandescent
            return (CGColor(red: 1.0, green: 0.65, blue: 0.25, alpha: 1),
                    CGColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1))
        }
    }
}
