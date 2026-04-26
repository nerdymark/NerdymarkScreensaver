import Cocoa

/// Tron light cycles: two AI cycles paint trails on a grid until one boxes
/// the other in. Each cycle does a flood-fill exploration from its current
/// position to score available area in each turn direction, picks the best.
final class TronCyclesScene: DemoScene {
    static let identifier = "tron_cycles"
    static let displayName = "Tron Cycles"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Cell Size", min: 6, max: 20, defaultValue: 10, format: "%.0f px"),
        .slider(key: "speed", label: "Cycle Speed", min: 8, max: 60, defaultValue: 25, format: "%.0f cells/s"),
    ]

    private struct Cycle {
        var x: Int; var y: Int
        var dx: Int; var dy: Int
        var color: CGColor
        var alive: Bool = true
    }

    private var size: CGSize = .zero
    private let cellSize: Int
    private let cellsPerSecond: Double
    private var w: Int = 0
    private var h: Int = 0
    private var grid: [Int8] = []   // 0 empty, 1 = cycle1 trail, 2 = cycle2 trail
    private var cycles: [Cycle] = []
    private var stepAccumulator: Double = 0
    private var elapsed: Double = 0
    private var deadAt: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.cellSize = max(4, Int(settings.double("scale", default: 10)))
        self.cellsPerSecond = settings.double("speed", default: 25)
        reset()
    }

    func resize(_ newSize: CGSize) {
        if newSize != size {
            size = newSize
            reset()
        }
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        // Pause on death briefly, then restart.
        if cycles.allSatisfy({ !$0.alive }) {
            if elapsed - deadAt > 2.0 { reset() }
            return
        }
        stepAccumulator += dt * cellsPerSecond
        while stepAccumulator >= 1 {
            stepAccumulator -= 1
            stepCycles()
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        // Black background with grid.
        ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))
        ctx.setStrokeColor(CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1))
        ctx.setLineWidth(1)
        for x in stride(from: 0, through: Int(targetSize.width), by: cellSize) {
            ctx.move(to: CGPoint(x: CGFloat(x), y: 0))
            ctx.addLine(to: CGPoint(x: CGFloat(x), y: targetSize.height))
        }
        for y in stride(from: 0, through: Int(targetSize.height), by: cellSize) {
            ctx.move(to: CGPoint(x: 0, y: CGFloat(y)))
            ctx.addLine(to: CGPoint(x: targetSize.width, y: CGFloat(y)))
        }
        ctx.strokePath()

        // Trails.
        for cy in 0..<h {
            for cx in 0..<w {
                let v = grid[cy * w + cx]
                if v != 0 {
                    let color = cycles[Int(v) - 1].color
                    ctx.setFillColor(color)
                    ctx.fill(CGRect(x: CGFloat(cx * cellSize), y: CGFloat(cy * cellSize),
                                     width: CGFloat(cellSize), height: CGFloat(cellSize)))
                }
            }
        }
        // Cycle heads (brighter).
        for c in cycles where c.alive {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: CGFloat(c.x * cellSize) - 2,
                                         y: CGFloat(c.y * cellSize) - 2,
                                         width: CGFloat(cellSize) + 4, height: CGFloat(cellSize) + 4))
        }
    }

    // MARK: - Sim

    private func stepCycles() {
        for i in 0..<cycles.count {
            guard cycles[i].alive else { continue }
            let c = cycles[i]
            // Try forward; if blocked, choose left/right by area.
            let candidates: [(dx: Int, dy: Int)] = [(c.dx, c.dy), (-c.dy, c.dx), (c.dy, -c.dx)]
            var bestDir = candidates[0]
            var bestScore = -1
            for cand in candidates {
                let nx = c.x + cand.dx
                let ny = c.y + cand.dy
                if nx < 0 || nx >= w || ny < 0 || ny >= h { continue }
                if grid[ny * w + nx] != 0 { continue }
                let score = floodArea(fromX: nx, fromY: ny, limit: 50)
                if score > bestScore {
                    bestScore = score
                    bestDir = cand
                }
            }
            if bestScore < 0 {
                cycles[i].alive = false
                deadAt = elapsed
                continue
            }
            cycles[i].dx = bestDir.dx
            cycles[i].dy = bestDir.dy
            cycles[i].x += bestDir.dx
            cycles[i].y += bestDir.dy
            grid[cycles[i].y * w + cycles[i].x] = Int8(i + 1)
        }
    }

    private func floodArea(fromX sx: Int, fromY sy: Int, limit: Int) -> Int {
        // Cheap BFS-ish bounded count.
        var visited = Set<Int>()
        var stack = [(sx, sy)]
        var count = 0
        while let (x, y) = stack.popLast(), count < limit {
            if x < 0 || x >= w || y < 0 || y >= h { continue }
            let key = y * w + x
            if visited.contains(key) { continue }
            if grid[key] != 0 { continue }
            visited.insert(key)
            count += 1
            stack.append((x + 1, y)); stack.append((x - 1, y))
            stack.append((x, y + 1)); stack.append((x, y - 1))
        }
        return count
    }

    private func reset() {
        w = max(8, Int(size.width) / cellSize)
        h = max(8, Int(size.height) / cellSize)
        grid = [Int8](repeating: 0, count: w * h)
        // Random starting positions in opposite quadrants, random initial
        // directions. Symmetric starts produce 4-fold symmetric trails which
        // can read as unfortunate symbols, so we deliberately break symmetry.
        let dirs: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let inset = 4
        let p1x = Int.random(in: inset..<(w / 2 - inset))
        let p1y = Int.random(in: inset..<(h - inset))
        let p2x = Int.random(in: (w / 2 + inset)..<(w - inset))
        let p2y = Int.random(in: inset..<(h - inset))
        let d1 = dirs.randomElement()!
        let d2 = dirs.randomElement()!
        cycles = [
            Cycle(x: p1x, y: p1y, dx: d1.0, dy: d1.1,
                   color: CGColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1)),
            Cycle(x: p2x, y: p2y, dx: d2.0, dy: d2.1,
                   color: CGColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1)),
        ]
        for (i, c) in cycles.enumerated() { grid[c.y * w + c.x] = Int8(i + 1) }
    }
}
