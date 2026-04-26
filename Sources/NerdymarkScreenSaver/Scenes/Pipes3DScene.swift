import Cocoa

/// Win95-style 3D pipes. Multiple "pipe heads" walk a discrete 3D grid one
/// cell per growth step, occasionally turning 90°. Each step adds a segment
/// to the global list; each turn adds a sphere joint at the corner. The
/// camera slowly orbits. When all heads are stuck (or the grid fills up),
/// pause briefly then reset with new pipes.
final class Pipes3DScene: DemoScene {
    static let identifier = "pipes_3d"
    static let displayName = "3D Pipes"

    static let options: [SceneOption] = [
        .slider(key: "pipeCount", label: "Pipes", min: 1, max: 6, defaultValue: 3, format: "%.0f"),
        .slider(key: "growthSpeed", label: "Growth Speed", min: 2, max: 30, defaultValue: 12, format: "%.0f seg/s"),
        .slider(key: "rotationSpeed", label: "Rotation Speed", min: 0.0, max: 1.0, defaultValue: 0.18, format: "%.2f"),
        .slider(key: "turnProbability", label: "Turn Probability", min: 0.05, max: 0.5, defaultValue: 0.18, format: "%.2f"),
        .toggle(key: "showJoints", label: "Show ball joints", defaultValue: true),
    ]

    private struct V3 { var x: Double; var y: Double; var z: Double }
    private struct Segment { var a: V3; var b: V3; var color: CGColor }
    private struct Joint { var pos: V3; var color: CGColor }

    private struct Pipe {
        var x: Int; var y: Int; var z: Int
        var dx: Int; var dy: Int; var dz: Int
        var color: CGColor
        var alive: Bool
    }

    private static let dirs: [(Int, Int, Int)] = [
        (1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1),
    ]

    // Grid dimensions in cells.
    private let gridW = 18
    private let gridH = 11
    private let gridD = 11

    private var size: CGSize = .zero
    private let pipeCount: Int
    private let growthSpeed: Double
    private let rotationSpeed: Double
    private let turnProb: Double
    private let showJoints: Bool

