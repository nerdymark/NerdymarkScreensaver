import Cocoa

/// Flag wave: render the chosen flag (Pride, Trans, USA, Palestine, Ukraine,
/// or random) into a pre-rendered offscreen image with the correct stripes
/// and overlay shape (rectangle canton for USA, triangle for Palestine),
/// then warp it column-by-column to simulate fabric flapping in wind.
///
/// Wave model: the LEFT edge is anchored (pole), wave amplitude grows with
/// distance from the pole, vertical displacement = amp(x) * sin(kx - ωt),
/// and per-column shading darkens troughs / brightens peaks for fabric
/// depth.
final class FlagWaveScene: DemoScene {
    static let identifier = "flag_wave"
    static let displayName = "Flag Wave"

    static let options: [SceneOption] = [
        .slider(key: "amplitude", label: "Wave Amplitude", min: 5, max: 80, defaultValue: 28, format: "%.0f px"),
        .slider(key: "frequency", label: "Wave Frequency", min: 0.005, max: 0.05, defaultValue: 0.018, format: "%.3f"),
        .slider(key: "speed", label: "Wave Speed", min: 0.3, max: 4, defaultValue: 1.5, format: "%.1f"),
        .slider(key: "shading", label: "Fabric Shading", min: 0, max: 1.0, defaultValue: 0.45, format: "%.2f"),
        .slider(key: "secondsPerFlag", label: "Cycle Duration", min: 10, max: 120, defaultValue: 45, format: "%.0fs"),
        .choice(key: "flag", label: "Flag",
                choices: ["Random", "Pride Rainbow", "Transgender", "USA", "Palestine", "Ukraine"],
                defaultValue: "Random"),
    ]

    private enum Overlay {
        case none
        /// Upper-left rectangle, width = fraction of flag width.
        case canton(color: CGColor, widthFraction: CGFloat, heightFraction: CGFloat)
        /// Triangle anchored on left edge, apex extending to the right.
        /// Apex x = `apexFraction` * flag width.
        case triangle(color: CGColor, apexFraction: CGFloat)
    }

    private struct FlagDef {
        let name: String
        let stripes: [CGColor]   // top to bottom
        let overlay: Overlay
    }

