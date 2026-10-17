# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Markup is a native macOS plain-text editor, written in Swift with AppKit, that will eventually edit Markdown. The scope ends there: the document stays plain text and the editor won't do anything beyond that.

## Building, running and testing

It is a Swift Package (no Xcode project), built with the Command Line Tools:

- `swift build` builds the app.
- `swift run` builds and launches it.
- `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` runs all tests.
- Add `--filter ListEditorTests/tabNestsAndShiftTabUnnests` to run a single test.

The `-plugin-path` flag is needed: the Command Line Tools keep the Swift Testing macro plugin in `plugins/testing/`, and the build doesn't reliably search there. Without the flag, test builds fail intermittently with "plugin for module 'TestingMacros' not found".

The machine has only the Command Line Tools, not full Xcode. They lack SwiftUI's macro plugins, so `@State` and other SwiftUI macros fail to compile. That is why the UI is plain AppKit; don't introduce SwiftUI unless full Xcode is installed.

## Targets

- `MarkupCore` is pure Swift with no AppKit. `BlockStyle` is the line styles (raw value = heading level, 0 = paragraph). `ListItem` (level + `ListMarker`: bullet / unchecked / checked) is a list line. `MarkdownCodec` converts Markdown to and from `[Line]`, losslessly. It recognises `#`/`##`/`###` + space, and `- `, `- [ ] `, `- [x] ` with two spaces of indent per level. Text that would otherwise read back as one of these is escaped with a backslash (`\# `, `\- `, `- \[ ] `). Tested by `MarkupCoreTests`.
- `Markup` is the app executable. `MarkupTests` drives a real `EditorWindowController` through NSTextView commands (`insertText` one character at a time, `doCommand(by:)`) and the style popup's action, with manual undo groups standing in for events.

## Architecture

The app uses AppKit's document architecture. `NSDocumentController` (never subclassed) creates documents and their windows and handles the File menu, unsaved-changes prompts and quitting. Markdown (`net.daringfireball.markdown`, `.md`/`.markdown`) is the only document type.

- `Info.plist` (repo root) declares the document type and names `MarkdownDocument` as its class. With no app bundle, `Package.swift` embeds it into the executable's `__TEXT,__info_plist` section with a linker flag, and that is where `NSDocumentController` reads it from. Adding a file type means editing this plist.
- `MarkdownDocument.swift` holds the Markdown read from disk, as UTF-8 with CRLF converted to LF. It hands this to the window controller and asks the controller for fresh Markdown when saving. It has `@objc(MarkdownDocument)` so the plist can name it without a module prefix. `autosavesInPlace` is off, to keep classic Save / Save As behaviour.
- `main.swift` starts `NSApplication` by hand (there is no nib or app bundle) and sets the activation policy to `.regular`, so that a process launched by `swift run` gets a Dock icon, a menu bar and focus.
- `MainMenu.swift` builds the menu bar in code. Menu items have a nil target and send standard selectors (`newDocument:`, `save:`, `saveAs:`, `performClose:`, `undo:`...) along the responder chain. The Edit menu has to exist for Cmd-C/V/Z/A to reach the text view.

### Editor model

`EditorWindowController` is split across files: window, invariants and undo helpers in the main file; `+Markdown` (load / save / copy); `+Styles` (popup, heading Return); `+Lists`. `EditorTextView` is an NSTextView subclass that forwards marker clicks and lets the controller write the pasteboard. It uses TextKit 1 (`usingTextLayoutManager: false`) so the layout manager can hit-test markers.

The text view never contains Markdown markers. A line's style lives in attributes on every character of the line, including its newline:
- **Headings:** `.blockStyle` (`BlockStyle+AppKit.swift`) plus the matching font.
- **List items:** the line starts with one U+FFFC attachment character carrying `.listMarker`, which draws the bullet or checkbox (`ListItem+AppKit.swift`, drawn with a handler so colours follow dark mode). Every character of the line carries `.listLevel` and an indented paragraph style. Even an empty item therefore has a character to hold its attributes.

`load(markdown:)` and `markdown` convert between the text storage and `MarkdownCodec` lines. Copying writes list markers back as Markdown. Pasting Markdown list lines converts them through the same path as typing. The text view is still `isRichText = false`, so users can't add any other formatting.

Invariants that the controller maintains:
- **Lines stay consistent.** `textStorage(_:didProcessEditing:)` makes a line that starts with a marker carry its item's attributes throughout. Any other line gets one block style (from its first character) and no list attributes. This handles joined lines and deleted markers. It changes attributes only.
- **Typed list syntax becomes markers.** `shouldChangeTextIn` records the edit and `textDidChange` acts on it (`applyListShortcuts`): `- ` → bullet, `[ ] `/`[x] ` after a bullet → checkbox, and stray markers inside a line are deleted. These are text changes, made through `replaceCharacters(in:with:)` so NSTextView registers the undo. They trigger only when the edit touches the syntax itself. Lines are processed top-down, so the nesting limit (at most one level deeper than the item above) sees converted lines.
- **The caret never rests before a marker.** `willChangeSelection` moves it after the marker. Moving left from there jumps to the previous line.
- **Typing attributes follow the caret's line.** They are reset on every selection change, and the popup is updated to match. An empty last line has no characters, so a style chosen there lives only in the typing attributes.
- **Commands:** Return (`doCommandBy`) continues a list (a new checkbox starts unticked). On an empty item it outdents the item, or ends the list at level 0. At the end of a heading it starts a paragraph. Tab and Shift-Tab change list level. The popup turns list lines into the chosen style.
- **Every attribute change is undoable.** Changes go through `changeAttributes(in:_:)`, which registers an undo that restores the previous attributes and registers its own redo. It calls `breakUndoCoalescing()`. Normalisation and shortcuts are skipped while undoing or redoing.
- **The controller's `undoManager` is the document's.** It is overridden, and also returned to the window, so all edits mark the document edited.
