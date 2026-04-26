import Cocoa
import CoreGraphics

/// Liquid-glass Apple logo: large  glyph in the screen center, with a
/// continuously-shifting rainbow palette behind it that's distorted by
/// per-pixel sin-wave refraction. The logo itself is rendered as a clipping
/// mask so the rainbow only shows inside its silhouette; outside the
/// silhouette is solid black with a faint glow for the "glass" feel.
final class AppleEventScene: DemoScene {
    static let identifier = "apple_event"
    static let displayName = "Apple Event"

    static let options: [SceneOption] = [
        .slider(key: "logoScale", label: "Logo Size", min: 0.2, max: 0.9, defaultValue: 0.55, format: "%.0f%%"),
        .slider(key: "speed", label: "Animation Speed", min: 0.2, max: 3.0, defaultValue: 1.0, format: "%.1fx"),
        .slider(key: "refractionStrength", label: "Refraction", min: 0, max: 30, defaultValue: 12, format: "%.0f px"),
        .slider(key: "scale", label: "Pixel Size", min: 1, max: 6, defaultValue: 2, format: "%.0fx"),
        .toggle(key: "glow", label: "Outer glow halo", defaultValue: true),
        .choice(key: "logoColor", label: "Logo Outline",
                choices: ["None", "White", "Soft Glow", "Mirror"],
                defaultValue: "Mirror"),
    ]

    private var size: CGSize = .zero
    private let logoScale: CGFloat
    private let speed: Double
    private let refractionStrength: Float
    private let scale: Int
    private let glow: Bool
    private let logoColor: String

    private var bitmap: PaletteBitmap
    private let palette: [UInt32] = AppleEventScene.makeRainbowPalette()
    private var time: Double = 0

