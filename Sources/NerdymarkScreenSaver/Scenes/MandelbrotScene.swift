import Cocoa
import CoreGraphics

/// Mandelbrot set, rendered at low resolution and palette-mapped, with a
/// slow auto-zoom into a curated list of pretty viewpoints. When zoom hits
/// max, recenters on a new pretty location and starts over.
final class MandelbrotScene: DemoScene {
    static let identifier = "mandelbrot"
    static let displayName = "Mandelbrot Zoom"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 3, format: "%.0fx"),
        .slider(key: "maxIterations", label: "Detail (iterations)", min: 64, max: 512, defaultValue: 200, format: "%.0f"),
        .slider(key: "zoomSpeed", label: "Zoom Speed", min: 0.05, max: 0.5, defaultValue: 0.18, format: "%.2f"),
        .choice(key: "palette", label: "Palette",
                choices: ["Cosmic", "Sunset", "Ice", "Acid"],
                defaultValue: "Cosmic"),
    ]

    /// Curated coordinates known to land on filigree boundaries.
    private struct ZoomTarget {
        let centerX: Double
        let centerY: Double
        let maxZoom: Double
    }
    private let targets: [ZoomTarget] = [
        ZoomTarget(centerX: -0.743643887037151, centerY:  0.131825904205330, maxZoom: 1e7),  // seahorse valley
        ZoomTarget(centerX: -0.10109636384562,  centerY:  0.95628651080914,  maxZoom: 1e6),  // mini-Mandelbrot
        ZoomTarget(centerX: -0.7269,            centerY:  0.1889,            maxZoom: 1e5),  // spiral
        ZoomTarget(centerX:  0.2929859127507,   centerY:  0.6117848324958,   maxZoom: 5e6),  // detail near edge
    ]

    private var size: CGSize = .zero
    private let scale: Int
    private let maxIter: Int
    private let zoomSpeed: Double
    private let paletteName: String
    private var palette: [UInt32]
    private var bitmap: PaletteBitmap

    private var targetIndex = 0
    private var zoom: Double = 1.0      // multiplied each frame
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.scale = max(1, Int(settings.double("scale", default: 3)))
        self.maxIter = max(32, Int(settings.double("maxIterations", default: 200)))
        self.zoomSpeed = settings.double("zoomSpeed", default: 0.18)
        self.paletteName = settings.string("palette", default: "Cosmic")
        self.palette = MandelbrotScene.makePalette(named: paletteName)
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
        zoom *= 1.0 + zoomSpeed * dt
        let target = targets[targetIndex]
        if zoom > target.maxZoom {
            targetIndex = (targetIndex + 1) % targets.count
            zoom = 1.0
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = bitmap.pixels else { return }
        let w = bitmap.width, h = bitmap.height
        let target = targets[targetIndex]

        // Map screen → complex plane.
        let span: Double = 3.5 / zoom
        let halfW: Double = Double(w) / 2.0
        let halfH: Double = Double(h) / 2.0
        let pixelStep: Double = span / Double(w)
        let cy0: Double = target.centerY - halfH * pixelStep

        for py in 0..<h {
            let cy = cy0 + Double(py) * pixelStep
            let row = py * w
            for px in 0..<w {
                let cx = target.centerX + (Double(px) - halfW) * pixelStep
                buf[row + px] = mandelColor(cx: cx, cy: cy)
            }
        }
        bitmap.present(in: ctx, size: targetSize, smooth: true)
    }

    @inline(__always)
    private func mandelColor(cx: Double, cy: Double) -> UInt32 {
        var x = 0.0, y = 0.0
        var x2 = 0.0, y2 = 0.0
        var iter = 0
        let maxI = maxIter
        while x2 + y2 <= 4.0 && iter < maxI {
            y = (x + x) * y + cy
            x = x2 - y2 + cx
            x2 = x * x
            y2 = y * y
            iter += 1
        }
        if iter == maxI { return 0xFF000000 }
        // Smooth coloring (continuous escape).
        let logZn = log(x2 + y2) / 2.0
        let nu = log(logZn / log(2.0)) / log(2.0)
        let smooth = Double(iter) + 1.0 - nu
        let idx = Int(smooth * 4) & 0xFF
        return palette[idx]
    }

    private static func makePalette(named name: String) -> [UInt32] {
        let stops: [(Int, (UInt8, UInt8, UInt8))]
        switch name {
        case "Sunset":
            stops = [(0,(0,0,30)),(64,(180,30,80)),(128,(255,130,50)),(192,(255,230,130)),(255,(0,0,30))]
        case "Ice":
            stops = [(0,(5,5,30)),(64,(20,80,180)),(128,(80,180,240)),(192,(220,240,255)),(255,(5,5,30))]
        case "Acid":
            stops = [(0,(0,30,0)),(64,(20,180,30)),(128,(180,255,30)),(192,(80,255,180)),(255,(0,30,0))]
        default: // Cosmic
            stops = [(0,(5,0,30)),(64,(60,20,160)),(128,(180,80,220)),(192,(255,200,255)),(255,(5,0,30))]
        }
        return PlasmaPalette.gradient(stops)
    }
}
