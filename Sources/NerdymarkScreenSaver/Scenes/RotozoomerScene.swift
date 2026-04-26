import Cocoa
import CoreGraphics

/// Rotozoomer: a tiled procedural texture sampled with a continuously
/// changing rotation + scale. We don't ship a bitmap asset — the texture
/// is generated procedurally (checkerboard or "nerdymark" wordmark stamp).
final class RotozoomerScene: DemoScene {
    static let identifier = "rotozoomer"
    static let displayName = "Rotozoomer"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Pixel Size", min: 1, max: 6, defaultValue: 2, format: "%.0fx"),
        .slider(key: "spinSpeed", label: "Rotation", min: -2, max: 2, defaultValue: 0.5, format: "%.1f rad/s"),
        .slider(key: "zoomSpeed", label: "Zoom Pulse", min: 0.0, max: 2.0, defaultValue: 0.6, format: "%.1f"),
        .choice(key: "texture", label: "Texture",
                choices: ["Checker", "Wordmark", "Plus Grid"],
                defaultValue: "Checker"),
        .choice(key: "palette", label: "Color Scheme",
                choices: ["Sunset", "Vapor", "Mono", "Acid"],
                defaultValue: "Vapor"),
    ]

    private var size: CGSize = .zero
    private let scale: Int
    private let spinSpeed: Double
    private let zoomSpeed: Double
    private let textureName: String
    private let paletteName: String

    private var bitmap: PaletteBitmap
    private var texture: [UInt32] = []   // 256x256 ARGB texture, wraps
    private static let texSize = 256
    private static let texMask = 255    // for fast wrap

    private var time: Double = 0
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.scale = max(1, Int(settings.double("scale", default: 2)))
        self.spinSpeed = settings.double("spinSpeed", default: 0.5)
        self.zoomSpeed = settings.double("zoomSpeed", default: 0.6)
        self.textureName = settings.string("texture", default: "Checker")
        self.paletteName = settings.string("palette", default: "Vapor")
        self.bitmap = PaletteBitmap(width: max(1, Int(size.width) / scale),
                                     height: max(1, Int(size.height) / scale))
        buildTexture()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        bitmap.resize(width: max(1, Int(newSize.width) / scale),
                       height: max(1, Int(newSize.height) / scale))
    }

    func tick(dt: TimeInterval) { time += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = bitmap.pixels else { return }
        let w = bitmap.width, h = bitmap.height
        let cx = Float(w) / 2
        let cy = Float(h) / 2

        // Pulsing zoom + spin.
        let angle = Float(time * spinSpeed)
        let zoom = Float(0.6 + 0.4 * sin(time * zoomSpeed * 2.0))   // 0.2 .. 1.0
        let cosA = cos(angle) * zoom
        let sinA = sin(angle) * zoom

        let texMaskI = RotozoomerScene.texMask

        for y in 0..<h {
            let dy = Float(y) - cy
            let row = y * w
            for x in 0..<w {
                let dx = Float(x) - cx
                // Affine: u = cosA*dx + sinA*dy, v = -sinA*dx + cosA*dy
                let u = cosA * dx + sinA * dy + Float(time) * 12.0
                let v = -sinA * dx + cosA * dy + Float(time) * 8.0
                let ui = Int(u) & texMaskI
                let vi = Int(v) & texMaskI
                buf[row + x] = texture[vi * RotozoomerScene.texSize + ui]
            }
        }
        bitmap.present(in: ctx, size: targetSize, smooth: false)
    }

    // MARK: - Texture build

    private func buildTexture() {
        let n = RotozoomerScene.texSize
        let total = n * n
        texture = [UInt32](repeating: 0, count: total)
        let (a, b) = paletteColors()

        switch textureName {
        case "Wordmark":
            buildWordmarkTexture(into: &texture, color: a, bg: b)
        case "Plus Grid":
            buildPlusGridTexture(into: &texture, color: a, bg: b)
        default:
            buildCheckerTexture(into: &texture, colorA: a, colorB: b)
        }
    }

    private func buildCheckerTexture(into buf: inout [UInt32], colorA: UInt32, colorB: UInt32) {
        let n = RotozoomerScene.texSize
        let cellSize = 32
        for y in 0..<n {
            for x in 0..<n {
                let cellX = x / cellSize
                let cellY = y / cellSize
                buf[y * n + x] = ((cellX + cellY) & 1 == 0) ? colorA : colorB
            }
        }
    }

    private func buildPlusGridTexture(into buf: inout [UInt32], color: UInt32, bg: UInt32) {
        let n = RotozoomerScene.texSize
        let pitch = 32
        let armW = 4
        for y in 0..<n {
            for x in 0..<n {
                let modX = x % pitch
                let modY = y % pitch
                let inH = modY > pitch / 2 - armW && modY < pitch / 2 + armW
                let inV = modX > pitch / 2 - armW && modX < pitch / 2 + armW
                buf[y * n + x] = (inH || inV) ? color : bg
            }
        }
    }

    private func buildWordmarkTexture(into buf: inout [UInt32], color: UInt32, bg: UInt32) {
        let n = RotozoomerScene.texSize
        // Fill with bg, then render text into a CGContext, sample it.
        for i in 0..<(n*n) { buf[i] = bg }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: n, height: n,
            bitsPerComponent: 8, bytesPerRow: n * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        ctx.setFillColor(.clear)
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))

        let wordmark = "nerdymark"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .black),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: wordmark, attributes: attrs)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        // Tile twice diagonally.
        str.draw(at: CGPoint(x: 8, y: 60))
        str.draw(at: CGPoint(x: 8, y: 180))
        NSGraphicsContext.restoreGraphicsState()

        if let data = ctx.data {
            let bytes = data.bindMemory(to: UInt32.self, capacity: n * n)
            for i in 0..<(n*n) {
                // White pixel (high alpha) → text color, else bg.
                let pixel = bytes[i]
                let alpha = (pixel >> 24) & 0xFF
                buf[i] = alpha > 128 ? color : bg
            }
        }
    }

    private func paletteColors() -> (UInt32, UInt32) {
        switch paletteName {
        case "Sunset":
            return (0xFFFF6B35, 0xFF1A0A2E)
        case "Mono":
            return (0xFFEEEEEE, 0xFF111111)
        case "Acid":
            return (0xFFC8FF40, 0xFF1A2E10)
        default: // Vapor
            return (0xFFFF71CE, 0xFF01CDFE)
        }
    }
}
