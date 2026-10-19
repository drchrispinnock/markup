# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Markup is a native macOS plain-text editor, written in Swift with AppKit, that will eventually edit Markdown. The scope ends there: the document stays plain text and the editor won't do anything beyond that.

## Building, running and testing

It is a Swift Package (no Xcode project), built with the Command Line Tools:

- `swift build` builds the app.
- `swift run` builds and launches it as a bare executable. Debug builds embed `img/Markup.png` in the executable's `__TEXT,__markup_icon` section (`Package.swift`), and `DevelopmentIcon` draws it as the app icon when there's no app bundle, cropped and clipped the way the icon script does it.
- `scripts/build-app.sh` makes `build/Markup.app`: a release build, `Info.plist`, and `AppIcon.icns` generated from `img/Markup.png` by `scripts/make-icon.swift`, all ad-hoc signed. The icon script makes the artwork's white surround transparent and clips it to exactly an 824×824 rounded rect (radius 185) at (100, 100) on a 1024 canvas. macOS 26 shows any other outline shrunk onto a grey plate.
- `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` runs all tests.
- Add `--filter ListEditorTests/tabNestsAndShiftTabUnnests` to run a single test.

The `-plugin-path` flag is needed: the Command Line Tools keep the Swift Testing macro plugin in `plugins/testing/`, and the build doesn't reliably search there. Without the flag, test builds fail intermittently with "plugin for module 'TestingMacros' not found".

The machine has only the Command Line Tools, not full Xcode. They lack SwiftUI's macro plugins, so `@State` and other SwiftUI macros fail to compile. That is why the UI is plain AppKit; don't introduce SwiftUI unless full Xcode is installed.

## Targets

- `MarkupCore` is pure Swift with no AppKit. `BlockStyle` is the line styles (raw value = heading level, 0 = paragraph, -1 = code). `ListItem` (level + `ListMarker`: bullet / unchecked / checked) is a list line. `MarkdownCodec` converts Markdown to and from `[Line]`, losslessly. It recognises `#`/`##`/`###` + space, and `- `, `- [ ] `, `- [x] ` with two spaces of indent per level. Lines between a ```` ``` ```` fence (with any info string, such as a language) and the next line of exactly as many backticks are `.code` lines kept verbatim; the first carries the `CodeFence` so it is written back as it was, and the fence is lengthened if a line inside would close it. Text that would otherwise read back as one of these is escaped with a backslash (`\# `, `\- `, `- \[ ] `, `` \``` `` when a closing line follows). `InlineMarkdown` reads and writes a line's `**bold**`, `*italic*`, `~~strikethrough~~`, `` `code` ``, `H_2_O` (subscript) and `x^2^` (superscript) as `InlineSpan`s, matching delimiters much as CommonMark does (code spans first, then emphasis with the rule of 3). Subscript and superscript follow Pandoc: single `_`/`^`, allowed inside words, but not across whitespace, so `x^2 + y^2` stays text; underscores never mean italic. and `MarkdownImage` reads `![alt](path)`. Tested by `MarkupCoreTests`.
- `Markup` is the app executable. `MarkupTests` drives a real `EditorWindowController` through NSTextView commands (`insertText` one character at a time, `doCommand(by:)`) and the style popup's action, with manual undo groups standing in for events.

## Architecture

The app uses AppKit's document architecture. `NSDocumentController` (never subclassed) creates documents and their windows and handles the File menu, unsaved-changes prompts and quitting. Markdown (`net.daringfireball.markdown`, `.md`/`.markdown`) is the only document type.

