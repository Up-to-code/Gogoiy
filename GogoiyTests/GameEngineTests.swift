import XCTest
@testable import Gogoiy

final class GameEngineTests: XCTestCase {
    func testBoardRejectsOutOfBoundsAndOverlappingPlacements() {
        let domino = piece("domino-h", color: .cyan)
        var board = Board()

        XCTAssertTrue(board.canPlace(domino, at: GridCell(row: 0, column: 0)))
        XCTAssertFalse(board.canPlace(domino, at: GridCell(row: 0, column: 7)))
        XCTAssertFalse(board.canPlace(domino, at: GridCell(row: -1, column: 0)))

        _ = board.place(domino, at: GridCell(row: 2, column: 2))
        XCTAssertFalse(board.canPlace(domino, at: GridCell(row: 2, column: 1)))
        XCTAssertFalse(board.canPlace(domino, at: GridCell(row: 2, column: 2)))
    }

    func testInvalidMoveDoesNotMutateState() {
        let domino = piece("domino-h", color: .coral)
        let state = makeState(board: Board(), tray: Tray(slots: [domino, nil, nil]))
        var engine = GameEngine(state: state, seed: 1)
        let original = engine.state

        XCTAssertThrowsError(
            try engine.place(pieceID: domino.id, at: GridCell(row: 0, column: 7))
        ) { error in
            XCTAssertEqual(error as? GameRuleError, .invalidPlacement)
        }
        XCTAssertEqual(engine.state, original)
    }

    func testCrossClearResolvesRowsAndColumnsSimultaneously() throws {
        let single = piece("single", color: .lime)
        var board = Board()
        for column in 0..<Board.sideLength where column != 4 {
            board[GridCell(row: 3, column: column)] = .lime
        }
        for row in 0..<Board.sideLength where row != 3 {
            board[GridCell(row: row, column: 4)] = .lime
        }
        let state = makeState(board: board, tray: Tray(slots: [single, nil, nil]))
        var engine = GameEngine(state: state, seed: 2)

        let result = try engine.place(pieceID: single.id, at: GridCell(row: 3, column: 4))

        XCTAssertEqual(result.clearedLineCount, 2)
        XCTAssertEqual(result.clearedCells.count, 15)
        XCTAssertEqual(result.scoreDelta, 41)
        XCTAssertEqual(result.combo, 1)
        result.clearedCells.forEach { XCTAssertNil(engine.state.board[$0]) }
    }

    func testConsecutiveClearsIncreaseComboAndBonus() throws {
        let first = piece("single", color: .cyan)
        let second = piece("single", color: .coral)
        let spare = piece("square", color: .violet)
        var board = Board()
        for column in 0..<7 {
            board[GridCell(row: 0, column: column)] = .cyan
            board[GridCell(row: 1, column: column)] = .coral
        }
        let tray = Tray(slots: [first, second, spare])
        var engine = GameEngine(state: makeState(board: board, tray: tray), seed: 3)

        let firstResult = try engine.place(pieceID: first.id, at: GridCell(row: 0, column: 7))
        let secondResult = try engine.place(pieceID: second.id, at: GridCell(row: 1, column: 7))

        XCTAssertEqual(firstResult.scoreDelta, 11)
        XCTAssertEqual(firstResult.combo, 1)
        XCTAssertEqual(secondResult.scoreDelta, 21)
        XCTAssertEqual(secondResult.combo, 2)
        XCTAssertEqual(engine.state.score, 32)
    }

    func testFullMixedColorLineDoesNotClear() throws {
        let finalPiece = piece("single", color: .amber)
        var board = Board()
        for column in 0..<7 {
            board[GridCell(row: 2, column: column)] = column < 4 ? .lime : .amber
        }
        let state = makeState(
            board: board,
            tray: Tray(slots: [finalPiece, piece("single", color: .cyan), nil])
        )
        var engine = GameEngine(state: state, seed: 31)

        let result = try engine.place(
            pieceID: finalPiece.id,
            at: GridCell(row: 2, column: 7)
        )

        XCTAssertEqual(result.clearedLineCount, 0)
        XCTAssertTrue(result.clearedCells.isEmpty)
        XCTAssertEqual(result.scoreDelta, 1)
        for column in 0..<Board.sideLength {
            XCTAssertNotNil(engine.state.board[GridCell(row: 2, column: column)])
        }
    }