    private var grid: [Bool] = []
    private var pipes: [Pipe] = []
    private var segments: [Segment] = []
    private var joints: [Joint] = []
    private var elapsed: Double = 0
    private var lastGrowthTime: Double = 0
    private var deadAt: Double = -1

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.pipeCount = max(1, Int(settings.double("pipeCount", default: 3)))
        self.growthSpeed = settings.double("growthSpeed", default: 12)
        self.rotationSpeed = settings.double("rotationSpeed", default: 0.18)
        self.turnProb = settings.double("turnProbability", default: 0.18)
        self.showJoints = settings.bool("showJoints", default: true)
        reset()
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        elapsed += dt
        // Grow pipes at fixed cadence.
        let stepInterval = 1.0 / max(0.5, growthSpeed)
        while elapsed - lastGrowthTime >= stepInterval {
            lastGrowthTime += stepInterval
            growAllPipes()
        }
        // If everyone is stuck (or the grid is mostly full), reset after a beat.
        if pipes.allSatisfy({ !$0.alive }) || segments.count > gridW * gridH * gridD * 3 / 4 {
            if deadAt < 0 { deadAt = elapsed }
            else if elapsed - deadAt > 4 {
                reset()
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        // Background gradient — dark navy to black.
        let top = CGColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1)
        let bot = CGColor(red: 0.0, green: 0.0, blue: 0.02, alpha: 1)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [bot, top] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0),
                                    end: CGPoint(x: 0, y: targetSize.height), options: [])
        }

        // Camera orientation: slow yaw + small pitch wobble.
        let yaw = elapsed * rotationSpeed
        let pitch = sin(elapsed * rotationSpeed * 0.5) * 0.3 + 0.2

        // Center the grid on the origin so rotation looks like an orbit
        // around the cube's center.
        let cx = -Double(gridW - 1) / 2
        let cy = -Double(gridH - 1) / 2
        let cz = -Double(gridD - 1) / 2

        // Camera + projection params, scaled to canvas.
        let canvasMin = Double(min(targetSize.width, targetSize.height))
        let focal = canvasMin * 0.35
        let camDist = Double(max(gridW, gridH)) * 1.6
        let screenCx = Double(targetSize.width) / 2
        let screenCy = Double(targetSize.height) / 2

        // Build renderable list with depth for sorting.
        struct Renderable { let depth: Double; let render: () -> Void }
        var items: [Renderable] = []
        items.reserveCapacity(segments.count + joints.count + 4)

        // Helper closures.
        func tx(_ v: V3) -> V3 {
            // Translate to origin, yaw around Y, pitch around X.
            let p = V3(x: v.x + cx, y: v.y + cy, z: v.z + cz)
            let cosY = cos(yaw), sinY = sin(yaw)
            let r1 = V3(x: p.x * cosY - p.z * sinY, y: p.y, z: p.x * sinY + p.z * cosY)
            let cosP = cos(pitch), sinP = sin(pitch)
            return V3(x: r1.x, y: r1.y * cosP - r1.z * sinP, z: r1.y * sinP + r1.z * cosP)
        }
        func proj(_ v: V3) -> CGPoint {
            let z = v.z + camDist
            let invZ = 1.0 / max(0.5, z)
            return CGPoint(x: screenCx + v.x * focal * invZ, y: screenCy + v.y * focal * invZ)
        }

        // Pipes (segments).
        for s in segments {
            let a = tx(s.a)
            let b = tx(s.b)
            let avgZ = (a.z + b.z) / 2
            let p1 = proj(a)
            let p2 = proj(b)
            // Thickness scales with depth.
            let avgDist = (a.z + b.z) / 2 + camDist
            let thickness = CGFloat(focal / max(1, avgDist) * 0.8)
            let color = s.color
            items.append(Renderable(depth: avgZ, render: {
                // Outline first, then bright core for tube look.
                ctx.setLineCap(.round)
                ctx.setStrokeColor(CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1))
                ctx.setLineWidth(max(2, thickness + 3))
                ctx.beginPath()
                ctx.move(to: p1); ctx.addLine(to: p2)
                ctx.strokePath()
                ctx.setStrokeColor(color)
                ctx.setLineWidth(max(1, thickness))
                ctx.beginPath()
                ctx.move(to: p1); ctx.addLine(to: p2)
                ctx.strokePath()
            }))
        }

        // Joints (sphere balls).
        if showJoints {
            for j in joints {
                let p = tx(j.pos)
                let pt = proj(p)
                let dist = p.z + camDist
                let r = CGFloat(focal / max(1, dist) * 0.9)
                let color = j.color
                items.append(Renderable(depth: p.z, render: {
                    // Radial gradient for sphere look.
                    let core = color.copy(alpha: 1) ?? color
                    let edge = CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
                    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                           colors: [core, edge] as CFArray, locations: [0, 1]) {
                        ctx.drawRadialGradient(g,
                                                startCenter: CGPoint(x: pt.x - r * 0.3, y: pt.y - r * 0.3),
                                                startRadius: 0,
                                                endCenter: pt, endRadius: r,
                                                options: [])
                    }
                }))
            }
        }

        items.sort { $0.depth < $1.depth }   // back to front
        for it in items { it.render() }
    }

    // MARK: - Simulation

    private func reset() {
        grid = [Bool](repeating: false, count: gridW * gridH * gridD)
        segments.removeAll()
        joints.removeAll()
        deadAt = -1
        lastGrowthTime = elapsed
        pipes = (0..<pipeCount).map { _ in spawnPipe() }
    }

    private func spawnPipe() -> Pipe {
        // Find an unoccupied cell.
        for _ in 0..<200 {
            let x = Int.random(in: 0..<gridW)
            let y = Int.random(in: 0..<gridH)
            let z = Int.random(in: 0..<gridD)
            if !cellOccupied(x: x, y: y, z: z) {
                let dir = Pipes3DScene.dirs.randomElement()!
                grid[idx(x, y, z)] = true
                return Pipe(x: x, y: y, z: z, dx: dir.0, dy: dir.1, dz: dir.2,
                            color: randomPipeColor(), alive: true)
            }
        }
        // Fallback: corner.
        grid[idx(0, 0, 0)] = true
        return Pipe(x: 0, y: 0, z: 0, dx: 1, dy: 0, dz: 0, color: randomPipeColor(), alive: true)
    }

    private func growAllPipes() {
        for i in 0..<pipes.count {
            guard pipes[i].alive else { continue }
            growPipe(i)
        }
    }

    private func growPipe(_ i: Int) {
        var p = pipes[i]
        // Decide if turning: if forced by occupied cell ahead OR random.
        let forwardX = p.x + p.dx, forwardY = p.y + p.dy, forwardZ = p.z + p.dz
        let canGoForward = inBounds(x: forwardX, y: forwardY, z: forwardZ) && !cellOccupied(x: forwardX, y: forwardY, z: forwardZ)
        let wantTurn = !canGoForward || Double.random(in: 0...1) < turnProb
        var (dx, dy, dz) = (p.dx, p.dy, p.dz)
        if wantTurn {
            // Pick a perpendicular direction with a free cell.
            let perps = Pipes3DScene.dirs.filter { d in d.0 * p.dx + d.1 * p.dy + d.2 * p.dz == 0 }
            let valid = perps.shuffled().first { d in
                let nx = p.x + d.0, ny = p.y + d.1, nz = p.z + d.2
                return inBounds(x: nx, y: ny, z: nz) && !cellOccupied(x: nx, y: ny, z: nz)
            }
            if let d = valid { dx = d.0; dy = d.1; dz = d.2 }
            else if canGoForward { /* fallback to forward */ }
            else {
                pipes[i].alive = false
                return
            }
        }
        let nx = p.x + dx, ny = p.y + dy, nz = p.z + dz
        if !inBounds(x: nx, y: ny, z: nz) || cellOccupied(x: nx, y: ny, z: nz) {
            pipes[i].alive = false
            return
        }
        // If we turned, drop a joint at the current position.
        if (dx, dy, dz) != (p.dx, p.dy, p.dz) {
            joints.append(Joint(pos: V3(x: Double(p.x), y: Double(p.y), z: Double(p.z)), color: p.color))
        }
        // Add segment.
        let a = V3(x: Double(p.x), y: Double(p.y), z: Double(p.z))
        let b = V3(x: Double(nx), y: Double(ny), z: Double(nz))
        segments.append(Segment(a: a, b: b, color: p.color))
        grid[idx(nx, ny, nz)] = true
        p.x = nx; p.y = ny; p.z = nz
        p.dx = dx; p.dy = dy; p.dz = dz
        pipes[i] = p
    }

    // MARK: - Grid helpers

    private func idx(_ x: Int, _ y: Int, _ z: Int) -> Int {
        return (z * gridH + y) * gridW + x
    }
    private func inBounds(x: Int, y: Int, z: Int) -> Bool {
        return x >= 0 && x < gridW && y >= 0 && y < gridH && z >= 0 && z < gridD
    }
    private func cellOccupied(x: Int, y: Int, z: Int) -> Bool {
        return grid[idx(x, y, z)]
    }

    // MARK: - Color

    private func randomPipeColor() -> CGColor {
        let palette: [CGColor] = [
            CGColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1),  // red
            CGColor(red: 0.30, green: 0.95, blue: 1.00, alpha: 1),  // cyan
            CGColor(red: 0.95, green: 0.85, blue: 0.20, alpha: 1),  // yellow
            CGColor(red: 0.40, green: 0.95, blue: 0.40, alpha: 1),  // lime
            CGColor(red: 0.90, green: 0.45, blue: 0.95, alpha: 1),  // magenta
            CGColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1),  // orange
            CGColor(red: 0.35, green: 0.55, blue: 1.00, alpha: 1),  // azure
        ]
        return palette.randomElement()!
    }
}
