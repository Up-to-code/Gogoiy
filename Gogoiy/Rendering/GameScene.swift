import SpriteKit
import UIKit

@MainActor
protocol GameSceneDelegate: AnyObject {
    var currentGameState: GameState { get }
    func gameSceneCanPlace(pieceID: UUID, at origin: GridCell) -> Bool
    func gameScenePreviewClearedCells(pieceID: UUID, at origin: GridCell) -> Set<GridCell>
    func gameScenePlace(pieceID: UUID, at origin: GridCell) -> MoveResult?
    func gameSceneDidFinishResolution(_ result: MoveResult)
    func gameScenePlayFeedback(_ cue: FeedbackController.Cue)
}

@MainActor
final class GameScene: SKScene {
    private enum Phase {
        case idle
        case dragging
        case resolving
        case gameOver
    }

    weak var gameDelegate: GameSceneDelegate?

    private let boardLayer = SKNode()
    private let blockLayer = SKNode()
    private let previewLayer = SKNode()
    private let trayLayer = SKNode()
    private let effectsLayer = SKNode()

    private var phase: Phase = .idle
    private var boardOrigin = CGPoint.zero
    private var boardSize: CGFloat = 0
    private var boardCellSize: CGFloat = 0
    private var trayPositions: [CGPoint] = []
    private var trayPieceNodes: [UUID: SKNode] = [:]
    private var dragNode: SKNode?
    private var draggedPiece: Piece?
    private var candidateOrigin: GridCell?
    private var candidateIsValid = false
    private var displayedState: GameState?
    private var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
        [boardLayer, blockLayer, previewLayer, trayLayer, effectsLayer].forEach(addChild)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        view.preferredFramesPerSecond = 60
        renderCurrentState(animatedTray: true)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 0, size.height > 0 else { return }
        let phaseBeforeRotation = phase
        renderCurrentState(animatedTray: false)
        if phaseBeforeRotation == .resolving {
            phase = .resolving
        }
    }

    func renderCurrentState(animatedTray: Bool = false) {
        guard let state = gameDelegate?.currentGameState else { return }
        displayedState = state
        removeAllVisuals()
        calculateLayout()
        drawBoardSurface()
        drawBoardBlocks(state.board)
        drawTray(state.tray, animated: animatedTray)
        phase = state.isGameOver ? .gameOver : .idle
    }

    func setGamePaused(_ paused: Bool) {
        isPaused = paused
    }

    func prepareForRestart() {
        isPaused = false
        phase = .idle
        dragNode?.removeFromParent()
        dragNode = nil
        draggedPiece = nil
        clearPreview()
        renderCurrentState(animatedTray: true)
    }

    func showHint(_ hint: PlacementHint) {
        guard phase == .idle else { return }
        clearPreview()
        drawPreview(
            for: hint.piece,
            at: hint.origin,
            isValid: true,
            matchingLineCells: hint.clearedCells
        )
        if let trayNode = trayPieceNodes[hint.piece.id], !reduceMotion {
            trayNode.run(.sequence([
                .scale(to: 1.14, duration: 0.16),
                .scale(to: 1, duration: 0.16)
            ]))
        }
        run(.sequence([
            .wait(forDuration: reduceMotion ? 1.2 : 2.4),
            .run { [weak self] in self?.clearPreview() }
        ]), withKey: "rewardedHint")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard
            phase == .idle,
            let touch = touches.first,
            let pieceID = pieceID(at: touch.location(in: self)),
            let piece = displayedState?.tray.availablePieces.first(where: { $0.id == pieceID }),
            let trayNode = trayPieceNodes[pieceID]
        else {
            return
        }

        phase = .dragging
        draggedPiece = piece
        trayNode.isHidden = true
        let node = makePieceNode(piece, cellSize: boardCellSize * 0.92, interactive: false)
        node.position = liftedPosition(for: touch.location(in: self))
        node.zPosition = 40
        node.alpha = 0.96
        node.setScale(reduceMotion ? 1 : 0.82)
        effectsLayer.addChild(node)
        if !reduceMotion {
            node.run(.scale(to: 1.06, duration: 0.1))
        }
        dragNode = node
        gameDelegate?.gameScenePlayFeedback(.pickup)
        updateDrag(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .dragging, let touch = touches.first else { return }
        updateDrag(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .dragging else { return }
        if let touch = touches.first {
            updateDrag(at: touch.location(in: self))
        }
        finishDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .dragging else { return }
        cancelDrag(playFeedback: false)
    }

    private func removeAllVisuals() {
        [boardLayer, blockLayer, previewLayer, trayLayer, effectsLayer].forEach {
            $0.removeAllChildren()
        }
        trayPieceNodes.removeAll()
        dragNode = nil
        draggedPiece = nil
        candidateOrigin = nil
        candidateIsValid = false
    }

    private func calculateLayout() {
        let landscape = size.width > size.height * 1.12
        let adClearance: CGFloat = landscape ? 70 : 58
        if landscape {
            let topClearance: CGFloat = 54
            boardSize = min(size.height - topClearance - adClearance - 18, size.width * 0.58)
            boardSize = max(220, boardSize)
            let combinedWidth = boardSize + min(250, size.width * 0.3)
            boardOrigin = CGPoint(
                x: max(24, (size.width - combinedWidth) / 2),
                y: max(adClearance + 8, (size.height - boardSize) / 2)
            )
            let trayX = boardOrigin.x + boardSize + (size.width - boardOrigin.x - boardSize) / 2
            let centerY = boardOrigin.y + boardSize / 2
            let spacing = min(118, boardSize * 0.28)
            trayPositions = [
                CGPoint(x: trayX, y: centerY + spacing),
                CGPoint(x: trayX, y: centerY),
                CGPoint(x: trayX, y: centerY - spacing)
            ]
        } else {
            let topHUDClearance = min(245, max(215, size.height * 0.27))
            let trayClearance = max(140, size.height * 0.18)
            let bottomClearance = adClearance + trayClearance
            let availableBoardHeight = size.height - topHUDClearance - bottomClearance

            boardSize = min(size.width - 28, availableBoardHeight)
            boardSize = max(240, boardSize)
            boardOrigin = CGPoint(
                x: (size.width - boardSize) / 2,
                y: bottomClearance
            )
            let spacing = min(size.width * 0.31, boardSize * 0.34)
            // Five-cell vertical pieces are the tallest tray shapes. Keep their lower edge
            // above the banner and their upper edge below the board on compact phones.
            let trayY = adClearance + max(82, trayClearance * 0.58)
            trayPositions = [
                CGPoint(x: size.width / 2 - spacing, y: trayY),
                CGPoint(x: size.width / 2, y: trayY),
                CGPoint(x: size.width / 2 + spacing, y: trayY)
            ]
        }
        boardCellSize = boardSize / CGFloat(Board.sideLength)
    }

    private func drawBoardSurface() {
        let shadow = SKShapeNode(
            rect: CGRect(
                x: boardOrigin.x + 2,
                y: boardOrigin.y - 5,
                width: boardSize,
                height: boardSize
            ),
            cornerRadius: boardCellSize * 0.22
        )
        shadow.fillColor = UIColor.black.withAlphaComponent(0.23)
        shadow.strokeColor = .clear
        shadow.zPosition = -2
        boardLayer.addChild(shadow)

        let surface = SKShapeNode(
            rect: CGRect(x: boardOrigin.x, y: boardOrigin.y, width: boardSize, height: boardSize),
            cornerRadius: boardCellSize * 0.22
        )
        surface.fillColor = UIColor.gogoiyBoard
        surface.strokeColor = UIColor.white.withAlphaComponent(0.08)
        surface.lineWidth = 1.5
        surface.zPosition = -1
        boardLayer.addChild(surface)

        for row in 0..<Board.sideLength {
            for column in 0..<Board.sideLength {
                let slot = SKShapeNode(
                    rectOf: CGSize(width: boardCellSize * 0.82, height: boardCellSize * 0.82),
                    cornerRadius: boardCellSize * 0.16
                )
                slot.position = point(for: GridCell(row: row, column: column))
                slot.fillColor = UIColor.gogoiySlot
                slot.strokeColor = UIColor.white.withAlphaComponent(0.025)
                slot.lineWidth = 1
                boardLayer.addChild(slot)
            }
        }
    }

    private func drawBoardBlocks(_ board: Board) {
        for row in 0..<Board.sideLength {
            for column in 0..<Board.sideLength {
                let cell = GridCell(row: row, column: column)
                if let color = board[cell] {
                    let node = makeCandyBlock(color: color, size: boardCellSize * 0.88)
                    node.position = point(for: cell)
                    node.name = blockName(for: cell)
                    blockLayer.addChild(node)
                }
            }
        }
    }

    private func drawTray(_ tray: Tray, animated: Bool) {
        trayPieceNodes.removeAll()
        let landscape = size.width > size.height * 1.12
        let pieceCellSize = min(boardCellSize * (landscape ? 0.55 : 0.58), 26)
        for index in tray.slots.indices {
            guard let piece = tray.slots[index], index < trayPositions.count else { continue }
            let node = makePieceNode(piece, cellSize: pieceCellSize, interactive: true)
            node.position = trayPositions[index]
            node.zPosition = 10
            trayLayer.addChild(node)
            trayPieceNodes[piece.id] = node

            if animated && !reduceMotion {
                node.setScale(0.05)
                node.alpha = 0
                node.run(.sequence([
                    .wait(forDuration: Double(index) * 0.07),
                    .group([
                        .fadeIn(withDuration: 0.16),
                        .sequence([
                            .scale(to: 1.12, duration: 0.14),
                            .scale(to: 1, duration: 0.09)
                        ])
                    ])
                ]))
            }
        }
    }

    private func makePieceNode(_ piece: Piece, cellSize: CGFloat, interactive: Bool) -> SKNode {
        let container = SKNode()
        let width = CGFloat(piece.shape.columns) * cellSize
        let height = CGFloat(piece.shape.rows) * cellSize
        for cell in piece.shape.cells {
            let block = makeCandyBlock(color: piece.color, size: cellSize * 0.88)
            block.position = CGPoint(
                x: (CGFloat(cell.column) + 0.5) * cellSize - width / 2,
                y: height / 2 - (CGFloat(cell.row) + 0.5) * cellSize
            )
            container.addChild(block)
        }
        if interactive {
            let hitTarget = SKShapeNode(
                rectOf: CGSize(width: max(64, width + 20), height: max(64, height + 20)),
                cornerRadius: 18
            )
            hitTarget.fillColor = .white
            hitTarget.strokeColor = .clear
            hitTarget.alpha = 0.001
            hitTarget.zPosition = -1
            container.addChild(hitTarget)
            container.name = "tray-piece"
            container.userData = ["pieceID": piece.id.uuidString]
        }
        return container
    }

    private func makeCandyBlock(color: BlockColor, size: CGFloat) -> SKNode {
        let container = SKNode()
        let shadow = SKShapeNode(
            rectOf: CGSize(width: size, height: size),
            cornerRadius: size * 0.19
        )
        shadow.position.y = -size * 0.055
        shadow.fillColor = color.uiColor.shadowed
        shadow.strokeColor = .clear
        container.addChild(shadow)

        let body = SKShapeNode(
            rectOf: CGSize(width: size, height: size * 0.92),
            cornerRadius: size * 0.18
        )
        body.fillColor = color.uiColor
        body.strokeColor = color.uiColor.highlighted.withAlphaComponent(0.72)
        body.lineWidth = max(1, size * 0.045)
        container.addChild(body)

        let shine = SKShapeNode(
            rectOf: CGSize(width: size * 0.62, height: size * 0.13),
            cornerRadius: size * 0.065
        )
        shine.position = CGPoint(x: -size * 0.03, y: size * 0.25)
        shine.fillColor = UIColor.white.withAlphaComponent(0.29)
        shine.strokeColor = .clear
        body.addChild(shine)
        return container
    }

    private func updateDrag(at location: CGPoint) {
        guard let dragNode, let piece = draggedPiece else { return }
        dragNode.position = liftedPosition(for: location)

        let pieceWidth = CGFloat(piece.shape.columns) * boardCellSize * 0.92
        let pieceHeight = CGFloat(piece.shape.rows) * boardCellSize * 0.92
        let topLeftCellCenter = CGPoint(
            x: dragNode.position.x - pieceWidth / 2 + boardCellSize * 0.46,
            y: dragNode.position.y + pieceHeight / 2 - boardCellSize * 0.46
        )
        let boardTopLeftCenter = CGPoint(
            x: boardOrigin.x + boardCellSize / 2,
            y: boardOrigin.y + boardSize - boardCellSize / 2
        )
        let column = Int(round((topLeftCellCenter.x - boardTopLeftCenter.x) / boardCellSize))
        let row = Int(round((boardTopLeftCenter.y - topLeftCellCenter.y) / boardCellSize))
        let origin = GridCell(row: row, column: column)
        candidateOrigin = origin
        candidateIsValid = gameDelegate?.gameSceneCanPlace(pieceID: piece.id, at: origin) ?? false
        let matchingLineCells = candidateIsValid
            ? gameDelegate?.gameScenePreviewClearedCells(pieceID: piece.id, at: origin) ?? []
            : []
        drawPreview(
            for: piece,
            at: origin,
            isValid: candidateIsValid,
            matchingLineCells: matchingLineCells
        )
    }

    private func finishDrag() {
        guard
            let piece = draggedPiece,
            let origin = candidateOrigin,
            candidateIsValid,
            let result = gameDelegate?.gameScenePlace(pieceID: piece.id, at: origin)
        else {
            cancelDrag(playFeedback: true)
            return
        }

        phase = .resolving
        dragNode?.removeFromParent()
        dragNode = nil
        draggedPiece = nil
        clearPreview()
        gameDelegate?.gameScenePlayFeedback(.placement)
        animateResolution(result)
    }

    private func cancelDrag(playFeedback: Bool) {
        clearPreview()
        if playFeedback {
            gameDelegate?.gameScenePlayFeedback(.invalid)
        }

        guard
            let piece = draggedPiece,
            let dragNode,
            let trayNode = trayPieceNodes[piece.id]
        else {
            phase = .idle
            self.dragNode?.removeFromParent()
            self.dragNode = nil
            draggedPiece = nil
            return
        }

        let finish = {
            dragNode.removeFromParent()
            trayNode.isHidden = false
            trayNode.setScale(0.84)
            trayNode.run(.scale(to: 1, duration: 0.1))
            self.dragNode = nil
            self.draggedPiece = nil
            self.phase = .idle
        }
        if reduceMotion {
            finish()
        } else {
            dragNode.run(.group([
                .move(to: trayNode.position, duration: 0.15),
                .scale(to: 0.62, duration: 0.15),
                .fadeAlpha(to: 0.6, duration: 0.15)
            ]), completion: finish)
        }
    }

    private func drawPreview(
        for piece: Piece,
        at origin: GridCell,
        isValid: Bool,
        matchingLineCells: Set<GridCell>
    ) {
        // Redrawing the visual preview must not clear the placement candidate
        // that touchesEnded uses to commit the move.
        previewLayer.removeAllChildren()
        for offset in piece.shape.cells {
            let cell = GridCell(
                row: origin.row + offset.row,
                column: origin.column + offset.column
            )
            guard (0..<Board.sideLength).contains(cell.row),
                  (0..<Board.sideLength).contains(cell.column)
            else {
                continue
            }
            let preview = SKShapeNode(
                rectOf: CGSize(width: boardCellSize * 0.83, height: boardCellSize * 0.83),
                cornerRadius: boardCellSize * 0.15
            )
            preview.position = point(for: cell)
            let previewColor: UIColor = matchingLineCells.isEmpty
                ? (isValid ? .gogoiyPreview : .gogoiyInvalid)
                : .gogoiyMatch
            preview.fillColor = previewColor
                .withAlphaComponent(0.22)
            preview.strokeColor = previewColor
            preview.lineWidth = max(2, boardCellSize * 0.055)
            preview.zPosition = 30
            previewLayer.addChild(preview)
        }

        for cell in matchingLineCells {
            let lineHint = SKShapeNode(
                rectOf: CGSize(width: boardCellSize * 0.9, height: boardCellSize * 0.9),
                cornerRadius: boardCellSize * 0.17
            )
            lineHint.position = point(for: cell)
            lineHint.fillColor = UIColor.gogoiyMatch.withAlphaComponent(0.12)
            lineHint.strokeColor = .gogoiyMatch
            lineHint.lineWidth = max(2.5, boardCellSize * 0.065)
            lineHint.glowWidth = boardCellSize * 0.12
            lineHint.zPosition = 29
            previewLayer.addChild(lineHint)
            if !reduceMotion {
                lineHint.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.45, duration: 0.34),
                    .fadeAlpha(to: 1, duration: 0.34)
                ])))
            }
        }
    }

    private func clearPreview() {
        previewLayer.removeAllChildren()
        candidateOrigin = nil
        candidateIsValid = false
    }

    private func animateResolution(_ result: MoveResult) {
        for cell in result.placedCells {
            let node = makeCandyBlock(color: result.piece.color, size: boardCellSize * 0.88)
            node.position = point(for: cell)
            node.name = blockName(for: cell)
            node.zPosition = 12
            blockLayer.addChild(node)
            if !reduceMotion {
                node.setScale(0.18)
                node.run(.sequence([
                    .scale(to: 1.16, duration: 0.09),
                    .scale(to: 1, duration: 0.07)
                ]))
            }
        }

        let placementDelay = reduceMotion ? 0.02 : 0.16
        run(.wait(forDuration: placementDelay)) { [weak self] in
            guard let self else { return }
            if result.clearedCells.isEmpty {
                self.showPoints(result.scoreDelta, at: result.placedCells)
                self.finishResolution(result, after: self.reduceMotion ? 0.01 : 0.06)
            } else {
                self.animateClear(result)
            }
        }
    }

    private func animateClear(_ result: MoveResult) {
        gameDelegate?.gameScenePlayFeedback(result.combo > 1 ? .combo : .clear)
        if result.combo > 1 {
            showCombo(result.combo)
        }
        showPoints(result.scoreDelta, at: Array(result.clearedCells), emphasized: true)

        for cell in result.clearedCells {
            let position = point(for: cell)
            emitParticles(at: position, color: .lime)
            showGreenFlash(at: position)
            blockLayer.children
                .filter { $0.name == blockName(for: cell) }
                .forEach { node in
                    if reduceMotion {
                        node.alpha = 0
                    } else {
                        node.run(.group([
                            .sequence([
                                .scale(to: 1.2, duration: 0.08),
                                .scale(to: 0.05, duration: 0.2)
                            ]),
                            .sequence([
                                .colorize(with: .white, colorBlendFactor: 0.9, duration: 0.08),
                                .fadeOut(withDuration: 0.2)
                            ])
                        ]))
                    }
                }
        }
        finishResolution(result, after: reduceMotion ? 0.05 : 0.34)
    }

    private func finishResolution(_ result: MoveResult, after delay: TimeInterval) {
        run(.wait(forDuration: delay)) { [weak self] in
            guard let self else { return }
            self.renderCurrentState(animatedTray: result.refilledTray)
            if result.refilledTray && !result.isGameOver {
                self.gameDelegate?.gameScenePlayFeedback(.refill)
            }
            self.phase = result.isGameOver ? .gameOver : .idle
            self.gameDelegate?.gameSceneDidFinishResolution(result)
        }
    }

    private func emitParticles(at position: CGPoint, color: BlockColor) {
        guard !reduceMotion else { return }
        for index in 0..<5 {
            let particle = SKShapeNode(
                rectOf: CGSize(width: boardCellSize * 0.14, height: boardCellSize * 0.14),
                cornerRadius: boardCellSize * 0.03
            )
            particle.position = position
            particle.fillColor = color.uiColor.highlighted
            particle.strokeColor = .clear
            particle.zPosition = 50
            effectsLayer.addChild(particle)
            let angle = CGFloat(index) / 5 * .pi * 2 + CGFloat.random(in: -0.25...0.25)
            let distance = boardCellSize * CGFloat.random(in: 0.55...1.15)
            let destination = CGPoint(
                x: position.x + cos(angle) * distance,
                y: position.y + sin(angle) * distance
            )
            particle.run(.sequence([
                .group([
                    .move(to: destination, duration: 0.3),
                    .rotate(byAngle: CGFloat.random(in: -2...2), duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                    .scale(to: 0.2, duration: 0.3)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func showGreenFlash(at position: CGPoint) {
        guard !reduceMotion else { return }
        let flash = SKShapeNode(
            rectOf: CGSize(width: boardCellSize * 0.9, height: boardCellSize * 0.9),
            cornerRadius: boardCellSize * 0.18
        )
        flash.position = position
        flash.fillColor = UIColor.gogoiyMatch.withAlphaComponent(0.72)
        flash.strokeColor = .white
        flash.lineWidth = 1.5
        flash.zPosition = 45
        effectsLayer.addChild(flash)
        flash.run(.sequence([
            .group([
                .scale(to: 1.35, duration: 0.22),
                .fadeOut(withDuration: 0.22)
            ]),
            .removeFromParent()
        ]))
    }

    private func showPoints(
        _ points: Int,
        at cells: [GridCell],
        emphasized: Bool = false
    ) {
        guard !cells.isEmpty else { return }
        let averageX = cells.map { point(for: $0).x }.reduce(0, +) / CGFloat(cells.count)
        let averageY = cells.map { point(for: $0).y }.reduce(0, +) / CGFloat(cells.count)
        let label = SKLabelNode(fontNamed: "AvenirNextRounded-Bold")
        label.text = "+\(points)"
        label.fontSize = emphasized ? min(38, boardCellSize * 0.82) : min(24, boardCellSize * 0.54)
        label.fontColor = emphasized ? .gogoiyMatch : .white
        label.position = CGPoint(x: averageX, y: averageY + boardCellSize * 0.35)
        label.zPosition = 85
        effectsLayer.addChild(label)
        if reduceMotion {
            label.run(.sequence([.wait(forDuration: 0.18), .removeFromParent()]))
        } else {
            label.setScale(0.35)
            label.run(.sequence([
                .group([
                    .scale(to: 1.12, duration: 0.12),
                    .moveBy(x: 0, y: boardCellSize * 0.35, duration: 0.3)
                ]),
                .group([
                    .scale(to: 0.9, duration: 0.16),
                    .fadeOut(withDuration: 0.16),
                    .moveBy(x: 0, y: boardCellSize * 0.25, duration: 0.16)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func showCombo(_ combo: Int) {
        let label = SKLabelNode(fontNamed: "AvenirNextRounded-Bold")
        label.text = "SWEET ×\(combo)"
        label.fontSize = min(34, boardCellSize * 0.76)
        label.fontColor = .white
        label.position = CGPoint(x: boardOrigin.x + boardSize / 2, y: boardOrigin.y + boardSize / 2)
        label.zPosition = 80
        effectsLayer.addChild(label)
        label.setScale(0.4)
        label.run(.sequence([
            .group([
                .scale(to: 1.12, duration: 0.14),
                .fadeIn(withDuration: 0.1)
            ]),
            .wait(forDuration: 0.2),
            .group([
                .moveBy(x: 0, y: boardCellSize * 0.6, duration: 0.2),
                .fadeOut(withDuration: 0.2)
            ]),
            .removeFromParent()
        ]))
    }

    private func point(for cell: GridCell) -> CGPoint {
        CGPoint(
            x: boardOrigin.x + (CGFloat(cell.column) + 0.5) * boardCellSize,
            y: boardOrigin.y + boardSize - (CGFloat(cell.row) + 0.5) * boardCellSize
        )
    }

    private func liftedPosition(for touchPosition: CGPoint) -> CGPoint {
        let lift = min(92, max(58, boardCellSize * 1.65))
        return CGPoint(x: touchPosition.x, y: touchPosition.y + lift)
    }

    private func blockName(for cell: GridCell) -> String {
        "block-\(cell.row)-\(cell.column)"
    }

    private func pieceID(at position: CGPoint) -> UUID? {
        for node in nodes(at: position) {
            var candidate: SKNode? = node
            for _ in 0..<4 {
                if
                    let value = candidate?.userData?["pieceID"] as? String,
                    let id = UUID(uuidString: value)
                {
                    return id
                }
                candidate = candidate?.parent
            }
        }
        return nil
    }

    private func colorForBlock(at cell: GridCell, fallback: BlockColor) -> BlockColor {
        displayedState?.board[cell] ?? fallback
    }
}

private extension BlockColor {
    var uiColor: UIColor {
        switch self {
        case .coral: .init(red: 0.98, green: 0.27, blue: 0.35, alpha: 1)
        case .amber: .init(red: 1, green: 0.69, blue: 0.13, alpha: 1)
        case .lime: .init(red: 0.28, green: 0.88, blue: 0.37, alpha: 1)
        case .cyan: .init(red: 0.16, green: 0.79, blue: 0.91, alpha: 1)
        case .violet: .init(red: 0.68, green: 0.28, blue: 0.9, alpha: 1)
        case .blue: .init(red: 0.22, green: 0.43, blue: 0.97, alpha: 1)
        }
    }
}

private extension UIColor {
    static let gogoiyBoard = UIColor(red: 0.075, green: 0.075, blue: 0.2, alpha: 0.96)
    static let gogoiySlot = UIColor(red: 0.11, green: 0.11, blue: 0.28, alpha: 1)
    static let gogoiyPreview = UIColor(red: 0.22, green: 0.94, blue: 0.97, alpha: 1)
    static let gogoiyInvalid = UIColor(red: 1, green: 0.31, blue: 0.4, alpha: 1)
    static let gogoiyMatch = UIColor(red: 0.24, green: 1, blue: 0.46, alpha: 1)

    var highlighted: UIColor {
        adjustedBrightness(by: 0.17)
    }

    var shadowed: UIColor {
        adjustedBrightness(by: -0.22)
    }

    func adjustedBrightness(by amount: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        else {
            return self
        }
        return UIColor(
            hue: hue,
            saturation: saturation,
            brightness: min(1, max(0, brightness + amount)),
            alpha: alpha
        )
    }
}
