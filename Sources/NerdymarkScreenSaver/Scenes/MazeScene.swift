import Cocoa

/// Recursive-backtracker maze: generates a maze, then auto-solves it with
/// BFS, animating both phases. Loops back to a fresh maze when done.
final class MazeScene: DemoScene {
    static let identifier = "maze"
    static let displayName = "Maze (Generate + Solve)"

    static let options: [SceneOption] = [
        .slider(key: "cellSize", label: "Cell Size", min: 12, max: 48, defaultValue: 22, format: "%.0f px"),
        .slider(key: "stepsPerSecond", label: "Speed", min: 30, max: 300, defaultValue: 120, format: "%.0f steps/s"),
        .choice(key: "color", label: "Solver Color",
                choices: ["Cyan", "Amber", "Magenta", "Lime"],
                defaultValue: "Cyan"),
    ]

    private enum Phase { case generating, solving, paused }

    private var size: CGSize = .zero
    private var cellSize: CGFloat
    private let stepsPerSecond: Double
    private let colorScheme: String

    private var cols: Int = 0
    private var rows: Int = 0

    // Walls per cell: top, right, bottom, left (true = wall present).
    private struct Cell {
        var walls: (Bool, Bool, Bool, Bool) = (true, true, true, true)
        var visited = false
    }
    private var grid: [Cell] = []

    private var genStack: [(Int, Int)] = []
    private var phase: Phase = .generating
    private var stepAccum: Double = 0
    private var pauseUntil: Double = 0
    private var elapsed: Double = 0

    // Solver state.
    private var solverFrontier: [(Int, Int)] = []
    private var solverParent: [Int: Int] = [:]   // index → parent index
    private var solverVisited: Set<Int> = []
    private var solutionPath: [Int] = []
    private var solverFinishedDrawIndex = 0

