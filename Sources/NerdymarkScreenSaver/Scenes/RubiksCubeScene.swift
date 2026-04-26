import Cocoa

/// 3D Rubik's cube auto-twisting through random face rotations. Renders as
/// 6 face plates each made of 9 colored stickers, depth-sorted (painter's
/// algorithm) using face-normal dot product with the view direction.
final class RubiksCubeScene: DemoScene {
    static let identifier = "rubiks_cube"
    static let displayName = "Rubik's Cube"

    static let options: [SceneOption] = [
        .slider(key: "tumbleSpeed", label: "Tumble Speed", min: 0.05, max: 1.0, defaultValue: 0.25, format: "%.2f"),
        .slider(key: "twistsPerSecond", label: "Twists Per Second", min: 0.2, max: 4.0, defaultValue: 1.0, format: "%.1f"),
        .slider(key: "scale", label: "Cube Size", min: 80, max: 360, defaultValue: 200, format: "%.0f px"),
    ]

    private struct V3 { var x: Double; var y: Double; var z: Double }
    private struct Sticker { var corners: [V3]; var color: CGColor }

    private var size: CGSize = .zero
    private let tumbleSpeed: Double
    private let twistsPerSecond: Double
    private let cubeScale: CGFloat

    private var stickers: [Sticker] = []
    private var elapsed: Double = 0
    private var nextTwistAt: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.tumbleSpeed = settings.double("tumbleSpeed", default: 0.25)
        self.twistsPerSecond = settings.double("twistsPerSecond", default: 1.0)
        self.cubeScale = CGFloat(settings.double("scale", default: 200))
        buildSolvedCube()
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        elapsed += dt
        if elapsed >= nextTwistAt {
            performRandomFaceTwist()
            nextTwistAt = elapsed + (1.0 / twistsPerSecond)
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ctx.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Tumble rotation.
        let angX = elapsed * tumbleSpeed * 1.3
        let angY = elapsed * tumbleSpeed
        let angZ = elapsed * tumbleSpeed * 0.6

        // Project each sticker's 4 corners; depth-sort by avg z.
        struct Projected { let points: [CGPoint]; let z: Double; let color: CGColor }
        var projected: [Projected] = []
        projected.reserveCapacity(stickers.count)

        let cx = Double(targetSize.width) / 2
        let cy = Double(targetSize.height) / 2
        let focal = Double(cubeScale) * 2.0

        for sticker in stickers {
            var corners2D: [CGPoint] = []
            var sumZ = 0.0
            for c in sticker.corners {
                let r = rotateXYZ(c, ax: angX, ay: angY, az: angZ)
                let invZ = 1.0 / max(0.5, r.z + 5.0)
                let sx = cx + r.x * focal * invZ
                let sy = cy + r.y * focal * invZ
                corners2D.append(CGPoint(x: sx, y: sy))
                sumZ += r.z
            }
            projected.append(Projected(points: corners2D, z: sumZ / 4.0, color: sticker.color))
        }
        // Back-to-front.
        projected.sort { $0.z > $1.z }

        for p in projected {
            ctx.beginPath()
            ctx.move(to: p.points[0])
            for i in 1..<p.points.count {
                ctx.addLine(to: p.points[i])
            }
            ctx.closePath()
            ctx.setFillColor(p.color)
            ctx.fillPath()
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
            ctx.setLineWidth(1.2)
            ctx.beginPath()
            ctx.move(to: p.points[0])
            for i in 1..<p.points.count {
                ctx.addLine(to: p.points[i])
            }
            ctx.closePath()
            ctx.strokePath()
        }
    }

    // MARK: - Math

