import Foundation

enum PieceCatalog {
    static let shapes: [PieceShape] = [
        PieceShape(name: "single", cells: cells([(0, 0)]), weight: 2),
        PieceShape(name: "domino-h", cells: cells([(0, 0), (0, 1)]), weight: 3),
        PieceShape(name: "domino-v", cells: cells([(0, 0), (1, 0)]), weight: 3),
        PieceShape(name: "tri-h", cells: cells([(0, 0), (0, 1), (0, 2)]), weight: 4),
        PieceShape(name: "tri-v", cells: cells([(0, 0), (1, 0), (2, 0)]), weight: 4),
        PieceShape(name: "four-h", cells: cells([(0, 0), (0, 1), (0, 2), (0, 3)]), weight: 3),
        PieceShape(name: "four-v", cells: cells([(0, 0), (1, 0), (2, 0), (3, 0)]), weight: 3),
        PieceShape(name: "five-h", cells: cells([(0, 0), (0, 1), (0, 2), (0, 3), (0, 4)]), weight: 2),
        PieceShape(name: "five-v", cells: cells([(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)]), weight: 2),
        PieceShape(name: "square", cells: cells([(0, 0), (0, 1), (1, 0), (1, 1)]), weight: 4),
        PieceShape(name: "corner-small-a", cells: cells([(0, 0), (1, 0), (1, 1)]), weight: 3),
        PieceShape(name: "corner-small-b", cells: cells([(0, 1), (1, 0), (1, 1)]), weight: 3),
        PieceShape(name: "corner-small-c", cells: cells([(0, 0), (0, 1), (1, 0)]), weight: 3),
        PieceShape(name: "corner-small-d", cells: cells([(0, 0), (0, 1), (1, 1)]), weight: 3),
        PieceShape(name: "corner-large-a", cells: cells([(0, 0), (1, 0), (2, 0), (2, 1), (2, 2)]), weight: 2),
        PieceShape(name: "corner-large-b", cells: cells([(0, 2), (1, 2), (2, 0), (2, 1), (2, 2)]), weight: 2),
        PieceShape(name: "corner-large-c", cells: cells([(0, 0), (0, 1), (0, 2), (1, 0), (2, 0)]), weight: 2),
        PieceShape(name: "corner-large-d", cells: cells([(0, 0), (0, 1), (0, 2), (1, 2), (2, 2)]), weight: 2),
        PieceShape(name: "tee", cells: cells([(0, 0), (0, 1), (0, 2), (1, 1)]), weight: 2),
        PieceShape(name: "zig", cells: cells([(0, 1), (0, 2), (1, 0), (1, 1)]), weight: 2),
        PieceShape(name: "zag", cells: cells([(0, 0), (0, 1), (1, 1), (1, 2)]), weight: 2),
        PieceShape(name: "rectangle-six", cells: cells([
            (0, 0), (0, 1), (0, 2),
            (1, 0), (1, 1), (1, 2)
        ]), weight: 1),
        PieceShape(name: "square-nine", cells: cells([
            (0, 0), (0, 1), (0, 2),
            (1, 0), (1, 1), (1, 2),
            (2, 0), (2, 1), (2, 2)
        ]), weight: 1)
    ]

    static let single = shapes.first { $0.name == "single" }!

    static let rewardedShapes: [PieceShape] = [
        "single", "domino-h", "domino-v", "tri-h", "tri-v", "square"
    ].compactMap { name in
        shapes.first { $0.name == name }
    }

    private static func cells(_ values: [(Int, Int)]) -> [GridCell] {
        values.map { GridCell(row: $0.0, column: $0.1) }
    }
}

struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
