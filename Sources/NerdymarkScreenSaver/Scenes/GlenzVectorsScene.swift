import Cocoa

/// "Glenz vectors": old-school translucent polyhedra (icosahedron) where
/// the back faces show through the front because each face is alpha-blended.
/// Used in many Amiga demos. We rotate around X+Y, then sort faces back-to-
/// front and draw with screen blend mode.
final class GlenzVectorsScene: DemoScene {
    static let identifier = "glenz_vectors"
    static let displayName = "Glenz Vectors"

    static let options: [SceneOption] = [
        .slider(key: "spinSpeed", label: "Spin Speed", min: 0.1, max: 2.0, defaultValue: 0.5, format: "%.1f rad/s"),
        .slider(key: "size", label: "Size", min: 100, max: 600, defaultValue: 280, format: "%.0f px"),
        .slider(key: "alpha", label: "Face Alpha", min: 0.1, max: 0.6, defaultValue: 0.3, format: "%.2f"),
        .choice(key: "shape", label: "Shape",
                choices: ["Icosahedron", "Octahedron", "Cube"],
                defaultValue: "Icosahedron"),
    ]

    private struct V3 { var x: Double; var y: Double; var z: Double }

    private var size: CGSize = .zero
    private let spinSpeed: Double
    private let modelSize: CGFloat
    private let faceAlpha: CGFloat
    private let shape: String
    private var vertices: [V3] = []
    private var faces: [[Int]] = []
    private var faceColors: [CGColor] = []
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.spinSpeed = settings.double("spinSpeed", default: 0.5)
        self.modelSize = CGFloat(settings.double("size", default: 280))
        self.faceAlpha = CGFloat(settings.double("alpha", default: 0.3))
        self.shape = settings.string("shape", default: "Icosahedron")
        buildShape()
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ctx.setFillColor(CGColor(red: 0.0, green: 0.0, blue: 0.04, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let angX = elapsed * spinSpeed
        let angY = elapsed * spinSpeed * 0.7
        let angZ = elapsed * spinSpeed * 0.4
        let cx = Double(targetSize.width) / 2
        let cy = Double(targetSize.height) / 2
        let r = Double(modelSize) / 2

        // Project all vertices.
        let projected: [(CGPoint, Double)] = vertices.map { v in
            let r1 = rotateY(v, by: angY)
            let r2 = rotateX(r1, by: angX)
            let r3 = rotateZ(r2, by: angZ)
            return (CGPoint(x: cx + r3.x * r, y: cy + r3.y * r), r3.z)
        }

        // Sort faces by mean z (back-to-front).
        let faceData: [(face: [Int], avgZ: Double)] = faces.enumerated().map { (i, face) in
            let avgZ = face.map { projected[$0].1 }.reduce(0, +) / Double(face.count)
            _ = i
            return (face, avgZ)
        }
        let sorted = faceData.sorted { $0.avgZ > $1.avgZ }   // back first

        ctx.setBlendMode(.screen)
        for (faceIndex, fd) in sorted.enumerated() {
            let face = fd.face
            ctx.beginPath()
            ctx.move(to: projected[face[0]].0)
            for i in 1..<face.count {
                ctx.addLine(to: projected[face[i]].0)
            }
            ctx.closePath()
            // Use the face's persistent color modulated by depth.
            let palIdx = faceIndex % faceColors.count
            let baseColor = faceColors[palIdx]
            let color = baseColor.copy(alpha: faceAlpha) ?? baseColor
            ctx.setFillColor(color)
            ctx.fillPath()
        }
        ctx.setBlendMode(.normal)

        // Edges (thin white strokes for definition).
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
        ctx.setLineWidth(1.0)
        for face in faces {
            ctx.beginPath()
            ctx.move(to: projected[face[0]].0)
            for i in 1..<face.count {
                ctx.addLine(to: projected[face[i]].0)
            }
            ctx.closePath()
            ctx.strokePath()
        }
    }

    // MARK: - Rotation

    private func rotateX(_ v: V3, by angle: Double) -> V3 {
        let c = cos(angle), s = sin(angle)
        return V3(x: v.x, y: v.y * c - v.z * s, z: v.y * s + v.z * c)
    }
    private func rotateY(_ v: V3, by angle: Double) -> V3 {
        let c = cos(angle), s = sin(angle)
        return V3(x: v.x * c + v.z * s, y: v.y, z: -v.x * s + v.z * c)
    }
    private func rotateZ(_ v: V3, by angle: Double) -> V3 {
        let c = cos(angle), s = sin(angle)
        return V3(x: v.x * c - v.y * s, y: v.x * s + v.y * c, z: v.z)
    }

    // MARK: - Geometry

    private func buildShape() {
        switch shape {
        case "Cube":
            let p: [V3] = [
                V3(x: -1, y: -1, z: -1), V3(x:  1, y: -1, z: -1),
                V3(x:  1, y:  1, z: -1), V3(x: -1, y:  1, z: -1),
                V3(x: -1, y: -1, z:  1), V3(x:  1, y: -1, z:  1),
                V3(x:  1, y:  1, z:  1), V3(x: -1, y:  1, z:  1),
            ]
            vertices = p
            faces = [
                [0,1,2,3], [4,5,6,7], [0,4,5,1], [2,6,7,3], [0,3,7,4], [1,5,6,2]
            ]

        case "Octahedron":
            vertices = [
                V3(x: 1, y: 0, z: 0), V3(x: -1, y: 0, z: 0),
                V3(x: 0, y: 1, z: 0), V3(x:  0, y: -1, z: 0),
                V3(x: 0, y: 0, z: 1), V3(x:  0, y:  0, z: -1),
            ]
            faces = [
                [0,2,4],[2,1,4],[1,3,4],[3,0,4],
                [2,0,5],[1,2,5],[3,1,5],[0,3,5],
            ]

        default: // Icosahedron
            let phi = (1.0 + sqrt(5.0)) / 2.0
            let n = 1.0 / sqrt(1.0 + phi * phi)
            let a = 1.0 * n
            let b = phi * n
            vertices = [
                V3(x:  0, y:  a, z:  b), V3(x:  0, y:  a, z: -b),
                V3(x:  0, y: -a, z:  b), V3(x:  0, y: -a, z: -b),
                V3(x:  a, y:  b, z:  0), V3(x:  a, y: -b, z:  0),
                V3(x: -a, y:  b, z:  0), V3(x: -a, y: -b, z:  0),
                V3(x:  b, y:  0, z:  a), V3(x:  b, y:  0, z: -a),
                V3(x: -b, y:  0, z:  a), V3(x: -b, y:  0, z: -a),
            ]
            faces = [
                [0,4,8],[0,8,2],[0,2,10],[0,10,6],[0,6,4],
                [4,9,8],[8,9,5],[8,5,2],[2,5,7],[2,7,10],
                [10,7,11],[10,11,6],[6,11,1],[6,1,4],[4,1,9],
                [3,5,9],[3,7,5],[3,11,7],[3,1,11],[3,9,1],
            ]
        }

        // Per-face fixed hues.
        faceColors = (0..<faces.count).map { i in
            let hue = CGFloat(i) / CGFloat(faces.count)
            return NSColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: 1).cgColor
        }
    }
}
