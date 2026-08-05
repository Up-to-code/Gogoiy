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

    func testSeededGeneratorIsDeterministicAndTrayDrawsFromCatalog() {
        let first = GameEngine(seed: 42)
        let second = GameEngine(seed: 42)

        XCTAssertEqual(
            first.state.tray.availablePieces.map(\.shape.name),
            second.state.tray.availablePieces.map(\.shape.name)
        )
        XCTAssertEqual(
            first.state.tray.availablePieces.map(\.color),
            second.state.tray.availablePieces.map(\.color)
        )

        let validShapes = Set(PieceCatalog.shapes.map(\.name))
        XCTAssertEqual(first.state.tray.availablePieces.count, 3)
        for piece in first.state.tray.availablePieces {
            XCTAssertTrue(validShapes.contains(piece.shape.name))
            XCTAssertTrue(BlockColor.allCases.contains(piece.color))
        }
    }

    func testTrayColorsAndShapesVaryAcrossSeedsInsteadOfBeingForced() {
        var colorCounts = [BlockColor: Int]()
        var shapeNames = Set<String>()
        for seed in 0..<60 {
            let engine = GameEngine(seed: UInt64(seed))
            for piece in engine.state.tray.availablePieces {
                colorCounts[piece.color, default: 0] += 1
                shapeNames.insert(piece.shape.name)
            }
        }
        XCTAssertGreaterThanOrEqual(
            colorCounts.count,
            2,
            "Tray colors should be randomized across the palette, not forced to one color"
        )
        XCTAssertGreaterThanOrEqual(
            shapeNames.count,
            3,
            "Tray shapes should be randomized across the catalog"
        )
    }

    func testTrayRefillDrawsThreeFreshRandomPieces() throws {
        let pieces = [
            piece("single", color: .cyan),
            piece("single", color: .amber),
            piece("single", color: .coral)
        ]
        var engine = GameEngine(
            state: makeState(board: Board(), tray: Tray(slots: pieces.map(Optional.some))),
            seed: 5
        )

        _ = try engine.place(pieceID: pieces[0].id, at: GridCell(row: 0, column: 0))
        _ = try engine.place(pieceID: pieces[1].id, at: GridCell(row: 0, column: 1))
        _ = try engine.place(pieceID: pieces[2].id, at: GridCell(row: 0, column: 2))

        let refilled = engine.state.tray.availablePieces
        XCTAssertEqual(refilled.count, 3)
        let validShapes = Set(PieceCatalog.shapes.map(\.name))
        for piece in refilled {
            XCTAssertTrue(validShapes.contains(piece.shape.name))
            XCTAssertTrue(BlockColor.allCases.contains(piece.color))
        }
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

    func testBestRewardedBlockPrefersShapeThatClearsMostLines() throws {
        var board = Board()
        for column in 0..<Board.sideLength {
            board[GridCell(row: 4, column: column)] = .amber
        }
        for row in 0..<Board.sideLength {
            board[GridCell(row: row, column: 4)] = .cyan
        }
        board[GridCell(row: 4, column: 4)] = nil
        let engine = GameEngine(
            state: makeState(
                board: board,
                tray: Tray(slots: [nil, nil, nil])
            ),
            seed: 9
        )

        let recommended = try XCTUnwrap(engine.bestRewardedBlock())
        let sample = Piece(shape: recommended.shape, color: recommended.color)

        XCTAssertTrue(engine.state.board.hasPlacement(for: sample))
        var preview = engine.state.board
        _ = preview.place(sample, at: GridCell(row: 4, column: 4))
        XCTAssertEqual(preview.completedLines().cells.count, 8)
    }

    func testBestRewardedBlockIsNilWhenNoRewardedShapeFits() {
        var board = Board()
        for row in 0..<Board.sideLength {
            for column in 0..<Board.sideLength {
                board[GridCell(row: row, column: column)] = .coral
            }
        }
        let engine = GameEngine(
            state: makeState(
                board: board,
                tray: Tray(slots: [nil, nil, nil])
            ),
            seed: 10
        )

        XCTAssertNil(engine.bestRewardedBlock())
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

}