    func testNonClearingPlacementResetsCombo() throws {
        let single = piece("single", color: .blue)
        let state = GameState(
            board: Board(),
            tray: Tray(slots: [single, nil, nil]),
            score: 50,
            bestScore: 50,
            combo: 3,
            isGameOver: false
        )
        var engine = GameEngine(state: state, seed: 4)

        let result = try engine.place(pieceID: single.id, at: GridCell(row: 4, column: 4))

        XCTAssertEqual(result.scoreDelta, 1)
        XCTAssertEqual(result.combo, 0)
        XCTAssertEqual(engine.state.combo, 0)
    }

    func testTrayRefillsOnlyAfterThirdPiece() throws {
        let pieces = [
            piece("single", color: .cyan),
            piece("single", color: .amber),
            piece("single", color: .coral)
        ]
        var engine = GameEngine(
            state: makeState(board: Board(), tray: Tray(slots: pieces.map(Optional.some))),
            seed: 5
        )

        let first = try engine.place(pieceID: pieces[0].id, at: GridCell(row: 0, column: 0))
        let second = try engine.place(pieceID: pieces[1].id, at: GridCell(row: 0, column: 1))
        let third = try engine.place(pieceID: pieces[2].id, at: GridCell(row: 0, column: 2))

        XCTAssertFalse(first.refilledTray)
        XCTAssertFalse(second.refilledTray)
        XCTAssertTrue(third.refilledTray)
        XCTAssertEqual(engine.state.tray.availablePieces.count, 3)
    }

    func testGameOverWhenNoRemainingPieceFits() throws {
        let single = piece("single", color: .cyan)
        let square = piece("square-nine", color: .coral)
        var board = Board()
        for row in 0..<Board.sideLength {
            for column in 0..<Board.sideLength where (row + column).isMultiple(of: 2) {
                board[GridCell(row: row, column: column)] = .violet
            }
        }
        let state = makeState(board: board, tray: Tray(slots: [single, square, nil]))
        var engine = GameEngine(state: state, seed: 6)

        let result = try engine.place(pieceID: single.id, at: GridCell(row: 0, column: 1))

        XCTAssertTrue(result.isGameOver)
        XCTAssertTrue(engine.state.isGameOver)
    }

    func testSeededGeneratorIsDeterministicAndInitialTrayIsPlayable() {
        let first = GameEngine(seed: 42)
        let second = GameEngine(seed: 42)

        XCTAssertEqual(
            first.state.tray.availablePieces.map(\.shape.name),
            second.state.tray.availablePieces.map(\.shape.name)
        )
        XCTAssertTrue(first.state.tray.availablePieces.contains {
            first.state.board.hasPlacement(for: $0)
        })
        XCTAssertTrue(
            hasCompleteSequence(
                board: first.state.board,
                pieces: first.state.tray.availablePieces
            )
        )
    }

    func testGeneratedTrayOffersACompleteBoardAwareRoute() throws {
        var board = Board()
        for column in 0..<7 {
            board[GridCell(row: 0, column: column)] = .cyan
        }
        let finalOldPiece = piece("single", color: .amber)
        var engine = GameEngine(
            state: makeState(
                board: board,
                tray: Tray(slots: [finalOldPiece, nil, nil])
            ),
            seed: 45
        )

        _ = try engine.place(pieceID: finalOldPiece.id, at: GridCell(row: 7, column: 7))

        XCTAssertTrue(
            hasCompleteSequence(
                board: engine.state.board,
                pieces: engine.state.tray.availablePieces
            )
        )
        XCTAssertTrue(engine.state.tray.availablePieces.contains { candidate in
            guard candidate.color == .cyan else { return false }
            return placements(of: candidate, on: engine.state.board).contains { origin in
                var preview = engine.state.board
                _ = preview.place(candidate, at: origin)
                return !preview.completedLines().cells.isEmpty
            }
        })
    }

    func testDifficultyLevelScalesAndCapsAtOneHundred() {
        XCTAssertEqual(makeState(board: Board(), tray: Tray(slots: []), score: 0).level, 1)
        XCTAssertEqual(makeState(board: Board(), tray: Tray(slots: []), score: 9_900).level, 100)
        XCTAssertEqual(makeState(board: Board(), tray: Tray(slots: []), score: 50_000).level, 100)
    }

