import AppKit
import MarkupCore

/// A heading a cross link can go to.
struct CrossLinkTarget: Equatable {
    /// The heading's file, or nil for the document being edited.
    var file: URL?
    /// Which of the file's headings it is, counting from 0.
    var index: Int
    var level: Int
    /// The heading as shown, without Markdown.
    var title: String
}

/// Cross links: the header's bookmark button and Format > Cross Link link
/// the selection to a heading chosen from a list, in this file or (as
/// `Settings.crossFileLinks` allows) another in the project. The link is
/// to the heading's ID, `#id` or `other.md#id`, given the heading one first
/// if it has none.
extension EditorViewController {
    @objc func insertCrossLink(_ sender: Any?) {
        guard !isShowingMarkdown else { return }
        present(makeCrossLinkController(), asPopoverRelativeTo: crossLinkButton.bounds, of: crossLinkButton,
                preferredEdge: crossLinkButton.isFlipped ? .maxY : .minY, behavior: .transient)
    }

    func makeCrossLinkController() -> CrossLinkController {
        CrossLinkController(targets: crossLinkTargets()) { [weak self] target in
            self?.link(to: target)
        }
    }

    /// The headings to offer: this document's first, then those of the
    /// project's other Markdown files.
    func crossLinkTargets() -> [CrossLinkTarget] {
        func targets(in headings: [Line], file: URL?) -> [CrossLinkTarget] {
            headings.enumerated().map { index, line in
                CrossLinkTarget(file: file, index: index, level: line.style.rawValue,
                                title: InlineMarkdown.spans(in: line.text).map(\.text).joined())
            }
        }
        var result = targets(in: headings, file: nil)
        if settings.crossFileLinks != .off, let project = document?.project {
            let own = document?.fileURL?.standardizedFileURL
            for file in project.markdownFiles() where file.url != own {
                result += targets(in: MarkdownCodec.lines(fromMarkdown: file.markdown).filter(\.isHeading), file: file.url)
            }
        }
        return result
    }

    /// Links the selection to `target`, or with none, inserts the heading's
    /// title linked to it.
    func link(to target: CrossLinkTarget) {
        guard let id = headingID(for: target) else { return }
        var destination = "#" + id
        if let file = target.file, settings.crossFileLinks == .withPath {
            destination = Self.relativePath(to: file, from: document?.fileURL?.deletingLastPathComponent()
                ?? document?.project?.root) + destination
        }
        var range = linkTargetRange()
        if range.length == 0 {
            textView.insertText(target.title, replacementRange: range)
            range.length = textView.selectedRange().location - range.location
        }
        setLink(destination, in: range)
        undoManager?.setActionName("Cross Link")
        view.window?.makeFirstResponder(textView)
    }

    /// The target heading's ID, given it one if needed. A heading in another
    /// file has its document opened in the project, if it isn't already, and
    /// left with unsaved changes if it gets an ID.
    private func headingID(for target: CrossLinkTarget) -> String? {
        guard let file = target.file else {
            return document?.headingID(at: target.index, settings: settings)
        }
        guard let project = document?.project else { return nil }
        let url = file.standardizedFileURL
        let other: MarkdownDocument
        if let open = project.documents.first(where: { $0.fileURL?.standardizedFileURL == url }) {
            other = open
        } else if let open = NSDocumentController.shared.document(for: url) as? MarkdownDocument {
            other = open
        } else {
            guard let opened = try? MarkdownDocument(contentsOf: url, ofType: "net.daringfireball.markdown") else { return nil }
            NSDocumentController.shared.addDocument(opened)
            project.adopt(opened)
            other = opened
        }
        return other.headingID(at: target.index, settings: settings)
    }

    /// `file`'s path from `folder`, or its whole path without one.
    static func relativePath(to file: URL, from folder: URL?) -> String {
        guard let folder else { return file.path }
        let from = folder.standardizedFileURL.pathComponents
        let to = file.standardizedFileURL.pathComponents
        var common = 0
        while common < min(from.count, to.count - 1), from[common] == to[common] { common += 1 }
        let path = Array(repeating: "..", count: from.count - common) + to[common...]
        return path.joined(separator: "/").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
    }
}

/// The cross link popover: the headings to choose from, by file, and a
/// Link button.
final class CrossLinkController: NSViewController {
    let targets: [CrossLinkTarget]
    let popUp = NSPopUpButton()
    let linkButton = NSButton(title: "Link", target: nil, action: nil)
    private let onLink: (CrossLinkTarget) -> Void

    init(targets: [CrossLinkTarget], onLink: @escaping (CrossLinkTarget) -> Void) {
        self.targets = targets
        self.onLink = onLink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        popUp.autoenablesItems = false
        let hasOtherFiles = targets.contains { $0.file != nil }
        var file: URL??
        for (number, target) in targets.enumerated() {
            // Each file's name heads its headings.
            if hasOtherFiles, file != .some(target.file) {
                file = .some(target.file)
                if popUp.numberOfItems > 0 { popUp.menu?.addItem(.separator()) }
                let name = target.file?.lastPathComponent ?? "This File"
                popUp.menu?.addItem(withTitle: name, action: nil, keyEquivalent: "").isEnabled = false
            }
            let item = NSMenuItem(title: target.title.isEmpty ? "Untitled Heading" : target.title, action: nil, keyEquivalent: "")
            item.indentationLevel = target.level - 1 + (hasOtherFiles ? 1 : 0)
            item.tag = number
            popUp.menu?.addItem(item)
        }
        if targets.isEmpty {
            popUp.addItem(withTitle: "No Headings")
            popUp.lastItem?.isEnabled = false
        } else {
            popUp.select(popUp.menu?.items.first { $0.isEnabled })
        }
        (popUp.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        popUp.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true

        linkButton.target = self
        linkButton.action = #selector(link(_:))
        linkButton.keyEquivalent = "\r"
        linkButton.isEnabled = !targets.isEmpty

        let title = NSTextField(labelWithString: "Insert Cross Link")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let row = NSStackView(views: [NSTextField(labelWithString: "Heading:"), popUp])
        row.spacing = 6
        let stack = NSStackView(views: [title, row, linkButton])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A margin around the controls. The popover ignores a stack view's
        // edge insets.
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            // The title on the left, the controls on the right.
            title.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        ])
        view = container
        preferredContentSize = container.fittingSize
    }

    /// The heading chosen.
    var selectedTarget: CrossLinkTarget? {
        guard let item = popUp.selectedItem, item.isEnabled, targets.indices.contains(item.tag) else { return nil }
        return targets[item.tag]
    }

    @objc func link(_ sender: Any?) {
        guard let target = selectedTarget else { return }
        if presentingViewController != nil { dismiss(self) }
        onLink(target)
    }
}
