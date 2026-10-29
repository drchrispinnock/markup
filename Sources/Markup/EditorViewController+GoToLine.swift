import AppKit

/// Edit > Go To Line: selects a line of the Markdown by its number, as the
/// Markdown view's line numbers show it. In the Formatted view that is the
/// text showing the line: a table's row selects its first cell, its
/// delimiter row the header, and front matter, which isn't shown, the start.
extension EditorViewController {
    @objc func showGoToLine(_ sender: Any?) {
        presentAtCaret(GoToLineController(lineCount: markdownLineCount) { [weak self] number in
            self?.goToLine(number)
        })
    }

    /// The number of lines in the Markdown, counting an empty last line.
    var markdownLineCount: Int {
        LineNumberRulerView.lineCount(of: isShowingMarkdown ? storage.string : markdown)
    }

    /// Selects line `number` (from 1) of the Markdown, or the nearest line
    /// there is, and scrolls to it.
    func goToLine(_ number: Int) {
        let location = textLocation(ofMarkdownLine: max(number, 1) - 1)
        let line = lineRange(at: location)
        var contents = contentsRange(of: line)
        if !isShowingMarkdown, contents.length > 0, listItem(at: line) != nil {
            // Not the list marker.
            contents = NSRange(location: contents.location + 1, length: contents.length - 1)
        }
        textView.setSelectedRange(contents)
        textView.scrollRangeToVisible(contents)
        view.window?.makeFirstResponder(textView)
        if contents.length > 0 { textView.showFindIndicator(for: contents) }
    }
}

/// The Go To Line popover: "Line:" with a number field, "of" the number of
/// lines, and a Go button.
final class GoToLineController: NSViewController {
    let field = NSTextField()
    let goButton = NSButton(title: "Go", target: nil, action: nil)
    let lineCount: Int
    private let onGo: (Int) -> Void

    init(lineCount: Int, onGo: @escaping (Int) -> Void) {
        self.lineCount = max(lineCount, 1)
        self.onGo = onGo
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        field.formatter = formatter
        field.alignment = .right
        field.placeholderString = "1"
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true

        goButton.target = self
        goButton.action = #selector(go(_:))
        goButton.keyEquivalent = "\r"

        let row = NSStackView(views: [NSTextField(labelWithString: "Line:"), field,
                                      NSTextField(labelWithString: "of \(lineCount)"), goButton])
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        // A margin around the controls. The popover ignores a stack view's
        // edge insets.
        let container = NSView()
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        view = container
        preferredContentSize = container.fittingSize
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(field)
    }

    /// Lines past the end go to the last line.
    @objc func go(_ sender: Any?) {
        guard let number = Int((field.currentEditor()?.string ?? field.stringValue)
            .trimmingCharacters(in: .whitespaces)), number > 0 else {
            NSSound.beep()
            return
        }
        if presentingViewController != nil { dismiss(self) }
        onGo(min(number, lineCount))
    }
}