- `Info.plist` (repo root) declares the document type and names `MarkdownDocument` as its class. With no app bundle, `Package.swift` embeds it into the executable's `__TEXT,__info_plist` section with a linker flag, and that is where `NSDocumentController` reads it from. Adding a file type means editing this plist.
- `MarkdownDocument.swift` holds the Markdown read from disk, as UTF-8 with CRLF converted to LF. It hands this to the window controller and asks the controller for fresh Markdown when saving. It has `@objc(MarkdownDocument)` so the plist can name it without a module prefix. `autosavesInPlace` is off, to keep classic Save / Save As behaviour.
- `main.swift` starts `NSApplication` by hand (there is no nib or app bundle) and sets the activation policy to `.regular`, so that a process launched by `swift run` gets a Dock icon, a menu bar and focus.
- `MainMenu.swift` builds the menu bar in code. The app menu uses the standard About panel, which reads its name, version and icon from the bundle. View > Show Markdown (⇧⌘M) reaches `EditorWindowController.toggleMarkdown(_:)` through the responder chain. Menu items have a nil target and send standard selectors (`newDocument:`, `save:`, `saveAs:`, `performClose:`, `undo:`...) along the responder chain. The Edit menu has to exist for Cmd-C/V/Z/A to reach the text view.

### Editor model

`EditorWindowController` is split across files: window, invariants and undo helpers in the main file; `+Markdown` (load / save / copy); `+Styles` (popup, heading Return, typing attributes); `+Lists`; `+Shortcuts` (typed Markdown syntax); `+Emphasis` (bold, italic, strikethrough, code, subscript and superscript buttons and Format menu); `+Code` (code blocks, Reload Images, and `EditorLayoutManager`, which shades code blocks); `+Images` (Insert Image button); `+ViewMode` (Formatted / Markdown switch). `EditorTextView` is an NSTextView subclass that forwards marker clicks and lets the controller write the pasteboard. It also owns the spelling and grammar settings: the Edit > Spelling and Grammar toggles are NSTextView actions, which it overrides to save the settings in `checkingDefaults` and post `.markupCheckingDefaultsChanged`, so every editor sharing those defaults follows. Defaults: spelling and grammar on, autocorrect off. Tests give editors a throwaway `UserDefaults` suite. It uses TextKit 1 (`usingTextLayoutManager: false`) so the layout manager can hit-test markers.