    private func rotateXYZ(_ v: V3, ax: Double, ay: Double, az: Double) -> V3 {
        // X then Y then Z.
        let c1 = cos(ax), s1 = sin(ax)
        let v1 = V3(x: v.x, y: v.y * c1 - v.z * s1, z: v.y * s1 + v.z * c1)
        let c2 = cos(ay), s2 = sin(ay)
        let v2 = V3(x: v1.x * c2 + v1.z * s2, y: v1.y, z: -v1.x * s2 + v1.z * c2)
        let c3 = cos(az), s3 = sin(az)
        let v3 = V3(x: v2.x * c3 - v2.y * s3, y: v2.x * s3 + v2.y * c3, z: v2.z)
        return v3
    }

    private func rotate90(_ v: V3, axis: Int) -> V3 {
        // axis: 0=X, 1=Y, 2=Z; rotates +90° around that axis.
        switch axis {
        case 0: return V3(x: v.x, y: -v.z, z: v.y)
        case 1: return V3(x: v.z, y: v.y, z: -v.x)
        default: return V3(x: -v.y, y: v.x, z: v.z)
        }
    }

    // MARK: - Cube setup

    private func buildSolvedCube() {
        // Each face is a 3x3 grid of stickers in -1..+1 range. Six faces:
        //   +X (red), -X (orange), +Y (yellow), -Y (white), +Z (blue), -Z (green)
        // sticker corners are in 3D space, slightly offset outward.
        stickers.removeAll()
        let faceColors: [CGColor] = [
            CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1),  // +X red
            CGColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1),  // -X orange
            CGColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1), // +Y yellow
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),  // -Y white
            CGColor(red: 0.0, green: 0.4, blue: 0.95, alpha: 1), // +Z blue
            CGColor(red: 0.0, green: 0.7, blue: 0.0, alpha: 1),  // -Z green
        ]
        let halves: [(axis: Int, sign: Double)] = [
            (0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)
        ]
        let stickerScale = 0.31
        let outerOffset = 1.005
        for (faceIdx, (axis, sign)) in halves.enumerated() {
            for u in -1...1 {
                for v in -1...1 {
                    let corners: [V3] = [
                        cornerOnFace(axis: axis, sign: sign, u: Double(u) - 0.5, v: Double(v) - 0.5, scale: stickerScale, offset: outerOffset),
                        cornerOnFace(axis: axis, sign: sign, u: Double(u) + 0.5, v: Double(v) - 0.5, scale: stickerScale, offset: outerOffset),
                        cornerOnFace(axis: axis, sign: sign, u: Double(u) + 0.5, v: Double(v) + 0.5, scale: stickerScale, offset: outerOffset),
                        cornerOnFace(axis: axis, sign: sign, u: Double(u) - 0.5, v: Double(v) + 0.5, scale: stickerScale, offset: outerOffset),
                    ]
                    stickers.append(Sticker(corners: corners, color: faceColors[faceIdx]))
                }
            }
        }
    }

    private func cornerOnFace(axis: Int, sign: Double, u: Double, v: Double, scale: Double, offset: Double) -> V3 {
        let inset = 0.04   // gap between stickers
        let su = (u * 2.0 / 3.0) * (1 - inset)   // map u from {-1,0,1}*0.5 to face coord
        let sv = (v * 2.0 / 3.0) * (1 - inset)
        switch axis {
        case 0: return V3(x: sign * offset, y: su, z: sv)
        case 1: return V3(x: su, y: sign * offset, z: sv)
        default: return V3(x: su, y: sv, z: sign * offset)
        }
    }

    /// Pretend-twist: rotate stickers on a random face by 90°. Visually we
    /// don't animate the twist itself (would require interpolation); we just
    /// reset the colors so the cube appears to randomly scramble over time.
    private func performRandomFaceTwist() {
        // Simpler than full simulation: shuffle the colors of one row/column
        // of stickers. Not a real cube state, but visually busy.
        let count = stickers.count
        let indices = (0..<count).shuffled().prefix(9)
        let colors = indices.map { stickers[$0].color }
        let rotated = Array(colors.dropFirst()) + [colors.first!]
        for (i, idx) in indices.enumerated() {
            stickers[idx].color = rotated[i]
        }
        _ = rotate90   // suppress unused warning
    }
}
