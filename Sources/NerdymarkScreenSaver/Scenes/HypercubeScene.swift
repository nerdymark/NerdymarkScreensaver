import Cocoa

/// Tesseract / 4D hypercube. 16 vertices in 4D, rotated through XY/ZW
/// planes (and others), projected to 3D, then to 2D. The 32 edges connect
/// vertices that differ in exactly one coordinate — drawn with depth-aware
/// thickness so receding edges look thinner.
final class HypercubeScene: DemoScene {
    static let identifier = "hypercube_4d"
    static let displayName = "Hypercube (4D)"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Rotation Speed", min: 0.2, max: 2.0, defaultValue: 0.6, format: "%.1f rad/s"),
        .slider(key: "thickness", label: "Edge Thickness", min: 1, max: 5, defaultValue: 2, format: "%.0f px"),
        .toggle(key: "vertices", label: "Show Vertex Dots", defaultValue: true),
        .choice(key: "color", label: "Color",
                choices: ["Cyan", "Rainbow", "Mono", "Sunset"],
                defaultValue: "Cyan"),
    ]

    private struct Vec4 {
        var x: Double; var y: Double; var z: Double; var w: Double
    }
    private struct Vec3 { var x: Double; var y: Double; var z: Double }

    private var size: CGSize = .zero
    private let speed: Double
    private let thickness: CGFloat
    private let showVertices: Bool
    private let colorScheme: String
    private var vertices: [Vec4] = []
    private var edges: [(Int, Int)] = []
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 0.6)
        self.thickness = CGFloat(settings.double("thickness", default: 2))
        self.showVertices = settings.bool("vertices", default: true)
        self.colorScheme = settings.string("color", default: "Cyan")
        buildHypercube()
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Two 4D rotation planes: XY and ZW (independent).
        let a = elapsed * speed
        let b = elapsed * speed * 0.7
        // Project all vertices.
        var projected: [Vec3] = []
        projected.reserveCapacity(vertices.count)
        for v in vertices {
            let r = rotate4D(v, xy: a, zw: b)
            projected.append(projectTo3D(r))
        }

        let cx = Double(targetSize.width) / 2
        let cy = Double(targetSize.height) / 2
        let focal = Double(min(targetSize.width, targetSize.height)) * 0.45

        ctx.setLineWidth(thickness)
        ctx.setLineCap(.round)

        // Edges, sorted by average z (back-to-front for additive feel).
        var edgeData: [(Int, Int, Double)] = edges.map { (i, j) in
            (i, j, (projected[i].z + projected[j].z) / 2)
        }
        edgeData.sort { $0.2 > $1.2 }

        for (i, j, avgZ) in edgeData {
            let p1 = projected[i]
            let p2 = projected[j]
            let invZ1 = 1.0 / max(0.5, p1.z + 4.0)
            let invZ2 = 1.0 / max(0.5, p2.z + 4.0)
            let s1 = CGPoint(x: cx + p1.x * focal * invZ1, y: cy + p1.y * focal * invZ1)
            let s2 = CGPoint(x: cx + p2.x * focal * invZ2, y: cy + p2.y * focal * invZ2)
            let depthFade = max(0.2, min(1.0, 1.0 - (avgZ + 4.0) / 10.0))
            ctx.setStrokeColor(edgeColor(forIndex: i, depth: depthFade))
            ctx.beginPath()
            ctx.move(to: s1)
            ctx.addLine(to: s2)
            ctx.strokePath()
        }

        // Vertex dots last.
        if showVertices {
            for (i, p) in projected.enumerated() {
                let invZ = 1.0 / max(0.5, p.z + 4.0)
                let sx = cx + p.x * focal * invZ
                let sy = cy + p.y * focal * invZ
                let r = max(2.0, 4.0 * focal * invZ * 0.06)
                ctx.setFillColor(edgeColor(forIndex: i, depth: 1.0))
                ctx.fillEllipse(in: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2))
            }
        }
    }

    // MARK: - Math

    private func rotate4D(_ v: Vec4, xy: Double, zw: Double) -> Vec4 {
        // XY rotation.
        let cosXY = cos(xy), sinXY = sin(xy)
        let nx = v.x * cosXY - v.y * sinXY
        let ny = v.x * sinXY + v.y * cosXY
        // ZW rotation.
        let cosZW = cos(zw), sinZW = sin(zw)
        let nz = v.z * cosZW - v.w * sinZW
        let nw = v.z * sinZW + v.w * cosZW
        return Vec4(x: nx, y: ny, z: nz, w: nw)
    }

    /// Project from 4D to 3D using the standard "view from W axis" formula:
    /// scale = 1 / (W_distance - w). Then we use that 3D point in the 2D
    /// projection above.
    private func projectTo3D(_ v: Vec4) -> Vec3 {
        let wDist = 3.5
        let factor = 1.0 / (wDist - v.w)
        return Vec3(x: v.x * factor, y: v.y * factor, z: v.z * factor)
    }

    private func edgeColor(forIndex i: Int, depth: Double) -> CGColor {
        switch colorScheme {
        case "Mono":
            return CGColor(red: depth * 0.95, green: depth * 0.95, blue: depth * 1.0, alpha: 1)
        case "Rainbow":
            let hue = (Double(i) / Double(vertices.count)).truncatingRemainder(dividingBy: 1.0)
            return NSColor(hue: CGFloat(hue), saturation: 0.85, brightness: CGFloat(depth), alpha: 1).cgColor
        case "Sunset":
            return CGColor(red: depth, green: depth * 0.5, blue: depth * 0.3, alpha: 1)
        default: // Cyan
            return CGColor(red: depth * 0.2, green: depth * 0.95, blue: depth, alpha: 1)
        }
    }

    // MARK: - Setup

    private func buildHypercube() {
        // 16 vertices: every combination of ±1 in each of 4 dimensions.
        vertices.removeAll()
        for i in 0..<16 {
            vertices.append(Vec4(
                x: (i & 1) == 0 ? -1 : 1,
                y: (i & 2) == 0 ? -1 : 1,
                z: (i & 4) == 0 ? -1 : 1,
                w: (i & 8) == 0 ? -1 : 1
            ))
        }
        // 32 edges: pairs of vertices differing in exactly one coord.
        edges.removeAll()
        for i in 0..<16 {
            for j in (i + 1)..<16 {
                let diff = i ^ j
                if diff != 0 && (diff & (diff - 1)) == 0 {
                    edges.append((i, j))
                }
            }
        }
    }
}