The text view never contains Markdown markers. A line's style lives in attributes on every character of the line, including its newline:
- **Headings:** `.blockStyle` (`BlockStyle+AppKit.swift`) plus the matching font.
- **List items:** the line starts with one U+FFFC attachment character carrying `.listMarker`, which draws the bullet or checkbox (`ListItem+AppKit.swift`, drawn with a handler so colours follow dark mode). Every character of the line carries `.listLevel` and an indented paragraph style. Even an empty item therefore has a character to hold its attributes.
- **Bold, italic, strikethrough, inline code, subscript and superscript:** `.inlineBold`, `.inlineItalic`, `.inlineStrikethrough`, `.inlineCode`, `.inlineSubscript` and `.inlineSuperscript` on the characters (`InlineStyle+AppKit.swift`). The font comes from the line's block style plus these (code is monospaced, subscript and superscript smaller and shifted with `.baselineOffset`), so wherever a line's style attributes are set, `applyInlineStyles(in:)` must follow to put the right font, strikethrough line, code shading and baseline offset back. The subscript and superscript buttons each take off the other. Typing takes the styles of the character before the caret; a button pressed with no selection is kept in `typingStyles` until the caret moves. Saving writes the styles line by line with `InlineMarkdown`, which puts spaces outside the delimiters and escapes literal `*`/`~` only when needed. Emphasis that changes mid-word (italic straight into bold) can't always be written as Markdown; the text survives but the styles may not.
- **Code blocks:** lines in the `.code` block style, kept exactly as typed: no inline styles (normalisation strips them, and the style buttons skip these lines) and no shortcuts. A non-plain fence is `.codeFence` on every character of its block, so splitting and joining lines keep it, and a change of fence between code lines starts a new block when saving. Return at the end of a code line makes another; on an empty last line of a block it ends the block. Typing ```` ``` ```` (or ```` ```lang ````) alone on a line and pressing Return starts a block. `emptyLineFence` goes with `emptyLineStyle` for an empty last code line.
- **Images:** `![alt](path)` (parsed by `MarkdownImage` in MarkupCore) is one U+FFFC attachment character carrying `.markdownImage`, the image's Markdown exactly as written, which saving and copying write back. View > Reload Images (`reloadImages`) replaces every image's attachment with one read from disk again. Its `ImageAttachmentCell` (`MarkdownImage+AppKit.swift`) draws the image at its actual size for now (wider images run past the window's edge), or an "Image not found" placeholder. The header's image button (`+Images`) inserts an image chosen from the images directory, with its path relative to that directory, by typing its Markdown and letting the shortcut convert it.

`load(markdown:)` and `markdown` convert between the text storage and `MarkdownCodec` lines. Copying writes list markers back as Markdown. Pasting Markdown list lines converts them through the same path as typing. The text view is still `isRichText = false`, so users can't add any other formatting.

Invariants that the controller maintains:
- **Lines stay consistent.** `textStorage(_:didProcessEditing:)` makes a line that starts with a marker carry its item's attributes throughout. Any other line gets one block style (from its first character) and no list attributes. This handles joined lines and deleted markers. It changes attributes only.
- **Typed Markdown syntax becomes styles.** `shouldChangeTextIn` records the edit and `textDidChange` acts on it (`applyMarkdownShortcuts`): `# `/`## `/`### ` → that heading (on any non-list line), `- ` → bullet, `[ ] `/`[x] ` after a bullet → checkbox, `*italic*`, `**bold**`, `~~strikethrough~~`, `` `code` ``, `_subscript_`, `^superscript^` anywhere → styled text (a just-typed closing `*`, `~`, `` ` ``, `_` or `^` waits for the next character, so `**` isn't taken as italic and what follows isn't styled; nothing converts inside inline code or after an unclosed backtick), `![alt](path)` anywhere → image, and stray markers inside a line are deleted. These are text changes, made through `replaceCharacters(in:with:)` so NSTextView registers the undo. They trigger only when the edit touches the syntax itself. Lines are processed top-down, so the nesting limit (at most one level deeper than the item above) sees converted lines.
- **The caret never rests before a marker.** `willChangeSelection` moves it after the marker. Moving left from there jumps to the previous line.
- **Typing attributes follow the caret's line.** They are reset on every selection change, and the popup is updated to match. An empty last line has no characters, so a style chosen there (from the popup or a typed `# `) is kept in `emptyLineStyle` for that caret location, and forgotten once the caret is anywhere else.
- **Commands:** Return (`doCommandBy`) continues a list (a new checkbox starts unticked). On an empty item it outdents the item, or ends the list at level 0. At the end of a heading it starts a paragraph. Tab and Shift-Tab change list level. The popup turns list lines into the chosen style.
- **Every attribute change is undoable.** Changes go through `changeAttributes(in:_:)`, which registers an undo that restores the previous attributes and registers its own redo. It calls `breakUndoCoalescing()`. Normalisation and shortcuts are skipped while undoing or redoing.
- **The controller's `undoManager` is the document's.** It is overridden, and also returned to the window, so all edits mark the document edited.

### Settings

Markup > Settings (`SettingsWindowController`, opened by `AppDelegate.showSettings`) edits `Settings`, which keeps app-wide settings in user defaults. Tests give it a throwaway `UserDefaults` suite.

- **Images directory** (`imagesDirectory`, key `MarkupImagesDirectory`, a folder path or unset). Image paths are looked up in the document's own folder first, then in this folder (`imageFolders`).

### Printing

File > Print (`MarkdownDocument+Printing.swift`) prints the document formatted, whichever view the window is in. It builds a separate text view from the document's current Markdown with `formattedText(fromMarkdown:)`, the same conversion `load(markdown:)` uses. The view is as wide as the page between the margins, and has the light (aqua) appearance so text prints dark in dark mode.

### Markdown view

The header's Formatted / Markdown switch (`+ViewMode`) replaces the text storage with the raw Markdown, in a monospaced font, and sets `isShowingMarkdown`. In that mode `markdown` returns the text as is, and the formatting machinery is off: normalisation, shortcuts, `doCommandBy` (so Return and Tab behave as plain text), the caret-before-marker rule and the style popup. Switching back runs `load(markdown:)`. Both views have one line per Markdown line, so the caret is carried across as (line number, distance from line end). Switching clears the undo stack, because undo steps hold ranges in the other view's text. This doesn't change the document's edited state.
