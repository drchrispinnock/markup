import AppKit

/// The editor's text view. It passes clicks on list markers to the
/// controller, and lets the controller decide what copied text looks like.
@MainActor
final class EditorTextView: NSTextView {
    /// Called with the character index of a clicked list marker. Returns true
    /// if it handled the click.
    var markerClickHandler: ((Int) -> Bool)?

    /// The plain text to put on the pasteboard for a range of the document.
    var plainTextForCopy: ((NSRange) -> String)?

    // MARK: - Spelling and grammar

    static let checkSpellingKey = "MarkupCheckSpellingWhileTyping"
    static let checkGrammarKey = "MarkupCheckGrammarWithSpelling"
    static let correctSpellingKey = "MarkupCorrectSpellingAutomatically"

    /// Where the spelling and grammar settings are kept. They are shared by
    /// every editor using the same defaults, and survive relaunching.
    var checkingDefaults = UserDefaults.standard {
        didSet { applyCheckingDefaults() }
    }

    private var isObservingCheckingDefaults = false

    /// Sets spelling and grammar checking from `checkingDefaults`. Spelling
    /// and grammar are checked by default. Automatic correction is off by
    /// default, because it changes words as you type.
    func applyCheckingDefaults() {
        checkingDefaults.register(defaults: [
            Self.checkSpellingKey: true,
            Self.checkGrammarKey: true,
            Self.correctSpellingKey: false,
        ])
        isContinuousSpellCheckingEnabled = checkingDefaults.bool(forKey: Self.checkSpellingKey)
        isGrammarCheckingEnabled = checkingDefaults.bool(forKey: Self.checkGrammarKey)
        isAutomaticSpellingCorrectionEnabled = checkingDefaults.bool(forKey: Self.correctSpellingKey)

        if !isObservingCheckingDefaults {
            isObservingCheckingDefaults = true
            NotificationCenter.default.addObserver(self, selector: #selector(checkingDefaultsChanged(_:)),
                                                   name: .markupCheckingDefaultsChanged, object: nil)
        }
    }

    @objc private func checkingDefaultsChanged(_ notification: Notification) {
        guard notification.object as? UserDefaults === checkingDefaults else { return }
        applyCheckingDefaults()
    }

    // The Edit > Spelling and Grammar toggles. NSTextView changes only its
    // own setting, so save it and tell the other editors.

    override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        saveCheckingDefaults()
    }

    override func toggleGrammarChecking(_ sender: Any?) {
        super.toggleGrammarChecking(sender)
        saveCheckingDefaults()
    }

    override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
        super.toggleAutomaticSpellingCorrection(sender)
        saveCheckingDefaults()
    }

    private func saveCheckingDefaults() {
        checkingDefaults.set(isContinuousSpellCheckingEnabled, forKey: Self.checkSpellingKey)
        checkingDefaults.set(isGrammarCheckingEnabled, forKey: Self.checkGrammarKey)
        checkingDefaults.set(isAutomaticSpellingCorrectionEnabled, forKey: Self.correctSpellingKey)
        NotificationCenter.default.post(name: .markupCheckingDefaultsChanged, object: checkingDefaults)
    }

    // MARK: - List markers

    override func mouseDown(with event: NSEvent) {
        if let index = markerIndex(at: convert(event.locationInWindow, from: nil)),
           markerClickHandler?(index) == true {
            return
        }
        super.mouseDown(with: event)
    }

    /// The index of the list marker drawn at `point`, in view coordinates.
    func markerIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.contains(containerPoint) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return textStorage.attribute(.listMarker, at: index, effectiveRange: nil) != nil ? index : nil
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string, let plainTextForCopy else {
            return super.writeSelection(to: pboard, type: type)
        }
        let text = selectedRanges.map { plainTextForCopy($0.rangeValue) }.joined(separator: "\n")
        return pboard.setString(text, forType: .string)
    }
}

extension Notification.Name {
    /// Posted with the `UserDefaults` whose spelling and grammar settings an
    /// editor has just changed.
    static let markupCheckingDefaultsChanged = Notification.Name("MarkupCheckingDefaultsChanged")
}
