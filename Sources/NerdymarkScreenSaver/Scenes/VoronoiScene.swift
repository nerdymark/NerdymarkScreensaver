import Cocoa

/// Voronoi diagram with moving sites. Each pixel is colored by the closest
/// site. Sites drift with sin/cos motion. Renders into a low-res buffer
/// then bilinear-upscales for performance.
final class VoronoiScene: DemoScene {
    static let identifier = "voronoi"
    static let displayName = "Voronoi Cells"

    static let options: [SceneOption] = [
        .slider(key: "siteCount", label: "Cell Count", min: 8, max: 80, defaultValue: 28, format: "%.0f"),
        .slider(key: "speed", label: "Drift Speed", min: 0.05, max: 1.0, defaultValue: 0.25, format: "%.2f"),
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
        .toggle(key: "showSites", label: "Show site dots", defaultValue: true),
        .toggle(key: "showEdges", label: "Show cell edges", defaultValue: true),
        .choice(key: "palette", label: "Palette",
                choices: ["Sunset", "Cool", "Spectrum", "Mono"],
                defaultValue: "Sunset"),
    ]

    private struct Site {
        var baseX: Double
        var baseY: Double
        var phaseX: Double
        var phaseY: Double
        var ampX: Double
        var ampY: Double
        var color: UInt32
    }

    private var size: CGSize = .zero
    private let siteCount: Int
    private let speed: Double
    private let pixelScale: Int
    private let showSites: Bool
    private let showEdges: Bool
    private let paletteName: String

    private var sites: [Site] = []
    private var bufW: Int = 0
    private var bufH: Int = 0
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var indexBuf: [UInt8] = []
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.siteCount = max(2, Int(settings.double("siteCount", default: 28)))
        self.speed = settings.double("speed", default: 0.25)
        self.pixelScale = max(2, Int(settings.double("scale", default: 4)))
        self.showSites = settings.bool("showSites", default: true)
        self.showEdges = settings.bool("showEdges", default: true)
        self.paletteName = settings.string("palette", default: "Sunset")
        seedSites()
        allocateBuf(for: size)
    }

    deinit { pixels?.deallocate() }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        seedSites()
        allocateBuf(for: newSize)
    }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = pixels, !sites.isEmpty else { return }

        // Compute current site positions (avoid recomputing per-pixel).
        var currentX = [Double](repeating: 0, count: sites.count)
        var currentY = [Double](repeating: 0, count: sites.count)
        for i in 0..<sites.count {
            let s = sites[i]
            currentX[i] = s.baseX + sin(elapsed * speed + s.phaseX) * s.ampX
            currentY[i] = s.baseY + cos(elapsed * speed * 1.3 + s.phaseY) * s.ampY
        }

        let bw = bufW, bh = bufH
        let scale = Double(pixelScale)
        for y in 0..<bh {
            let py = Double(y) * scale + scale / 2
            for x in 0..<bw {
                let px = Double(x) * scale + scale / 2
                var bestI = 0
                var bestD = Double.infinity
                var secondD = Double.infinity
                for i in 0..<sites.count {
                    let dx = px - currentX[i]
                    let dy = py - currentY[i]
                    let d = dx * dx + dy * dy
                    if d < bestD { secondD = bestD; bestD = d; bestI = i }
                    else if d < secondD { secondD = d }
                }
                let bufIdx = y * bw + x
                indexBuf[bufIdx] = UInt8(bestI & 0xFF)
                // Edge: small difference between best & second-best distance.
                let edgeFrac = (sqrt(secondD) - sqrt(bestD))
                if showEdges && edgeFrac < 1.5 {
                    buf[bufIdx] = 0xFF000000  // black
                } else {
                    buf[bufIdx] = sites[bestI].color
                }
            }
        }

        let bytesPerRow = bw * 4
        guard let provider = CGDataProvider(dataInfo: nil, data: buf, size: bytesPerRow * bh, releaseData: { _, _, _ in }),
              let image = CGImage(width: bw, height: bh, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: bytesPerRow, space: colorSpace,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))

        if showSites {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
            for i in 0..<sites.count {
                let cx = CGFloat(currentX[i])
                let cy = CGFloat(currentY[i])
                ctx.fillEllipse(in: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
            }
        }
    }

    // MARK: - Setup

    private func seedSites() {
        sites = (0..<siteCount).map { i in
            let hue = Double(i) / Double(siteCount)
            let color = colorForSite(hue: hue, index: i)
            return Site(
                baseX: Double.random(in: 0...Double(size.width)),
                baseY: Double.random(in: 0...Double(size.height)),
                phaseX: Double.random(in: 0..<(2 * .pi)),
                phaseY: Double.random(in: 0..<(2 * .pi)),
                ampX: Double.random(in: 30...100),
                ampY: Double.random(in: 30...100),
                color: color
            )
        }
    }

    private func allocateBuf(for newSize: CGSize) {
        pixels?.deallocate()
        bufW = max(1, Int(newSize.width) / pixelScale)
        bufH = max(1, Int(newSize.height) / pixelScale)
        pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: bufW * bufH)
        indexBuf = [UInt8](repeating: 0, count: bufW * bufH)
    }

    private func colorForSite(hue: Double, index: Int) -> UInt32 {
        let (r, g, b): (Double, Double, Double)
        switch paletteName {
        case "Cool":
            r = 0.1 + 0.4 * hue; g = 0.4 + 0.4 * hue; b = 0.7 + 0.3 * (1 - hue)
        case "Spectrum":
            let c = NSColor(hue: CGFloat(hue), saturation: 0.7, brightness: 0.95, alpha: 1)
            r = Double(c.redComponent); g = Double(c.greenComponent); b = Double(c.blueComponent)
        case "Mono":
            let v = 0.2 + 0.7 * hue
            r = v; g = v; b = v
        default: // Sunset
            r = 0.4 + 0.5 * hue; g = 0.2 + 0.4 * hue; b = 0.5 - 0.3 * hue
        }
        let R = UInt32(max(0, min(255, r * 255)))
        let G = UInt32(max(0, min(255, g * 255)))
        let B = UInt32(max(0, min(255, b * 255)))
        return (0xFF << 24) | (R << 16) | (G << 8) | B
    }
}
