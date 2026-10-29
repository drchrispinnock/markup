import Foundation
import MarkupCore

/// App-wide settings, kept in user defaults.
@MainActor
final class Settings {
    static let shared = Settings(defaults: .standard)

    static let imagesDirectoryKey = "MarkupImagesDirectory"
    static let openProjectsKey = "MarkupOpenProjects"
    static let addsHeadingIDsKey = "MarkupAddsHeadingIDs"
    static let headingIDFormKey = "MarkupHeadingIDForm"
    static let headingIDSchemeKey = "MarkupHeadingIDScheme"
    static let crossFileLinksKey = "MarkupCrossFileLinks"
    // Named when variables were called tags, so the setting is kept.
    static let quickVariablesKey = "MarkupQuickTags"
    static let hangingBibliographyKey = "MarkupHangingBibliography"
    static let showsLineNumbersKey = "MarkupShowsLineNumbers"

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The first folder to look in for a document's images. Nil if none is
    /// set.
    var imagesDirectory: URL? {
        get {
            defaults.string(forKey: Self.imagesDirectoryKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        set {
            defaults.set(newValue?.path, forKey: Self.imagesDirectoryKey)
        }
    }

    /// Whether saving gives headings without an ID a new one. On unless
    /// turned off.
    var addsHeadingIDs: Bool {
        get { defaults.object(forKey: Self.addsHeadingIDsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.addsHeadingIDsKey) }
    }

    /// How new heading IDs are written: `{#id: x}` on the line above unless
    /// changed.
    var headingIDForm: HeadingAnchor.Form {
        get { defaults.string(forKey: Self.headingIDFormKey).flatMap(HeadingAnchor.Form.init) ?? .idLine }
        set { defaults.set(newValue.rawValue, forKey: Self.headingIDFormKey) }
    }

    /// How new heading IDs are made: from the file's name, the level and
    /// the first word unless changed.
    var headingIDScheme: HeadingIDScheme {
        get { defaults.string(forKey: Self.headingIDSchemeKey).flatMap(HeadingIDScheme.init) ?? .fileLevelWord }
        set { defaults.set(newValue.rawValue, forKey: Self.headingIDSchemeKey) }
    }

    /// How a cross link (Format > Cross Link) goes to a heading in another
    /// file of the project.
    enum CrossFileLinks: String, CaseIterable {
        /// `#id` alone, as Leanpub needs: IDs are unique across the project.
        case idOnly
        /// `other.md#id`, the file's path from this one, as GitHub and most
        /// previewers need.
        case withPath
        /// Only headings in the same file are offered.
        case off
    }

    /// `idOnly` unless changed.
    var crossFileLinks: CrossFileLinks {
        get { defaults.string(forKey: Self.crossFileLinksKey).flatMap(CrossFileLinks.init) ?? .idOnly }
        set { defaults.set(newValue.rawValue, forKey: Self.crossFileLinksKey) }
    }

    /// Whether typing `@name@` inserts the variable `name`. Off unless turned on.
    var quickVariables: Bool {
        get { defaults.bool(forKey: Self.quickVariablesKey) }
        set { defaults.set(newValue, forKey: Self.quickVariablesKey) }
    }

    /// Whether Insert > Bibliography writes the bibliography between
    /// Leanpub's `{begin-hanging-paragraphs}` and `{end-hanging-paragraphs}`.
    /// On unless turned off.
    var hangingBibliography: Bool {
        get { defaults.object(forKey: Self.hangingBibliographyKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.hangingBibliographyKey) }
    }

    /// Whether the Markdown view numbers its lines. Off unless turned on.
    /// Posts `.markupShowsLineNumbersChanged` when set, so every editor
    /// follows.
    var showsLineNumbers: Bool {
        get { defaults.bool(forKey: Self.showsLineNumbersKey) }
        set {
            defaults.set(newValue, forKey: Self.showsLineNumbersKey)
            NotificationCenter.default.post(name: .markupShowsLineNumbersChanged, object: self)
        }
    }

    /// A project window open when the app last quit: its folder, and the
    /// file it showed, if any.
    struct OpenProject: Equatable {
        var folder: URL
        var file: URL?
    }

    /// The project windows open when the app last quit, to open again at
    /// launch.
    var openProjects: [OpenProject] {
        get {
            let saved = defaults.array(forKey: Self.openProjectsKey) as? [[String: String]] ?? []
            return saved.compactMap { project in
                project["folder"].map { folder in
                    OpenProject(folder: URL(fileURLWithPath: folder, isDirectory: true),
                                file: project["file"].map { URL(fileURLWithPath: $0) })
                }
            }
        }
        set {
            defaults.set(newValue.map { project in
                ["folder": project.folder.path, "file": project.file?.path].compactMapValues { $0 }
            }, forKey: Self.openProjectsKey)
        }
    }

    /// The folders an image's path is looked up in, in order: the images
    /// directory, then the document's own folder, then its `resources` and
    /// `images` subfolders, then its parent (`..`), as a Jekyll post in
    /// `_posts` has the site's root.
    func imageFolders(forDocumentAt documentURL: URL?) -> [URL] {
        let folder = documentURL?.deletingLastPathComponent()
        return [imagesDirectory, folder, folder?.appendingPathComponent("resources", isDirectory: true),
                folder?.appendingPathComponent("images", isDirectory: true), folder?.deletingLastPathComponent()].compactMap { $0 }
    }
}

extension Notification.Name {
    /// Posted by `Settings` when `showsLineNumbers` changes.
    static let markupShowsLineNumbersChanged = Notification.Name("MarkupShowsLineNumbersChanged")
}
