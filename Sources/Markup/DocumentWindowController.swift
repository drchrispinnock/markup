import AppKit

/// A window showing one document's editor.
@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    let editor: EditorViewController

    init(editor: EditorViewController) {
        self.editor = editor
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        window.minSize = NSSize(width: 480, height: 320)
        window.center()
        window.initialFirstResponder = editor.textView
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editor.undoManager
    }
}
