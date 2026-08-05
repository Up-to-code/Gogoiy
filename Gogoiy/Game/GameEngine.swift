import Foundation

struct GameEngine: Sendable {
    private(set) var state: GameState
    private var random: SeededRandomNumberGenerator

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max), bestScore: Int = 0) {
        random = SeededRandomNumberGenerator(seed: seed)
        state = GameState(
            board: Board(),
            tray: Tray(slots: []),
            score: 0,
            bestScore: bestScore,
            combo: 0,
            isGameOver: false
        )
        state.tray = makePlayableTray(for: state.board)
    }

    init(state: GameState, seed: UInt64) {
        self.state = state
        random = SeededRandomNumberGenerator(seed: seed)
    }

    mutating func restart(seed: UInt64? = nil) {
        let bestScore = state.bestScore
        if let seed {
            random = SeededRandomNumberGenerator(seed: seed)
        }
        state = GameState(
            board: Board(),
            tray: Tray(slots: []),
            score: 0,
            bestScore: bestScore,
            combo: 0,
            isGameOver: false
        )
        state.tray = makePlayableTray(for: state.board)
    }

    func canPlace(pieceID: UUID, at origin: GridCell) -> Bool {
        guard
            !state.isGameOver,
            let piece = state.tray.availablePieces.first(where: { $0.id == pieceID })
        else {
            return false
        }
        return state.board.canPlace(piece, at: origin)
    }

    func previewClearedCells(pieceID: UUID, at origin: GridCell) -> Set<GridCell> {
        guard
            let piece = state.tray.availablePieces.first(where: { $0.id == pieceID }),
            state.board.canPlace(piece, at: origin)
        else {
            return []
        }
        var previewBoard = state.board
        _ = previewBoard.place(piece, at: origin)
        return previewBoard.completedLines().cells
    }

    func bestPlacementHint() -> PlacementHint? {
        var bestHint: PlacementHint?
        for piece in state.tray.availablePieces {
            for row in 0..<Board.sideLength {
                for column in 0..<Board.sideLength {
                    let origin = GridCell(row: row, column: column)
                    guard state.board.canPlace(piece, at: origin) else { continue }
                    var previewBoard = state.board
                    _ = previewBoard.place(piece, at: origin)
                    let clearedCells = previewBoard.completedLines().cells
                    let candidate = PlacementHint(
                        piece: piece,
                        origin: origin,
                        clearedCells: clearedCells
                    )
                    if bestHint == nil
                        || clearedCells.count > (bestHint?.clearedCells.count ?? 0) {
                        bestHint = candidate
                    }
                }
            }
        }
        return bestHint
    }

    func canUseRewardedShape(_ shape: PieceShape) -> Bool {
        let sample = Piece(shape: shape, color: .cyan)
        return !state.isGameOver && state.board.hasPlacement(for: sample)
    }

    @discardableResult
    mutating func replaceFirstAvailablePiece(
        with shape: PieceShape,
        color: BlockColor
    ) -> Piece? {
        guard
            let slotIndex = state.tray.slots.firstIndex(where: { $0 != nil }),
            canUseRewardedShape(shape)
        else {
            return nil
        }
        let piece = Piece(shape: shape, color: color)
        state.tray.slots[slotIndex] = piece
        state.isGameOver = false
        return piece
    }

    mutating func place(pieceID: UUID, at origin: GridCell) throws -> MoveResult {
        guard !state.isGameOver else {
            throw GameRuleError.gameOver
        }
        guard
            let slotIndex = state.tray.slots.firstIndex(where: { $0?.id == pieceID }),
            let piece = state.tray.slots[slotIndex]
        else {
            throw GameRuleError.pieceUnavailable
        }
        guard state.board.canPlace(piece, at: origin) else {
            throw GameRuleError.invalidPlacement
        }

        let placedCells = state.board.place(piece, at: origin)
        let completed = state.board.completedLines()
        state.board.clear(completed.cells)

        let placedPoints = placedCells.count
        var events: [ScoreEvent] = [.placed(cells: placedPoints)]
        let lineCount = completed.rows.count + completed.columns.count
        var bonus = 0
        if lineCount > 0 {
            state.combo += 1
            bonus = 10 * lineCount * lineCount * state.combo
            events.append(.linesCleared(lines: lineCount, combo: state.combo, bonus: bonus))
        } else {
            state.combo = 0
        }

        let scoreDelta = placedPoints + bonus
        state.score += scoreDelta
        state.bestScore = max(state.bestScore, state.score)
        state.tray.slots[slotIndex] = nil

        var refilledTray = false
        if state.tray.isEmpty {
            state.tray = makePlayableTray(for: state.board)
            refilledTray = true
        }

        state.isGameOver = !state.tray.availablePieces.contains {
            state.board.hasPlacement(for: $0)
        }

        return MoveResult(
            piece: piece,
            origin: origin,
            placedCells: placedCells,
            clearedCells: completed.cells,
            clearedLineCount: lineCount,
            scoreEvents: events,
            scoreDelta: scoreDelta,
            combo: state.combo,
            refilledTray: refilledTray,
            isGameOver: state.isGameOver
        )
    }

    private mutating func makePlayableTray(for board: Board) -> Tray {
        // Draw three blocks independently: each slot pairs a random shape with a
        // random color. There is no board simulation and no rescue coloring, so
        // the tray is genuinely random every refill and the board does not get
        // an automatic win handed to it.
        let pieces = (0..<3).map { _ in randomPiece() }
        return Tray(slots: pieces.map(Optional.some))
    }

    private mutating func randomPiece() -> Piece {
        let shape = PieceCatalog.shapes.randomElement(using: &random)!
        let color = BlockColor.allCases.randomElement(using: &random)!
        return Piece(shape: shape, color: color)
    }
}