    private static let flags: [FlagDef] = [
        FlagDef(name: "Pride Rainbow", stripes: [
            CGColor(red: 0.90, green: 0.0, blue: 0.0, alpha: 1),
            CGColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1),
            CGColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1),
            CGColor(red: 0.0, green: 0.7, blue: 0.0, alpha: 1),
            CGColor(red: 0.0, green: 0.4, blue: 0.95, alpha: 1),
            CGColor(red: 0.5, green: 0.0, blue: 0.6, alpha: 1),
        ], overlay: .none),
        FlagDef(name: "Transgender", stripes: [
            CGColor(red: 0.36, green: 0.81, blue: 0.98, alpha: 1),
            CGColor(red: 0.96, green: 0.66, blue: 0.72, alpha: 1),
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            CGColor(red: 0.96, green: 0.66, blue: 0.72, alpha: 1),
            CGColor(red: 0.36, green: 0.81, blue: 0.98, alpha: 1),
        ], overlay: .none),
        FlagDef(name: "USA", stripes: (0..<13).map { i in
            i % 2 == 0
                ? CGColor(red: 0.70, green: 0.10, blue: 0.18, alpha: 1)
                : CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        }, overlay: .canton(color: CGColor(red: 0.0, green: 0.15, blue: 0.45, alpha: 1),
                             widthFraction: 0.4, heightFraction: 7.0 / 13.0)),
        FlagDef(name: "Palestine", stripes: [
            CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1),
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            CGColor(red: 0.0, green: 0.45, blue: 0.20, alpha: 1),
        ], overlay: .triangle(color: CGColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1),
                               apexFraction: 0.30)),
        FlagDef(name: "Ukraine", stripes: [
            CGColor(red: 0.0, green: 0.34, blue: 0.72, alpha: 1),
            CGColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1),
        ], overlay: .none),
    ]

    private var size: CGSize = .zero
    private let amplitude: CGFloat
    private let frequency: Double
    private let speed: Double
    private let shading: Double
    private let secondsPerFlag: Double
    private let flagPick: String

    private var elapsed: Double = 0
    private var currentFlagIdx = 0
    private var currentFlagSwitchedAt: Double = 0

    // Cached pre-rendered flag image (rebuilt when flag or rect size changes).
    private var flagImage: CGImage?
    private var flagImageForIdx: Int = -1
    private var flagImagePixelSize: CGSize = .zero

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.amplitude = CGFloat(settings.double("amplitude", default: 28))
        self.frequency = settings.double("frequency", default: 0.018)
        self.speed = settings.double("speed", default: 1.5)
        self.shading = settings.double("shading", default: 0.45)
        self.secondsPerFlag = settings.double("secondsPerFlag", default: 45)
        self.flagPick = settings.string("flag", default: "Random")
        currentFlagIdx = pickFlagIndex()
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        elapsed += dt
        if flagPick == "Random" && elapsed - currentFlagSwitchedAt > secondsPerFlag {
            currentFlagIdx = (currentFlagIdx + 1) % FlagWaveScene.flags.count
            currentFlagSwitchedAt = elapsed
            flagImage = nil   // force rebuild for new flag
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize

        // Black background.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Compute flag rect (centered, with margin + room for vertical sway).
        let margin: CGFloat = 60
        let flagRect = CGRect(x: margin, y: margin + amplitude,
                               width: targetSize.width - margin * 2,
                               height: targetSize.height - margin * 2 - amplitude * 2)

        // Make sure cached image matches current flag + rect dimensions.
        ensureFlagImage(rect: flagRect)
        guard let img = flagImage else {
            drawFlagLabel(name: FlagWaveScene.flags[currentFlagIdx].name, ctx: ctx, in: targetSize)
            return
        }

        // Render the flag image as a series of vertical strips, each shifted
        // vertically by the wave function. Anchor on the LEFT (pole), so
        // amplitude scales 0→1 left-to-right.
        let stripWidth: CGFloat = 4
        let imgW = CGFloat(img.width)
        let imgH = CGFloat(img.height)
        let dstW = flagRect.width
        let dstH = flagRect.height
        let xToImgX = imgW / dstW
        var x: CGFloat = 0
        while x < dstW {
            let xNorm = Double(x) / Double(dstW)
            let anchor = pow(xNorm, 0.85)   // 0 at pole, ~1 at fly end
            let phase = (Double(x) * frequency) - elapsed * speed
            let yOff = CGFloat(sin(phase) * Double(amplitude)) * CGFloat(anchor)
            // Slight horizontal compression at peaks (cos -> 0 = at peak).
            let xCompress = CGFloat(cos(phase)) * 0.5
            let actualStripW = stripWidth + xCompress * 0.6
            // Per-strip light/dark shading: dark at troughs (sin negative)
            // plus a "behind a fold" effect where cos changes sign.
            let shadeBase = CGFloat(0.5 + cos(phase) * 0.5)   // 0..1 across the wave
            let brightness = 1.0 - CGFloat(shading) * (1 - shadeBase) * CGFloat(anchor)

            // Source image strip.
            let srcX = Int((x * xToImgX).rounded(.down))
            let srcW = max(1, Int((actualStripW * xToImgX).rounded(.up)))
            let srcRect = CGRect(x: srcX, y: 0,
                                  width: min(Int(imgW) - srcX, srcW),
                                  height: Int(imgH))
            guard let stripImg = img.cropping(to: srcRect) else {
                x += stripWidth
                continue
            }
            let dstRect = CGRect(x: flagRect.minX + x,
                                  y: flagRect.minY + yOff,
                                  width: actualStripW + 1,
                                  height: dstH)
            ctx.saveGState()
            if shading > 0 && brightness < 1 {
                // Apply shading by drawing then overlaying a translucent black.
                ctx.draw(stripImg, in: dstRect)
                ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1 - brightness))
                ctx.fill(dstRect)
            } else {
                ctx.draw(stripImg, in: dstRect)
            }
            ctx.restoreGState()
            x += stripWidth
        }

        drawFlagLabel(name: FlagWaveScene.flags[currentFlagIdx].name, ctx: ctx, in: targetSize)
    }

    // MARK: - Pre-rendered flag image

    private func ensureFlagImage(rect: CGRect) {
        let pixelW = max(1, Int(rect.width))
        let pixelH = max(1, Int(rect.height))
        let needed = CGSize(width: pixelW, height: pixelH)
        if flagImage != nil && flagImageForIdx == currentFlagIdx && flagImagePixelSize == needed {
            return
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let bmp = CGContext(data: nil, width: pixelW, height: pixelH,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: cs, bitmapInfo: bi) else { return }
        let flag = FlagWaveScene.flags[currentFlagIdx]
        // Draw stripes top-to-bottom. CGContext bitmap is bottom-up coords by
        // default — top of flag = high y in CG terms.
        let stripeH = CGFloat(pixelH) / CGFloat(flag.stripes.count)
        for (i, color) in flag.stripes.enumerated() {
            // stripes[0] is the top stripe.
            let topY = CGFloat(pixelH) - CGFloat(i + 1) * stripeH
            bmp.setFillColor(color)
            bmp.fill(CGRect(x: 0, y: topY, width: CGFloat(pixelW), height: stripeH + 1))
        }
        // Overlay.
        switch flag.overlay {
        case .none:
            break
        case .canton(let color, let wf, let hf):
            // Upper-left rectangle: high y in CG bitmap coords.
            let cw = CGFloat(pixelW) * wf
            let ch = CGFloat(pixelH) * hf
            bmp.setFillColor(color)
            bmp.fill(CGRect(x: 0, y: CGFloat(pixelH) - ch, width: cw, height: ch))
        case .triangle(let color, let apexFraction):
            // Triangle anchored on left edge with apex at (apexFraction*W, H/2).
            bmp.setFillColor(color)
            bmp.beginPath()
            bmp.move(to: CGPoint(x: 0, y: 0))
            bmp.addLine(to: CGPoint(x: 0, y: CGFloat(pixelH)))
            bmp.addLine(to: CGPoint(x: CGFloat(pixelW) * apexFraction, y: CGFloat(pixelH) / 2))
            bmp.closePath()
            bmp.fillPath()
        }
        flagImage = bmp.makeImage()
        flagImageForIdx = currentFlagIdx
        flagImagePixelSize = needed
    }

    // MARK: - Helpers

    private func drawFlagLabel(name: String, ctx: CGContext, in s: CGSize) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]
        let str = NSAttributedString(string: name.uppercased(), attributes: attrs)
        let txtSize = str.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: CGPoint(x: (s.width - txtSize.width) / 2, y: 16))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func pickFlagIndex() -> Int {
        if flagPick == "Random" { return Int.random(in: 0..<FlagWaveScene.flags.count) }
        return FlagWaveScene.flags.firstIndex(where: { $0.name == flagPick }) ?? 0
    }
}