    private var startCell = 0
    private var endCell = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.cellSize = CGFloat(settings.double("cellSize", default: 22))
        self.stepsPerSecond = settings.double("stepsPerSecond", default: 120)
        self.colorScheme = settings.string("color", default: "Cyan")
        rebuild()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        rebuild()
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        if phase == .paused {
            if elapsed > pauseUntil { startNewMaze() }
            return
        }
        stepAccum += dt
        let interval = 1.0 / stepsPerSecond
        while stepAccum >= interval {
            stepAccum -= interval
            switch phase {
            case .generating: stepGen()
            case .solving:    stepSolver()
            case .paused: break
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        ctx.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let originX = (targetSize.width - CGFloat(cols) * cellSize) / 2
        let originY = (targetSize.height - CGFloat(rows) * cellSize) / 2

        // Visited cells get a subtle background.
        for y in 0..<rows {
            for x in 0..<cols {
                let i = y * cols + x
                if grid[i].visited {
                    let rect = CGRect(x: originX + CGFloat(x) * cellSize,
                                       y: originY + CGFloat(y) * cellSize,
                                       width: cellSize, height: cellSize)
                    ctx.setFillColor(CGColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1))
                    ctx.fill(rect)
                }
            }
        }

        // Walls.
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.85, blue: 0.95, alpha: 0.85))
        ctx.setLineWidth(1.5)
        ctx.beginPath()
        for y in 0..<rows {
            for x in 0..<cols {
                let i = y * cols + x
                let cellX = originX + CGFloat(x) * cellSize
                let cellY = originY + CGFloat(y) * cellSize
                let (top, right, bottom, left) = grid[i].walls
                if top {
                    ctx.move(to: CGPoint(x: cellX, y: cellY + cellSize))
                    ctx.addLine(to: CGPoint(x: cellX + cellSize, y: cellY + cellSize))
                }
                if bottom {
                    ctx.move(to: CGPoint(x: cellX, y: cellY))
                    ctx.addLine(to: CGPoint(x: cellX + cellSize, y: cellY))
                }
                if left {
                    ctx.move(to: CGPoint(x: cellX, y: cellY))
                    ctx.addLine(to: CGPoint(x: cellX, y: cellY + cellSize))
                }
                if right {
                    ctx.move(to: CGPoint(x: cellX + cellSize, y: cellY))
                    ctx.addLine(to: CGPoint(x: cellX + cellSize, y: cellY + cellSize))
                }
            }
        }
        ctx.strokePath()

        // Start + end markers.
        drawCellDot(ctx: ctx, cellIndex: startCell, originX: originX, originY: originY,
                     color: CGColor(red: 0.4, green: 1, blue: 0.4, alpha: 1))
        drawCellDot(ctx: ctx, cellIndex: endCell, originX: originX, originY: originY,
                     color: CGColor(red: 1, green: 0.4, blue: 0.4, alpha: 1))

        // Solver visited (light fill).
        let sc = solverColor()
        for cellIndex in solverVisited {
            let x = cellIndex % cols
            let y = cellIndex / cols
            let rect = CGRect(x: originX + CGFloat(x) * cellSize + 2,
                               y: originY + CGFloat(y) * cellSize + 2,
                               width: cellSize - 4, height: cellSize - 4)
            ctx.setFillColor(sc.copy(alpha: 0.18) ?? sc)
            ctx.fill(rect)
        }

        // Final solution path (drawn progressively).
        if !solutionPath.isEmpty {
            ctx.setStrokeColor(sc)
            ctx.setLineWidth(3.0)
            ctx.setLineCap(.round)
            ctx.beginPath()
            let visibleCount = min(solverFinishedDrawIndex, solutionPath.count)
            for (i, cellIndex) in solutionPath[..<visibleCount].enumerated() {
                let x = cellIndex % cols
                let y = cellIndex / cols
                let pt = CGPoint(x: originX + CGFloat(x) * cellSize + cellSize / 2,
                                  y: originY + CGFloat(y) * cellSize + cellSize / 2)
                if i == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
            }
            ctx.strokePath()
        }
    }

    private func drawCellDot(ctx: CGContext, cellIndex: Int, originX: CGFloat, originY: CGFloat, color: CGColor) {
        let x = cellIndex % cols
        let y = cellIndex / cols
        let cx = originX + CGFloat(x) * cellSize + cellSize / 2
        let cy = originY + CGFloat(y) * cellSize + cellSize / 2
        let r = cellSize * 0.25
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private func solverColor() -> CGColor {
        switch colorScheme {
        case "Amber":   return CGColor(red: 1, green: 0.65, blue: 0.1, alpha: 1)
        case "Magenta": return CGColor(red: 1, green: 0.2, blue: 0.85, alpha: 1)
        case "Lime":    return CGColor(red: 0.55, green: 1, blue: 0.2, alpha: 1)
        default:        return CGColor(red: 0.2, green: 0.95, blue: 1, alpha: 1)
        }
    }

    // MARK: - Generation (recursive backtracker, animated one cell at a time)

    private func stepGen() {
        if genStack.isEmpty {
            // Generation finished. Switch to solving.
            phase = .solving
            startSolver()
            return
        }
        guard let (x, y) = genStack.last else { return }
        let unvisited = uncarvedNeighbors(x: x, y: y)
        if unvisited.isEmpty {
            genStack.removeLast()
            return
        }
        let (nx, ny, dir) = unvisited.randomElement()!
        knockWall(x: x, y: y, nx: nx, ny: ny, dir: dir)
        grid[ny * cols + nx].visited = true
        genStack.append((nx, ny))
    }

    private func uncarvedNeighbors(x: Int, y: Int) -> [(Int, Int, Int)] {
        var result: [(Int, Int, Int)] = []
        // dir: 0=top, 1=right, 2=bottom, 3=left
        let candidates: [(Int, Int, Int)] = [(x, y + 1, 0), (x + 1, y, 1), (x, y - 1, 2), (x - 1, y, 3)]
        for (nx, ny, dir) in candidates {
            if nx < 0 || ny < 0 || nx >= cols || ny >= rows { continue }
            if grid[ny * cols + nx].visited { continue }
            result.append((nx, ny, dir))
        }
        return result
    }

    private func knockWall(x: Int, y: Int, nx: Int, ny: Int, dir: Int) {
        let i = y * cols + x
        let j = ny * cols + nx
        switch dir {
        case 0: grid[i].walls.0 = false; grid[j].walls.2 = false
        case 1: grid[i].walls.1 = false; grid[j].walls.3 = false
        case 2: grid[i].walls.2 = false; grid[j].walls.0 = false
        default: grid[i].walls.3 = false; grid[j].walls.1 = false
        }
    }

    // MARK: - Solver (BFS)

    private func startSolver() {
        solverFrontier = [cellCoord(startCell)]
        solverParent.removeAll()
        solverVisited = [startCell]
        solutionPath = []
        solverFinishedDrawIndex = 0
    }

    private func stepSolver() {
        guard !solverFrontier.isEmpty else {
            // Animate path-draw, then pause.
            if solverFinishedDrawIndex < solutionPath.count {
                solverFinishedDrawIndex += 1
            } else if phase != .paused {
                phase = .paused
                pauseUntil = elapsed + 2.5
            }
            return
        }
        let (x, y) = solverFrontier.removeFirst()
        let i = y * cols + x
        if i == endCell {
            // Reconstruct path.
            var path: [Int] = [endCell]
            var cur = endCell
            while let p = solverParent[cur] {
                path.append(p)
                cur = p
            }
            solutionPath = path.reversed()
            solverFinishedDrawIndex = 0
            solverFrontier.removeAll()
            return
        }
        // Expand: walk through openings.
        let walls = grid[i].walls
        let candidates: [(Int, Int)] = [
            (walls.0 ? -1 : 0, walls.0 ? 0 : 1),
            (walls.1 ? 0 : 1,  0),
            (walls.2 ? 0 : 0,  walls.2 ? 0 : -1),
            (walls.3 ? 0 : -1, 0),
        ]
        // Manual neighbor walk based on which walls are open.
        var nexts: [(Int, Int)] = []
        if !walls.0 { nexts.append((x, y + 1)) }
        if !walls.1 { nexts.append((x + 1, y)) }
        if !walls.2 { nexts.append((x, y - 1)) }
        if !walls.3 { nexts.append((x - 1, y)) }
        for (nx, ny) in nexts {
            if nx < 0 || ny < 0 || nx >= cols || ny >= rows { continue }
            let ni = ny * cols + nx
            if solverVisited.contains(ni) { continue }
            solverVisited.insert(ni)
            solverParent[ni] = i
            solverFrontier.append((nx, ny))
        }
        _ = candidates
    }

    private func cellCoord(_ index: Int) -> (Int, Int) {
        return (index % cols, index / cols)
    }

    // MARK: - Build

    private func rebuild() {
        cols = max(8, Int(size.width / cellSize))
        rows = max(8, Int(size.height / cellSize))
        startNewMaze()
    }

    private func startNewMaze() {
        grid = [Cell](repeating: Cell(), count: cols * rows)
        // Pick start corner randomly.
        let startX = Int.random(in: 0..<cols)
        let startY = Int.random(in: 0..<rows)
        let endX = Int.random(in: 0..<cols)
        let endY = Int.random(in: 0..<rows)
        startCell = startY * cols + startX
        endCell = endY * cols + endX
        grid[startCell].visited = true
        genStack = [(startX, startY)]
        phase = .generating
        solverVisited = []
        solverParent = [:]
        solutionPath = []
        solverFrontier = []
    }
}
