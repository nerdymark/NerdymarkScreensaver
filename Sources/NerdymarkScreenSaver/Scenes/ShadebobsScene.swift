import Cocoa
import CoreGraphics

/// "Shadebobs" — N small soft circles tracing Lissajous-like paths, each
/// drawn additively into a low-res buffer. The buffer fades each frame so
/// trails dissolve. Hue cycles through the palette over time.
final class ShadebobsScene: DemoScene {
    static let identifier = "shadebobs"
    static let displayName = "Shadebobs"

    static let options: [SceneOption] = [
        .slider(key: "bobCount", label: "Bobs", min: 1, max: 8, defaultValue: 3, format: "%.0f"),
        .slider(key: "bobSize", label: "Bob Size", min: 12, max: 60, defaultValue: 28, format: "%.0f px"),
        .slider(key: "trailLen", label: "Trail Length", min: 0.85, max: 0.99, defaultValue: 0.95, format: "%.2f"),
        .slider(key: "speed", label: "Path Speed", min: 0.3, max: 2.5, defaultValue: 1.0, format: "%.1fx"),
        .choice(key: "palette", label: "Palette",
                choices: ["Neon", "Sunset", "Forest", "Cyberpunk"],
                defaultValue: "Neon"),
    ]

    private struct Bob {
        var freqX: Double
        var freqY: Double
        var phaseX: Double
        var phaseY: Double
        var hueOffset: Double
    }

    private var size: CGSize = .zero
    private var bobs: [Bob] = []
    private let bobSize: CGFloat
    private let trailLen: Double
    private let speed: Double
    private let palette: [UInt32]   // 256-entry LUT

    // Accumulator buffer holds [0..255] intensity per pixel; we map through
    // the palette at draw time and decay each tick to fade trails.
    private var intensity: [UInt8] = []
    private var pixelBuffer: UnsafeMutablePointer<UInt32>?
    private var bWidth = 0
    private var bHeight = 0
    private let scale = 3
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var elapsed: TimeInterval = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        let count = max(1, Int(settings.double("bobCount", default: 3)))
        self.bobSize = CGFloat(settings.double("bobSize", default: 28))
        self.trailLen = settings.double("trailLen", default: 0.95)
        self.speed = settings.double("speed", default: 1.0)
        self.palette = ShadebobsScene.makePalette(named: settings.string("palette", default: "Neon"))
        self.bobs = (0..<count).map { _ in
            Bob(
                freqX: Double.random(in: 0.4...1.4),
                freqY: Double.random(in: 0.4...1.4),
                phaseX: Double.random(in: 0..<(2.0 * .pi)),
                phaseY: Double.random(in: 0..<(2.0 * .pi)),
                hueOffset: Double.random(in: 0..<1)
            )
        }
        allocate(for: size)
    }

    deinit { pixelBuffer?.deallocate() }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        allocate(for: newSize)
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        // Decay buffer.
        let decay = UInt8(max(1, Int((1 - trailLen) * 255)))
        for i in intensity.indices {
            intensity[i] = intensity[i] > decay ? intensity[i] - decay : 0
        }
        // Draw each bob's contribution.
        let bobR = max(2, Int(bobSize / CGFloat(scale)))
        for bob in bobs {
            let cx = (sin(elapsed * bob.freqX * speed + bob.phaseX) * 0.45 + 0.5) * Double(bWidth)
            let cy = (cos(elapsed * bob.freqY * speed + bob.phaseY) * 0.45 + 0.5) * Double(bHeight)
            stamp(cx: Int(cx), cy: Int(cy), radius: bobR)
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buffer = pixelBuffer else { return }

        // Map intensity → palette LUT into the pixel buffer.
        for i in 0..<intensity.count {
            buffer[i] = palette[Int(intensity[i])]
        }

        let bytesPerRow = bWidth * 4
        let bytesTotal = bytesPerRow * bHeight
        guard let provider = CGDataProvider(
            dataInfo: nil, data: buffer, size: bytesTotal,
            releaseData: { _, _, _ in }
        ) else { return }
        guard let image = CGImage(
            width: bWidth, height: bHeight,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        ) else { return }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))
    }

    // MARK: - Stamp / buffer

    /// Add a soft circular bump to the intensity buffer (additive, saturates).
    private func stamp(cx: Int, cy: Int, radius: Int) {
        let r2 = radius * radius
        let yMin = max(0, cy - radius)
        let yMax = min(bHeight - 1, cy + radius)
        let xMin = max(0, cx - radius)
        let xMax = min(bWidth - 1, cx + radius)
        for y in yMin...yMax {
            let dy = y - cy
            for x in xMin...xMax {
                let dx = x - cx
                let d2 = dx * dx + dy * dy
                if d2 > r2 { continue }
                let falloff = 1.0 - Double(d2) / Double(r2)
                let bump = UInt16(falloff * falloff * 80)
                let idx = y * bWidth + x
                let combined = UInt16(intensity[idx]) + bump
                intensity[idx] = combined > 255 ? 255 : UInt8(combined)
            }
        }
    }

    private func allocate(for newSize: CGSize) {
        pixelBuffer?.deallocate()
        bWidth = max(1, Int(newSize.width) / scale)
        bHeight = max(1, Int(newSize.height) / scale)
        let count = bWidth * bHeight
        intensity = [UInt8](repeating: 0, count: count)
        pixelBuffer = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
    }

    // MARK: - Palettes

    private static func makePalette(named name: String) -> [UInt32] {
        switch name {
        case "Sunset":
            return gradient([(0,(0,0,0)),(40,(60,0,40)),(120,(220,80,30)),(200,(255,200,80)),(255,(255,255,200))])
        case "Forest":
            return gradient([(0,(0,0,0)),(60,(0,40,20)),(140,(40,160,60)),(220,(180,255,160)),(255,(255,255,200))])
        case "Cyberpunk":
            return gradient([(0,(0,0,0)),(60,(20,0,60)),(120,(255,0,180)),(190,(0,255,200)),(255,(255,255,255))])
        default: // Neon
            return gradient([(0,(0,0,0)),(60,(0,30,80)),(140,(0,180,255)),(210,(255,0,180)),(255,(255,255,255))])
        }
    }

    private static func gradient(_ stops: [(Int, (UInt8, UInt8, UInt8))]) -> [UInt32] {
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
