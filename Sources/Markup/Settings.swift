import Foundation

/// App-wide settings, kept in user defaults.
@MainActor
final class Settings {
    static let shared = Settings(defaults: .standard)

    static let imagesDirectoryKey = "MarkupImagesDirectory"
    static let openProjectsKey = "MarkupOpenProjects"

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
    /// `images` subfolders.
    func imageFolders(forDocumentAt documentURL: URL?) -> [URL] {
        let folder = documentURL?.deletingLastPathComponent()
        return [imagesDirectory, folder, folder?.appendingPathComponent("resources", isDirectory: true),
                folder?.appendingPathComponent("images", isDirectory: true)].compactMap { $0 }
    }
}
