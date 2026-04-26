import Cocoa

/// Moiré: two periodic patterns rotated against each other produce
/// large-scale beating fringes. Two sets of concentric rings, each rotating
/// independently. The pattern is rendered ONCE into an offscreen bitmap
/// per layer (color); the per-frame work is just a translate+rotate+draw of
/// the cached image. Avoids drawing hundreds of large stroked shapes per
/// frame, which previously triggered the macOS screensaver CPU watchdog.
final class MoireScene: DemoScene {
    static let identifier = "moire"
    static let displayName = "Moiré"

    static let options: [SceneOption] = [
        .slider(key: "spacing", label: "Pattern Spacing", min: 8, max: 36, defaultValue: 16, format: "%.0f px"),
        .slider(key: "rotSpeedA", label: "Speed A", min: 0.0, max: 0.5, defaultValue: 0.05, format: "%.2f rad/s"),
        .slider(key: "rotSpeedB", label: "Speed B", min: 0.0, max: 0.5, defaultValue: 0.07, format: "%.2f rad/s"),
        .choice(key: "pattern", label: "Pattern",
                choices: ["Lines", "Concentric Rings", "Hex Grid"],
                defaultValue: "Concentric Rings"),
        .choice(key: "tint", label: "Tint",
                choices: ["Mono", "Cyan-Magenta", "Phosphor Green"],
                defaultValue: "Cyan-Magenta"),
    ]

    private var size: CGSize = .zero
    private let spacing: CGFloat
    private let rotSpeedA: Double
    private let rotSpeedB: Double
    private let pattern: String
    private let tint: String

    private var angleA: Double = 0
    private var angleB: Double = 0
    private var elapsed: Double = 0

    // Cached pre-rendered patterns (one per color/layer).
    private var imageA: CGImage?
    private var imageB: CGImage?
    private var imageSide: CGFloat = 0  // square side length
    private var cacheBuiltForSize: CGSize = .zero

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.spacing = max(8, CGFloat(settings.double("spacing", default: 16)))
        self.rotSpeedA = settings.double("rotSpeedA", default: 0.05)
        self.rotSpeedB = settings.double("rotSpeedB", default: 0.07)
        self.pattern = settings.string("pattern", default: "Concentric Rings")
        self.tint = settings.string("tint", default: "Cyan-Magenta")
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        elapsed += dt
        angleA += dt * rotSpeedA
        angleB += dt * rotSpeedB
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ensureCachedImages()
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let cx = targetSize.width / 2
        let cy = targetSize.height / 2
        let half = imageSide / 2
        let rect = CGRect(x: -half, y: -half, width: imageSide, height: imageSide)

        if let imgA = imageA {
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(angleA))
            ctx.draw(imgA, in: rect)
            ctx.restoreGState()
        }

        if let imgB = imageB {
            ctx.saveGState()
            // Drift the second layer slightly so concentric ring centers don't
            // coincide — that's what produces the moving fringe pattern.
            ctx.translateBy(x: cx + sin(elapsed * 0.3) * 80, y: cy + cos(elapsed * 0.4) * 60)
            ctx.rotate(by: CGFloat(angleB))
            ctx.setBlendMode(.screen)
            ctx.draw(imgB, in: rect)
            ctx.restoreGState()
            ctx.setBlendMode(.normal)
        }
    }

    // MARK: - Pattern rendering (cached)

    private func ensureCachedImages() {
        if imageA != nil && cacheBuiltForSize == size { return }
        // Image side covers the diagonal so rotation never reveals corners.
        let diag = sqrt(size.width * size.width + size.height * size.height)
        imageSide = diag + spacing * 2
        let pixelSide = Int(imageSide.rounded(.up))
        guard pixelSide > 0 else { return }

        let (colA, colB) = colors()
        imageA = renderPattern(pixelSide: pixelSide, color: colA)
        imageB = renderPattern(pixelSide: pixelSide, color: colB)
        cacheBuiltForSize = size
    }

    private func renderPattern(pixelSide: Int, color: CGColor) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: pixelSide, height: pixelSide,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: cs, bitmapInfo: bi) else { return nil }
        ctx.translateBy(x: CGFloat(pixelSide) / 2, y: CGFloat(pixelSide) / 2)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(1.0)
        drawPattern(into: ctx, extent: CGFloat(pixelSide) / 2)
        return ctx.makeImage()
    }

    private func drawPattern(into ctx: CGContext, extent: CGFloat) {
        switch pattern {
        case "Lines":
            var y = -extent
            ctx.beginPath()
            while y <= extent {
                ctx.move(to: CGPoint(x: -extent, y: y))
                ctx.addLine(to: CGPoint(x: extent, y: y))
                y += spacing
            }
            ctx.strokePath()
        case "Hex Grid":
            // Filled small dots are far cheaper than stroked ellipses.
            var y = -extent
            var row = 0
            let dotSize: CGFloat = 1.5
            while y <= extent {
                var x = -extent + (row % 2 == 0 ? 0 : spacing / 2)
                while x <= extent {
                    ctx.fill(CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
                    x += spacing
                }
                y += spacing * 0.866
                row += 1
            }
        default: // Concentric Rings — batched into a single path.
            ctx.beginPath()
            var r: CGFloat = spacing
            while r <= extent {
                ctx.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                r += spacing
            }
            ctx.strokePath()
        }
    }

    private func colors() -> (CGColor, CGColor) {
        switch tint {
        case "Mono":
            return (CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.7),
                    CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.7))
        case "Phosphor Green":
            return (CGColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 0.7),
                    CGColor(red: 0.0, green: 0.7, blue: 1.0, alpha: 0.7))
        default: // Cyan-Magenta
            return (CGColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.7),
                    CGColor(red: 1.0, green: 0.2, blue: 0.85, alpha: 0.7))
        }
    }
}

