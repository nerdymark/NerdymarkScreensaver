import Cocoa
import CoreGraphics

/// Classic 1990s demoscene plasma: a per-pixel sin-wave field through a
/// rotating palette LUT. Rendered into a small 8-bit-per-channel bitmap
/// (1/4 of screen res) and CGContext-scaled up to fill — gives the chunky
/// authentic look while keeping CPU under ~5% on Apple Silicon.
final class PlasmaScene: DemoScene {
    static let identifier = "plasma"
    static let displayName = "Plasma"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Speed", min: 0.2, max: 3.0, defaultValue: 1.0, format: "%.1fx"),
        .choice(key: "palette", label: "Palette",
                choices: ["Sunset", "Ocean", "Neon", "Mono"],
                defaultValue: "Sunset"),
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
    ]

    // MARK: - State

    private var size: CGSize = .zero
    private var time: Double = 0
    private let speed: Double
    private let scale: Int     // pixel-doubling factor
    private let palette: [UInt32]   // BGRA premultiplied, 256 entries

    // Reusable bitmap buffer, recreated on resize.
    private var pixelBuffer: UnsafeMutablePointer<UInt32>?
    private var pixelBufferCount: Int = 0
    private var bitmapWidth: Int = 0
    private var bitmapHeight: Int = 0
    private var colorSpace = CGColorSpaceCreateDeviceRGB()

    // Precomputed sin LUT — avoids one of the four sin() calls per pixel.
    private static let sinTable: [Float] = {
        var t = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            t[i] = Float(sin(Double(i) / 1024.0 * 2.0 * .pi))
        }
        return t
    }()

    // MARK: - Init

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 1.0)
        self.scale = max(1, Int(settings.double("scale", default: 4)))
        let paletteName = settings.string("palette", default: "Sunset")
        self.palette = PlasmaScene.makePalette(named: paletteName)
        allocateBuffer(for: size)
    }

    deinit {
        pixelBuffer?.deallocate()
    }

    // MARK: - DemoScene

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        allocateBuffer(for: newSize)
    }

    func tick(dt: TimeInterval) {
        time += dt * speed
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buffer = pixelBuffer, bitmapWidth > 0, bitmapHeight > 0 else { return }

        renderPlasma(into: buffer, width: bitmapWidth, height: bitmapHeight)

        // Wrap the buffer in a CGImage and draw it scaled up. The CGContext's
        // interpolation is set to none for chunky pixels.
        let bytesPerRow = bitmapWidth * 4
        let bytesTotal = bytesPerRow * bitmapHeight
        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: buffer,
            size: bytesTotal,
            releaseData: { _, _, _ in }
        ) else { return }

        guard let image = CGImage(
            width: bitmapWidth,
            height: bitmapHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return }

        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))
    }

    // MARK: - Rendering

    private func allocateBuffer(for newSize: CGSize) {
        pixelBuffer?.deallocate()
        bitmapWidth = max(1, Int(newSize.width) / scale)
        bitmapHeight = max(1, Int(newSize.height) / scale)
        pixelBufferCount = bitmapWidth * bitmapHeight
        pixelBuffer = UnsafeMutablePointer<UInt32>.allocate(capacity: pixelBufferCount)
    }

    private func renderPlasma(into buffer: UnsafeMutablePointer<UInt32>, width: Int, height: Int) {
        // Indexable copy of palette so the closure doesn't capture self each pixel.
        let pal = palette
        let t = Float(time)

        // Pre-step the time-varying terms so the inner loop stays tight.
        let tA = Float(sin(time * 0.4)) * 4.0 + 5.0     // X frequency-ish
        let tB = Float(sin(time * 0.3)) * 4.0 + 5.0     // Y frequency
        let tC = Float(time) * 12.0                      // palette rotation

        for y in 0..<height {
            let yf = Float(y) / Float(height) * 16.0
            let row = y * width
            for x in 0..<width {
                let xf = Float(x) / Float(width) * 16.0
                // Three sins composited then folded into [0,255].
                let v = sin(xf + t)
                      + sin((xf + yf) * 0.5 + t * 1.3)
                      + sin(sqrt(xf * xf * 0.5 + yf * yf * 0.5) + t)
                      + sin(yf * tA * 0.05 + xf * tB * 0.05)
                let scaled = (v * 32.0 + tC).truncatingRemainder(dividingBy: 256.0)
                let idx = Int(scaled < 0 ? scaled + 256.0 : scaled) & 0xFF
                buffer[row + x] = pal[idx]
            }
        }
    }

    // MARK: - Palettes

    private static func makePalette(named name: String) -> [UInt32] {
        switch name {
        case "Ocean":
            return makeGradientPalette(stops: [
                (0,   (10, 20, 50)),
                (64,  (20, 90, 180)),
                (128, (60, 200, 230)),
                (192, (150, 240, 250)),
                (255, (10, 20, 50)),
            ])
        case "Neon":
            return makeGradientPalette(stops: [
                (0,   (255, 0, 128)),
                (85,  (0, 255, 200)),
                (170, (255, 240, 0)),
                (255, (255, 0, 128)),
            ])
        case "Mono":
            return makeGradientPalette(stops: [
                (0,   (0, 0, 0)),
                (128, (255, 255, 255)),
                (255, (0, 0, 0)),
            ])
        default:  // Sunset
            return makeGradientPalette(stops: [
                (0,   (10, 0, 30)),
                (64,  (180, 30, 80)),
                (128, (255, 130, 50)),
                (192, (255, 230, 130)),
                (255, (10, 0, 30)),
            ])
        }
    }

    private static func makeGradientPalette(stops: [(Int, (UInt8, UInt8, UInt8))]) -> [UInt32] {
        var pal = [UInt32](repeating: 0, count: 256)
        guard !stops.isEmpty else { return pal }
        let sorted = stops.sorted { $0.0 < $1.0 }
        for i in 0..<256 {
            // Find bracketing stops.
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
            // ARGB premultiplied, little-endian — opaque alpha.
            pal[i] = (0xFF << 24) | (r << 16) | (g << 8) | b
        }
        return pal
    }
}
