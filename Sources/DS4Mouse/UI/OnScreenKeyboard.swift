import AppKit
import SwiftUI

/// Our own on-screen keyboard, driven by the gamepad. See SPEC.md, Р-25.
///
/// A floating panel that never takes focus, so the text field you were typing in stays active.
/// The highlighted key moves with the left stick / D-pad, Cross types it. Characters are sent as
/// Unicode text, so Russian works whatever input language macOS is set to.
final class OnScreenKeyboard: ObservableObject {
    struct Page {
        let name: String
        let rows: [[String]]
    }

    static let pages: [Page] = [
        Page(name: "RU", rows: rows("1234567890", "йцукенгшщзхъ", "фывапролджэё", "ячсмитьбю,.")),
        Page(name: "EN", rows: rows("1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.?")),
        Page(name: "123", rows: rows("1234567890", "-/:;()₽$&@\"", ".,?!'#%*+=", "_\\|~<>[]{}€")),
    ]

    private static func rows(_ r: String...) -> [[String]] { r.map { $0.map(String.init) } }

    @Published private(set) var page = 0
    @Published private(set) var row = 1
    @Published private(set) var col = 0
    @Published private(set) var shift = false
    @Published private(set) var lastTyped: String?

    private var panel: NSPanel?
    var isVisible: Bool { panel?.isVisible == true }

    /// Sends the typed text to the focused app.
    var type: (String) -> Void = { _ in }

    var rows: [[String]] { Self.pages[page].rows }
    var maxRowLength: Int { rows.map(\.count).max() ?? 1 }

    func label(_ key: String) -> String { shift ? key.uppercased() : key }

    // MARK: - Gamepad actions

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        shift = false
    }

    /// dx: -1 left / +1 right, dy: -1 up / +1 down. Wraps around at the edges.
    func move(dx: Int, dy: Int) {
        if dx != 0 {
            let n = rows[row].count
            col = (col + dx + n) % n
        }
        if dy != 0 {
            let x = center(row: row, col: col)
            row = (row + dy + rows.count) % rows.count
            col = nearestCol(row: row, x: x)
        }
    }

    func pressSelected() {
        let text = label(rows[row][col])
        type(text)
        lastTyped = text
        shift = false   // one capital letter, like the first tap of Shift on iPhone
    }

    func toggleShift() { shift.toggle() }

    func nextPage() {
        let x = center(row: row, col: col)
        page = (page + 1) % Self.pages.count
        row = min(row, rows.count - 1)
        col = nearestCol(row: row, x: x)
        if let panel { resize(panel) }
    }

    // MARK: - Layout helpers

    /// Rows are centered, so a key's x position depends on the row length.
    private func center(row: Int, col: Int) -> Double {
        Double(maxRowLength - rows[row].count) / 2 + Double(col) + 0.5
    }

    private func nearestCol(row: Int, x: Double) -> Int {
        (0..<rows[row].count).min { abs(center(row: row, col: $0) - x) < abs(center(row: row, col: $1) - x) } ?? 0
    }

    // MARK: - Window

    private func makePanel() -> NSPanel {
        let panel = KeyboardPanel(contentRect: .zero,
                                  styleMask: [.nonactivatingPanel, .borderless],
                                  backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true   // gamepad only; clicks go to the window underneath
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: KeyboardView(model: self))
        resize(panel)
        return panel
    }

    private func resize(_ panel: NSPanel) {
        guard let view = panel.contentView else { return }
        let size = view.fittingSize
        let origin = panel.frame.origin
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.isVisible { position(panel) }
    }

    /// Bottom center of the screen with the mouse cursor.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.minY + 24))
    }
}

private final class KeyboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct KeyboardView: View {
    @ObservedObject var model: OnScreenKeyboard

    private let keySize: CGFloat = 44
    private let gap: CGFloat = 6

    var body: some View {
        VStack(spacing: gap) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { r, keys in
                HStack(spacing: gap) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { c, key in
                        let selected = r == model.row && c == model.col
                        Text(model.label(key))
                            .font(.system(size: 20, weight: selected ? .bold : .regular))
                            .frame(width: keySize, height: keySize)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
                    }
                }
            }
            HStack(spacing: 14) {
                Text(OnScreenKeyboard.pages.enumerated().map { $0.offset == model.page ? "[\($0.element.name)]" : $0.element.name }
                    .joined(separator: " "))
                    .fontWeight(.semibold)
                Text("✕ ввод   □ Shift\(model.shift ? " ●" : "")   △ раскладка   ○ закрыть   R2 ⌫   тачпад — пробел")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .fixedSize()
    }
}
