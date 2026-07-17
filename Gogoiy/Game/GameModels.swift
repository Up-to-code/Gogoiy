import Foundation

struct GridCell: Hashable, Sendable {
    let row: Int
    let column: Int
}

enum BlockColor: Int, CaseIterable, Sendable {
    case coral
    case amber
    case lime
    case cyan
    case violet
    case blue
}

struct PieceShape: Hashable, Sendable {
    let name: String
    let cells: [GridCell]
    let weight: Int

    init(name: String, cells: [GridCell], weight: Int = 1) {
        self.name = name
        self.cells = Self.normalized(cells)
        self.weight = max(1, weight)
    }

    var rows: Int {
        (cells.map(\.row).max() ?? 0) + 1
    }

    var columns: Int {
        (cells.map(\.column).max() ?? 0) + 1
    }

    private static func normalized(_ cells: [GridCell]) -> [GridCell] {
        let minimumRow = cells.map(\.row).min() ?? 0
        let minimumColumn = cells.map(\.column).min() ?? 0
        return cells
            .map { GridCell(row: $0.row - minimumRow, column: $0.column - minimumColumn) }
            .sorted {
                $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row
            }
    }
}

struct Piece: Identifiable, Hashable, Sendable {
    let id: UUID
    let shape: PieceShape
    let color: BlockColor

    init(id: UUID = UUID(), shape: PieceShape, color: BlockColor) {
        self.id = id
        self.shape = shape
        self.color = color
    }
}

struct Tray: Equatable, Sendable {
    var slots: [Piece?]

    var availablePieces: [Piece] {
        slots.compactMap { $0 }
    }

    var isEmpty: Bool {
        availablePieces.isEmpty
    }
}

struct Board: Equatable, Sendable {
    static let sideLength = 8
    private(set) var cells: [BlockColor?]

    init(cells: [BlockColor?] = Array(repeating: nil, count: sideLength * sideLength)) {
        precondition(cells.count == Self.sideLength * Self.sideLength)
        self.cells = cells
    }

    subscript(_ cell: GridCell) -> BlockColor? {
        get {
            guard contains(cell) else { return nil }
            return cells[index(for: cell)]
        }
        set {
            precondition(contains(cell))
            cells[index(for: cell)] = newValue
        }
    }

    func contains(_ cell: GridCell) -> Bool {
        (0..<Self.sideLength).contains(cell.row)
            && (0..<Self.sideLength).contains(cell.column)
    }

    func canPlace(_ piece: Piece, at origin: GridCell) -> Bool {
        piece.shape.cells.allSatisfy { offset in
            let target = GridCell(
                row: origin.row + offset.row,
                column: origin.column + offset.column
            )
            return contains(target) && self[target] == nil
        }
    }

    func hasPlacement(for piece: Piece) -> Bool {
        for row in 0..<Self.sideLength {
            for column in 0..<Self.sideLength
            where canPlace(piece, at: GridCell(row: row, column: column)) {
                return true
            }
        }
        return false
    }

    mutating func place(_ piece: Piece, at origin: GridCell) -> [GridCell] {
        precondition(canPlace(piece, at: origin))
        return piece.shape.cells.map { offset in
            let target = GridCell(
                row: origin.row + offset.row,
                column: origin.column + offset.column
            )
            self[target] = piece.color
            return target
        }
    }

    func completedLines() -> (rows: [Int], columns: [Int], cells: Set<GridCell>) {
        let rows = (0..<Self.sideLength).filter { row in
            let colors = (0..<Self.sideLength).compactMap {
                self[GridCell(row: row, column: $0)]
            }
            return colors.count == Self.sideLength && Set(colors).count == 1
        }
        let columns = (0..<Self.sideLength).filter { column in
            let colors = (0..<Self.sideLength).compactMap {
                self[GridCell(row: $0, column: column)]
            }
            return colors.count == Self.sideLength && Set(colors).count == 1
        }

        var completedCells = Set<GridCell>()
        rows.forEach { row in
            (0..<Self.sideLength).forEach {
                completedCells.insert(GridCell(row: row, column: $0))
            }
        }
        columns.forEach { column in
            (0..<Self.sideLength).forEach {
                completedCells.insert(GridCell(row: $0, column: column))
            }
        }
        return (rows, columns, completedCells)
    }

    mutating func clear(_ completedCells: Set<GridCell>) {
        completedCells.forEach { self[$0] = nil }
    }

    private func index(for cell: GridCell) -> Int {
        cell.row * Self.sideLength + cell.column
    }
}

enum ScoreEvent: Equatable, Sendable {
    case placed(cells: Int)
    case linesCleared(lines: Int, combo: Int, bonus: Int)
}

struct MoveResult: Equatable, Sendable {
    let piece: Piece
    let origin: GridCell
    let placedCells: [GridCell]
    let clearedCells: Set<GridCell>
    let clearedLineCount: Int
    let scoreEvents: [ScoreEvent]
    let scoreDelta: Int
    let combo: Int
    let refilledTray: Bool
    let isGameOver: Bool
}

struct PlacementHint: Equatable, Sendable {
    let piece: Piece
    let origin: GridCell
    let clearedCells: Set<GridCell>
}

struct GameState: Equatable, Sendable {
    var board: Board
    var tray: Tray
    var score: Int
    var bestScore: Int
    var combo: Int
    var isGameOver: Bool
}

enum GameRuleError: Error, Equatable {
    case gameOver
    case pieceUnavailable
    case invalidPlacement
}
