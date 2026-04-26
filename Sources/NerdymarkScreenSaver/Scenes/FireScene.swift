import Cocoa

/// Plasma fire: an animated 2D sin-noise field is multiplied by a vertical
/// falloff (full at bottom, zero near top) and mapped through a fire palette.
/// Renders into a low-res heat buffer and scales up bilinearly so the result
/// is smooth/fluid rather than the pixelated DOOM-fire jitter. The noise
/// scrolls downward over time so the flames appear to flicker upward.
final class FireScene: DemoScene {
    static let identifier = "fire"
    static let displayName = "Plasma Fire"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Flame Speed", min: 0.3, max: 4.0, defaultValue: 1.4, format: "%.1f"),
        .slider(key: "height", label: "Flame Height", min: 0.3, max: 1.0, defaultValue: 0.7, format: "%.2f"),
        .slider(key: "turbulence", label: "Turbulence", min: 0.5, max: 3.0, defaultValue: 1.5, format: "%.1f"),
        .slider(key: "intensity", label: "Brightness", min: 0.6, max: 1.6, defaultValue: 1.0, format: "%.2f"),
        .choice(key: "palette", label: "Palette",
                choices: ["Classic", "Cool Blue", "Toxic Green", "Plasma Pink"],
                defaultValue: "Classic"),
    ]

    private var size: CGSize = .zero
    private let speed: Double
    private let flameHeight: Double
    private let turbulence: Double
    private let intensity: Double
    private let palette: [UInt32]   // 256-entry ARGB LUT

    // Low-res heat buffer (smooth bilinear upscale to screen size).
    private var bufW: Int = 0
    private var bufH: Int = 0
    private var pixels: UnsafeMutablePointer<UInt32>?
    private let bufScale = 4   // 1 buffer pixel = bufScale screen px
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 1.4)
        self.flameHeight = settings.double("height", default: 0.7)
        self.turbulence = settings.double("turbulence", default: 1.5)
        self.intensity = settings.double("intensity", default: 1.0)
        self.palette = FireScene.makePalette(named: settings.string("palette", default: "Classic"))
        allocate(for: size)
    }

    deinit {
        pixels?.deallocate()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        allocate(for: newSize)
    }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = pixels else { return }

        // Sample the plasma field into the low-res buffer. y=0 is the BOTTOM
        // of the screen (we draw flipped: bottom row is hottest).
        let bw = bufW
        let bh = bufH
        let t = elapsed * speed
        let turbScale = turbulence * 0.04

        for y in 0..<bh {
            // 0 at bottom, 1 at top. Hottest near 0; fades by `flameHeight`.
            let yFrac = 1.0 - Double(y) / Double(bh)
            let mask = max(0.0, 1.0 - yFrac / max(0.05, flameHeight))
            let maskShaped = pow(mask, 1.6)
            let yScaled = Double(y) * turbScale
            for x in 0..<bw {
                let xScaled = Double(x) * turbScale
                // Layered sin "noise" — three octaves at different frequencies.
                let n1 = sin(xScaled * 1.0 + yScaled * 1.7 + t * 1.3)
                let n2 = sin(xScaled * 2.3 - yScaled * 2.1 + t * 1.9)
                let n3 = sin(xScaled * 0.6 + yScaled * 0.5 - t * 0.8) * 0.7
                let raw = (n1 + n2 + n3) / 2.7   // ~ -1..1
                let noise01 = (raw + 1) * 0.5     // 0..1
                // Combine: mask defines envelope, noise modulates within it.
                let h = noise01 * 0.55 + maskShaped * 0.55
                let heat = max(0, min(1, h * maskShaped * intensity))
                let idx = Int(heat * 255)
                buf[(bh - 1 - y) * bw + x] = palette[idx]
            }
        }

        let bytesPerRow = bw * 4
        let bytesTotal = bytesPerRow * bh
        guard let provider = CGDataProvider(
            dataInfo: nil, data: buf, size: bytesTotal,
            releaseData: { _, _, _ in }
        ) else { return }

        guard let image = CGImage(
            width: bw, height: bh,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        ) else { return }

        // Black ground.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))
    }

    // MARK: - Buffer

    private func allocate(for newSize: CGSize) {
        pixels?.deallocate()
        bufW = max(1, Int(newSize.width) / bufScale)
        bufH = max(1, Int(newSize.height) / bufScale)
        pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: bufW * bufH)
    }

    // MARK: - Palette LUT

    private static func makePalette(named name: String) -> [UInt32] {
        switch name {
        case "Cool Blue":
            return gradient(stops: [
                (0,   (0, 0, 0)),
                (40,  (4, 0, 30)),
                (110, (15, 18, 110)),
                (190, (90, 160, 240)),
                (255, (235, 245, 255)),
            ])
        case "Toxic Green":
            return gradient(stops: [
                (0,   (0, 0, 0)),
                (40,  (0, 18, 0)),
                (120, (28, 130, 22)),
                (200, (160, 240, 90)),
                (255, (255, 255, 210)),
            ])
        case "Plasma Pink":
            return gradient(stops: [
                (0,   (0, 0, 0)),
                (40,  (28, 0, 40)),
                (130, (160, 30, 130)),
                (210, (255, 110, 200)),
                (255, (255, 235, 255)),
            ])
        default: // Classic fire
            return gradient(stops: [
                (0,   (0, 0, 0)),
                (28,  (35, 0, 0)),
                (80,  (140, 18, 0)),
                (165, (245, 110, 0)),
                (220, (255, 210, 60)),
                (255, (255, 255, 220)),
            ])
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