    func testRewardedBlockReplacesFirstRemainingTrayPieceWithoutMutatingBoard() throws {
        let first = piece("domino-h", color: .amber)
        let second = piece("square", color: .violet)
        let originalBoard = Board()
        var engine = GameEngine(
            state: makeState(
                board: originalBoard,
                tray: Tray(slots: [nil, first, second])
            ),
            seed: 43
        )
        let requestedShape = try XCTUnwrap(
            PieceCatalog.rewardedShapes.first { $0.name == "tri-v" }
        )

        let replacement = try XCTUnwrap(
            engine.replaceFirstAvailablePiece(with: requestedShape, color: .lime)
        )

        XCTAssertEqual(engine.state.board, originalBoard)
        XCTAssertNil(engine.state.tray.slots[0])
        XCTAssertEqual(engine.state.tray.slots[1], replacement)
        XCTAssertEqual(engine.state.tray.slots[2], second)
        XCTAssertEqual(replacement.shape, requestedShape)
        XCTAssertEqual(replacement.color, .lime)
    }

    func testRewardedBlockRejectsShapeThatDoesNotFit() throws {
        var board = Board()
        for row in 0..<Board.sideLength {
            for column in 0..<Board.sideLength {
                board[GridCell(row: row, column: column)] = .cyan
            }
        }
        board[GridCell(row: 7, column: 7)] = nil
        let original = makeState(
            board: board,
            tray: Tray(slots: [piece("single", color: .coral), nil, nil])
        )
        var engine = GameEngine(state: original, seed: 44)
        let domino = try XCTUnwrap(
            PieceCatalog.rewardedShapes.first { $0.name == "domino-h" }
        )

        XCTAssertNil(engine.replaceFirstAvailablePiece(with: domino, color: .blue))
        XCTAssertEqual(engine.state, original)
    }

    func testRestartPreservesBestScoreAndClearsRunState() throws {
        let single = piece("single", color: .lime)
        var engine = GameEngine(
            state: makeState(
                board: Board(),
                tray: Tray(slots: [single, nil, nil]),
                score: 120,
                bestScore: 240
            ),
            seed: 7
        )

        engine.restart(seed: 8)

        XCTAssertEqual(engine.state.score, 0)
        XCTAssertEqual(engine.state.bestScore, 240)
        XCTAssertEqual(engine.state.board, Board())
        XCTAssertEqual(engine.state.tray.availablePieces.count, 3)
    }

    func testPreferencesPersistScoreAndFeedbackSettings() throws {
        let suiteName = "GogoiyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = Preferences(defaults: defaults)

        preferences.bestScore = 987
        preferences.soundEnabled = false
        preferences.musicEnabled = false
        preferences.hapticsEnabled = false

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.bestScore, 987)
        XCTAssertFalse(reloaded.soundEnabled)
        XCTAssertFalse(reloaded.musicEnabled)
        XCTAssertFalse(reloaded.hapticsEnabled)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func piece(_ name: String, color: BlockColor) -> Piece {
        Piece(shape: PieceCatalog.shapes.first { $0.name == name }!, color: color)
    }

    private func makeState(
        board: Board,
        tray: Tray,
        score: Int = 0,
        bestScore: Int = 0
    ) -> GameState {
        GameState(
            board: board,
            tray: tray,
            score: score,
            bestScore: bestScore,
            combo: 0,
            isGameOver: false
        )
    }

    private func hasCompleteSequence(board: Board, pieces: [Piece]) -> Bool {
        guard let piece = pieces.first else { return true }
        let remaining = Array(pieces.dropFirst())
        for origin in placements(of: piece, on: board) {
            var nextBoard = board
            _ = nextBoard.place(piece, at: origin)
            nextBoard.clear(nextBoard.completedLines().cells)
            if hasCompleteSequence(board: nextBoard, pieces: remaining) {
                return true
            }
        }
        return false
    }

    private func placements(of piece: Piece, on board: Board) -> [GridCell] {
        (0..<Board.sideLength).flatMap { row in
            (0..<Board.sideLength).compactMap { column in
                let origin = GridCell(row: row, column: column)
                return board.canPlace(piece, at: origin) ? origin : nil
            }
        }
    }
}
