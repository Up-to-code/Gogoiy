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
        // Build against a simulated board so every tray has a known route where
        // all three pieces can be placed. Retrying introduces variety without
        // giving up the solvability guarantee.
        for _ in 0..<8 {
            if let pieces = makePlannedTray(for: board) {
                return Tray(slots: pieces.map(Optional.some))
            }
        }

        // A malformed or completely blocked board can make a three-move route
        // impossible. Singles preserve every remaining legal opportunity.
        let pieces = (0..<3).map { _ in
            Piece(shape: PieceCatalog.single, color: bestRescueColor(for: board))
        }
        return Tray(slots: pieces.map(Optional.some))
    }

    private struct PlannedMove {
        let piece: Piece
        let resultingBoard: Board
        let quality: Int
    }

    private mutating func makePlannedTray(for startingBoard: Board) -> [Piece]? {
        var planningBoard = startingBoard
        var pieces: [Piece] = []

        for _ in 0..<3 {
            let candidates = plannedMoves(for: planningBoard, excluding: pieces.map(\.shape.name))
            guard !candidates.isEmpty else { return nil }

            let window = min(candidates.count, 3 + state.level / 5)
            let selectedIndex = weightedRank(in: window)
            let selected = candidates[selectedIndex]
            pieces.append(selected.piece)
            planningBoard = selected.resultingBoard
        }

        return pieces
    }

    private func plannedMoves(for board: Board, excluding recentShapes: [String]) -> [PlannedMove] {
        let maximumCells: Int
        switch state.level {
        case 1...15: maximumCells = 4
        case 16...35: maximumCells = 5
        default: maximumCells = 9
        }

        var moves: [PlannedMove] = []
        for shape in PieceCatalog.shapes where shape.cells.count <= maximumCells {
            for color in BlockColor.allCases {
                let piece = Piece(shape: shape, color: color)
                for row in 0..<Board.sideLength {
                    for column in 0..<Board.sideLength {
                        let origin = GridCell(row: row, column: column)
                        guard board.canPlace(piece, at: origin) else { continue }

                        var result = board
                        _ = result.place(piece, at: origin)
                        let completed = result.completedLines()
                        result.clear(completed.cells)

                        let lineCount = completed.rows.count + completed.columns.count
                        let varietyPenalty = recentShapes.contains(shape.name) ? 18 : 0
                        let challengeBonus = shape.cells.count * state.level / 5
                        let quality = lineCount * 600
                            + completed.cells.count * 35
                            + boardQuality(result)
                            + shape.weight
                            + challengeBonus
                            - varietyPenalty
                        moves.append(
                            PlannedMove(piece: piece, resultingBoard: result, quality: quality)
                        )
                    }
                }
            }
        }

        return moves.sorted { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
            if lhs.piece.shape.cells.count != rhs.piece.shape.cells.count {
                return lhs.piece.shape.cells.count < rhs.piece.shape.cells.count
            }
            if lhs.piece.shape.name != rhs.piece.shape.name {
                return lhs.piece.shape.name < rhs.piece.shape.name
            }
            return lhs.piece.color.rawValue < rhs.piece.color.rawValue
        }
    }

    private func boardQuality(_ board: Board) -> Int {
        var quality = board.cells.reduce(0) { $0 + ($1 == nil ? 2 : 0) }

        for index in 0..<Board.sideLength {
            let rowColors = (0..<Board.sideLength).compactMap {
                board[GridCell(row: index, column: $0)]
            }
            let columnColors = (0..<Board.sideLength).compactMap {
                board[GridCell(row: $0, column: index)]
            }
            quality += lineQuality(rowColors)
            quality += lineQuality(columnColors)
        }

        return quality
    }

    private func lineQuality(_ colors: [BlockColor]) -> Int {
        guard !colors.isEmpty else { return 0 }
        let distinctColors = Set(colors).count
        if distinctColors == 1 {
            return colors.count * colors.count * 4
        }
        return -(colors.count * distinctColors * 5)
    }

    private mutating func weightedRank(in count: Int) -> Int {
        guard count > 1 else { return 0 }
        let totalWeight = count * (count + 1) / 2
        var selection = Int.random(in: 0..<totalWeight, using: &random)
        for index in 0..<count {
            selection -= count - index
            if selection < 0 { return index }
        }
        return 0
    }

    private func bestRescueColor(for board: Board) -> BlockColor {
        BlockColor.allCases.max { lhs, rhs in
            rescueColorScore(lhs, on: board) < rescueColorScore(rhs, on: board)
        } ?? .cyan
    }

    private func rescueColorScore(_ color: BlockColor, on board: Board) -> Int {
        var score = 0
        for index in 0..<Board.sideLength {
            let rowMatches = (0..<Board.sideLength).filter {
                board[GridCell(row: index, column: $0)] == color
            }.count
            let columnMatches = (0..<Board.sideLength).filter {
                board[GridCell(row: $0, column: index)] == color
            }.count
            score += rowMatches * rowMatches + columnMatches * columnMatches
        }
        return score
    }
}
