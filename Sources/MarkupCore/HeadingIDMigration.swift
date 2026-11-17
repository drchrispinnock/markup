import Foundation

/// Makes a book's heading IDs ones Leanpub accepts: Markua takes only IDs
/// that start with a letter (`HeadingAnchor.isMarkuaID`), and only `{id: x}`
/// or `{#x}` above a heading, not `{#id: x}`, which Markup once wrote. Each
/// ID it doesn't accept is renamed, along with the links to it, across all
/// of the book's files at once, since a link may go to any of them.
public enum HeadingIDMigration {
    /// The new name of each of `ids` that Markua doesn't accept, unlike
    /// every other ID and each other.
    public static func renames(for ids: Set<String>) -> [String: String] {
        var taken = ids
        var renames: [String: String] = [:]
        for id in ids.sorted() where !HeadingAnchor.isMarkuaID(id) {
            let new = HeadingAnchor.markuaID(for: id, taken: taken)
            taken.insert(new)
            renames[id] = new
        }
        return renames
    }

    /// `anchor` with its ID renamed by `renames` and written `{id: x}` if
    /// it was `{#id: x}`, or nil if neither changes it.
    public static func migrated(_ anchor: HeadingAnchor, renames: [String: String]) -> HeadingAnchor? {
        let new = renames[anchor.id]
        guard new != nil || anchor.form == .idLine else { return nil }
        var anchor = anchor
        anchor.id = new ?? anchor.id
        if anchor.form == .idLine { anchor.form = .idAttribute }
        anchor.written = nil
        return anchor
    }

    /// `destination` going to the renamed heading, if it goes to one
    /// `renames` renames.
    public static func migrated(destination: String, renames: [String: String]) -> String? {
        guard let reference = HeadingReference(destination: destination), let new = renames[reference.id],
              let hash = destination.lastIndex(of: "#") else { return nil }
        return destination[...hash] + new
    }

    /// `markdown` with its headings' IDs and the links to them migrated.
    /// Code and front matter are left alone.
    public static func migrating(markdown: String, renames: [String: String]) -> String {
        var lines = MarkdownCodec.lines(fromMarkdown: markdown)
        var changed = false
        for index in lines.indices where lines[index].style != .code && lines[index].style != .frontMatter {
            if lines[index].isHeading, let anchor = lines[index].anchor, let new = migrated(anchor, renames: renames) {
                lines[index].anchor = new
                changed = true
            }
            let text = migratingLinks(in: lines[index].text, renames: renames)
            if text != lines[index].text {
                lines[index].text = text
                changed = true
            }
        }
        return changed ? MarkdownCodec.markdown(from: lines) : markdown
    }

    /// `text` with the destinations of its links, `](destination)`, that go
    /// to renamed headings changed.
    static func migratingLinks(in text: String, renames: [String: String]) -> String {
        guard !renames.isEmpty, text.contains("](") else { return text }
        let pattern = try! NSRegularExpression(pattern: #"\]\(<?([^()\s<>]*#[^()\s<>]+)"#)
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: text),
                  let new = migrated(destination: String(text[range]), renames: renames) else { continue }
            result.replaceSubrange(range, with: new)
        }
        return result
    }
}