    /// Pre-rasterized alpha mask of the Apple glyph at low res (matches the
    /// PaletteBitmap dimensions). Recomputed on resize.
    private var maskAlpha: [UInt8] = []   // 0=outside, 255=inside
    private var maskValid: Bool = false

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.logoScale = CGFloat(settings.double("logoScale", default: 0.55))
        self.speed = settings.double("speed", default: 1.0)
        self.refractionStrength = Float(settings.double("refractionStrength", default: 12))
        self.scale = max(1, Int(settings.double("scale", default: 2)))
        self.glow = settings.bool("glow", default: true)
        self.logoColor = settings.string("logoColor", default: "Mirror")
        self.bitmap = PaletteBitmap(width: max(1, Int(size.width) / scale),
                                     height: max(1, Int(size.height) / scale))
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        bitmap.resize(width: max(1, Int(newSize.width) / scale),
                       height: max(1, Int(newSize.height) / scale))
        maskValid = false
    }

    func tick(dt: TimeInterval) { time += dt * speed }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = bitmap.pixels else { return }
        let w = bitmap.width, h = bitmap.height

        // Background: solid black (the glass sits over a void).
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Lazily render the alpha mask of the Apple glyph at bitmap resolution.
        if !maskValid || maskAlpha.count != w * h {
            renderMask()
            maskValid = true
        }

        // For each pixel, compute a refracted lookup into the rainbow palette.
        // Refraction: shift sample coordinates by sin(t + x/y).
        let pal = palette
        let t = Float(time)
        let r = refractionStrength
        let cx = Float(w) / 2, cy = Float(h) / 2

        for y in 0..<h {
            let row = y * w
            for x in 0..<w {
                let m = maskAlpha[row + x]
                if m == 0 {
                    buf[row + x] = 0xFF000000   // opaque black
                    continue
                }
                // Refraction: sample shifts by sin waves to fake glass.
                let xf = Float(x) - cx
                let yf = Float(y) - cy
                let dx = sin(yf * 0.05 + t * 1.3) * r
                let dy = cos(xf * 0.05 + t * 1.7) * r
                // Rainbow lookup: hue from radial distance + time + refraction.
                let dist = sqrt((xf + dx) * (xf + dx) + (yf + dy) * (yf + dy))
                let hueIdx = Int((dist * 0.5 + t * 30.0).truncatingRemainder(dividingBy: 256.0))
                let safe = (hueIdx + 256) & 0xFF
                buf[row + x] = pal[safe]
            }
        }
        bitmap.present(in: ctx, size: targetSize, smooth: true)

        // Optional: draw a faint outer halo around the logo silhouette as
        // glass-like glow (full-res, drawn over the upscaled bitmap).
        if glow {
            drawHalo(ctx: ctx, targetSize: targetSize)
        }
        if logoColor != "None" {
            drawLogoOutline(ctx: ctx, targetSize: targetSize)
        }
    }

    // MARK: - Mask rendering

    private func renderMask() {
        let w = bitmap.width
        let h = bitmap.height
        let count = w * h
        maskAlpha = [UInt8](repeating: 0, count: count)

        // Render the Apple glyph into a grayscale CGContext at bitmap res,
        // then read alpha values back into our mask array.
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Render the glyph as white. We use the Unicode Apple logo character
        // U+F8FF — rendered with the system font macOS provides.
        let fontSize = CGFloat(min(w, h)) * logoScale
        let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let glyph = "\u{F8FF}"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 1, alpha: 1),
        ]
        let str = NSAttributedString(string: glyph, attributes: attrs)
        let textSize = str.size()
        let drawX = (CGFloat(w) - textSize.width) / 2
        let drawY = (CGFloat(h) - textSize.height) / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: CGPoint(x: drawX, y: drawY))
        NSGraphicsContext.restoreGraphicsState()

        // Read pixels.
        if let data = ctx.data {
            let bytes = data.bindMemory(to: UInt8.self, capacity: count)
            for i in 0..<count {
                maskAlpha[i] = bytes[i]
            }
        }
    }

    private func drawLogoOutline(ctx: CGContext, targetSize: CGSize) {
        let fontSize = min(targetSize.width, targetSize.height) * logoScale
        let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let glyph = "\u{F8FF}"

        let strokeColor: NSColor
        switch logoColor {
        case "White":     strokeColor = NSColor.white.withAlphaComponent(0.4)
        case "Soft Glow": strokeColor = NSColor.white.withAlphaComponent(0.18)
        default:          strokeColor = NSColor(white: 0.95, alpha: 0.55)  // Mirror
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.clear,
            .strokeColor: strokeColor,
            .strokeWidth: -3,
        ]
        let str = NSAttributedString(string: glyph, attributes: attrs)
        let textSize = str.size()
        let drawX = (targetSize.width - textSize.width) / 2
        let drawY = (targetSize.height - textSize.height) / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: CGPoint(x: drawX, y: drawY))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHalo(ctx: CGContext, targetSize: CGSize) {
        // Soft white glow approximated by drawing the glyph multiple times
        // with shadow at varying opacities.
        let fontSize = min(targetSize.width, targetSize.height) * logoScale
        let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let glyph = "\u{F8FF}"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.clear,
        ]
        let str = NSAttributedString(string: glyph, attributes: attrs)
        let textSize = str.size()
        let drawX = (targetSize.width - textSize.width) / 2
        let drawY = (targetSize.height - textSize.height) / 2

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 28,
                       color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        // Draw a faint white-stroked version to seed the shadow.
        let glowAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 1, alpha: 0.05),
        ]
        NSAttributedString(string: glyph, attributes: glowAttrs)
            .draw(at: CGPoint(x: drawX, y: drawY))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
        _ = attrs   // silence unused warning if any
        _ = str
    }

    // MARK: - Palette

    private static func makeRainbowPalette() -> [UInt32] {
        // Full spectrum hue cycle, max saturation/brightness. 256 entries.
        var pal = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            let hue = CGFloat(i) / 256.0
            let c = NSColor(hue: hue, saturation: 0.95, brightness: 1.0, alpha: 1)
            let r = UInt32((c.redComponent * 255).rounded())
            let g = UInt32((c.greenComponent * 255).rounded())
            let b = UInt32((c.blueComponent * 255).rounded())
            pal[i] = (0xFF << 24) | (r << 16) | (g << 8) | b
        }
        return pal
    }
}
