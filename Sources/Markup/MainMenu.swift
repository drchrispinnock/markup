import AppKit

/// Without a nib the app has no menu bar, and without an Edit menu the
/// standard shortcuts (copy, paste, undo, select all) don't reach the text view.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        // The standard About panel takes the name, version and icon from the
        // app bundle.
        appMenu.addItem(withTitle: "About Markup",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Markup", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Markup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenu: appMenu, title: "Markup")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Open Project…", action: #selector(AppDelegate.openProject(_:)), keyEquivalent: "O")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Page Setup…", action: #selector(NSDocument.runPageLayout(_:)), keyEquivalent: "P")
        fileMenu.addItem(withTitle: "Print…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        mainMenu.addItem(submenu: fileMenu, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(submenu: findMenu(), title: "Find")
        editMenu.addItem(submenu: spellingMenu(), title: "Spelling and Grammar")
        mainMenu.addItem(submenu: editMenu, title: "Edit")

        let formatMenu = NSMenu(title: "Format")
        formatMenu.addItem(withTitle: "Bold", action: #selector(EditorViewController.toggleBold(_:)), keyEquivalent: "b")
        formatMenu.addItem(withTitle: "Italic", action: #selector(EditorViewController.toggleItalic(_:)), keyEquivalent: "i")
        formatMenu.addItem(withTitle: "Strikethrough",
                           action: #selector(EditorViewController.toggleStrikethrough(_:)), keyEquivalent: "X")
        formatMenu.addItem(withTitle: "Code", action: #selector(EditorViewController.toggleCode(_:)), keyEquivalent: "e")
        formatMenu.addItem(withTitle: "Subscript", action: #selector(EditorViewController.toggleSubscript(_:)),
                           keyEquivalent: "-").keyEquivalentModifierMask = [.command, .control]
        formatMenu.addItem(withTitle: "Superscript", action: #selector(EditorViewController.toggleSuperscript(_:)),
                           keyEquivalent: "=").keyEquivalentModifierMask = [.command, .control]
        formatMenu.addItem(withTitle: "Highlight", action: #selector(EditorViewController.toggleHighlight(_:)),
                           keyEquivalent: "H")
        mainMenu.addItem(submenu: formatMenu, title: "Format")

        let insertMenu = NSMenu(title: "Insert")
        insertMenu.addItem(withTitle: "Link…", action: #selector(EditorViewController.editLink(_:)), keyEquivalent: "k")
        insertMenu.addItem(withTitle: "Cross Link…", action: #selector(EditorViewController.insertCrossLink(_:)),
                           keyEquivalent: "K")
        insertMenu.addItem(withTitle: "Table…", action: #selector(EditorViewController.insertTable(_:)), keyEquivalent: "")
        insertMenu.addItem(withTitle: "Image…", action: #selector(EditorViewController.insertImage(_:)), keyEquivalent: "")
        insertMenu.addItem(.separator())
        insertMenu.addItem(withTitle: "Variable…", action: #selector(EditorViewController.insertVariable(_:)), keyEquivalent: "")
        insertMenu.addItem(withTitle: "Citation…", action: #selector(EditorViewController.insertCitation(_:)), keyEquivalent: "")
        insertMenu.addItem(withTitle: "Bibliography", action: #selector(EditorViewController.insertBibliography(_:)),
                           keyEquivalent: "")
        // Only project windows have a variables.txt or bibliography.txt.
        insertMenu.addItem(withTitle: "Update Variables in Project",
                           action: #selector(ProjectWindowController.updateVariablesInProject(_:)), keyEquivalent: "")
        mainMenu.addItem(submenu: insertMenu, title: "Insert")

        let viewMenu = NSMenu(title: "View")
        // NSSplitViewController handles this in project windows, and retitles
        // it Show Sidebar or Hide Sidebar.
        viewMenu.addItem(withTitle: "Hide Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)),
                         keyEquivalent: "s").keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Show Markdown",
                         action: #selector(EditorViewController.toggleMarkdown(_:)), keyEquivalent: "M")
        viewMenu.addItem(withTitle: "Reload Images",
                         action: #selector(EditorViewController.reloadImages(_:)), keyEquivalent: "R")
        mainMenu.addItem(submenu: viewMenu, title: "View")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        mainMenu.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    /// NSTextView handles these through its NSTextFinder, which shows the
    /// find bar. Each item's tag is its `NSTextFinder.Action`.
    private static func findMenu() -> NSMenu {
        let menu = NSMenu(title: "Find")
        let items: [(String, NSTextFinder.Action, String, NSEvent.ModifierFlags)] = [
            ("Find…", .showFindInterface, "f", [.command]),
            ("Find and Replace…", .showReplaceInterface, "f", [.command, .option]),
            ("Find Next", .nextMatch, "g", [.command]),
            ("Find Previous", .previousMatch, "g", [.command, .shift]),
            // ⌘E is Format > Code.
            ("Use Selection for Find", .setSearchString, "", []),
        ]
        for (title, action, key, modifiers) in items {
            let item = menu.addItem(withTitle: title, action: #selector(NSTextView.performTextFinderAction(_:)),
                                    keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.tag = action.rawValue
        }
        return menu
    }

    /// NSTextView handles these actions and ticks the toggles to match its
    /// settings. `EditorTextView` saves the toggles' settings.
    private static func spellingMenu() -> NSMenu {
        let menu = NSMenu(title: "Spelling and Grammar")
        menu.addItem(withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        menu.addItem(withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check Spelling While Typing",
                     action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Check Grammar With Spelling",
                     action: #selector(NSTextView.toggleGrammarChecking(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Correct Spelling Automatically",
                     action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)), keyEquivalent: "")
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
