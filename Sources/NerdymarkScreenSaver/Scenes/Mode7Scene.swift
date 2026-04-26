import Cocoa
import CoreGraphics

/// SNES Mode 7-style perspective floor: a 2D pattern projected as if you're
/// looking at a flat ground plane at an angle. The horizon sits in the
/// middle of the screen; closer ground samples larger; the camera scrolls
/// forward over an infinite checkered floor.
final class Mode7Scene: DemoScene {
    static let identifier = "mode7"
    static let displayName = "Mode 7 Floor"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Pixel Size", min: 1, max: 6, defaultValue: 2, format: "%.0fx"),
        .slider(key: "scrollSpeed", label: "Scroll Speed", min: 0.5, max: 8, defaultValue: 2.5, format: "%.1f"),
        .slider(key: "turnSpeed", label: "Turn Speed", min: 0, max: 1.5, defaultValue: 0.3, format: "%.2f rad/s"),
        .choice(key: "skyTint", label: "Sky",
                choices: ["Sunset", "Cyan", "Dusk", "Black"],
                defaultValue: "Sunset"),
        .choice(key: "floor", label: "Floor",
                choices: ["Checker", "Grid", "Vapor Tiles"],
                defaultValue: "Vapor Tiles"),
    ]

    private var size: CGSize = .zero
    private let scale: Int
    private let scrollSpeed: Double
    private let turnSpeed: Double
    private let skyTint: String
    private let floorPattern: String

    private var bitmap: PaletteBitmap
    private var time: Double = 0
    private var heading: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.scale = max(1, Int(settings.double("scale", default: 2)))
        self.scrollSpeed = settings.double("scrollSpeed", default: 2.5)
        self.turnSpeed = settings.double("turnSpeed", default: 0.3)
        self.skyTint = settings.string("skyTint", default: "Sunset")
        self.floorPattern = settings.string("floor", default: "Vapor Tiles")
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
        time += dt
        // Gentle sin-modulated turn so the camera meanders.
        heading += dt * turnSpeed * sin(time * 0.3)
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = bitmap.pixels else { return }
        let w = bitmap.width, h = bitmap.height
        let horizon = h / 2
        let camX = Float(time * scrollSpeed)
        let camY = Float(time * scrollSpeed * 0.5)
        let cosH = cos(Float(heading))
        let sinH = sin(Float(heading))

        let (skyTop, skyBottom) = skyColors()
        // Pre-extract sky channels — keeps the per-row math simple enough
        // for swiftc to type-check quickly.
        let topR = Double((skyTop >> 16) & 0xFF)
        let topG = Double((skyTop >> 8) & 0xFF)
        let topB = Double(skyTop & 0xFF)
        let botR = Double((skyBottom >> 16) & 0xFF)
        let botG = Double((skyBottom >> 8) & 0xFF)
        let botB = Double(skyBottom & 0xFF)
        let horizonD = Double(horizon)
        for y in 0..<horizon {
            let yFrac = Double(y) / horizonD
            let invFrac = 1.0 - yFrac
            let r = UInt32(yFrac * topR + invFrac * botR)
            let g = UInt32(yFrac * topG + invFrac * botG)
            let b = UInt32(yFrac * topB + invFrac * botB)
            let pix: UInt32 = (0xFF << 24) | (r << 16) | (g << 8) | b
            let row = (h - 1 - y) * w   // sky at top of screen
            for x in 0..<w {
                buf[row + x] = pix
            }
        }

        // Floor: standard Mode-7 raycaster equation.
        // For each row below horizon, distance to the camera plane is:
        //   d = focalLength * cameraHeight / row_below_horizon
        let focal = Float(h) * 0.6
        let cameraHeight: Float = 1.0

        for y in 0..<horizon {
            let rowBelowHorizon = Float(y + 1)
            let d = focal * cameraHeight / rowBelowHorizon
            let row = y * w   // y measured from bottom of screen here
            for x in 0..<w {
                // Map pixel to floor coords.
                let pxX = Float(x - w / 2)
                let worldX = (cosH * d - sinH * pxX) * 0.05 + camX
                let worldY = (sinH * d + cosH * pxX) * 0.05 + camY
                buf[row + x] = floorColor(worldX: worldX, worldY: worldY)
            }
        }

        bitmap.present(in: ctx, size: targetSize, smooth: false)
    }

    // MARK: - Floor pattern

    private func floorColor(worldX: Float, worldY: Float) -> UInt32 {
        let cellX = Int(worldX.rounded(.down))
        let cellY = Int(worldY.rounded(.down))
        let isAlt = (cellX + cellY) & 1 == 0

        switch floorPattern {
        case "Grid":
            let fX = worldX - Float(cellX)
            let fY = worldY - Float(cellY)
            let isLine = fX < 0.05 || fX > 0.95 || fY < 0.05 || fY > 0.95
            return isLine ? 0xFFFFFFFF : 0xFF1A1A2E
        case "Vapor Tiles":
            return isAlt ? 0xFFFF71CE : 0xFF01CDFE
        default: // Checker
            return isAlt ? 0xFFEEEEEE : 0xFF111111
        }
    }

    // MARK: - Sky colors (top, bottom of sky region)

    private func skyColors() -> (UInt32, UInt32) {
        switch skyTint {
        case "Cyan":   return (0xFF002B5C, 0xFF66E0FF)
        case "Dusk":   return (0xFF1A0033, 0xFFFF66B3)
        case "Black":  return (0xFF000000, 0xFF1A1A2E)
        default:       return (0xFF1A0033, 0xFFFF8C42) // Sunset
        }
    }
}
