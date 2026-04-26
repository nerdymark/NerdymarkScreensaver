import Cocoa

/// Tetris auto-play. The "AI" picks a random valid landing column for each
/// piece (not optimal — leaves gaps deliberately so the well looks alive).
/// Lines clear with a flash. Game resets when blocks reach the top.
final class FallingBlocksScene: DemoScene {
    static let identifier = "falling_blocks"
    static let displayName = "Falling Blocks"

    static let options: [SceneOption] = [
        .slider(key: "blockSize", label: "Block Size", min: 14, max: 48, defaultValue: 24, format: "%.0f px"),
        .slider(key: "fallStepsPerSecond", label: "Drop Speed", min: 5, max: 60, defaultValue: 22, format: "%.0f /s"),
    ]

    private static let pieces: [[[Int]]] = [
        // O
        [[1,1],[1,1]],
        // I
        [[1,1,1,1]],
        // T
        [[0,1,0],[1,1,1]],
        // L
        [[1,0],[1,0],[1,1]],
        // J
        [[0,1],[0,1],[1,1]],
        // S
        [[0,1,1],[1,1,0]],
        // Z
        [[1,1,0],[0,1,1]],
    ]
    private static let pieceColors: [CGColor] = [
        CGColor(red: 1, green: 0.95, blue: 0.0, alpha: 1),    // yellow O
        CGColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1),  // cyan I
        CGColor(red: 0.7, green: 0.0, blue: 0.95, alpha: 1),  // purple T
        CGColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1),   // orange L
        CGColor(red: 0.0, green: 0.3, blue: 1.0, alpha: 1),   // blue J
        CGColor(red: 0.0, green: 0.95, blue: 0.3, alpha: 1),  // green S
        CGColor(red: 1.0, green: 0.0, blue: 0.3, alpha: 1),   // red Z
    ]

    private var size: CGSize = .zero
    private let blockSize: CGFloat
    private let fallStepsPerSecond: Double

    // Board: cell value -1 = empty, 0..6 = piece type stored.
    private var cols: Int = 10
    private var rows: Int = 0
    private var board: [Int8] = []

    private var currentPiece: [[Int]] = []
    private var currentColor: Int = 0
    private var pieceX: Int = 0
    private var pieceY: Int = 0
    private var stepAccum: Double = 0
    private var elapsed: Double = 0
    private var clearFlashUntil: Double = 0
    private var clearedRows: [Int] = []

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.blockSize = CGFloat(settings.double("blockSize", default: 24))
        self.fallStepsPerSecond = settings.double("fallStepsPerSecond", default: 22)
        rebuild()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        rebuild()
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        stepAccum += dt
        let interval = 1.0 / fallStepsPerSecond
        while stepAccum >= interval {
            stepAccum -= interval
            stepGame()
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        ctx.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let originX = (targetSize.width - CGFloat(cols) * blockSize) / 2
        let originY: CGFloat = 20

        // Border.
        ctx.setStrokeColor(CGColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1))
        ctx.setLineWidth(2)
        ctx.stroke(CGRect(x: originX - 2, y: originY - 2, width: CGFloat(cols) * blockSize + 4, height: CGFloat(rows) * blockSize + 4))

        // Settled board.
        for y in 0..<rows {
            for x in 0..<cols {
                let v = board[y * cols + x]
                if v < 0 { continue }
                drawBlock(ctx: ctx, x: x, y: y, originX: originX, originY: originY, color: FallingBlocksScene.pieceColors[Int(v)])
            }
        }

        // Falling piece.
        let piece = currentPiece
        for (rowIdx, row) in piece.enumerated() {
            for (colIdx, cell) in row.enumerated() {
                if cell == 1 {
                    let bx = pieceX + colIdx
                    let by = pieceY - rowIdx
                    if by >= 0 && by < rows && bx >= 0 && bx < cols {
                        drawBlock(ctx: ctx, x: bx, y: by, originX: originX, originY: originY, color: FallingBlocksScene.pieceColors[currentColor])
                    }
                }
            }
        }

        // Line-clear flash.
        if elapsed < clearFlashUntil && !clearedRows.isEmpty {
            let alpha = (clearFlashUntil - elapsed) / 0.25
            for r in clearedRows {
                let rect = CGRect(x: originX, y: originY + CGFloat(r) * blockSize, width: CGFloat(cols) * blockSize, height: blockSize)
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(alpha)))
                ctx.fill(rect)
            }
        }
    }

    private func drawBlock(ctx: CGContext, x: Int, y: Int, originX: CGFloat, originY: CGFloat, color: CGColor) {
        let rect = CGRect(x: originX + CGFloat(x) * blockSize,
                           y: originY + CGFloat(y) * blockSize,
                           width: blockSize, height: blockSize).insetBy(dx: 1, dy: 1)
        ctx.setFillColor(color)
        ctx.fill(rect)
        // Bevel: lighter top stroke, darker bottom.
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        ctx.setLineWidth(1.5)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
        ctx.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 1))
        ctx.strokePath()
    }

    // MARK: - Game logic

    private func stepGame() {
        if currentPiece.isEmpty {
            spawnPiece()
            return
        }
        // Falling: try to drop one row.
        if collides(piece: currentPiece, x: pieceX, y: pieceY - 1) {
            // Lock piece into board.
            for (rowIdx, row) in currentPiece.enumerated() {
                for (colIdx, cell) in row.enumerated() {
                    if cell == 1 {
                        let bx = pieceX + colIdx
                        let by = pieceY - rowIdx
                        if by >= 0 && by < rows && bx >= 0 && bx < cols {
                            board[by * cols + bx] = Int8(currentColor)
                        }
                    }
                }
            }
            checkClears()
            // Spawn next piece. Reset if it can't even fit.
            spawnPiece()
            if collides(piece: currentPiece, x: pieceX, y: pieceY) {
                resetGame()
            }
        } else {
            pieceY -= 1
        }
    }

    private func collides(piece: [[Int]], x: Int, y: Int) -> Bool {
        for (rowIdx, row) in piece.enumerated() {
            for (colIdx, cell) in row.enumerated() {
                if cell != 1 { continue }
                let bx = x + colIdx
                let by = y - rowIdx
                if bx < 0 || bx >= cols || by < 0 { return true }
                if by < rows && board[by * cols + bx] >= 0 { return true }
            }
        }
        return false
    }

    private func checkClears() {
        var rowsToClear: [Int] = []
        for y in 0..<rows {
            var full = true
            for x in 0..<cols {
                if board[y * cols + x] < 0 { full = false; break }
            }
            if full { rowsToClear.append(y) }
        }
        guard !rowsToClear.isEmpty else { return }
        clearedRows = rowsToClear
        clearFlashUntil = elapsed + 0.25
        // Sort descending so we remove top-down without index shift confusion.
        rowsToClear.sort(by: >)
        for r in rowsToClear {
            // Shift everything above row r down by 1.
            for y in r..<(rows - 1) {
                for x in 0..<cols {
                    board[y * cols + x] = board[(y + 1) * cols + x]
                }
            }
            // Clear top.
            for x in 0..<cols {
                board[(rows - 1) * cols + x] = -1
            }
        }
    }

    private func spawnPiece() {
        let idx = Int.random(in: 0..<FallingBlocksScene.pieces.count)
        currentPiece = FallingBlocksScene.pieces[idx]
        currentColor = idx
        let pieceWidth = currentPiece[0].count
        // Random column where the piece fits, simulating a casual AI player.
        pieceX = Int.random(in: 0...max(0, cols - pieceWidth))
        pieceY = rows - 1
    }

    private func rebuild() {
        cols = max(8, min(14, Int(size.width / blockSize / 4)))
        if cols < 8 { cols = 10 }
        rows = max(15, Int(size.height / blockSize) - 2)
        board = [Int8](repeating: -1, count: cols * rows)
        spawnPiece()
    }

    private func resetGame() {
        for i in board.indices { board[i] = -1 }
        spawnPiece()
    }
}
